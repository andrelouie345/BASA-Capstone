-- ARAL memo rules as school settings (Division Memorandum 180 s. 2026,
-- Valencia City; spec docs/superpowers/specs/2026-11-18-aral-division-memo-design.md,
-- plan docs/superpowers/plans/2026-11-18-aral-memo-a-settings.md, Task 2).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261114010000.
-- App update required on all devices: yes (a rule change: an older app does
-- not know the new settings, so it would let a tutor save work the server
-- now refuses, e.g. a 12th learner in a class of at most 10).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Every DepEd-given ARAL number the Division memo changes becomes an
-- aral_settings key. Absent key = today's rule, so a school outside the
-- Division sees no change. A school's row wins over the default row
-- (school_id null), which wins over the built-in default. The app reads the
-- same keys (lib/core/services/aral_rule_settings.dart):
--   class_max_learners          1-50, default 15 (checked here: the class cap)
--   class_min_learners          0-50, 0 = none, <= the maximum (app notice only)
--   session_max_minutes         1-120, absent = today (checked here)
--   sessions_weekdays_only      true/false, default false (checked here)
--   class_min_sessions_per_week 0-7, default 0 (app reminder only)
--   basis_round                 'bosy' / 'mosy', default 'bosy' (app only)
--   checkin_after_sessions      [first, second], increasing, 1-200,
--                               default [16, 32] (app only)
--   irip_weeks                  1-26, default 8 (checked here)
-- session_max_minutes stops at 120 (not 240 as the spec first said) because
-- aral_sessions.minutes is limited to 1-120 in both databases.
--
-- Changes:
--   1. CHECK constraints on aral_settings, one per key (CASE keeps the type
--      test before the cast).
--   2. aral_setting(school, key): the value that counts for a school.
--   3. The class cap (constraint trigger aral_enrollments_class_cap, still
--      deferred by sync_apply) reads class_max_learners. Only taking a new
--      place is checked: a learner who keeps their place, an exit, an
--      attendance mark or an edit in a class over a lowered maximum still
--      saves.
--   4. Sessions: an insert, or an update that changes the date, minutes or
--      set-up, is refused on a Saturday/Sunday or with the weekend set-up
--      when the school holds sessions on weekdays only, and above the
--      school's longest session. Saved sessions are not re-checked.
--   5. IRIP: weeks 1-26 in the table; a new week above the school's cycle
--      length is refused. Saved weeks stay when the length is lowered.
-- Stops (changes nothing) when a stored value of a new key breaks its check.
-- RLS: unchanged (aral_settings, aral_enrollments, aral_sessions and
-- aral_irip_weeks keep their policies; the new function only reads
-- aral_settings, whose rows every signed-in user of the school may read).

-- 0. Existing values must fit the new checks.
do $$
declare
  bad text;
begin
  select string_agg(format('id %s (school %s): %s', id, coalesce(school_id::text, 'region'),
                           settings - array(select k from jsonb_object_keys(settings) k
                                            where k not in ('class_max_learners', 'class_min_learners',
                                              'session_max_minutes', 'sessions_weekdays_only',
                                              'class_min_sessions_per_week', 'basis_round',
                                              'checkin_after_sessions', 'irip_weeks'))),
                    '; ' order by id)
    into bad
    from public.aral_settings
   where settings ?| array['class_max_learners', 'class_min_learners', 'session_max_minutes',
                           'sessions_weekdays_only', 'class_min_sessions_per_week', 'basis_round',
                           'checkin_after_sessions', 'irip_weeks'];
  if bad is not null then
    raise notice 'aral_settings rows with ARAL memo keys (checked by the constraints below): %', bad;
  end if;
end $$;

-- 1. One CHECK per key.
alter table public.aral_settings drop constraint if exists aral_settings_class_max;
alter table public.aral_settings add constraint aral_settings_class_max check (
  case
    when not (settings ? 'class_max_learners') then true
    when jsonb_typeof(settings -> 'class_max_learners') <> 'number' then false
    else (settings ->> 'class_max_learners')::numeric between 1 and 50
         and (settings ->> 'class_max_learners')::numeric = trunc((settings ->> 'class_max_learners')::numeric)
  end);

alter table public.aral_settings drop constraint if exists aral_settings_class_min;
alter table public.aral_settings add constraint aral_settings_class_min check (
  case
    when not (settings ? 'class_min_learners') then true
    when jsonb_typeof(settings -> 'class_min_learners') <> 'number' then false
    when not ((settings ->> 'class_min_learners')::numeric between 0 and 50
              and (settings ->> 'class_min_learners')::numeric = trunc((settings ->> 'class_min_learners')::numeric))
      then false
    -- the same row's maximum; a maximum on another row is checked by the app
    when jsonb_typeof(settings -> 'class_max_learners') = 'number'
      then (settings ->> 'class_min_learners')::numeric <= (settings ->> 'class_max_learners')::numeric
    else true
  end);

