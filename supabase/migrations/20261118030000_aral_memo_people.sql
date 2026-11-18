-- ARAL memo, people: section advisers, tutor type and class session type, with
-- their rules (Division Memorandum 180 s. 2026; spec
-- docs/superpowers/specs/2026-11-18-aral-division-memo-design.md sections 3
-- and 6, plan docs/superpowers/plans/2026-11-18-aral-memo-b-people-forms.md,
-- Task 1).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261118020000.
-- App update required on all devices: yes (new refusals: an older app would
-- let a tutor save a session or a placement the server now refuses).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- New columns (all optional):
--   sections.adviser_name      the adviser's name as the school writes it
--   sections.adviser_user_id   the adviser when they have a BASA account; a
--                              user of the section's school (checked when it
--                              is written; a user who later moves school or
--                              is turned off keeps the link and still counts
--                              as the adviser until the coordinator changes it)
--   users.tutor_type           'internal' (a teacher of the school) /
--                              'external'; null = no daily limit
--   aral_classes.session_type  'pull_out' / 'before_after' (ARAL Form 1)
-- New aral_settings keys (absent = today's behaviour):
--   adviser_tutors_own_class             true/false, default true (allowed)
--   internal_tutor_max_sessions_per_day  1-10, absent = no limit
--   external_tutor_max_minutes_per_day   1-600, absent = no limit
--
-- Changes:
--   1. The columns and their CHECKs; the setting CHECKs.
--   2. sections: the adviser must be a user of the section's school.
--   3. Adviser rule (adviser_tutors_own_class false): placing a learner in a
--      class whose tutor advises the learner's home section is refused
--      (aral_check_class_placement), and so is giving a class a tutor who
--      advises the home section of one of its active learners (new trigger
--      aral_classes_adviser_rule). Setting a section's adviser is never
--      refused (owner 2026-11-18), so a coordinator can always fix it.
--   4. Daily tutor limits: sessions held by a tutor (aral_sessions.tutor_id)
--      on one date at one school; an internal tutor at most N sessions, an
--      external tutor at most N minutes. Checked at the end state inside the
--      existing constraint trigger aral_sessions_one_per_day (deferrable,
--      already deferred by sync_apply while it writes an upload, so an
--      offline swap of dates applies), serialized per tutor and date. Only a
--      new session or a changed date or length is checked: a saved day is not
--      re-checked when a tutor's type or the limit changes.
--   5. users.tutor_type may be updated through the API (column grant beside
--      is_active).
-- RLS: reviewed, unchanged.
--   sections: writes stay admin/coordinator of the school and superadmin
--     (sections_*_scoped); tutors still only read their sections.
--   users: users_update_scoped already limits updates to admin/coordinator of
--     the user's school (and superadmin) and never one's own row, so a tutor
--     can't change their own type; only the column grant is added.
--   aral_classes, aral_sessions, aral_enrollments, aral_settings: policies
--     unchanged; the new checks run in SECURITY DEFINER triggers.

-- 0. Existing values must fit the new setting checks.
do $$
declare
  bad text;
begin
  select string_agg(format('id %s (school %s)', id, coalesce(school_id::text, 'region')), '; ' order by id)
    into bad
    from public.aral_settings
   where settings ?| array['adviser_tutors_own_class', 'internal_tutor_max_sessions_per_day',
                           'external_tutor_max_minutes_per_day'];
  if bad is not null then
    raise notice 'aral_settings rows with ARAL memo people keys (checked by the constraints below): %', bad;
  end if;
end $$;

-- 1. Columns and checks.
alter table public.sections add column if not exists adviser_name text;
alter table public.sections add column if not exists adviser_user_id uuid
  references public.users (id) on delete set null;
alter table public.sections drop constraint if exists sections_adviser_name_check;
alter table public.sections add constraint sections_adviser_name_check
  check (adviser_name is null or btrim(adviser_name) <> '');

alter table public.users add column if not exists tutor_type text;
alter table public.users drop constraint if exists users_tutor_type_check;
alter table public.users add constraint users_tutor_type_check
  check (tutor_type is null or tutor_type in ('internal', 'external'));

alter table public.aral_classes add column if not exists session_type text;
alter table public.aral_classes drop constraint if exists aral_classes_session_type_check;
alter table public.aral_classes add constraint aral_classes_session_type_check
  check (session_type is null or session_type in ('pull_out', 'before_after'));

create index if not exists sections_adviser_user on public.sections (adviser_user_id)
  where adviser_user_id is not null;
create index if not exists aral_sessions_tutor_day on public.aral_sessions (tutor_id, held_on);

alter table public.aral_settings drop constraint if exists aral_settings_adviser_tutors_own_class;
alter table public.aral_settings add constraint aral_settings_adviser_tutors_own_class check (
  not (settings ? 'adviser_tutors_own_class') or jsonb_typeof(settings -> 'adviser_tutors_own_class') = 'boolean');

alter table public.aral_settings drop constraint if exists aral_settings_internal_tutor_day;
alter table public.aral_settings add constraint aral_settings_internal_tutor_day check (
  case
    when not (settings ? 'internal_tutor_max_sessions_per_day') then true
    when jsonb_typeof(settings -> 'internal_tutor_max_sessions_per_day') <> 'number' then false
    else (settings ->> 'internal_tutor_max_sessions_per_day')::numeric between 1 and 10
         and (settings ->> 'internal_tutor_max_sessions_per_day')::numeric
             = trunc((settings ->> 'internal_tutor_max_sessions_per_day')::numeric)
  end);

alter table public.aral_settings drop constraint if exists aral_settings_external_tutor_day;
alter table public.aral_settings add constraint aral_settings_external_tutor_day check (
  case
    when not (settings ? 'external_tutor_max_minutes_per_day') then true
    when jsonb_typeof(settings -> 'external_tutor_max_minutes_per_day') <> 'number' then false
    else (settings ->> 'external_tutor_max_minutes_per_day')::numeric between 1 and 600
         and (settings ->> 'external_tutor_max_minutes_per_day')::numeric
             = trunc((settings ->> 'external_tutor_max_minutes_per_day')::numeric)
  end);

-- 2. A section's adviser is a user of the section's school.
create or replace function public.sections_adviser_same_school()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.adviser_user_id is not null
     and (tg_op = 'INSERT' or new.adviser_user_id is distinct from old.adviser_user_id
          or new.school_id is distinct from old.school_id)
     and not exists (select 1 from public.users where id = new.adviser_user_id and school_id = new.school_id) then
    raise exception 'a section''s adviser must be a user of the section''s school';
  end if;
  return new;
end;
$$;

drop trigger if exists sections_adviser_same_school on public.sections;
create trigger sections_adviser_same_school before insert or update on public.sections
  for each row execute function public.sections_adviser_same_school();

-- 3. The adviser rule.
-- True when the school lets an adviser tutor their own learners (the default).
create or replace function basa_private.aral_adviser_may_tutor(p_school_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select coalesce((basa_private.aral_setting(p_school_id, 'adviser_tutors_own_class') #>> '{}')::boolean, true);
$$;

revoke all on function basa_private.aral_adviser_may_tutor(bigint) from public, anon, authenticated;

-- Placement (as in 20261024050000, plus the adviser rule).
create or replace function public.aral_check_class_placement(
  p_id bigint, p_class_id bigint, p_student_id bigint, p_section_id bigint, p_school_id bigint,
  p_school_year text, p_key_stage text, p_track text)
 returns void language plpgsql security definer set search_path to 'public'
as $$
declare
  c record;
  v_learner text;
  v_section text;
begin
  perform pg_advisory_xact_lock(hashtext('aral_class:' || p_class_id::text));
  select school_id, school_year, program, tutor_id into c from public.aral_classes where id = p_class_id;
  if not found or c.school_id is distinct from p_school_id or c.school_year is distinct from p_school_year then
    raise exception 'the ARAL class belongs to another school or school year';
  end if;
  if c.program is not null and c.program is distinct from p_key_stage || coalesce('_' || p_track, '') then
    raise exception 'the learner''s program does not match the ARAL class';
  end if;
  if c.tutor_id is not null and not basa_private.aral_adviser_may_tutor(p_school_id) then
    select s.section_name into v_section from public.sections s
     where s.id = p_section_id and s.adviser_user_id = c.tutor_id;
    if found then
      select btrim(first_name || ' ' || last_name) into v_learner from public.students where id = p_student_id;
      raise exception '% of % has the class tutor as adviser: an adviser does not tutor their own learners at this school',
        coalesce(v_learner, 'the learner'), v_section;
    end if;
  end if;
end;
$$;

-- A class's new tutor must not advise the home section of one of its active learners.
create or replace function public.aral_classes_adviser_rule()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  r record;
begin
  if new.tutor_id is null or new.tutor_id is not distinct from old.tutor_id
     or basa_private.aral_adviser_may_tutor(new.school_id) then
    return new;
  end if;
  select btrim(st.first_name || ' ' || st.last_name) as learner, s.section_name into r
    from public.aral_enrollments e
    join public.sections s on s.id = e.section_id
    join public.students st on st.id = e.student_id
   where e.class_id = new.id and e.status = 'active' and s.adviser_user_id = new.tutor_id
   order by st.last_name, st.first_name
   limit 1;
  if found then
    raise exception 'the new tutor is the adviser of % (%): an adviser does not tutor their own learners at this school',
      r.learner, r.section_name;
  end if;
  return new;
end;
$$;

drop trigger if exists aral_classes_adviser_rule on public.aral_classes;
create trigger aral_classes_adviser_rule before update of tutor_id on public.aral_classes
  for each row execute function public.aral_classes_adviser_rule();

-- 4. Daily tutor limits, checked at the end state.
create or replace function basa_private.aral_check_tutor_day(p_tutor_id uuid, p_school_id bigint, p_held_on date)
 returns void language plpgsql security definer set search_path to 'public'
as $$
declare
  v_type text;
  v_max integer;
  v_used integer;
begin
  select tutor_type into v_type from public.users where id = p_tutor_id;
  if v_type = 'internal' then
    v_max := basa_private.aral_setting_int(p_school_id, 'internal_tutor_max_sessions_per_day', null);
    if v_max is null then
      return;
    end if;
    select count(*) into v_used from public.aral_sessions
     where tutor_id = p_tutor_id and school_id = p_school_id and held_on = p_held_on;
    if v_used > v_max then
      raise exception 'an internal tutor holds at most % ARAL sessions a day at this school (% on %)',
        v_max, v_used, p_held_on;
    end if;
  elsif v_type = 'external' then
    v_max := basa_private.aral_setting_int(p_school_id, 'external_tutor_max_minutes_per_day', null);
    if v_max is null then
      return;
    end if;
    select coalesce(sum(minutes), 0) into v_used from public.aral_sessions
     where tutor_id = p_tutor_id and school_id = p_school_id and held_on = p_held_on;
    if v_used > v_max then
      raise exception 'an external tutor holds at most % minutes of ARAL sessions a day at this school (% on %)',
        v_max, v_used, p_held_on;
    end if;
  end if;
end;
$$;

revoke all on function basa_private.aral_check_tutor_day(uuid, bigint, date) from public, anon, authenticated;

-- The end-state session checks (one per class per date, as in 20261024050000;
-- now also the tutor's daily limit). The name stays because sync_apply defers
-- this trigger by name.
create or replace function public.aral_sessions_one_per_day()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.class_id is not null and (tg_op = 'INSERT' or new.held_on is distinct from old.held_on) then
    perform pg_advisory_xact_lock(hashtext('aral_class_sessions:' || new.class_id::text));
    perform aral_check_session_day(new.id, new.class_id, new.held_on);
  end if;
  if tg_op = 'INSERT' or (new.held_on, new.minutes) is distinct from (old.held_on, old.minutes) then
    perform pg_advisory_xact_lock(hashtext('aral_tutor_day:' || new.tutor_id::text || ':' || new.held_on::text));
    perform basa_private.aral_check_tutor_day(new.tutor_id, new.school_id, new.held_on);
  end if;
  return null;
end;
$$;

-- 5. Admins and coordinators set a user's tutor type through the API.
revoke update on public.users from authenticated;
grant update (is_active, tutor_type) on public.users to authenticated;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261118030000', 'aral_memo_people', true)
on conflict (id) do nothing;
