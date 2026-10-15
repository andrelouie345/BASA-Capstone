-- ARAL-Reading: one session per tutor per date, unless the school's
-- admin/coordinator allows several for that tutor (piece A2c). Idempotent:
-- safe to run in the Supabase SQL Editor more than once. Needs
-- 20261015050000_aral_enrollments.sql (aral_check_tutor) and
-- 20261015060000_aral_sessions.sql.
--
-- Owner decision (2026-10-15): by default a tutor holds at most one ARAL
-- session per date; a coordinator can switch on "multiple sessions per day"
-- per tutor (e.g. a tutor running two groups).
--
--  * aral_tutor_settings: one row per tutor (no row = the defaults). Offline-
--    first like the roster: devices write locally; this waits for the sync.
--  * Sessions: a second session of the same tutor on the same date is refused
--    unless the tutor's switch is on. Checked on insert and when the date
--    changes, under the tutor+year advisory lock the numbering already takes
--    (so two devices can't both slip in). Sessions already on the same date
--    stay as they are (the switch may be turned off later).
--
-- RLS (aral_tutor_settings): read = superadmin, admin/coordinator of the
-- school, or the tutor themselves; write = superadmin or admin/coordinator of
-- the school. anon revoked. The tutor must be an active tutor of that school
-- (aral_check_tutor); tutor and school never change.

create table if not exists public.aral_tutor_settings (
  tutor_id                   uuid primary key references public.users(id),
  school_id                  bigint not null references public.schools(id),
  multiple_sessions_per_day  boolean not null default false,
  updated_by                 uuid references public.users(id),
  updated_at                 timestamptz not null default now()
);
create index if not exists aral_tutor_settings_school on public.aral_tutor_settings (school_id);

create or replace function public.aral_tutor_settings_before_write()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if tg_op = 'UPDATE' and (new.tutor_id, new.school_id) is distinct from (old.tutor_id, old.school_id) then
    raise exception 'an ARAL tutor setting keeps its tutor and school';
  end if;
  if auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  new.updated_at := now();
  if tg_op = 'INSERT' then
    perform aral_check_tutor(new.tutor_id, new.school_id);
  end if;
  return new;
end;
$$;

drop trigger if exists aral_tutor_settings_before_write on public.aral_tutor_settings;
create trigger aral_tutor_settings_before_write
  before insert or update on public.aral_tutor_settings
  for each row execute function public.aral_tutor_settings_before_write();

drop policy if exists aral_tutor_settings_select on public.aral_tutor_settings;
create policy aral_tutor_settings_select on public.aral_tutor_settings
  for select to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
    or (current_user_role() = 'tutor' and tutor_id = auth.uid())
  );

drop policy if exists aral_tutor_settings_insert on public.aral_tutor_settings;
create policy aral_tutor_settings_insert on public.aral_tutor_settings
  for insert to authenticated
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
  );

drop policy if exists aral_tutor_settings_update on public.aral_tutor_settings;
create policy aral_tutor_settings_update on public.aral_tutor_settings
  for update to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
  )
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
  );

drop policy if exists aral_tutor_settings_delete on public.aral_tutor_settings;
create policy aral_tutor_settings_delete on public.aral_tutor_settings
  for delete to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
  );

alter table public.aral_tutor_settings enable row level security;
revoke all on public.aral_tutor_settings from anon;

-- One session per tutor per date (unless allowed). Called by the session
-- triggers after they take the tutor+year lock.
create or replace function public.aral_check_session_day(p_id bigint, p_tutor_id uuid, p_held_on date)
 returns void language plpgsql security definer set search_path to 'public'
as $$
begin
  if coalesce((select multiple_sessions_per_day from public.aral_tutor_settings where tutor_id = p_tutor_id), false) then
    return;
  end if;
  if exists (select 1 from public.aral_sessions
             where tutor_id = p_tutor_id and held_on = p_held_on and id is distinct from p_id) then
    raise exception 'this tutor already has an ARAL session on that date (a coordinator can allow several per day)';
  end if;
end;
$$;
revoke all on function public.aral_check_session_day(bigint, uuid, date) from public, anon, authenticated;

-- Same as 20261015060000, plus the one-per-day check.
create or replace function public.aral_sessions_before_insert()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  new.created_at := now();
  new.updated_at := now();
  -- serialize numbering (and the one-per-day check) per tutor and year
  perform pg_advisory_xact_lock(hashtext('aral_sessions:' || new.tutor_id::text || ':' || new.school_year));
  select coalesce(max(session_no), 0) + 1 into new.session_no
  from public.aral_sessions
  where tutor_id = new.tutor_id and school_year = new.school_year;
  perform aral_check_tutor(new.tutor_id, new.school_id);
  perform aral_check_session_day(null, new.tutor_id, new.held_on);
  return new;
end;
$$;

create or replace function public.aral_sessions_before_update()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  -- The one-per-day rule holds for SQL Editor maintenance too.
  if new.held_on is distinct from old.held_on then
    perform pg_advisory_xact_lock(hashtext('aral_sessions:' || new.tutor_id::text || ':' || new.school_year));
    perform aral_check_session_day(new.id, new.tutor_id, new.held_on);
  end if;
  if auth.uid() is null then
    return new; -- SQL Editor maintenance
  end if;
  if (new.tutor_id, new.school_id, new.school_year, new.session_no, new.created_by, new.created_at)
     is distinct from
     (old.tutor_id, old.school_id, old.school_year, old.session_no, old.created_by, old.created_at) then
    raise exception 'an ARAL session keeps its tutor, school, year and number; only the date, minutes, set-up, lesson and remarks change';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
-- The session triggers already point at these functions (20261015060000).
