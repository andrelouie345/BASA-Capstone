-- ARAL memo, people: final review fixes (plan
-- docs/superpowers/plans/2026-11-18-aral-memo-b-people-forms.md, final review
-- I2 and M1).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261118030000.
-- App update required on all devices: no (both changes only accept more:
-- an upload the server refused before, and a same-day edit).
--
--   I2. The adviser rule on placement is checked at the end of an upload, with
--       the class cap (aral_enrollments_class_cap, deferred by sync_apply),
--       instead of in the immediate placement check. An upload applies new
--       and changed learners before class changes, so a coordinator who
--       offline gave a class another tutor and then placed the old tutor's
--       advisees in it had the whole upload refused against the old tutor.
--       Direct writes are still checked at once (the constraint trigger is
--       DEFERRABLE INITIALLY IMMEDIATE). The tutor-change side
--       (aral_classes_adviser_rule) stays immediate: updates go children
--       first, so it already sees the final learners.
--   M1. The daily tutor limits on an edit of the same day check only a longer
--       session (the external tutor's minutes): the session count doesn't
--       change, so a day over a limit set later keeps its sessions editable.
--       A new date is checked in full, as before. The device (SQLite v48) and
--       the app check the same.
--
-- RLS: no table, view or policy changes. Every function keeps its owner,
-- security definer and search_path; the basa_private helper stays revoked
-- from the API roles.

-- I2. Placement without the adviser rule (as in 20261024050000).
create or replace function public.aral_check_class_placement(
  p_id bigint, p_class_id bigint, p_student_id bigint, p_section_id bigint, p_school_id bigint,
  p_school_year text, p_key_stage text, p_track text)
 returns void language plpgsql security definer set search_path to 'public'
as $$
declare
  c record;
begin
  perform pg_advisory_xact_lock(hashtext('aral_class:' || p_class_id::text));
  select school_id, school_year, program into c from public.aral_classes where id = p_class_id;
  if not found or c.school_id is distinct from p_school_id or c.school_year is distinct from p_school_year then
    raise exception 'the ARAL class belongs to another school or school year';
  end if;
  if c.program is not null and c.program is distinct from p_key_stage || coalesce('_' || p_track, '') then
    raise exception 'the learner''s program does not match the ARAL class';
  end if;
end;
$$;

-- I2. The end-state placement checks: the school's class maximum (as in
-- 20261118010000) and the adviser rule (moved here from the placement check).
create or replace function public.aral_enrollments_class_cap()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_max integer;
  v_tutor uuid;
  v_section text;
  v_learner text;
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
  -- The class's tutor at the end of the upload must not advise the learner's section.
  select tutor_id into v_tutor from public.aral_classes where id = new.class_id;
  if v_tutor is not null and not basa_private.aral_adviser_may_tutor(new.school_id) then
    select s.section_name into v_section from public.sections s
     where s.id = new.section_id and s.adviser_user_id = v_tutor;
    if found then
      select btrim(first_name || ' ' || last_name) into v_learner from public.students where id = new.student_id;
      raise exception '% of % has the class tutor as adviser: an adviser does not tutor their own learners at this school',
        coalesce(v_learner, 'the learner'), v_section;
    end if;
  end if;
  return null;
end;
$$;

-- M1. The daily limits; p_minutes_only = an edit of the same day that made a
-- session longer: only the external tutor's minutes are checked.
create or replace function basa_private.aral_check_tutor_day(p_tutor_id uuid, p_school_id bigint, p_held_on date,
                                                             p_minutes_only boolean)
 returns void language plpgsql security definer set search_path to 'public'
as $$
declare
  v_type text;
  v_max integer;
  v_used integer;
begin
  select tutor_type into v_type from public.users where id = p_tutor_id;
  if v_type = 'internal' and not p_minutes_only then
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

revoke all on function basa_private.aral_check_tutor_day(uuid, bigint, date, boolean) from public, anon, authenticated;

create or replace function public.aral_sessions_one_per_day()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.class_id is not null and (tg_op = 'INSERT' or new.held_on is distinct from old.held_on) then
    perform pg_advisory_xact_lock(hashtext('aral_class_sessions:' || new.class_id::text));
    perform aral_check_session_day(new.id, new.class_id, new.held_on);
  end if;
  if tg_op = 'INSERT' or new.held_on is distinct from old.held_on then
    perform pg_advisory_xact_lock(hashtext('aral_tutor_day:' || new.tutor_id::text || ':' || new.held_on::text));
    perform basa_private.aral_check_tutor_day(new.tutor_id, new.school_id, new.held_on, false);
  elsif new.minutes > old.minutes then
    perform pg_advisory_xact_lock(hashtext('aral_tutor_day:' || new.tutor_id::text || ':' || new.held_on::text));
    perform basa_private.aral_check_tutor_day(new.tutor_id, new.school_id, new.held_on, true);
  end if;
  return null;
end;
$$;

-- The three-argument helper of 20261118030000 is no longer called.
drop function if exists basa_private.aral_check_tutor_day(uuid, bigint, date);

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261119010000', 'aral_memo_review', false)
on conflict (id) do nothing;