alter table public.aral_settings drop constraint if exists aral_settings_session_max_minutes;
alter table public.aral_settings add constraint aral_settings_session_max_minutes check (
  case
    when not (settings ? 'session_max_minutes') then true
    when jsonb_typeof(settings -> 'session_max_minutes') <> 'number' then false
    else (settings ->> 'session_max_minutes')::numeric between 1 and 120
         and (settings ->> 'session_max_minutes')::numeric = trunc((settings ->> 'session_max_minutes')::numeric)
  end);

alter table public.aral_settings drop constraint if exists aral_settings_weekdays_only;
alter table public.aral_settings add constraint aral_settings_weekdays_only check (
  not (settings ? 'sessions_weekdays_only') or jsonb_typeof(settings -> 'sessions_weekdays_only') = 'boolean');

alter table public.aral_settings drop constraint if exists aral_settings_min_sessions_week;
alter table public.aral_settings add constraint aral_settings_min_sessions_week check (
  case
    when not (settings ? 'class_min_sessions_per_week') then true
    when jsonb_typeof(settings -> 'class_min_sessions_per_week') <> 'number' then false
    else (settings ->> 'class_min_sessions_per_week')::numeric between 0 and 7
         and (settings ->> 'class_min_sessions_per_week')::numeric
             = trunc((settings ->> 'class_min_sessions_per_week')::numeric)
  end);

alter table public.aral_settings drop constraint if exists aral_settings_basis_round;
alter table public.aral_settings add constraint aral_settings_basis_round check (
  not (settings ? 'basis_round')
  or (jsonb_typeof(settings -> 'basis_round') = 'string' and settings ->> 'basis_round' in ('bosy', 'mosy')));

alter table public.aral_settings drop constraint if exists aral_settings_checkin_after_sessions;
alter table public.aral_settings add constraint aral_settings_checkin_after_sessions check (
  case
    when not (settings ? 'checkin_after_sessions') then true
    when jsonb_typeof(settings -> 'checkin_after_sessions') <> 'array' then false
    when jsonb_array_length(settings -> 'checkin_after_sessions') <> 2 then false
    when jsonb_typeof(settings -> 'checkin_after_sessions' -> 0) <> 'number'
      or jsonb_typeof(settings -> 'checkin_after_sessions' -> 1) <> 'number' then false
    else (settings -> 'checkin_after_sessions' ->> 0)::numeric between 1 and 200
         and (settings -> 'checkin_after_sessions' ->> 1)::numeric between 1 and 200
         and (settings -> 'checkin_after_sessions' ->> 0)::numeric
             = trunc((settings -> 'checkin_after_sessions' ->> 0)::numeric)
         and (settings -> 'checkin_after_sessions' ->> 1)::numeric
             = trunc((settings -> 'checkin_after_sessions' ->> 1)::numeric)
         and (settings -> 'checkin_after_sessions' ->> 0)::numeric
             < (settings -> 'checkin_after_sessions' ->> 1)::numeric
  end);

alter table public.aral_settings drop constraint if exists aral_settings_irip_weeks;
alter table public.aral_settings add constraint aral_settings_irip_weeks check (
  case
    when not (settings ? 'irip_weeks') then true
    when jsonb_typeof(settings -> 'irip_weeks') <> 'number' then false
    else (settings ->> 'irip_weeks')::numeric between 1 and 26
         and (settings ->> 'irip_weeks')::numeric = trunc((settings ->> 'irip_weeks')::numeric)
  end);

-- 2. The value that counts for a school: its own row, else the default row,
-- else null (the caller applies the built-in default).
create or replace function public.aral_setting(p_school_id bigint, p_key text)
 returns jsonb language sql stable security definer set search_path to 'public'
as $$
  select coalesce(
    (select settings -> p_key from public.aral_settings
      where school_id = p_school_id and settings ? p_key),
    (select settings -> p_key from public.aral_settings
      where school_id is null and settings ? p_key));
$$;

revoke all on function public.aral_setting(bigint, text) from public, anon;
grant execute on function public.aral_setting(bigint, text) to authenticated, service_role;

-- A whole-number setting, or the built-in default.
create or replace function basa_private.aral_setting_int(p_school_id bigint, p_key text, p_default integer)
 returns integer language sql stable security definer set search_path to 'public'
