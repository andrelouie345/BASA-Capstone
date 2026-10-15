-- ARAL-Reading session log and attendance (piece A2a): aral_sessions (the ARAL
-- Program Lesson Log, one tutor's meeting) and aral_attendance (one mark per
-- learner per session). Idempotent: safe to run in the Supabase SQL Editor more
-- than once. Needs 20261015050000_aral_enrollments.sql.
--
-- Owner decisions (2026-10-15):
--  * A session is one tutor's meeting on a date; its attendance covers that
--    tutor's ARAL learners, even from different sections.
--  * Attendance marks: present / absent / excused (+ an optional note).
--  * The log keeps minutes, set-up (pull-out / during class / after class /
--    weekend / other), the session number and the lesson, and remarks.
--  * Tutors record their own sessions; admins/coordinators of the school record
--    or correct any session there.
--  * Offline-first like the roster: devices write locally; this waits for sync.
--
-- Rules:
--  * session_no is assigned here: the tutor's nth session of the school year
--    (gaps stay when a session is deleted). It never changes.
--  * minutes 1-120 (DepEd: at most 1 h on weekdays, 2 h on weekends; the
--    weekday hour is a warning in the app, not a refusal here).
--  * The session's tutor is an active tutor of its school. A tutor can only
--    create sessions for themselves.
--  * An attendance row's learner is in ARAL in the session's school and year and
--    was active on the session date (entered on or before it, not exited before
--    it). The tutor need not match (a substitute may cover a class).
--  * tutor, school, year, session_no and the creator never change; an
--    attendance row keeps its session and learner.
--
-- RLS: enabled below. Sessions: read/write = superadmin, admin/coordinator of
-- the school, or the session's own tutor. Attendance follows its session.
-- anon revoked.

-- Sessions ---------------------------------------------------------------------

create table if not exists public.aral_sessions (
  id           bigint generated always as identity primary key,
  tutor_id     uuid not null references public.users(id),
  school_id    bigint not null references public.schools(id),
  school_year  text not null,
  session_no   integer not null default 0,
  held_on      date not null,
  minutes      integer not null check (minutes between 1 and 120),
  setup        text not null check (setup in ('pull_out', 'during_class', 'after_class', 'weekend', 'other')),
  lesson       text,
  remarks      text,
  created_by   uuid references public.users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint aral_sessions_school_year_format check (
    case when school_year ~ '^\d{4}-\d{4}$'
         then right(school_year, 4)::int = left(school_year, 4)::int + 1
         else false end)
);
create index if not exists aral_sessions_tutor on public.aral_sessions (tutor_id, school_year, held_on);
create index if not exists aral_sessions_school on public.aral_sessions (school_id, school_year, held_on);

create or replace function public.aral_session_readable(p_session_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.aral_sessions s
    where s.id = p_session_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and s.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and s.tutor_id = auth.uid()))
  );
$$;

-- Same scope as reading (sessions have no finalized state).
create or replace function public.aral_session_writable(p_session_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select public.aral_session_readable(p_session_id);
$$;

create or replace function public.aral_sessions_before_insert()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  new.created_at := now();
  new.updated_at := now();
  -- serialize numbering per tutor and year
  perform pg_advisory_xact_lock(hashtext('aral_sessions:' || new.tutor_id::text || ':' || new.school_year));
  select coalesce(max(session_no), 0) + 1 into new.session_no
  from public.aral_sessions
  where tutor_id = new.tutor_id and school_year = new.school_year;
  perform aral_check_tutor(new.tutor_id, new.school_id);
  return new;
end;
$$;

create or replace function public.aral_sessions_before_update()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
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

drop trigger if exists aral_sessions_before_insert on public.aral_sessions;
create trigger aral_sessions_before_insert
  before insert on public.aral_sessions
  for each row execute function public.aral_sessions_before_insert();
drop trigger if exists aral_sessions_before_update on public.aral_sessions;
create trigger aral_sessions_before_update
  before update on public.aral_sessions
  for each row execute function public.aral_sessions_before_update();

drop policy if exists aral_sessions_select on public.aral_sessions;
create policy aral_sessions_select on public.aral_sessions
  for select to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
    or (current_user_role() = 'tutor' and tutor_id = auth.uid())
  );

-- A tutor creates sessions for themselves in their own school; admins and
-- coordinators for any active tutor of their school (aral_check_tutor).
drop policy if exists aral_sessions_insert on public.aral_sessions;
create policy aral_sessions_insert on public.aral_sessions
  for insert to authenticated
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
    or (current_user_role() = 'tutor' and tutor_id = auth.uid() and school_id = current_user_school_id())
  );

drop policy if exists aral_sessions_update on public.aral_sessions;
create policy aral_sessions_update on public.aral_sessions
  for update to authenticated
  using (aral_session_writable(id))
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
    or (current_user_role() = 'tutor' and tutor_id = auth.uid())
  );

drop policy if exists aral_sessions_delete on public.aral_sessions;
create policy aral_sessions_delete on public.aral_sessions
  for delete to authenticated
  using (aral_session_writable(id));

-- Attendance -------------------------------------------------------------------

create table if not exists public.aral_attendance (
  id             bigint generated always as identity primary key,
  session_id     bigint not null references public.aral_sessions(id) on delete cascade,
  enrollment_id  bigint not null references public.aral_enrollments(id) on delete cascade,
  mark           text not null check (mark in ('present', 'absent', 'excused')),
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint aral_attendance_one_per_session unique (session_id, enrollment_id)
);
create index if not exists aral_attendance_enrollment on public.aral_attendance (enrollment_id);

create or replace function public.check_aral_attendance()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_ok boolean;
begin
  if auth.uid() is null then
    return new;
  end if;
  if not aral_session_writable(new.session_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  if tg_op = 'UPDATE' then
    if (new.session_id, new.enrollment_id) is distinct from (old.session_id, old.enrollment_id) then
      raise exception 'an attendance mark keeps its session and learner; delete it and add a new one instead';
    end if;
    new.created_at := old.created_at;
    new.updated_at := now();
    return new;
  end if;
  select exists (
    select 1
    from public.aral_sessions s
    join public.aral_enrollments e
      on e.school_id = s.school_id and e.school_year = s.school_year
    where s.id = new.session_id and e.id = new.enrollment_id
      and e.entered_on <= s.held_on
      and (e.exited_on is null or e.exited_on >= s.held_on)
  ) into v_ok;
  if not v_ok then
    raise exception 'that learner was not in ARAL in this school on the session date';
  end if;
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists aral_attendance_check on public.aral_attendance;
create trigger aral_attendance_check
  before insert or update on public.aral_attendance
  for each row execute function public.check_aral_attendance();

drop policy if exists aral_attendance_select on public.aral_attendance;
create policy aral_attendance_select on public.aral_attendance
  for select to authenticated using (aral_session_readable(session_id));
drop policy if exists aral_attendance_write on public.aral_attendance;
create policy aral_attendance_write on public.aral_attendance
  for all to authenticated
  using (aral_session_writable(session_id))
  with check (aral_session_writable(session_id));

alter table public.aral_sessions enable row level security;
alter table public.aral_attendance enable row level security;
revoke all on public.aral_sessions, public.aral_attendance from anon;