as $$
  select coalesce((public.aral_setting(p_school_id, p_key) #>> '{}')::numeric::integer, p_default);
$$;

revoke all on function basa_private.aral_setting_int(bigint, text, integer) from public, anon, authenticated;

-- 3. The class cap (as in 20261024050000, with the school's maximum).
create or replace function public.aral_enrollments_class_cap()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_max integer;
begin
  if new.class_id is null or new.status <> 'active' then
    return null;
  end if;
  if tg_op = 'UPDATE' and new.class_id is not distinct from old.class_id and old.status = 'active'
     and (new.school_id, new.school_year) is not distinct from (old.school_id, old.school_year) then
    return null; -- kept their place
  end if;
  perform pg_advisory_xact_lock(hashtext('aral_class:' || new.class_id::text));
  v_max := basa_private.aral_setting_int(new.school_id, 'class_max_learners', 15);
  if (select count(*) from public.aral_enrollments where class_id = new.class_id and status = 'active') > v_max then
    raise exception 'an ARAL class has at most % active learners', v_max;
  end if;
  return null;
end;
$$;

-- 4. Sessions: the school's weekday and length rules.
create or replace function basa_private.aral_check_session_rules(p_school_id bigint, p_held_on date,
                                                                 p_minutes integer, p_setup text)
 returns void language plpgsql stable security definer set search_path to 'public'
as $$
declare
  v_max integer;
begin
  if coalesce((public.aral_setting(p_school_id, 'sessions_weekdays_only') #>> '{}')::boolean, false)
     and (extract(isodow from p_held_on) in (6, 7) or p_setup = 'weekend') then
    raise exception 'ARAL sessions are held Monday to Friday at this school';
  end if;
  v_max := basa_private.aral_setting_int(p_school_id, 'session_max_minutes', null);
  if v_max is not null and p_minutes > v_max then
    raise exception 'an ARAL session at this school lasts at most % minutes', v_max;
  end if;
end;
$$;

revoke all on function basa_private.aral_check_session_rules(bigint, date, integer, text)
  from public, anon, authenticated;

create or replace function public.aral_sessions_before_insert()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  c record;
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  new.created_at := now();
  new.updated_at := now();
  if new.class_id is null then
    raise exception 'a new ARAL session needs a class';
  end if;
  select school_id, school_year into c from public.aral_classes where id = new.class_id;
  if not found or c.school_id is distinct from new.school_id or c.school_year is distinct from new.school_year then
    raise exception 'the ARAL class belongs to another school or school year';
  end if;
  perform basa_private.aral_check_session_rules(new.school_id, new.held_on, new.minutes, new.setup);
  -- serialize numbering per class
  perform pg_advisory_xact_lock(hashtext('aral_class_sessions:' || new.class_id::text));
  select coalesce(max(session_no), 0) + 1 into new.session_no
  from public.aral_sessions where class_id = new.class_id;
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
  if (new.tutor_id, new.class_id, new.school_id, new.school_year, new.session_no, new.created_by, new.created_at)
     is distinct from
     (old.tutor_id, old.class_id, old.school_id, old.school_year, old.session_no, old.created_by, old.created_at) then
    raise exception 'an ARAL session keeps its tutor, class, school, year and number; only the date, minutes, set-up, lesson and remarks change';
  end if;
  if (new.held_on, new.minutes, new.setup) is distinct from (old.held_on, old.minutes, old.setup) then
    perform basa_private.aral_check_session_rules(new.school_id, new.held_on, new.minutes, new.setup);
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- 5. IRIP: weeks 1-26; a new week stays within the school's cycle length.
alter table public.aral_irip_weeks drop constraint if exists aral_irip_weeks_week_no_check;
alter table public.aral_irip_weeks add constraint aral_irip_weeks_week_no_check check (week_no between 1 and 26);

create or replace function public.aral_irip_weeks_before_write() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
declare
  v_program text;
  v_active  boolean;
  v_weeks   integer;
  t         record;
begin
  if tg_op = 'UPDATE' then
    if (new.enrollment_id, new.cycle_no, new.week_no, new.strand, new.created_by, new.created_at)
       is distinct from
       (old.enrollment_id, old.cycle_no, old.week_no, old.strand, old.created_by, old.created_at) then
      raise exception 'an IRIP week keeps its learner, cycle, week and strand; only the target, status and notes change';
    end if;
    if new.target_id is distinct from old.target_id and old.status is not null then
      raise exception 'a rated IRIP week keeps its target';
    end if;
  else
    if auth.uid() is not null then
      new.created_by := auth.uid();
    end if;
    new.created_at := now();
    v_weeks := basa_private.aral_setting_int(
      (select school_id from public.aral_enrollments where id = new.enrollment_id), 'irip_weeks', 8);
    if new.week_no > v_weeks then
      raise exception 'an IRIP cycle at this school has % weeks', v_weeks;
    end if;
    if new.week_no > 1 and not exists (
      select 1 from public.aral_irip_weeks
      where enrollment_id = new.enrollment_id and cycle_no = new.cycle_no
        and week_no = new.week_no - 1 and strand = new.strand) then
      raise exception 'an IRIP week needs the previous week of its cycle';
    end if;
  end if;
  new.updated_at := now();

  if tg_op = 'INSERT' or new.target_id is distinct from old.target_id then
    select aral_irip_program(key_stage, track), status = 'active' into v_program, v_active
    from public.aral_enrollments where id = new.enrollment_id;
    if not coalesce(v_active, false) then
      raise exception 'the learner is not active in ARAL';
    end if;
    select program, strand, is_active into t from public.aral_irip_targets where id = new.target_id;
    if v_program is null then
      raise exception 'the learner''s ARAL program has no IRIP (Foundational and KS1)';
    end if;
    if t.program is distinct from v_program or t.strand is distinct from new.strand or not t.is_active then
      raise exception 'that reading target is not in the learner''s IRIP list';
    end if;
  end if;
  return new;
end;
$$;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261118010000', 'aral_memo_settings', true)
on conflict (id) do nothing;
