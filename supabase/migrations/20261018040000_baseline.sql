-- BASA baseline: the complete database schema (public) as of 2026-10-18.
--
-- A NEW deployment runs this file first, then every migration in this folder
-- that is newer than it, then the seeds (README, section 2). An existing
-- project that already has this schema runs nothing.
--
-- Generated from a schema-only pg_dump of the live project (sample-files/db/
-- baseline_dump.sql) and checked: built on an empty Postgres, run twice, then
-- re-dumped and compared with the live dump object by object (503 objects
-- identical; the only differences are formatting). Idempotent: safe to run
-- more than once.
--
-- Squashes the 29 migrations of 2026-10-12..18, which are kept in
-- supabase/migrations_archive/ as history: they could not build a fresh
-- database on their own (the core tables, the CRLA tables/views and some
-- functions were first created by hand, before migrations were tracked).
--
-- Left out: testTable (dev-only) and rls_auto_enable() (Supabase's own
-- "automatically enable RLS" setting). Data is not included: the regions,
-- check-in tools, IRIP targets and Phil-IRI passages come from supabase/seeds/.
--
-- RLS: every table has RLS enabled with its live policies; all views are
-- security_invoker; SECURITY DEFINER functions set search_path. The last
-- section re-applies the migrations' GRANT/REVOKE statements (anon gets nothing
-- on the module tables, some functions are callable by no client role).

SET check_function_bodies = false;


-- functions --------------------------------------------------------------

-- aral_check_session_day(bigint, uuid, date)
CREATE OR REPLACE FUNCTION public.aral_check_session_day(p_id bigint, p_tutor_id uuid, p_held_on date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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

-- aral_check_tutor(uuid, bigint)
CREATE OR REPLACE FUNCTION public.aral_check_tutor(p_tutor_id uuid, p_school_id bigint) RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if p_tutor_id is null or auth.uid() is null then
    return;
  end if;
  if not (is_superadmin() or p_school_id = current_user_school_id()) then
    return;
  end if;
  if not exists (
    select 1 from public.users
    where id = p_tutor_id and role = 'tutor' and is_active and school_id = p_school_id
  ) then
    raise exception 'the ARAL tutor must be an active tutor of the learner''s school';
  end if;
end;
$$;

-- aral_checkin_answers_before_write()
CREATE OR REPLACE FUNCTION public.aral_checkin_answers_before_write() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
declare
  i record;
begin
  if tg_op = 'UPDATE' and (new.checkin_id, new.item_id, new.created_at)
     is distinct from (old.checkin_id, old.item_id, old.created_at) then
    raise exception 'an answer keeps its check-in and item; only the response and mark change';
  end if;

  select it.kind, it.answer_key into i
  from public.aral_checkin_items it
  join public.aral_checkins c on c.tool_id = it.tool_id
  where it.id = new.item_id and c.id = new.checkin_id;
  if not found then
    raise exception 'that item is not on the check-in''s tool';
  end if;

  if i.kind = 'choice' then
    new.response := nullif(upper(btrim(new.response)), '');
    if new.response is not null and new.response !~ '^[A-E]$' then
      raise exception 'a multiple-choice answer is a letter A-E (or empty)';
    end if;
    new.is_correct := coalesce(new.response = i.answer_key, false);
  elsif new.is_correct is null then
    raise exception 'an open item needs a right/wrong mark';
  end if;

  if tg_op = 'INSERT' then
    new.created_at := now();
  end if;
  new.updated_at := now();
  return new;
end;
$_$;

-- aral_checkin_readable(bigint)
CREATE OR REPLACE FUNCTION public.aral_checkin_readable(p_checkin_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (select 1 from public.aral_checkins c
                 where c.id = p_checkin_id and aral_enrollment_readable(c.enrollment_id));
$$;

-- aral_checkin_writable(bigint)
CREATE OR REPLACE FUNCTION public.aral_checkin_writable(p_checkin_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (select 1 from public.aral_checkins c
                 where c.id = p_checkin_id and aral_irip_writable(c.enrollment_id));
$$;

-- aral_checkins_before_write()
CREATE OR REPLACE FUNCTION public.aral_checkins_before_write() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  e record;
  t record;
begin
  if tg_op = 'UPDATE' then
    if (new.enrollment_id, new.tool_id, new.attempt_no, new.created_by, new.created_at)
       is distinct from
       (old.enrollment_id, old.tool_id, old.attempt_no, old.created_by, old.created_at) then
      raise exception 'a check-in keeps its learner, tool and attempt; only the date and notes change';
    end if;
  end if;

  -- Locked so two check-ins of one learner get distinct attempt numbers.
  select status, key_stage, track, entered_on into e
  from public.aral_enrollments where id = new.enrollment_id for update;

  if tg_op = 'INSERT' then
    if e.status is distinct from 'active' then
      raise exception 'the learner is not active in ARAL';
    end if;
    select key_stage, track, is_active into t from public.aral_checkin_tools where id = new.tool_id;
    if t.key_stage is distinct from e.key_stage or t.track is distinct from e.track or not t.is_active then
      raise exception 'that check-in tool is not for the learner''s ARAL program';
    end if;
    select coalesce(max(attempt_no), 0) + 1 into new.attempt_no
    from public.aral_checkins
    where enrollment_id = new.enrollment_id and tool_id = new.tool_id;
    if auth.uid() is not null then
      new.created_by := auth.uid();
    end if;
    new.created_at := now();
  end if;

  if new.taken_on < e.entered_on then
    raise exception 'a check-in cannot be dated before the learner entered ARAL';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- aral_enrollment_readable(bigint)
CREATE OR REPLACE FUNCTION public.aral_enrollment_readable(p_enrollment_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.aral_enrollments e
    where e.id = p_enrollment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and e.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and (e.tutor_id = auth.uid() or tutor_has_section(e.section_id))))
  );
$$;

-- aral_enrollments_before_insert()
CREATE OR REPLACE FUNCTION public.aral_enrollments_before_insert() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
    new.status := 'active';
    new.exited_on := null;
    new.exit_reason := null;
  end if;
  new.created_at := now();
  new.updated_at := now();
  perform aral_check_tutor(new.tutor_id, new.school_id);
  return new;
end;
$$;

-- aral_enrollments_before_update()
CREATE OR REPLACE FUNCTION public.aral_enrollments_before_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  -- The cap holds for SQL Editor maintenance too.
  if new.status = 'active' and (old.status <> 'active' or new.section_id is distinct from old.section_id
                                or new.school_year is distinct from old.school_year) then
    perform aral_check_section_cap(new.id, new.section_id, new.school_year);
  end if;
  if auth.uid() is null then
    return new; -- SQL Editor maintenance
  end if;
  if (new.student_id, new.school_id, new.school_year, new.basis_source, new.basis_round, new.basis_level,
      new.basis_assessment_id, new.created_by, new.created_at)
     is distinct from
     (old.student_id, old.school_id, old.school_year, old.basis_source, old.basis_round, old.basis_level,
      old.basis_assessment_id, old.created_by, old.created_at) then
    raise exception 'an ARAL enrollment keeps its learner, school, year and basis; only the placement, tutor, status and notes change';
  end if;
  if new.tutor_id is distinct from old.tutor_id then
    perform aral_check_tutor(new.tutor_id, new.school_id);
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- aral_irip_program(text, text)
CREATE OR REPLACE FUNCTION public.aral_irip_program(p_key_stage text, p_track text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select case
    when p_key_stage in ('ks2', 'ks3') and p_track = 'basic' then 'basic_ks23'
    when p_key_stage = 'ks2' and p_track = 'plus' then 'plus_ks2'
    when p_key_stage = 'ks3' and p_track = 'plus' then 'plus_ks3'
  end;
$$;

-- aral_irip_weeks_before_write()
CREATE OR REPLACE FUNCTION public.aral_irip_weeks_before_write() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_program text;
  v_active  boolean;
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

-- aral_irip_writable(bigint)
CREATE OR REPLACE FUNCTION public.aral_irip_writable(p_enrollment_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.aral_enrollments e
    where e.id = p_enrollment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and e.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and e.tutor_id = auth.uid()))
  );
$$;

-- aral_material_links_stamp()
CREATE OR REPLACE FUNCTION public.aral_material_links_stamp() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  new.updated_at := now();
  if auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

-- aral_material_visible_to_school(bigint, bigint)
CREATE OR REPLACE FUNCTION public.aral_material_visible_to_school(p_material_id bigint, p_school_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.aral_materials m
    where m.id = p_material_id and (m.school_id is null or m.school_id = p_school_id)
  );
$$;

-- aral_materials_stamp()
CREATE OR REPLACE FUNCTION public.aral_materials_stamp() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.created_at := now();
    if auth.uid() is not null then
      new.created_by := auth.uid();
    end if;
  else
    new.created_by := old.created_by;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

-- aral_session_readable(bigint)
CREATE OR REPLACE FUNCTION public.aral_session_readable(p_session_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.aral_sessions s
    where s.id = p_session_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and s.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and s.tutor_id = auth.uid()))
  );
$$;

-- aral_session_writable(bigint)
CREATE OR REPLACE FUNCTION public.aral_session_writable(p_session_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.aral_session_readable(p_session_id);
$$;

-- aral_sessions_before_insert()
CREATE OR REPLACE FUNCTION public.aral_sessions_before_insert() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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

-- aral_sessions_before_update()
CREATE OR REPLACE FUNCTION public.aral_sessions_before_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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

-- aral_settings_stamp()
CREATE OR REPLACE FUNCTION public.aral_settings_stamp() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  new.updated_at := now();
  if auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

-- aral_tutor_settings_before_write()
CREATE OR REPLACE FUNCTION public.aral_tutor_settings_before_write() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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

-- check_aral_attendance()
CREATE OR REPLACE FUNCTION public.check_aral_attendance() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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

-- check_crla_part1_variant()
CREATE OR REPLACE FUNCTION public.check_crla_part1_variant() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_variant text;
begin
  if auth.uid() is not null and not crla_assessment_writable(new.assessment_id) then
    raise exception 'new row violates row-level security policy for table "%"', tg_table_name
      using errcode = '42501';
  end if;

  select subject_variant into v_variant
  from public.crla_assessments where id = new.assessment_id;

  if v_variant is null then
    raise exception 'crla_assessments % does not exist', new.assessment_id;
  end if;

  if not (v_variant = any(tg_argv)) then
    raise exception '% requires subject_variant in (%), but assessment % is %',
      tg_table_name, array_to_string(tg_argv, ', '), new.assessment_id, v_variant;
  end if;

  return new;
end;
$$;

-- check_crla_part2_limits()
CREATE OR REPLACE FUNCTION public.check_crla_part2_limits() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
declare
  v_grade int;
  v_variant text;
  v_max int;
  v_cap int;
begin
  -- Answer like RLS first, so the limits below don't reveal other schools' rows.
  if auth.uid() is not null and not crla_assessment_writable(new.assessment_id) then
    raise exception 'new row violates row-level security policy for table "%"', tg_table_name
      using errcode = '42501';
  end if;

  select (case when sec.grade_level ~ '^[0-9]+$' then sec.grade_level::int end), ca.subject_variant into v_grade, v_variant
  from public.crla_assessments ca
  join public.sections sec on sec.id = ca.section_id
  where ca.id = new.assessment_id;

  if not found then
    raise exception 'crla_assessments % does not exist', new.assessment_id;
  end if;

  v_max := crla_comprehension_max(v_grade, v_variant);
  if new.comprehension_correct > v_max then
    raise exception 'comprehension_correct % is above the Grade % % maximum of %',
      new.comprehension_correct, v_grade, v_variant, v_max using errcode = '23514';
  end if;

  v_cap := crla_time_cap_seconds(v_grade, v_variant);
  if new.time_minutes * 60 + new.time_seconds > v_cap then
    raise exception 'reading time %:% is over the Grade % % limit of % seconds',
      new.time_minutes, lpad(new.time_seconds::text, 2, '0'), v_grade, v_variant, v_cap
      using errcode = '23514';
  end if;

  return new;
end;
$_$;

-- check_phil_iri_answer()
CREATE OR REPLACE FUNCTION public.check_phil_iri_answer() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_key text;
  v_ok boolean;
begin
  if auth.uid() is not null and not phil_iri_reading_writable(new.reading_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select q.answer_key, q.passage_id = r.passage_id into v_key, v_ok
  from public.phil_iri_questions q, public.phil_iri_readings r
  where q.id = new.question_id and r.id = new.reading_id;
  if not coalesce(v_ok, false) then
    raise exception 'question % is not a question of this reading''s passage', new.question_id;
  end if;
  new.is_correct := new.chosen is not null and new.chosen = v_key;
  return new;
end;
$$;

-- check_phil_iri_miscue()
CREATE OR REPLACE FUNCTION public.check_phil_iri_miscue() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_words integer;
  v_method text;
begin
  if auth.uid() is null then
    return new;
  end if;
  if not phil_iri_reading_writable(new.reading_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select p.word_count, r.method into v_words, v_method
  from public.phil_iri_readings r join public.phil_iri_passages p on p.id = r.passage_id
  where r.id = new.reading_id;
  if v_method = 'silent' then
    raise exception 'a silent reading has no miscues';
  end if;
  -- An insertion may sit after the last word (index = word count).
  if new.word_index > v_words or (new.miscue_type <> 'insertion' and new.word_index >= v_words) then
    raise exception 'word % is outside the passage (% words)', new.word_index, v_words;
  end if;
  return new;
end;
$$;

-- check_phil_iri_passage_level()
CREATE OR REPLACE FUNCTION public.check_phil_iri_passage_level() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_graded boolean;
begin
  if auth.uid() is not null and not phil_iri_collection_writable(new.collection_id) then
    raise exception 'new row violates row-level security policy for table "%"', tg_table_name
      using errcode = '42501';
  end if;
  select is_grade_leveled into v_graded
  from public.phil_iri_collections where id = new.collection_id;
  if v_graded and new.level is null then
    raise exception 'a passage in a grade-leveled collection needs a level';
  end if;
  if not v_graded and new.level is not null then
    raise exception 'a passage in a non-graded collection has no level';
  end if;
  return new;
end;
$$;

-- check_phil_iri_reading()
CREATE OR REPLACE FUNCTION public.check_phil_iri_reading() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_level integer;
  v_graded boolean;
  v_active boolean;
  v_grade integer;
  v_test_type text;
  v_round text;
  v_year text;
  v_student bigint;
  v_read_title text;
begin
  if auth.uid() is null then
    return new;
  end if;
  if not phil_iri_assessment_writable(new.assessment_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  if tg_op = 'UPDATE' and (new.assessment_id, new.passage_id, new.method)
                          is distinct from (old.assessment_id, old.passage_id, old.method) then
    raise exception 'a reading keeps its session, passage and method; delete it and add a new one instead';
  end if;
  if not phil_iri_passage_readable(new.passage_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select p.level, c.is_grade_leveled, p.is_active and c.is_active, p.test_type
    into v_level, v_graded, v_active, v_test_type
  from public.phil_iri_passages p
  join public.phil_iri_collections c on c.id = p.collection_id
  where p.id = new.passage_id;
  if tg_op = 'INSERT' and not v_active then
    raise exception 'this passage or its collection is not active';
  end if;
  if v_graded then
    select phil_iri_section_grade(a.section_id) into v_grade
    from public.phil_iri_assessments a where a.id = new.assessment_id;
    if v_level is distinct from v_grade then
      raise exception 'a Grade % learner reads a Grade % passage (got a Grade % passage)', v_grade, v_grade, v_level;
    end if;
  end if;
  if tg_op = 'INSERT' then
    select a.round, a.school_year, a.student_id into v_round, v_year, v_student
    from public.phil_iri_assessments a where a.id = new.assessment_id;
    if v_test_type is not null
       and v_test_type is distinct from (case v_round when 'bosy' then 'pre' when 'eosy' then 'post' else 'mosy' end) then
      raise exception 'a % session does not read a % passage (BOSY reads pre, MOSY mosy, EOSY post passages)',
        v_round, v_test_type;
    end if;
    select p.title into v_read_title
    from public.phil_iri_readings r
    join public.phil_iri_assessments a on a.id = r.assessment_id
    join public.phil_iri_passages p on p.id = r.passage_id
    where a.student_id = v_student
      and (r.passage_id = new.passage_id
           or phil_iri_text_key(p.body) = (select phil_iri_text_key(body) from public.phil_iri_passages
                                          where id = new.passage_id))
      -- Oral follow-up of a silent reading: same round and year, another session.
      and not (new.method <> 'silent' and r.method = 'silent'
               and r.assessment_id <> new.assessment_id
               and a.round = v_round and a.school_year = v_year)
    limit 1;
    if v_read_title is not null then
      raise exception 'this learner has already read "%"; a learner never reads the same passage twice', v_read_title;
    end if;
  end if;
  return new;
end;
$$;

-- check_phil_iri_rubric_score()
CREATE OR REPLACE FUNCTION public.check_phil_iri_rubric_score() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_min integer;
  v_max integer;
begin
  if auth.uid() is not null and not phil_iri_assessment_writable(new.assessment_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select scale_min, scale_max into v_min, v_max
  from public.phil_iri_rubric_criteria where id = new.criterion_id;
  if new.score < v_min or new.score > v_max then
    raise exception 'score % is outside %..%', new.score, v_min, v_max;
  end if;
  return new;
end;
$$;

-- crla_assessment_readable(bigint)
CREATE OR REPLACE FUNCTION public.crla_assessment_readable(p_assessment_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.crla_assessments ca
    WHERE ca.id = p_assessment_id
      AND (is_superadmin()
           OR (current_user_role() IN ('admin','coordinator') AND ca.school_id = current_user_school_id())
           OR (current_user_role() = 'tutor' AND tutor_has_student(ca.student_id)))
  );
$$;

-- crla_assessment_thresholds(bigint)
CREATE OR REPLACE FUNCTION public.crla_assessment_thresholds(p_assessment_id bigint) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.crla_threshold_defaults() || coalesce(ca.thresholds_snapshot, '{}'::jsonb)
  from public.crla_assessments ca where ca.id = p_assessment_id;
$$;

-- crla_assessment_writable(bigint)
CREATE OR REPLACE FUNCTION public.crla_assessment_writable(p_assessment_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.crla_assessments ca
    WHERE ca.id = p_assessment_id
      AND (is_superadmin()
           OR (current_user_role() IN ('admin','coordinator') AND ca.school_id = current_user_school_id())
           OR (current_user_role() = 'tutor' AND tutor_has_section(ca.section_id)))
  );
$$;

-- crla_assessments_before_insert()
CREATE OR REPLACE FUNCTION public.crla_assessments_before_insert() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  select coalesce(max(attempt_no), 0) + 1 into new.attempt_no
  from public.crla_assessments
  where student_id = new.student_id
    and school_id = new.school_id
    and section_id = new.section_id
    and subject_variant = new.subject_variant
    and school_year = new.school_year;

  if auth.uid() is not null then
    new.administered_by := auth.uid();
  end if;
  if auth.uid() is not null or new.thresholds_snapshot is null then
    new.thresholds_snapshot := public.crla_effective_thresholds(new.school_id);
  else
    -- No JWT (SQL Editor, seed): a given snapshot is completed with defaults.
    new.thresholds_snapshot := public.crla_threshold_defaults() || new.thresholds_snapshot;
  end if;
  new.reading_profile := null; -- filled once Part 1 exists
  return new;
end;
$$;

-- crla_comprehension_max(integer, text)
CREATE OR REPLACE FUNCTION public.crla_comprehension_max(p_grade integer, p_variant text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select case
    when p_grade = 1 then 5
    when p_grade = 3 and p_variant in ('mt', 'fil') then 7
    else 6
  end;
$$;

-- crla_effective_thresholds(bigint)
CREATE OR REPLACE FUNCTION public.crla_effective_thresholds(p_school_id bigint) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.crla_threshold_defaults()
      || coalesce((select settings from public.crla_thresholds where school_id is null), '{}'::jsonb)
      || coalesce((select settings from public.crla_thresholds where school_id = p_school_id), '{}'::jsonb);
$$;

-- crla_part1_eng_level(integer, jsonb)
CREATE OR REPLACE FUNCTION public.crla_part1_eng_level(p_total integer, t jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select case
    when p_total is null then null
    when p_total <= (t->>'part1_eng_full_max')::int then 'Full Refresher'
    when p_total <= (t->>'part1_eng_moderate_max')::int then 'Moderate Refresher'
    when p_total <= (t->>'part1_eng_light_max')::int then 'Light Refresher'
    else 'Grade Ready'
  end;
$$;

-- crla_part1_set_level()
CREATE OR REPLACE FUNCTION public.crla_part1_set_level() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  t jsonb := public.crla_assessment_thresholds(new.assessment_id);
begin
  if tg_table_name = 'crla_part1_standard' then
    new.reading_level := public.crla_part1_std_level(
      new.task1_score,
      case when new.task1_score < 7 then new.task1_score + coalesce(new.task2_low_score, 0)
           else new.task1_score + 10 + coalesce(new.task2_high_score, 0) end,
      t);
  else
    new.reading_level := public.crla_part1_eng_level(
      new.task1_score + coalesce(new.task2_score, 0), t);
  end if;
  return new;
end;
$$;

-- crla_part1_std_level(integer, integer, jsonb)
CREATE OR REPLACE FUNCTION public.crla_part1_std_level(p_task1 integer, p_total integer, t jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select case
    when p_task1 is null or p_total is null then null
    when p_task1 < 7 then
      case when p_total <= (t->>'part1_std_full_max')::int then 'Full Refresher' else 'Moderate Refresher' end
    else
      case when p_total <= (t->>'part1_std_light_max')::int then 'Light Refresher' else 'Grade Ready' end
  end;
$$;

-- crla_reading_profile(text, numeric, integer, integer, text)
CREATE OR REPLACE FUNCTION public.crla_reading_profile(p_level text, p_pct numeric, p_comp integer, p_grade integer, p_variant text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select public.crla_reading_profile_t(p_level, p_pct, p_comp, p_grade, p_variant,
                                       public.crla_threshold_defaults());
$$;

-- crla_reading_profile_t(text, numeric, integer, integer, text, jsonb)
CREATE OR REPLACE FUNCTION public.crla_reading_profile_t(p_level text, p_pct numeric, p_comp integer, p_grade integer, p_variant text, t jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select case
    when p_level is null then null
    when p_level = 'Full Refresher'
      or (x.mod_low and p_level = 'Moderate Refresher') then 'Low Emerging Reader'
    when p_pct is null or p_comp is null then null
    when p_pct <= x.a
      or (p_pct > x.a and p_pct <= x.b and p_comp <= x.h) then 'High Emerging Reader'
    when (p_pct > x.a and p_pct < x.mid and p_comp >= x.h + 1)
      or (p_pct > x.b and p_pct < x.below and p_comp <= x.d2) then 'Developing Reader'
    when (p_pct >= x.mid and p_pct < x.below and p_comp >= x.d2 + 1)
      or (p_pct > x.top and p_comp <= x.g - 1) then 'Transitioning Reader'
    when p_pct > x.top and p_comp >= x.g then 'Reading At Grade Level'
  end
  from (
    select (t->>'pct_high_emerging_max')::numeric / 100 as a,
           (t->>'pct_low_band_max')::numeric / 100 as b,
           (t->>'pct_mid_band_min')::numeric / 100 as mid,
           (t->>'pct_top_band_above')::numeric / 100 as top,
           (t->>'pct_mid_band_below')::numeric / 100 as below,
           (t->>(s.k || '_h'))::int as h,
           (t->>(s.k || '_d2'))::int as d2,
           (t->>(s.k || '_g'))::int as g,
           coalesce((t->>(s.k || '_moderate_is_low_emerging'))::boolean, false) as mod_low
    from (select public.crla_sheet_key(p_grade, p_variant) as k) s
  ) x;
$$;

-- crla_refresh_profile(bigint)
CREATE OR REPLACE FUNCTION public.crla_refresh_profile(p_assessment_id bigint) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
  -- Same joins as crla_results (story by region, language, grade, story_no).
  update public.crla_assessments ca
  set reading_profile = (
    select public.crla_reading_profile_t(
             coalesce(p1s.reading_level, p1e.reading_level),
             p2.words_read::numeric / nullif(cs.word_count, 0)::numeric,
             p2.comprehension_correct,
             g.grade,
             ca.subject_variant,
             public.crla_threshold_defaults() || coalesce(ca.thresholds_snapshot, '{}'::jsonb))
    from public.sections sec
    join public.schools sch on sch.id = ca.school_id
    cross join lateral (
      select case when sec.grade_level ~ '^[0-9]+$' then sec.grade_level::int end as grade) g
    left join public.crla_part1_standard p1s on p1s.assessment_id = ca.id
    left join public.crla_part1_english p1e on p1e.assessment_id = ca.id
    left join public.crla_part2_fluency p2 on p2.assessment_id = ca.id
    left join public.crla_stories cs on cs.region_id = sch.region_id
      and cs.language = ca.language
      and cs.grade = g.grade
      and cs.story_no = p2.story_no
    where sec.id = ca.section_id)
  where ca.id = p_assessment_id;
$_$;

-- crla_refresh_profile_trigger()
CREATE OR REPLACE FUNCTION public.crla_refresh_profile_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  perform public.crla_refresh_profile(coalesce(new.assessment_id, old.assessment_id));
  return null;
end;
$$;

-- crla_regenerate_results(bigint[])
CREATE OR REPLACE FUNCTION public.crla_regenerate_results(p_assessment_ids bigint[]) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_missing int;
  v_denied int;
  v_id bigint;
  v_count int := 0;
begin
  select count(*) into v_missing
  from unnest(p_assessment_ids) as u(id)
  where not exists (select 1 from public.crla_assessments ca where ca.id = u.id);
  if v_missing > 0 then
    raise exception 'no CRLA assessment with % of the given ids', v_missing;
  end if;

  if auth.uid() is not null and not is_superadmin() then
    select count(*) into v_denied
    from public.crla_assessments ca
    where ca.id = any(p_assessment_ids)
      and not (current_user_role() in ('admin', 'coordinator')
               and ca.school_id = current_user_school_id());
    if v_denied > 0 then
      raise exception 'only an admin or coordinator of the school can regenerate CRLA results'
        using errcode = '42501';
    end if;
  end if;

  for v_id in select distinct u.id from unnest(p_assessment_ids) as u(id) loop
    update public.crla_assessments
    set thresholds_snapshot = public.crla_effective_thresholds(school_id)
    where id = v_id;
    -- Re-run the level triggers (they read the new snapshot).
    update public.crla_part1_standard set task1_score = task1_score where assessment_id = v_id;
    update public.crla_part1_english set task1_score = task1_score where assessment_id = v_id;
    perform public.crla_refresh_profile(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- crla_sheet_key(integer, text)
CREATE OR REPLACE FUNCTION public.crla_sheet_key(p_grade integer, p_variant text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select case
    when p_grade = 1 then 'g1'
    when p_grade = 3 and p_variant in ('mt', 'fil') then 'g3_mtfil'
    when p_grade = 3 then 'g3_eng'
    else 'g2'
  end;
$$;

-- crla_threshold_defaults()
CREATE OR REPLACE FUNCTION public.crla_threshold_defaults() RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select '{
    "part1_std_full_max": 10, "part1_std_light_max": 26,
    "part1_eng_full_max": 0, "part1_eng_moderate_max": 10, "part1_eng_light_max": 16,
    "pct_high_emerging_max": 25, "pct_low_band_max": 50, "pct_mid_band_min": 51,
    "pct_top_band_above": 75, "pct_mid_band_below": 76,
    "g1_h": 0, "g1_d2": 1, "g1_g": 4, "g1_moderate_is_low_emerging": true,
    "g2_h": 0, "g2_d2": 2, "g2_g": 5, "g2_moderate_is_low_emerging": false,
    "g3_mtfil_h": 1, "g3_mtfil_d2": 3, "g3_mtfil_g": 6, "g3_mtfil_moderate_is_low_emerging": false,
    "g3_eng_h": 0, "g3_eng_d2": 2, "g3_eng_g": 5, "g3_eng_moderate_is_low_emerging": false
  }'::jsonb;
$$;

-- crla_thresholds_stamp()
CREATE OR REPLACE FUNCTION public.crla_thresholds_stamp() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  new.updated_at := now();
  if auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

-- crla_time_cap_seconds(integer, text)
CREATE OR REPLACE FUNCTION public.crla_time_cap_seconds(p_grade integer, p_variant text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select case
    when p_grade = 1 then 60
    when p_grade = 3 and p_variant in ('mt', 'fil') then 180
    else 120
  end;
$$;

-- current_user_role()
CREATE OR REPLACE FUNCTION public.current_user_role() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select role from public.users where id = auth.uid() and is_active;
$$;

-- current_user_school_id()
CREATE OR REPLACE FUNCTION public.current_user_school_id() RETURNS bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select school_id from public.users where id = auth.uid() and is_active;
$$;

-- guard_school_identity()
CREATE OR REPLACE FUNCTION public.guard_school_identity() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
begin
  if auth.uid() is not null
     and (new.school_id is distinct from old.school_id
          or new.region_id is distinct from old.region_id)
     and not public.is_superadmin() then
    raise exception 'Only the superadmin can change a school''s DepEd school ID or region.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- is_superadmin()
CREATE OR REPLACE FUNCTION public.is_superadmin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce(
    (select role = 'admin' and school_id is null
       from public.users where id = auth.uid() and is_active),
    false);
$$;

-- lock_phil_iri_collection_grading()
CREATE OR REPLACE FUNCTION public.lock_phil_iri_collection_grading() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.is_grade_leveled is distinct from old.is_grade_leveled
     and exists (select 1 from public.phil_iri_passages where collection_id = old.id) then
    raise exception 'a collection with passages cannot change whether it is grade-leveled';
  end if;
  return new;
end;
$$;

-- lock_phil_iri_read_passage()
CREATE OR REPLACE FUNCTION public.lock_phil_iri_read_passage() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if (new.body, new.word_count, new.level, new.collection_id)
     is distinct from (old.body, old.word_count, old.level, old.collection_id)
     and exists (select 1 from public.phil_iri_readings where passage_id = old.id) then
    raise exception 'this passage has already been read; its text, word count, level and collection are locked (add a new passage instead)';
  end if;
  return new;
end;
$$;

-- phil_iri_assessment_readable(bigint)
CREATE OR REPLACE FUNCTION public.phil_iri_assessment_readable(p_assessment_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.phil_iri_assessments a
    where a.id = p_assessment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and a.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and tutor_has_student(a.student_id)))
  );
$$;

-- phil_iri_assessment_writable(bigint)
CREATE OR REPLACE FUNCTION public.phil_iri_assessment_writable(p_assessment_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.phil_iri_assessments a
    where a.id = p_assessment_id
      and a.status <> 'finalized'
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and a.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and tutor_has_section(a.section_id)))
  );
$$;

-- phil_iri_assessments_before_insert()
CREATE OR REPLACE FUNCTION public.phil_iri_assessments_before_insert() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  select coalesce(max(attempt_no), 0) + 1 into new.attempt_no
  from public.phil_iri_assessments
  where student_id = new.student_id and school_id = new.school_id
    and section_id = new.section_id and round = new.round
    and school_year = new.school_year;
  if auth.uid() is not null then
    new.administered_by := auth.uid();
    new.status := 'in_progress';
    new.completed_at := null;
    new.finalized_at := null;
    new.thresholds_snapshot := null;
  end if;
  return new;
end;
$$;

-- phil_iri_assessments_before_update()
CREATE OR REPLACE FUNCTION public.phil_iri_assessments_before_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if auth.uid() is null then
    return new; -- SQL Editor maintenance
  end if;
  if old.status = 'finalized' then
    raise exception 'a finalized Phil-IRI assessment cannot be changed';
  end if;
  if (new.student_id, new.school_id, new.section_id, new.school_year, new.round,
      new.attempt_no, new.administered_by, new.assessed_at)
     is distinct from
     (old.student_id, old.school_id, old.section_id, old.school_year, old.round,
      old.attempt_no, old.administered_by, old.assessed_at) then
    raise exception 'only the status of a Phil-IRI assessment can change';
  end if;

  if new.status = 'finalized' then
    if not (is_superadmin() or current_user_role() in ('admin', 'coordinator')) then
      raise exception 'only an admin or coordinator can finalize a Phil-IRI assessment';
    end if;
    if old.status <> 'completed' then
      raise exception 'only a completed Phil-IRI assessment can be finalized';
    end if;
    if new.thresholds_snapshot is null then
      raise exception 'finalizing needs the thresholds snapshot';
    end if;
    new.finalized_at := now();
    new.completed_at := old.completed_at;
  else
    new.thresholds_snapshot := null;
    new.finalized_at := null;
    if new.status = 'completed' and old.status = 'in_progress' then
      new.completed_at := now();
    elsif new.status = 'in_progress' then
      new.completed_at := null;
    else
      new.completed_at := old.completed_at;
    end if;
  end if;
  return new;
end;
$$;

-- phil_iri_collection_readable(bigint)
CREATE OR REPLACE FUNCTION public.phil_iri_collection_readable(p_collection_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.phil_iri_collections c
    where c.id = p_collection_id
      and (is_superadmin()
           or c.school_id is null
           or c.school_id = current_user_school_id())
  );
$$;

-- phil_iri_collection_writable(bigint)
CREATE OR REPLACE FUNCTION public.phil_iri_collection_writable(p_collection_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.phil_iri_collections c
    where c.id = p_collection_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator')
               and c.school_id is not null
               and c.school_id = current_user_school_id()))
  );
$$;

-- phil_iri_deny(text)
CREATE OR REPLACE FUNCTION public.phil_iri_deny(p_table text) RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
  raise exception 'new row violates row-level security policy for table "%"', p_table
    using errcode = '42501';
end;
$$;

-- phil_iri_gst_results_before_insert()
CREATE OR REPLACE FUNCTION public.phil_iri_gst_results_before_insert() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_grade integer := phil_iri_section_grade(new.section_id);
begin
  -- Runs before RLS: only check sections of the caller's own school, so the
  -- message can't reveal another school's section grade (RLS rejects those).
  if auth.uid() is not null and not (is_superadmin() or exists (
       select 1 from public.sections where id = new.section_id and school_id = current_user_school_id())) then
    v_grade := null;
  end if;
  if v_grade is not null and new.max_score <> (case when v_grade >= 7 then 40 else 20 end) then
    raise exception 'the GST for Grade % is out of %', v_grade, case when v_grade >= 7 then 40 else 20 end;
  end if;
  select coalesce(max(attempt_no), 0) + 1 into new.attempt_no
  from public.phil_iri_gst_results
  where student_id = new.student_id and school_id = new.school_id
    and section_id = new.section_id and school_year = new.school_year;
  if auth.uid() is not null then
    new.administered_by := auth.uid();
  end if;
  return new;
end;
$$;

-- phil_iri_passage_readable(bigint)
CREATE OR REPLACE FUNCTION public.phil_iri_passage_readable(p_passage_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.phil_iri_passages p
    where p.id = p_passage_id and phil_iri_collection_readable(p.collection_id)
  );
$$;

-- phil_iri_passage_writable(bigint)
CREATE OR REPLACE FUNCTION public.phil_iri_passage_writable(p_passage_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.phil_iri_passages p
    where p.id = p_passage_id and phil_iri_collection_writable(p.collection_id)
  );
$$;

-- phil_iri_reading_readable(bigint)
CREATE OR REPLACE FUNCTION public.phil_iri_reading_readable(p_reading_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.phil_iri_readings r
    where r.id = p_reading_id and phil_iri_assessment_readable(r.assessment_id)
  );
$$;

-- phil_iri_reading_writable(bigint)
CREATE OR REPLACE FUNCTION public.phil_iri_reading_writable(p_reading_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.phil_iri_readings r
    where r.id = p_reading_id and phil_iri_assessment_writable(r.assessment_id)
  );
$$;

-- phil_iri_section_grade(bigint)
CREATE OR REPLACE FUNCTION public.phil_iri_section_grade(p_section_id bigint) RETURNS integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
  select case when grade_level ~ '^[0-9]+$' then grade_level::int end
  from public.sections where id = p_section_id;
$_$;

-- phil_iri_stamp_created_by()
CREATE OR REPLACE FUNCTION public.phil_iri_stamp_created_by() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  return new;
end;
$$;

-- phil_iri_text_key(text)
CREATE OR REPLACE FUNCTION public.phil_iri_text_key(p_body text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select translate(lower(p_body), E' \n\r\t.,!?;:''"`-—–()[]‘’“”…/', '');
$$;

-- phil_iri_thresholds_stamp()
CREATE OR REPLACE FUNCTION public.phil_iri_thresholds_stamp() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  new.updated_at := now();
  if auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

-- section_in_school(bigint, bigint)
CREATE OR REPLACE FUNCTION public.section_in_school(p_section_id bigint, p_school_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.sections
    where id = p_section_id and school_id = p_school_id
  );
$$;

-- set_updated_at()
CREATE OR REPLACE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- student_in_school(bigint, bigint)
CREATE OR REPLACE FUNCTION public.student_in_school(p_student_id bigint, p_school_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.students
    where id = p_student_id and school_id = p_school_id
  );
$$;

-- sync_student_school_id()
CREATE OR REPLACE FUNCTION public.sync_student_school_id() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  update public.students
  set school_id = (select school_id from public.sections where id = new.section_id)
  where id = new.student_id;
  return new;
end;
$$;

-- tutor_has_section(bigint)
CREATE OR REPLACE FUNCTION public.tutor_has_section(p_section_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.current_user_role() = 'tutor' and exists (
    select 1 from public.tutor_section_assignments
    where tutor_id = auth.uid() and section_id = p_section_id
  );
$$;

-- tutor_has_student(bigint)
CREATE OR REPLACE FUNCTION public.tutor_has_student(p_student_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.current_user_role() = 'tutor' and exists (
    select 1
    from public.enrollments e
    join public.tutor_section_assignments tsa on tsa.section_id = e.section_id
    where e.student_id = p_student_id and tsa.tutor_id = auth.uid()
  );
$$;

-- user_in_school(uuid, bigint)
CREATE OR REPLACE FUNCTION public.user_in_school(p_user_id uuid, p_school_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id AND school_id = p_school_id);
$$;

-- validate_tutor_section_assignment()
CREATE OR REPLACE FUNCTION public.validate_tutor_section_assignment() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_tutor_role text;
  v_tutor_school bigint;
  v_tutor_active boolean;
  v_section_school bigint;
begin
  if tg_op = 'INSERT' then
    new.assigned_by := auth.uid();
    new.assigned_at := now();
  else
    new.assigned_by := old.assigned_by;
    new.assigned_at := old.assigned_at;
  end if;

  select role, school_id, is_active into v_tutor_role, v_tutor_school, v_tutor_active
  from public.users where id = new.tutor_id;

  if v_tutor_role is distinct from 'tutor' then
    raise exception 'tutor_id % is not a tutor visible to you', new.tutor_id;
  end if;

  if not v_tutor_active then
    raise exception 'tutor % is inactive', new.tutor_id;
  end if;

  select school_id into v_section_school
  from public.sections where id = new.section_id;

  if v_section_school is null or v_tutor_school is distinct from v_section_school then
    raise exception 'tutor % and section % are not in the same school (or the section is not visible to you)',
      new.tutor_id, new.section_id;
  end if;

  return new;
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;


-- tables -----------------------------------------------------------------

-- aral_attendance
CREATE TABLE IF NOT EXISTS public.aral_attendance (
    id bigint NOT NULL,
    session_id bigint NOT NULL,
    enrollment_id bigint NOT NULL,
    mark text NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT aral_attendance_mark_check CHECK ((mark = ANY (ARRAY['present'::text, 'absent'::text, 'excused'::text])))
);

-- aral_checkin_answers
CREATE TABLE IF NOT EXISTS public.aral_checkin_answers (
    id bigint NOT NULL,
    checkin_id bigint NOT NULL,
    item_id bigint NOT NULL,
    response text,
    is_correct boolean NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

-- aral_checkin_items
CREATE TABLE IF NOT EXISTS public.aral_checkin_items (
    id bigint NOT NULL,
    tool_id bigint NOT NULL,
    item_no integer NOT NULL,
    label text,
    section text,
    kind text NOT NULL,
    answer_key text,
    prompt text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT aral_checkin_items_item_no_check CHECK ((item_no >= 1)),
    CONSTRAINT aral_checkin_items_key CHECK (((kind = 'open'::text) OR COALESCE((answer_key ~ '^[A-E]$'::text), false))),
    CONSTRAINT aral_checkin_items_kind_check CHECK ((kind = ANY (ARRAY['choice'::text, 'open'::text])))
);

-- aral_checkin_tools
CREATE TABLE IF NOT EXISTS public.aral_checkin_tools (
    id bigint NOT NULL,
    key_stage text NOT NULL,
    track text NOT NULL,
    checkpoint integer NOT NULL,
    language text NOT NULL,
    title text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT aral_checkin_tools_checkpoint_check CHECK ((checkpoint = ANY (ARRAY[16, 32]))),
    CONSTRAINT aral_checkin_tools_key_stage_check CHECK ((key_stage = ANY (ARRAY['ks2'::text, 'ks3'::text]))),
    CONSTRAINT aral_checkin_tools_language_check CHECK ((language = ANY (ARRAY['filipino'::text, 'english'::text]))),
    CONSTRAINT aral_checkin_tools_track_check CHECK ((track = ANY (ARRAY['basic'::text, 'plus'::text])))
);

-- aral_checkins
CREATE TABLE IF NOT EXISTS public.aral_checkins (
    id bigint NOT NULL,
    enrollment_id bigint NOT NULL,
    tool_id bigint NOT NULL,
    attempt_no integer DEFAULT 0 NOT NULL,
    taken_on date NOT NULL,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

-- aral_enrollments
CREATE TABLE IF NOT EXISTS public.aral_enrollments (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    school_id bigint NOT NULL,
    section_id bigint NOT NULL,
    school_year text NOT NULL,
    key_stage text NOT NULL,
    track text,
    tutor_id uuid,
    status text DEFAULT 'active'::text NOT NULL,
    entered_on date DEFAULT CURRENT_DATE NOT NULL,
    exited_on date,
    exit_reason text,
    basis_source text NOT NULL,
    basis_round text,
    basis_level text,
    basis_assessment_id bigint,
    suggested_key_stage text,
    suggested_track text,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    suggestion_round text,
    suggestion_level text,
    suggestion_assessment_id bigint,
    suggested_on date,
    CONSTRAINT aral_enrollments_basis CHECK (((basis_source = 'manual'::text) OR (basis_level IS NOT NULL))),
    CONSTRAINT aral_enrollments_basis_round_check CHECK ((basis_round = ANY (ARRAY['bosy'::text, 'mosy'::text, 'mosy1'::text, 'mosy2'::text, 'mosy3'::text, 'eosy'::text]))),
    CONSTRAINT aral_enrollments_basis_source_check CHECK ((basis_source = ANY (ARRAY['crla'::text, 'phil_iri'::text, 'manual'::text]))),
    CONSTRAINT aral_enrollments_exit CHECK (((status = 'exited'::text) = ((exited_on IS NOT NULL) AND (exit_reason IS NOT NULL)))),
    CONSTRAINT aral_enrollments_exit_after_entry CHECK (((exited_on IS NULL) OR (exited_on >= entered_on))),
    CONSTRAINT aral_enrollments_exit_reason_check CHECK ((exit_reason = ANY (ARRAY['grade_level_ready'::text, 'transferred_out'::text, 'dropped_out'::text, 'other'::text]))),
    CONSTRAINT aral_enrollments_key_stage_check CHECK ((key_stage = ANY (ARRAY['ks1'::text, 'ks2'::text, 'ks3'::text]))),
    CONSTRAINT aral_enrollments_school_year_format CHECK (
CASE
    WHEN (school_year ~ '^\d{4}-\d{4}$'::text) THEN (("right"(school_year, 4))::integer = (("left"(school_year, 4))::integer + 1))
    ELSE false
END),
    CONSTRAINT aral_enrollments_status_check CHECK ((status = ANY (ARRAY['active'::text, 'exited'::text]))),
    CONSTRAINT aral_enrollments_suggested_key_stage_check CHECK ((suggested_key_stage = ANY (ARRAY['ks1'::text, 'ks2'::text, 'ks3'::text]))),
    CONSTRAINT aral_enrollments_suggested_track_check CHECK ((suggested_track = ANY (ARRAY['basic'::text, 'plus'::text]))),
    CONSTRAINT aral_enrollments_suggestion_round_check CHECK ((suggestion_round = ANY (ARRAY['bosy'::text, 'mosy'::text, 'mosy1'::text, 'mosy2'::text, 'mosy3'::text, 'eosy'::text]))),
    CONSTRAINT aral_enrollments_track CHECK (((key_stage = 'ks1'::text) = (track IS NULL))),
    CONSTRAINT aral_enrollments_track_check CHECK ((track = ANY (ARRAY['basic'::text, 'plus'::text])))
);

-- aral_irip_targets
CREATE TABLE IF NOT EXISTS public.aral_irip_targets (
    id bigint NOT NULL,
    program text NOT NULL,
    strand text NOT NULL,
    seq integer NOT NULL,
    focus text,
    letter_focus text,
    sight_words text,
    skills text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT aral_irip_targets_content CHECK (
CASE
    WHEN (program = 'basic_ks23'::text) THEN (focus IS NOT NULL)
    ELSE (skills IS NOT NULL)
END),
    CONSTRAINT aral_irip_targets_program_check CHECK ((program = ANY (ARRAY['basic_ks23'::text, 'plus_ks2'::text, 'plus_ks3'::text]))),
    CONSTRAINT aral_irip_targets_seq_check CHECK ((seq >= 1)),
    CONSTRAINT aral_irip_targets_strand CHECK (((program = 'basic_ks23'::text) = (strand = ANY (ARRAY['filipino'::text, 'english'::text])))),
    CONSTRAINT aral_irip_targets_strand_check CHECK ((strand = ANY (ARRAY['filipino'::text, 'english'::text, 'main'::text])))
);

-- aral_irip_weeks
CREATE TABLE IF NOT EXISTS public.aral_irip_weeks (
    id bigint NOT NULL,
    enrollment_id bigint NOT NULL,
    cycle_no integer DEFAULT 1 NOT NULL,
    week_no integer NOT NULL,
    strand text NOT NULL,
    target_id bigint NOT NULL,
    status text,
    rated_on date,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT aral_irip_weeks_cycle_no_check CHECK ((cycle_no >= 1)),
    CONSTRAINT aral_irip_weeks_rated CHECK (((status IS NULL) = (rated_on IS NULL))),
    CONSTRAINT aral_irip_weeks_status_check CHECK ((status = ANY (ARRAY['observed'::text, 'partial'::text, 'not_observed'::text]))),
    CONSTRAINT aral_irip_weeks_strand_check CHECK ((strand = ANY (ARRAY['filipino'::text, 'english'::text, 'main'::text]))),
    CONSTRAINT aral_irip_weeks_week_no_check CHECK (((week_no >= 1) AND (week_no <= 8)))
);

-- aral_material_links
CREATE TABLE IF NOT EXISTS public.aral_material_links (
    id bigint NOT NULL,
    material_id bigint NOT NULL,
    school_id bigint NOT NULL,
    link text NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT aral_material_links_link_check CHECK ((link ~* '^https?://[^[:space:]]+$'::text))
);

-- aral_materials
CREATE TABLE IF NOT EXISTS public.aral_materials (
    id bigint NOT NULL,
    school_id bigint,
    title text NOT NULL,
    description text,
    key_stage text NOT NULL,
    track text,
    kind text DEFAULT 'learner'::text NOT NULL,
    language text DEFAULT 'English'::text NOT NULL,
    min_grade integer DEFAULT 7 NOT NULL,
    max_grade integer DEFAULT 10 NOT NULL,
    file_name text,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    link text,
    CONSTRAINT aral_materials_file_name CHECK (((file_name IS NULL) OR (length(btrim(file_name)) > 0))),
    CONSTRAINT aral_materials_grades CHECK ((((min_grade >= 1) AND (min_grade <= 12)) AND ((max_grade >= min_grade) AND (max_grade <= 12)))),
    CONSTRAINT aral_materials_key_stage_check CHECK ((key_stage = ANY (ARRAY['foundational'::text, 'ks1'::text, 'ks2'::text, 'ks3'::text]))),
    CONSTRAINT aral_materials_kind_check CHECK ((kind = ANY (ARRAY['learner'::text, 'tutor'::text, 'supplementary'::text]))),
    CONSTRAINT aral_materials_ks3_high_school CHECK (((key_stage <> 'ks3'::text) OR (min_grade >= 7))),
    CONSTRAINT aral_materials_language_check CHECK ((language = ANY (ARRAY['English'::text, 'Filipino'::text]))),
    CONSTRAINT aral_materials_link CHECK (((link IS NULL) OR (link ~* '^https?://[^[:space:]]+$'::text))),
    CONSTRAINT aral_materials_title_check CHECK ((length(btrim(title)) > 0)),
    CONSTRAINT aral_materials_track CHECK (((key_stage = ANY (ARRAY['ks2'::text, 'ks3'::text])) OR (track IS NULL))),
    CONSTRAINT aral_materials_track_check CHECK ((track = ANY (ARRAY['basic'::text, 'plus'::text])))
);

-- aral_sessions
CREATE TABLE IF NOT EXISTS public.aral_sessions (
    id bigint NOT NULL,
    tutor_id uuid NOT NULL,
    school_id bigint NOT NULL,
    school_year text NOT NULL,
    session_no integer DEFAULT 0 NOT NULL,
    held_on date NOT NULL,
    minutes integer NOT NULL,
    setup text NOT NULL,
    lesson text,
    remarks text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT aral_sessions_minutes_check CHECK (((minutes >= 1) AND (minutes <= 120))),
    CONSTRAINT aral_sessions_school_year_format CHECK (
CASE
    WHEN (school_year ~ '^\d{4}-\d{4}$'::text) THEN (("right"(school_year, 4))::integer = (("left"(school_year, 4))::integer + 1))
    ELSE false
END),
    CONSTRAINT aral_sessions_setup_check CHECK ((setup = ANY (ARRAY['pull_out'::text, 'during_class'::text, 'after_class'::text, 'weekend'::text, 'other'::text])))
);

-- aral_settings
CREATE TABLE IF NOT EXISTS public.aral_settings (
    id bigint NOT NULL,
    school_id bigint,
    settings jsonb NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT aral_settings_foundational_program CHECK (((NOT (settings ? 'foundational_program'::text)) OR (jsonb_typeof((settings -> 'foundational_program'::text)) = 'boolean'::text))),
    CONSTRAINT aral_settings_pass_pct CHECK (((NOT (settings ? 'checkin_pass_pct'::text)) OR ((jsonb_typeof((settings -> 'checkin_pass_pct'::text)) = 'number'::text) AND ((((settings ->> 'checkin_pass_pct'::text))::numeric >= (1)::numeric) AND (((settings ->> 'checkin_pass_pct'::text))::numeric <= (100)::numeric))))),
    CONSTRAINT aral_settings_settings_check CHECK ((jsonb_typeof(settings) = 'object'::text))
);

-- aral_tutor_settings
CREATE TABLE IF NOT EXISTS public.aral_tutor_settings (
    tutor_id uuid NOT NULL,
    school_id bigint NOT NULL,
    multiple_sessions_per_day boolean DEFAULT false NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

-- crla_assessments
CREATE TABLE IF NOT EXISTS public.crla_assessments (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    school_id bigint NOT NULL,
    section_id bigint NOT NULL,
    school_year text NOT NULL,
    subject_variant text NOT NULL,
    language text NOT NULL,
    attempt_no smallint NOT NULL,
    assessed_at date NOT NULL,
    administered_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    thresholds_snapshot jsonb,
    reading_profile text,
    round text DEFAULT 'bosy'::text NOT NULL,
    CONSTRAINT crla_assessments_round_check CHECK ((round = ANY (ARRAY['bosy'::text, 'mosy'::text, 'eosy'::text]))),
    CONSTRAINT crla_assessments_school_year_format CHECK (
CASE
    WHEN (school_year ~ '^\d{4}-\d{4}$'::text) THEN (("right"(school_year, 4))::integer = (("left"(school_year, 4))::integer + 1))
    ELSE false
END),
    CONSTRAINT crla_assessments_subject_variant_check CHECK ((subject_variant = ANY (ARRAY['mt'::text, 'fil'::text, 'eng'::text])))
);

-- crla_part1_english
CREATE TABLE IF NOT EXISTS public.crla_part1_english (
    assessment_id bigint NOT NULL,
    task1_score smallint NOT NULL,
    task2_score smallint,
    total_score smallint GENERATED ALWAYS AS ((task1_score + COALESCE((task2_score)::integer, 0))) STORED,
    reading_level text,
    CONSTRAINT crla_part1_english_task1_score_check CHECK (((task1_score >= 0) AND (task1_score <= 10))),
    CONSTRAINT crla_part1_english_task2_gate_check CHECK ((((task1_score = 0) AND (task2_score IS NULL)) OR ((task1_score >= 1) AND (task1_score <= 10)))),
    CONSTRAINT crla_part1_english_task2_score_check CHECK (((task2_score >= 0) AND (task2_score <= 10)))
);

-- crla_part1_standard
CREATE TABLE IF NOT EXISTS public.crla_part1_standard (
    assessment_id bigint NOT NULL,
    task1_score smallint NOT NULL,
    task2_low_score smallint,
    task2_high_score smallint,
    total_score smallint GENERATED ALWAYS AS (
CASE
    WHEN (task1_score < 7) THEN (task1_score + COALESCE((task2_low_score)::integer, 0))
    ELSE ((task1_score + 10) + COALESCE((task2_high_score)::integer, 0))
END) STORED,
    reading_level text,
    CONSTRAINT crla_part1_standard_branch_check CHECK ((((task1_score < 7) AND (task2_high_score IS NULL)) OR ((task1_score >= 7) AND (task2_low_score IS NULL)))),
    CONSTRAINT crla_part1_standard_task1_score_check CHECK (((task1_score >= 0) AND (task1_score <= 10))),
    CONSTRAINT crla_part1_standard_task2_high_score_check CHECK (((task2_high_score >= 0) AND (task2_high_score <= 10))),
    CONSTRAINT crla_part1_standard_task2_low_score_check CHECK (((task2_low_score >= 0) AND (task2_low_score <= 10)))
);

-- crla_part2_fluency
CREATE TABLE IF NOT EXISTS public.crla_part2_fluency (
    assessment_id bigint NOT NULL,
    story_no smallint NOT NULL,
    miscues smallint NOT NULL,
    words_read smallint NOT NULL,
    time_minutes smallint NOT NULL,
    time_seconds smallint NOT NULL,
    wpm numeric GENERATED ALWAYS AS (
CASE
    WHEN (((time_minutes * 60) + time_seconds) > 0) THEN round((((words_read)::numeric / (((time_minutes * 60) + time_seconds))::numeric) * (60)::numeric), 1)
    ELSE NULL::numeric
END) STORED,
    comprehension_correct smallint NOT NULL,
    learner_experience_rating smallint,
    observation_level smallint,
    remarks text,
    CONSTRAINT crla_part2_fluency_comprehension_correct_check CHECK (((comprehension_correct >= 0) AND (comprehension_correct <= 7))),
    CONSTRAINT crla_part2_fluency_learner_experience_rating_check CHECK (((learner_experience_rating >= 1) AND (learner_experience_rating <= 5))),
    CONSTRAINT crla_part2_fluency_miscues_check CHECK ((miscues >= 0)),
    CONSTRAINT crla_part2_fluency_observation_level_check CHECK (((observation_level >= 1) AND (observation_level <= 4))),
    CONSTRAINT crla_part2_fluency_story_no_check CHECK ((story_no = ANY (ARRAY[1, 2]))),
    CONSTRAINT crla_part2_fluency_time_minutes_check CHECK ((time_minutes >= 0)),
    CONSTRAINT crla_part2_fluency_time_seconds_check CHECK (((time_seconds >= 0) AND (time_seconds <= 59))),
    CONSTRAINT crla_part2_fluency_words_read_check CHECK ((words_read >= 0))
);

-- crla_stories
CREATE TABLE IF NOT EXISTS public.crla_stories (
    id bigint NOT NULL,
    region_id smallint NOT NULL,
    language text NOT NULL,
    grade smallint NOT NULL,
    story_no smallint NOT NULL,
    title text NOT NULL,
    word_count integer NOT NULL,
    source_story_no smallint,
    CONSTRAINT crla_stories_grade_check CHECK ((grade = ANY (ARRAY[1, 2, 3]))),
    CONSTRAINT crla_stories_story_no_check CHECK ((story_no = ANY (ARRAY[1, 2]))),
    CONSTRAINT crla_stories_word_count_check CHECK ((word_count > 0))
);

-- schools
CREATE TABLE IF NOT EXISTS public.schools (
    id bigint NOT NULL,
    school_id text NOT NULL,
    school_name text NOT NULL,
    division text,
    region_id smallint
);

-- sections
CREATE TABLE IF NOT EXISTS public.sections (
    id bigint NOT NULL,
    school_id bigint NOT NULL,
    school_year text NOT NULL,
    grade_level text NOT NULL,
    section_name text NOT NULL,
    CONSTRAINT sections_school_year_format CHECK (
CASE
    WHEN (school_year ~ '^\d{4}-\d{4}$'::text) THEN (("right"(school_year, 4))::integer = (("left"(school_year, 4))::integer + 1))
    ELSE false
END)
);

-- enrollments
CREATE TABLE IF NOT EXISTS public.enrollments (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    section_id bigint NOT NULL,
    school_year text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    CONSTRAINT enrollments_school_year_format CHECK (
CASE
    WHEN (school_year ~ '^\d{4}-\d{4}$'::text) THEN (("right"(school_year, 4))::integer = (("left"(school_year, 4))::integer + 1))
    ELSE false
END)
);

-- students
CREATE TABLE IF NOT EXISTS public.students (
    id bigint NOT NULL,
    lrn text NOT NULL,
    last_name text NOT NULL,
    first_name text NOT NULL,
    middle_name text,
    sex text,
    birth_date date,
    mother_tongue text,
    ip_group text,
    religion text,
    address_street text,
    barangay text,
    municipality text,
    province text,
    father_name text,
    mother_maiden_name text,
    guardian_name text,
    guardian_relationship text,
    contact_number text,
    learning_modality text,
    remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    school_id bigint
);

-- crla_thresholds
CREATE TABLE IF NOT EXISTS public.crla_thresholds (
    id bigint NOT NULL,
    school_id bigint,
    settings jsonb NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT crla_thresholds_settings_check CHECK ((jsonb_typeof(settings) = 'object'::text))
);

-- import_conflicts
CREATE TABLE IF NOT EXISTS public.import_conflicts (
    id bigint NOT NULL,
    lrn text NOT NULL,
    section_id bigint,
    reason text NOT NULL,
    incoming_data jsonb NOT NULL,
    existing_student_id bigint,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- login_logs
CREATE TABLE IF NOT EXISTS public.login_logs (
    id bigint NOT NULL,
    user_id uuid,
    email_attempted text NOT NULL,
    success boolean NOT NULL,
    method text NOT NULL,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    failure_reason text
);

-- phil_iri_answers
CREATE TABLE IF NOT EXISTS public.phil_iri_answers (
    id bigint NOT NULL,
    reading_id bigint NOT NULL,
    question_id bigint NOT NULL,
    chosen text,
    is_correct boolean DEFAULT false NOT NULL,
    looked_back boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT phil_iri_answers_chosen_check CHECK ((chosen ~ '^[a-z]$'::text))
);

-- phil_iri_assessments
CREATE TABLE IF NOT EXISTS public.phil_iri_assessments (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    school_id bigint NOT NULL,
    section_id bigint NOT NULL,
    school_year text NOT NULL,
    attempt_no integer DEFAULT 0 NOT NULL,
    round text NOT NULL,
    status text DEFAULT 'in_progress'::text NOT NULL,
    assessed_at date NOT NULL,
    completed_at timestamp with time zone,
    finalized_at timestamp with time zone,
    administered_by uuid,
    thresholds_snapshot jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT phil_iri_assessments_finalized_snapshot CHECK (((status = 'finalized'::text) = ((finalized_at IS NOT NULL) AND (thresholds_snapshot IS NOT NULL)))),
    CONSTRAINT phil_iri_assessments_round_check CHECK ((round = ANY (ARRAY['bosy'::text, 'mosy1'::text, 'mosy2'::text, 'mosy3'::text, 'eosy'::text]))),
    CONSTRAINT phil_iri_assessments_school_year_format CHECK (
CASE
    WHEN (school_year ~ '^\d{4}-\d{4}$'::text) THEN (("right"(school_year, 4))::integer = (("left"(school_year, 4))::integer + 1))
    ELSE false
END),
    CONSTRAINT phil_iri_assessments_status_check CHECK ((status = ANY (ARRAY['in_progress'::text, 'completed'::text, 'finalized'::text]))),
    CONSTRAINT phil_iri_assessments_thresholds_snapshot_check CHECK (((thresholds_snapshot IS NULL) OR (jsonb_typeof(thresholds_snapshot) = 'object'::text)))
);

-- phil_iri_collections
CREATE TABLE IF NOT EXISTS public.phil_iri_collections (
    id bigint NOT NULL,
    school_id bigint,
    name text NOT NULL,
    description text,
    is_prescribed boolean DEFAULT false NOT NULL,
    is_grade_leveled boolean DEFAULT true NOT NULL,
    has_comprehension boolean DEFAULT true NOT NULL,
    reading_order jsonb,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT phil_iri_collections_name_check CHECK ((length(TRIM(BOTH FROM name)) > 0)),
    CONSTRAINT phil_iri_collections_prescribed_region CHECK (((NOT is_prescribed) OR (school_id IS NULL))),
    CONSTRAINT phil_iri_collections_reading_order_check CHECK (((reading_order IS NULL) OR (jsonb_typeof(reading_order) = 'array'::text)))
);

-- phil_iri_gst_results
CREATE TABLE IF NOT EXISTS public.phil_iri_gst_results (
    id bigint NOT NULL,
    student_id bigint NOT NULL,
    school_id bigint NOT NULL,
    section_id bigint NOT NULL,
    school_year text NOT NULL,
    attempt_no integer DEFAULT 0 NOT NULL,
    max_score integer NOT NULL,
    total_score integer NOT NULL,
    literal_correct integer,
    inferential_correct integer,
    critical_correct integer,
    taken_at date NOT NULL,
    administered_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT phil_iri_gst_results_breakdown CHECK (((literal_correct IS NULL) OR (inferential_correct IS NULL) OR (critical_correct IS NULL) OR (((literal_correct + inferential_correct) + critical_correct) = total_score))),
    CONSTRAINT phil_iri_gst_results_critical_correct_check CHECK ((critical_correct >= 0)),
    CONSTRAINT phil_iri_gst_results_inferential_correct_check CHECK ((inferential_correct >= 0)),
    CONSTRAINT phil_iri_gst_results_literal_correct_check CHECK ((literal_correct >= 0)),
    CONSTRAINT phil_iri_gst_results_max_score_check CHECK ((max_score = ANY (ARRAY[20, 40]))),
    CONSTRAINT phil_iri_gst_results_school_year_format CHECK (
CASE
    WHEN (school_year ~ '^\d{4}-\d{4}$'::text) THEN (("right"(school_year, 4))::integer = (("left"(school_year, 4))::integer + 1))
    ELSE false
END),
    CONSTRAINT phil_iri_gst_results_score CHECK (((total_score >= 0) AND (total_score <= max_score)))
);

-- phil_iri_miscues
CREATE TABLE IF NOT EXISTS public.phil_iri_miscues (
    id bigint NOT NULL,
    reading_id bigint NOT NULL,
    word_index integer NOT NULL,
    miscue_type text NOT NULL,
    spoken_text text,
    self_corrected boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT phil_iri_miscues_miscue_type_check CHECK ((miscue_type = ANY (ARRAY['mispronunciation'::text, 'omission'::text, 'substitution'::text, 'insertion'::text, 'repetition'::text, 'transposition'::text, 'reversal'::text]))),
    CONSTRAINT phil_iri_miscues_word_index_check CHECK ((word_index >= 0))
);

-- phil_iri_passages
CREATE TABLE IF NOT EXISTS public.phil_iri_passages (
    id bigint NOT NULL,
    collection_id bigint NOT NULL,
    language text DEFAULT 'English'::text NOT NULL,
    test_type text,
    set_code text,
    level integer,
    selection_no integer,
    title text NOT NULL,
    motivation text,
    body text NOT NULL,
    word_count integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT phil_iri_passages_body_check CHECK ((length(TRIM(BOTH FROM body)) > 0)),
    CONSTRAINT phil_iri_passages_language_check CHECK ((language = 'English'::text)),
    CONSTRAINT phil_iri_passages_level_check CHECK (((level >= 1) AND (level <= 12))),
    CONSTRAINT phil_iri_passages_selection_no_check CHECK ((selection_no > 0)),
    CONSTRAINT phil_iri_passages_test_type_check CHECK ((test_type = ANY (ARRAY['pre'::text, 'mosy'::text, 'post'::text]))),
    CONSTRAINT phil_iri_passages_title_check CHECK ((length(TRIM(BOTH FROM title)) > 0)),
    CONSTRAINT phil_iri_passages_word_count_check CHECK ((word_count > 0))
);

-- phil_iri_questions
CREATE TABLE IF NOT EXISTS public.phil_iri_questions (
    id bigint NOT NULL,
    passage_id bigint NOT NULL,
    question_no integer NOT NULL,
    question_type text,
    prompt text NOT NULL,
    choices jsonb NOT NULL,
    answer_key text NOT NULL,
    CONSTRAINT phil_iri_questions_answer_key_check CHECK ((answer_key ~ '^[a-z]$'::text)),
    CONSTRAINT phil_iri_questions_choices_check CHECK (((jsonb_typeof(choices) = 'array'::text) AND (jsonb_array_length(choices) >= 2))),
    CONSTRAINT phil_iri_questions_key_in_choices CHECK (((ascii(answer_key) - ascii('a'::text)) < jsonb_array_length(choices))),
    CONSTRAINT phil_iri_questions_prompt_check CHECK ((length(TRIM(BOTH FROM prompt)) > 0)),
    CONSTRAINT phil_iri_questions_question_no_check CHECK ((question_no > 0)),
    CONSTRAINT phil_iri_questions_question_type_check CHECK ((question_type = ANY (ARRAY['L'::text, 'I'::text, 'C'::text])))
);

-- phil_iri_readings
CREATE TABLE IF NOT EXISTS public.phil_iri_readings (
    id bigint NOT NULL,
    assessment_id bigint NOT NULL,
    sequence_no integer NOT NULL,
    passage_id bigint NOT NULL,
    method text DEFAULT 'whole_text'::text NOT NULL,
    reading_seconds integer,
    words_read integer,
    obs_word_by_word boolean DEFAULT false NOT NULL,
    obs_lacks_expression boolean DEFAULT false NOT NULL,
    obs_voice_inaudible boolean DEFAULT false NOT NULL,
    obs_disregards_punctuation boolean DEFAULT false NOT NULL,
    obs_points_to_words boolean DEFAULT false NOT NULL,
    obs_little_analysis boolean DEFAULT false NOT NULL,
    obs_other text,
    word_reading_score numeric,
    words_per_minute numeric,
    accuracy_level text,
    speed text,
    word_reading_level text,
    comprehension_score numeric,
    comprehension_level text,
    profile text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT phil_iri_readings_accuracy_level_check CHECK ((accuracy_level = ANY (ARRAY['independent'::text, 'instructional'::text, 'frustration'::text, 'nonReader'::text]))),
    CONSTRAINT phil_iri_readings_comprehension_level_check CHECK ((comprehension_level = ANY (ARRAY['independent'::text, 'instructional'::text, 'frustration'::text]))),
    CONSTRAINT phil_iri_readings_comprehension_score_check CHECK (((comprehension_score >= (0)::numeric) AND (comprehension_score <= (1)::numeric))),
    CONSTRAINT phil_iri_readings_method_check CHECK ((method = ANY (ARRAY['whole_text'::text, 'one_minute'::text, 'silent'::text]))),
    CONSTRAINT phil_iri_readings_method_fields CHECK ((((method = ANY (ARRAY['whole_text'::text, 'silent'::text])) AND (words_read IS NULL)) OR ((method = 'one_minute'::text) AND (reading_seconds IS NULL)))),
    CONSTRAINT phil_iri_readings_profile_check CHECK ((profile = ANY (ARRAY['independent'::text, 'instructional'::text, 'frustration'::text, 'nonReader'::text]))),
    CONSTRAINT phil_iri_readings_reading_seconds_check CHECK ((reading_seconds > 0)),
    CONSTRAINT phil_iri_readings_sequence_no_check CHECK ((sequence_no > 0)),
    CONSTRAINT phil_iri_readings_speed_check CHECK ((speed = ANY (ARRAY['struggling'::text, 'slow'::text, 'average'::text, 'fast'::text]))),
    CONSTRAINT phil_iri_readings_word_reading_level_check CHECK ((word_reading_level = ANY (ARRAY['independent'::text, 'instructional'::text, 'frustration'::text, 'nonReader'::text]))),
    CONSTRAINT phil_iri_readings_word_reading_score_check CHECK (((word_reading_score >= (0)::numeric) AND (word_reading_score <= (1)::numeric))),
    CONSTRAINT phil_iri_readings_words_per_minute_check CHECK ((words_per_minute >= (0)::numeric)),
    CONSTRAINT phil_iri_readings_words_read_check CHECK ((words_read > 0))
);

-- phil_iri_rubric_criteria
CREATE TABLE IF NOT EXISTS public.phil_iri_rubric_criteria (
    id bigint NOT NULL,
    collection_id bigint NOT NULL,
    criterion_no integer NOT NULL,
    name text NOT NULL,
    scale_min integer DEFAULT 1 NOT NULL,
    scale_max integer NOT NULL,
    CONSTRAINT phil_iri_rubric_criteria_criterion_no_check CHECK ((criterion_no > 0)),
    CONSTRAINT phil_iri_rubric_criteria_name_check CHECK ((length(TRIM(BOTH FROM name)) > 0)),
    CONSTRAINT phil_iri_rubric_criteria_scale CHECK ((scale_min < scale_max))
);

-- phil_iri_rubric_scores
CREATE TABLE IF NOT EXISTS public.phil_iri_rubric_scores (
    id bigint NOT NULL,
    assessment_id bigint NOT NULL,
    criterion_id bigint NOT NULL,
    score integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- phil_iri_thresholds
CREATE TABLE IF NOT EXISTS public.phil_iri_thresholds (
    id bigint NOT NULL,
    school_id bigint,
    settings jsonb NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT phil_iri_thresholds_settings_check CHECK ((jsonb_typeof(settings) = 'object'::text))
);

-- regions
CREATE TABLE IF NOT EXISTS public.regions (
    id smallint NOT NULL,
    code text NOT NULL,
    name text NOT NULL
);

-- tutor_section_assignments
CREATE TABLE IF NOT EXISTS public.tutor_section_assignments (
    id bigint NOT NULL,
    tutor_id uuid NOT NULL,
    section_id bigint NOT NULL,
    assigned_by uuid,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL
);

-- users
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL,
    email text NOT NULL,
    full_name text NOT NULL,
    role text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    school_id bigint,
    CONSTRAINT users_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'coordinator'::text, 'tutor'::text])))
);


-- views ------------------------------------------------------------------

-- crla_results
CREATE OR REPLACE VIEW public.crla_results WITH (security_invoker='true') AS
 SELECT ca.id AS assessment_id,
    ca.student_id,
    ca.school_id,
    ca.section_id,
    ca.school_year,
    ca.subject_variant,
    ca.language,
    ca.attempt_no,
    ca.assessed_at,
    COALESCE(p1s.total_score, p1e.total_score) AS part1_total_score,
    COALESCE(p1s.reading_level, p1e.reading_level) AS part1_reading_level,
    p2.story_no,
    p2.words_read,
    p2.miscues,
    p2.wpm,
    p2.comprehension_correct,
    p2.learner_experience_rating,
    p2.observation_level,
    p2.remarks,
    round(((p2.words_read)::numeric / (NULLIF(cs.word_count, 0))::numeric), 4) AS pct_correct_words_read,
    ca.reading_profile,
    ca.round
   FROM ((((((public.crla_assessments ca
     LEFT JOIN public.crla_part1_standard p1s ON ((p1s.assessment_id = ca.id)))
     LEFT JOIN public.crla_part1_english p1e ON ((p1e.assessment_id = ca.id)))
     LEFT JOIN public.crla_part2_fluency p2 ON ((p2.assessment_id = ca.id)))
     JOIN public.sections sec ON ((sec.id = ca.section_id)))
     JOIN public.schools sch ON ((sch.id = ca.school_id)))
     LEFT JOIN public.crla_stories cs ON (((cs.region_id = sch.region_id) AND (cs.language = ca.language) AND (cs.grade =
        CASE
            WHEN (sec.grade_level ~ '^[0-9]+$'::text) THEN (sec.grade_level)::integer
            ELSE NULL::integer
        END) AND (cs.story_no = p2.story_no))));

-- crla_latest_attempts
CREATE OR REPLACE VIEW public.crla_latest_attempts WITH (security_invoker='true') AS
 SELECT DISTINCT ON (student_id, section_id, subject_variant, school_year, round) assessment_id,
    student_id,
    school_id,
    section_id,
    school_year,
    subject_variant,
    language,
    attempt_no,
    assessed_at,
    part1_total_score,
    part1_reading_level,
    story_no,
    words_read,
    miscues,
    wpm,
    comprehension_correct,
    learner_experience_rating,
    observation_level,
    remarks,
    pct_correct_words_read,
    reading_profile,
    round
   FROM public.crla_results cr
  ORDER BY student_id, section_id, subject_variant, school_year, round, attempt_no DESC;

-- crla_section_summary
CREATE OR REPLACE VIEW public.crla_section_summary WITH (security_invoker='true') AS
 WITH enrolled AS (
         SELECT e.section_id,
            e.school_year,
            st_1.sex,
            count(*) AS learners_enrolled
           FROM (public.enrollments e
             JOIN public.students st_1 ON ((st_1.id = e.student_id)))
          WHERE (e.status = 'active'::text)
          GROUP BY e.section_id, e.school_year, st_1.sex
        )
 SELECT la.section_id,
    la.school_id,
    la.school_year,
    la.subject_variant,
    la.language,
    st.sex,
    en.learners_enrolled,
    count(*) AS learners_assessed,
    count(*) FILTER (WHERE (la.part1_reading_level = 'Full Refresher'::text)) AS full_refresher,
    count(*) FILTER (WHERE (la.part1_reading_level = 'Moderate Refresher'::text)) AS moderate_refresher,
    count(*) FILTER (WHERE (la.part1_reading_level = 'Light Refresher'::text)) AS light_refresher,
    count(*) FILTER (WHERE (la.part1_reading_level = 'Grade Ready'::text)) AS grade_ready,
    round(avg(la.pct_correct_words_read) FILTER (WHERE (la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text)), 4) AS avg_reading_fluency,
    round(avg(((la.comprehension_correct)::numeric / (public.crla_comprehension_max(
        CASE
            WHEN (sec.grade_level ~ '^[0-9]+$'::text) THEN (sec.grade_level)::integer
            ELSE NULL::integer
        END, la.subject_variant))::numeric)) FILTER (WHERE (la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text)), 4) AS avg_reading_comprehension,
    round(avg(la.wpm) FILTER (WHERE (la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text)), 1) AS avg_wpm,
    count(*) FILTER (WHERE (la.reading_profile = 'Low Emerging Reader'::text)) AS low_emerging_reader,
    count(*) FILTER (WHERE (la.reading_profile = 'High Emerging Reader'::text)) AS high_emerging_reader,
    count(*) FILTER (WHERE (la.reading_profile = 'Developing Reader'::text)) AS developing_reader,
    count(*) FILTER (WHERE (la.reading_profile = 'Transitioning Reader'::text)) AS transitioning_reader,
    count(*) FILTER (WHERE (la.reading_profile = 'Reading At Grade Level'::text)) AS reading_at_grade_level,
    la.round
   FROM (((public.crla_latest_attempts la
     JOIN public.students st ON ((st.id = la.student_id)))
     JOIN public.sections sec ON ((sec.id = la.section_id)))
     LEFT JOIN enrolled en ON (((en.section_id = la.section_id) AND (en.school_year = la.school_year) AND (en.sex = st.sex))))
  GROUP BY la.section_id, la.school_id, la.school_year, la.subject_variant, la.language, st.sex, en.learners_enrolled, la.round;

-- crla_school_summary
CREATE OR REPLACE VIEW public.crla_school_summary WITH (security_invoker='true') AS
 SELECT css.school_id,
    sec.grade_level,
    css.school_year,
    css.subject_variant,
    css.language,
    css.sex,
    sum(css.learners_enrolled) AS learners_enrolled,
    sum(css.learners_assessed) AS learners_assessed,
    sum(css.full_refresher) AS full_refresher,
    sum(css.moderate_refresher) AS moderate_refresher,
    sum(css.light_refresher) AS light_refresher,
    sum(css.grade_ready) AS grade_ready,
    round(avg(css.avg_reading_fluency), 4) AS avg_reading_fluency,
    round(avg(css.avg_reading_comprehension), 4) AS avg_reading_comprehension,
    round(avg(css.avg_wpm), 1) AS avg_wpm,
    sum(css.low_emerging_reader) AS low_emerging_reader,
    sum(css.high_emerging_reader) AS high_emerging_reader,
    sum(css.developing_reader) AS developing_reader,
    sum(css.transitioning_reader) AS transitioning_reader,
    sum(css.reading_at_grade_level) AS reading_at_grade_level,
    css.round
   FROM (public.crla_section_summary css
     JOIN public.sections sec ON ((sec.id = css.section_id)))
  GROUP BY css.school_id, sec.grade_level, css.school_year, css.subject_variant, css.language, css.sex, css.round;

-- crla_school_summary_weighted
CREATE OR REPLACE VIEW public.crla_school_summary_weighted WITH (security_invoker='true') AS
 WITH enrolled AS (
         SELECT sec_1.school_id,
            sec_1.grade_level,
            e.school_year,
            st_1.sex,
            count(*) AS learners_enrolled
           FROM ((public.enrollments e
             JOIN public.sections sec_1 ON ((sec_1.id = e.section_id)))
             JOIN public.students st_1 ON ((st_1.id = e.student_id)))
          WHERE (e.status = 'active'::text)
          GROUP BY sec_1.school_id, sec_1.grade_level, e.school_year, st_1.sex
        )
 SELECT la.school_id,
    sec.grade_level,
    la.school_year,
    la.subject_variant,
    la.language,
    st.sex,
    en.learners_enrolled,
    count(*) AS learners_assessed,
    count(*) FILTER (WHERE (la.part1_reading_level = 'Full Refresher'::text)) AS full_refresher,
    count(*) FILTER (WHERE (la.part1_reading_level = 'Moderate Refresher'::text)) AS moderate_refresher,
    count(*) FILTER (WHERE (la.part1_reading_level = 'Light Refresher'::text)) AS light_refresher,
    count(*) FILTER (WHERE (la.part1_reading_level = 'Grade Ready'::text)) AS grade_ready,
    round(avg(la.pct_correct_words_read) FILTER (WHERE (la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text)), 4) AS avg_reading_fluency,
    round(avg(((la.comprehension_correct)::numeric / (public.crla_comprehension_max(
        CASE
            WHEN (sec.grade_level ~ '^[0-9]+$'::text) THEN (sec.grade_level)::integer
            ELSE NULL::integer
        END, la.subject_variant))::numeric)) FILTER (WHERE (la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text)), 4) AS avg_reading_comprehension,
    round(avg(la.wpm) FILTER (WHERE (la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text)), 1) AS avg_wpm,
    count(*) FILTER (WHERE (la.reading_profile = 'Low Emerging Reader'::text)) AS low_emerging_reader,
    count(*) FILTER (WHERE (la.reading_profile = 'High Emerging Reader'::text)) AS high_emerging_reader,
    count(*) FILTER (WHERE (la.reading_profile = 'Developing Reader'::text)) AS developing_reader,
    count(*) FILTER (WHERE (la.reading_profile = 'Transitioning Reader'::text)) AS transitioning_reader,
    count(*) FILTER (WHERE (la.reading_profile = 'Reading At Grade Level'::text)) AS reading_at_grade_level,
    la.round
   FROM (((public.crla_latest_attempts la
     JOIN public.sections sec ON ((sec.id = la.section_id)))
     JOIN public.students st ON ((st.id = la.student_id)))
     LEFT JOIN enrolled en ON (((en.school_id = la.school_id) AND (en.grade_level = sec.grade_level) AND (en.school_year = la.school_year) AND (en.sex = st.sex))))
  GROUP BY la.school_id, sec.grade_level, la.school_year, la.subject_variant, la.language, st.sex, en.learners_enrolled, la.round;


-- sequences --------------------------------------------------------------

-- aral_attendance_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_attendance'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_attendance ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_attendance_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- aral_checkin_answers_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_checkin_answers'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_checkin_answers ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_checkin_answers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- aral_checkin_items_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_checkin_items'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_checkin_items ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_checkin_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- aral_checkin_tools_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_checkin_tools'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_checkin_tools ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_checkin_tools_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- aral_checkins_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_checkins'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_checkins ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_checkins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- aral_enrollments_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_enrollments'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_enrollments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_enrollments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- aral_irip_targets_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_irip_targets'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_irip_targets ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_irip_targets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- aral_irip_weeks_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_irip_weeks'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_irip_weeks ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_irip_weeks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- aral_material_links_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_material_links'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_material_links ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_material_links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- aral_materials_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_materials'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_materials ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_materials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- aral_sessions_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_sessions'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_sessions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- aral_settings_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.aral_settings'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.aral_settings ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aral_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- crla_assessments_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.crla_assessments'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.crla_assessments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.crla_assessments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- crla_stories_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.crla_stories'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.crla_stories ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.crla_stories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- crla_thresholds_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.crla_thresholds'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.crla_thresholds ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.crla_thresholds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- enrollments_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.enrollments'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.enrollments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.enrollments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- import_conflicts_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.import_conflicts'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.import_conflicts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.import_conflicts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- login_logs_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.login_logs'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.login_logs ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.login_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- phil_iri_answers_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.phil_iri_answers'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.phil_iri_answers ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phil_iri_answers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- phil_iri_assessments_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.phil_iri_assessments'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.phil_iri_assessments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phil_iri_assessments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- phil_iri_collections_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.phil_iri_collections'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.phil_iri_collections ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phil_iri_collections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- phil_iri_gst_results_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.phil_iri_gst_results'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.phil_iri_gst_results ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phil_iri_gst_results_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- phil_iri_miscues_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.phil_iri_miscues'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.phil_iri_miscues ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phil_iri_miscues_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- phil_iri_passages_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.phil_iri_passages'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.phil_iri_passages ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phil_iri_passages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- phil_iri_questions_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.phil_iri_questions'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.phil_iri_questions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phil_iri_questions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- phil_iri_readings_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.phil_iri_readings'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.phil_iri_readings ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phil_iri_readings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- phil_iri_rubric_criteria_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.phil_iri_rubric_criteria'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.phil_iri_rubric_criteria ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phil_iri_rubric_criteria_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- phil_iri_rubric_scores_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.phil_iri_rubric_scores'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.phil_iri_rubric_scores ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phil_iri_rubric_scores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- phil_iri_thresholds_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.phil_iri_thresholds'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.phil_iri_thresholds ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.phil_iri_thresholds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- schools_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.schools'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.schools ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.schools_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- sections_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.sections'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.sections ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.sections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- students_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.students'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.students ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.students_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;

-- tutor_section_assignments_id_seq
DO $$ BEGIN
  IF (SELECT attidentity FROM pg_attribute WHERE attrelid = 'public.tutor_section_assignments'::regclass AND attname = 'id') = '' THEN
    EXECUTE 'ALTER TABLE public.tutor_section_assignments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.tutor_section_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
)';
  END IF;
END $$;


-- constraints ------------------------------------------------------------

-- aral_attendance aral_attendance_one_per_session
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_attendance_one_per_session' AND conrelid = 'public.aral_attendance'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_attendance
    ADD CONSTRAINT aral_attendance_one_per_session UNIQUE (session_id, enrollment_id)';
  END IF;
END $$;

-- aral_attendance aral_attendance_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_attendance_pkey' AND conrelid = 'public.aral_attendance'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_attendance
    ADD CONSTRAINT aral_attendance_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_checkin_answers aral_checkin_answers_one
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkin_answers_one' AND conrelid = 'public.aral_checkin_answers'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkin_answers
    ADD CONSTRAINT aral_checkin_answers_one UNIQUE (checkin_id, item_id)';
  END IF;
END $$;

-- aral_checkin_answers aral_checkin_answers_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkin_answers_pkey' AND conrelid = 'public.aral_checkin_answers'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkin_answers
    ADD CONSTRAINT aral_checkin_answers_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_checkin_items aral_checkin_items_order
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkin_items_order' AND conrelid = 'public.aral_checkin_items'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkin_items
    ADD CONSTRAINT aral_checkin_items_order UNIQUE (tool_id, item_no)';
  END IF;
END $$;

-- aral_checkin_items aral_checkin_items_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkin_items_pkey' AND conrelid = 'public.aral_checkin_items'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkin_items
    ADD CONSTRAINT aral_checkin_items_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_checkin_tools aral_checkin_tools_one
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkin_tools_one' AND conrelid = 'public.aral_checkin_tools'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkin_tools
    ADD CONSTRAINT aral_checkin_tools_one UNIQUE (key_stage, track, checkpoint)';
  END IF;
END $$;

-- aral_checkin_tools aral_checkin_tools_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkin_tools_pkey' AND conrelid = 'public.aral_checkin_tools'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkin_tools
    ADD CONSTRAINT aral_checkin_tools_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_checkins aral_checkins_attempt
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkins_attempt' AND conrelid = 'public.aral_checkins'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkins
    ADD CONSTRAINT aral_checkins_attempt UNIQUE (enrollment_id, tool_id, attempt_no)';
  END IF;
END $$;

-- aral_checkins aral_checkins_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkins_pkey' AND conrelid = 'public.aral_checkins'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkins
    ADD CONSTRAINT aral_checkins_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_enrollments aral_enrollments_one_per_year
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_enrollments_one_per_year' AND conrelid = 'public.aral_enrollments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_enrollments
    ADD CONSTRAINT aral_enrollments_one_per_year UNIQUE (student_id, school_year)';
  END IF;
END $$;

-- aral_enrollments aral_enrollments_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_enrollments_pkey' AND conrelid = 'public.aral_enrollments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_enrollments
    ADD CONSTRAINT aral_enrollments_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_irip_targets aral_irip_targets_order
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_irip_targets_order' AND conrelid = 'public.aral_irip_targets'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_irip_targets
    ADD CONSTRAINT aral_irip_targets_order UNIQUE (program, strand, seq)';
  END IF;
END $$;

-- aral_irip_targets aral_irip_targets_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_irip_targets_pkey' AND conrelid = 'public.aral_irip_targets'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_irip_targets
    ADD CONSTRAINT aral_irip_targets_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_irip_weeks aral_irip_weeks_one
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_irip_weeks_one' AND conrelid = 'public.aral_irip_weeks'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_irip_weeks
    ADD CONSTRAINT aral_irip_weeks_one UNIQUE (enrollment_id, cycle_no, week_no, strand)';
  END IF;
END $$;

-- aral_irip_weeks aral_irip_weeks_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_irip_weeks_pkey' AND conrelid = 'public.aral_irip_weeks'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_irip_weeks
    ADD CONSTRAINT aral_irip_weeks_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_material_links aral_material_links_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_material_links_key' AND conrelid = 'public.aral_material_links'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_material_links
    ADD CONSTRAINT aral_material_links_key UNIQUE (material_id, school_id)';
  END IF;
END $$;

-- aral_material_links aral_material_links_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_material_links_pkey' AND conrelid = 'public.aral_material_links'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_material_links
    ADD CONSTRAINT aral_material_links_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_materials aral_materials_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_materials_pkey' AND conrelid = 'public.aral_materials'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_materials
    ADD CONSTRAINT aral_materials_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_sessions aral_sessions_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_sessions_pkey' AND conrelid = 'public.aral_sessions'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_sessions
    ADD CONSTRAINT aral_sessions_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_settings aral_settings_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_settings_pkey' AND conrelid = 'public.aral_settings'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_settings
    ADD CONSTRAINT aral_settings_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- aral_tutor_settings aral_tutor_settings_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_tutor_settings_pkey' AND conrelid = 'public.aral_tutor_settings'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_tutor_settings
    ADD CONSTRAINT aral_tutor_settings_pkey PRIMARY KEY (tutor_id)';
  END IF;
END $$;

-- crla_assessments crla_assessments_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_assessments_pkey' AND conrelid = 'public.crla_assessments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_assessments
    ADD CONSTRAINT crla_assessments_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- crla_assessments crla_assessments_unique_attempt
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_assessments_unique_attempt' AND conrelid = 'public.crla_assessments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_assessments
    ADD CONSTRAINT crla_assessments_unique_attempt UNIQUE (student_id, school_id, section_id, subject_variant, school_year, attempt_no)';
  END IF;
END $$;

-- crla_part1_english crla_part1_english_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_part1_english_pkey' AND conrelid = 'public.crla_part1_english'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_part1_english
    ADD CONSTRAINT crla_part1_english_pkey PRIMARY KEY (assessment_id)';
  END IF;
END $$;

-- crla_part1_standard crla_part1_standard_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_part1_standard_pkey' AND conrelid = 'public.crla_part1_standard'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_part1_standard
    ADD CONSTRAINT crla_part1_standard_pkey PRIMARY KEY (assessment_id)';
  END IF;
END $$;

-- crla_part2_fluency crla_part2_fluency_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_part2_fluency_pkey' AND conrelid = 'public.crla_part2_fluency'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_part2_fluency
    ADD CONSTRAINT crla_part2_fluency_pkey PRIMARY KEY (assessment_id)';
  END IF;
END $$;

-- crla_stories crla_stories_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_stories_pkey' AND conrelid = 'public.crla_stories'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_stories
    ADD CONSTRAINT crla_stories_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- crla_stories crla_stories_region_lang_grade_story_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_stories_region_lang_grade_story_key' AND conrelid = 'public.crla_stories'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_stories
    ADD CONSTRAINT crla_stories_region_lang_grade_story_key UNIQUE (region_id, language, grade, story_no)';
  END IF;
END $$;

-- crla_thresholds crla_thresholds_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_thresholds_pkey' AND conrelid = 'public.crla_thresholds'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_thresholds
    ADD CONSTRAINT crla_thresholds_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- enrollments enrollments_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'enrollments_pkey' AND conrelid = 'public.enrollments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- enrollments enrollments_student_id_school_year_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'enrollments_student_id_school_year_key' AND conrelid = 'public.enrollments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_student_id_school_year_key UNIQUE (student_id, school_year)';
  END IF;
END $$;

-- import_conflicts import_conflicts_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'import_conflicts_pkey' AND conrelid = 'public.import_conflicts'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.import_conflicts
    ADD CONSTRAINT import_conflicts_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- login_logs login_logs_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'login_logs_pkey' AND conrelid = 'public.login_logs'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.login_logs
    ADD CONSTRAINT login_logs_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- phil_iri_answers phil_iri_answers_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_answers_pkey' AND conrelid = 'public.phil_iri_answers'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_answers
    ADD CONSTRAINT phil_iri_answers_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- phil_iri_answers phil_iri_answers_question_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_answers_question_key' AND conrelid = 'public.phil_iri_answers'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_answers
    ADD CONSTRAINT phil_iri_answers_question_key UNIQUE (reading_id, question_id)';
  END IF;
END $$;

-- phil_iri_assessments phil_iri_assessments_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_assessments_pkey' AND conrelid = 'public.phil_iri_assessments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_assessments
    ADD CONSTRAINT phil_iri_assessments_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- phil_iri_collections phil_iri_collections_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_collections_pkey' AND conrelid = 'public.phil_iri_collections'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_collections
    ADD CONSTRAINT phil_iri_collections_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- phil_iri_gst_results phil_iri_gst_results_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_gst_results_pkey' AND conrelid = 'public.phil_iri_gst_results'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_gst_results
    ADD CONSTRAINT phil_iri_gst_results_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- phil_iri_miscues phil_iri_miscues_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_miscues_pkey' AND conrelid = 'public.phil_iri_miscues'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_miscues
    ADD CONSTRAINT phil_iri_miscues_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- phil_iri_passages phil_iri_passages_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_passages_pkey' AND conrelid = 'public.phil_iri_passages'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_passages
    ADD CONSTRAINT phil_iri_passages_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- phil_iri_questions phil_iri_questions_no_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_questions_no_key' AND conrelid = 'public.phil_iri_questions'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_questions
    ADD CONSTRAINT phil_iri_questions_no_key UNIQUE (passage_id, question_no)';
  END IF;
END $$;

-- phil_iri_questions phil_iri_questions_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_questions_pkey' AND conrelid = 'public.phil_iri_questions'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_questions
    ADD CONSTRAINT phil_iri_questions_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- phil_iri_readings phil_iri_readings_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_readings_pkey' AND conrelid = 'public.phil_iri_readings'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_readings
    ADD CONSTRAINT phil_iri_readings_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- phil_iri_readings phil_iri_readings_seq_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_readings_seq_key' AND conrelid = 'public.phil_iri_readings'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_readings
    ADD CONSTRAINT phil_iri_readings_seq_key UNIQUE (assessment_id, sequence_no)';
  END IF;
END $$;

-- phil_iri_rubric_criteria phil_iri_rubric_criteria_no_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_rubric_criteria_no_key' AND conrelid = 'public.phil_iri_rubric_criteria'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_rubric_criteria
    ADD CONSTRAINT phil_iri_rubric_criteria_no_key UNIQUE (collection_id, criterion_no)';
  END IF;
END $$;

-- phil_iri_rubric_criteria phil_iri_rubric_criteria_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_rubric_criteria_pkey' AND conrelid = 'public.phil_iri_rubric_criteria'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_rubric_criteria
    ADD CONSTRAINT phil_iri_rubric_criteria_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- phil_iri_rubric_scores phil_iri_rubric_scores_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_rubric_scores_key' AND conrelid = 'public.phil_iri_rubric_scores'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_rubric_scores
    ADD CONSTRAINT phil_iri_rubric_scores_key UNIQUE (assessment_id, criterion_id)';
  END IF;
END $$;

-- phil_iri_rubric_scores phil_iri_rubric_scores_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_rubric_scores_pkey' AND conrelid = 'public.phil_iri_rubric_scores'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_rubric_scores
    ADD CONSTRAINT phil_iri_rubric_scores_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- phil_iri_thresholds phil_iri_thresholds_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_thresholds_pkey' AND conrelid = 'public.phil_iri_thresholds'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_thresholds
    ADD CONSTRAINT phil_iri_thresholds_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- regions regions_code_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'regions_code_key' AND conrelid = 'public.regions'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.regions
    ADD CONSTRAINT regions_code_key UNIQUE (code)';
  END IF;
END $$;

-- regions regions_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'regions_pkey' AND conrelid = 'public.regions'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.regions
    ADD CONSTRAINT regions_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- schools schools_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'schools_pkey' AND conrelid = 'public.schools'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.schools
    ADD CONSTRAINT schools_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- schools schools_school_id_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'schools_school_id_key' AND conrelid = 'public.schools'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.schools
    ADD CONSTRAINT schools_school_id_key UNIQUE (school_id)';
  END IF;
END $$;

-- sections sections_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sections_pkey' AND conrelid = 'public.sections'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- sections sections_school_id_school_year_grade_level_section_name_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sections_school_id_school_year_grade_level_section_name_key' AND conrelid = 'public.sections'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_school_id_school_year_grade_level_section_name_key UNIQUE (school_id, school_year, grade_level, section_name)';
  END IF;
END $$;

-- students students_lrn_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'students_lrn_key' AND conrelid = 'public.students'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_lrn_key UNIQUE (lrn)';
  END IF;
END $$;

-- students students_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'students_pkey' AND conrelid = 'public.students'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- tutor_section_assignments tutor_section_assignments_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tutor_section_assignments_pkey' AND conrelid = 'public.tutor_section_assignments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.tutor_section_assignments
    ADD CONSTRAINT tutor_section_assignments_pkey PRIMARY KEY (id)';
  END IF;
END $$;

-- tutor_section_assignments tutor_section_assignments_tutor_section_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tutor_section_assignments_tutor_section_key' AND conrelid = 'public.tutor_section_assignments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.tutor_section_assignments
    ADD CONSTRAINT tutor_section_assignments_tutor_section_key UNIQUE (tutor_id, section_id)';
  END IF;
END $$;

-- users users_email_key
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_email_key' AND conrelid = 'public.users'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email)';
  END IF;
END $$;

-- users users_pkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_pkey' AND conrelid = 'public.users'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id)';
  END IF;
END $$;


-- fk constraints ---------------------------------------------------------

-- aral_attendance aral_attendance_enrollment_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_attendance_enrollment_id_fkey' AND conrelid = 'public.aral_attendance'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_attendance
    ADD CONSTRAINT aral_attendance_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.aral_enrollments(id) ON DELETE CASCADE';
  END IF;
END $$;

-- aral_attendance aral_attendance_session_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_attendance_session_id_fkey' AND conrelid = 'public.aral_attendance'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_attendance
    ADD CONSTRAINT aral_attendance_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.aral_sessions(id) ON DELETE CASCADE';
  END IF;
END $$;

-- aral_checkin_answers aral_checkin_answers_checkin_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkin_answers_checkin_id_fkey' AND conrelid = 'public.aral_checkin_answers'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkin_answers
    ADD CONSTRAINT aral_checkin_answers_checkin_id_fkey FOREIGN KEY (checkin_id) REFERENCES public.aral_checkins(id) ON DELETE CASCADE';
  END IF;
END $$;

-- aral_checkin_answers aral_checkin_answers_item_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkin_answers_item_id_fkey' AND conrelid = 'public.aral_checkin_answers'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkin_answers
    ADD CONSTRAINT aral_checkin_answers_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.aral_checkin_items(id)';
  END IF;
END $$;

-- aral_checkin_items aral_checkin_items_tool_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkin_items_tool_id_fkey' AND conrelid = 'public.aral_checkin_items'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkin_items
    ADD CONSTRAINT aral_checkin_items_tool_id_fkey FOREIGN KEY (tool_id) REFERENCES public.aral_checkin_tools(id)';
  END IF;
END $$;

-- aral_checkins aral_checkins_created_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkins_created_by_fkey' AND conrelid = 'public.aral_checkins'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkins
    ADD CONSTRAINT aral_checkins_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- aral_checkins aral_checkins_enrollment_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkins_enrollment_id_fkey' AND conrelid = 'public.aral_checkins'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkins
    ADD CONSTRAINT aral_checkins_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.aral_enrollments(id) ON DELETE CASCADE';
  END IF;
END $$;

-- aral_checkins aral_checkins_tool_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_checkins_tool_id_fkey' AND conrelid = 'public.aral_checkins'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_checkins
    ADD CONSTRAINT aral_checkins_tool_id_fkey FOREIGN KEY (tool_id) REFERENCES public.aral_checkin_tools(id)';
  END IF;
END $$;

-- aral_enrollments aral_enrollments_created_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_enrollments_created_by_fkey' AND conrelid = 'public.aral_enrollments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_enrollments
    ADD CONSTRAINT aral_enrollments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- aral_enrollments aral_enrollments_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_enrollments_school_id_fkey' AND conrelid = 'public.aral_enrollments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_enrollments
    ADD CONSTRAINT aral_enrollments_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- aral_enrollments aral_enrollments_section_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_enrollments_section_id_fkey' AND conrelid = 'public.aral_enrollments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_enrollments
    ADD CONSTRAINT aral_enrollments_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(id)';
  END IF;
END $$;

-- aral_enrollments aral_enrollments_student_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_enrollments_student_id_fkey' AND conrelid = 'public.aral_enrollments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_enrollments
    ADD CONSTRAINT aral_enrollments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id)';
  END IF;
END $$;

-- aral_enrollments aral_enrollments_tutor_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_enrollments_tutor_id_fkey' AND conrelid = 'public.aral_enrollments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_enrollments
    ADD CONSTRAINT aral_enrollments_tutor_id_fkey FOREIGN KEY (tutor_id) REFERENCES public.users(id)';
  END IF;
END $$;

-- aral_irip_weeks aral_irip_weeks_created_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_irip_weeks_created_by_fkey' AND conrelid = 'public.aral_irip_weeks'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_irip_weeks
    ADD CONSTRAINT aral_irip_weeks_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- aral_irip_weeks aral_irip_weeks_enrollment_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_irip_weeks_enrollment_id_fkey' AND conrelid = 'public.aral_irip_weeks'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_irip_weeks
    ADD CONSTRAINT aral_irip_weeks_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES public.aral_enrollments(id) ON DELETE CASCADE';
  END IF;
END $$;

-- aral_irip_weeks aral_irip_weeks_target_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_irip_weeks_target_id_fkey' AND conrelid = 'public.aral_irip_weeks'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_irip_weeks
    ADD CONSTRAINT aral_irip_weeks_target_id_fkey FOREIGN KEY (target_id) REFERENCES public.aral_irip_targets(id)';
  END IF;
END $$;

-- aral_material_links aral_material_links_material_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_material_links_material_id_fkey' AND conrelid = 'public.aral_material_links'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_material_links
    ADD CONSTRAINT aral_material_links_material_id_fkey FOREIGN KEY (material_id) REFERENCES public.aral_materials(id) ON DELETE CASCADE';
  END IF;
END $$;

-- aral_material_links aral_material_links_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_material_links_school_id_fkey' AND conrelid = 'public.aral_material_links'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_material_links
    ADD CONSTRAINT aral_material_links_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- aral_material_links aral_material_links_updated_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_material_links_updated_by_fkey' AND conrelid = 'public.aral_material_links'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_material_links
    ADD CONSTRAINT aral_material_links_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- aral_materials aral_materials_created_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_materials_created_by_fkey' AND conrelid = 'public.aral_materials'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_materials
    ADD CONSTRAINT aral_materials_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- aral_materials aral_materials_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_materials_school_id_fkey' AND conrelid = 'public.aral_materials'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_materials
    ADD CONSTRAINT aral_materials_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- aral_sessions aral_sessions_created_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_sessions_created_by_fkey' AND conrelid = 'public.aral_sessions'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_sessions
    ADD CONSTRAINT aral_sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- aral_sessions aral_sessions_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_sessions_school_id_fkey' AND conrelid = 'public.aral_sessions'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_sessions
    ADD CONSTRAINT aral_sessions_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- aral_sessions aral_sessions_tutor_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_sessions_tutor_id_fkey' AND conrelid = 'public.aral_sessions'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_sessions
    ADD CONSTRAINT aral_sessions_tutor_id_fkey FOREIGN KEY (tutor_id) REFERENCES public.users(id)';
  END IF;
END $$;

-- aral_settings aral_settings_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_settings_school_id_fkey' AND conrelid = 'public.aral_settings'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_settings
    ADD CONSTRAINT aral_settings_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- aral_settings aral_settings_updated_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_settings_updated_by_fkey' AND conrelid = 'public.aral_settings'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_settings
    ADD CONSTRAINT aral_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- aral_tutor_settings aral_tutor_settings_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_tutor_settings_school_id_fkey' AND conrelid = 'public.aral_tutor_settings'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_tutor_settings
    ADD CONSTRAINT aral_tutor_settings_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- aral_tutor_settings aral_tutor_settings_tutor_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_tutor_settings_tutor_id_fkey' AND conrelid = 'public.aral_tutor_settings'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_tutor_settings
    ADD CONSTRAINT aral_tutor_settings_tutor_id_fkey FOREIGN KEY (tutor_id) REFERENCES public.users(id)';
  END IF;
END $$;

-- aral_tutor_settings aral_tutor_settings_updated_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'aral_tutor_settings_updated_by_fkey' AND conrelid = 'public.aral_tutor_settings'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.aral_tutor_settings
    ADD CONSTRAINT aral_tutor_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- crla_assessments crla_assessments_administered_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_assessments_administered_by_fkey' AND conrelid = 'public.crla_assessments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_assessments
    ADD CONSTRAINT crla_assessments_administered_by_fkey FOREIGN KEY (administered_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- crla_assessments crla_assessments_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_assessments_school_id_fkey' AND conrelid = 'public.crla_assessments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_assessments
    ADD CONSTRAINT crla_assessments_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- crla_assessments crla_assessments_section_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_assessments_section_id_fkey' AND conrelid = 'public.crla_assessments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_assessments
    ADD CONSTRAINT crla_assessments_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(id)';
  END IF;
END $$;

-- crla_assessments crla_assessments_student_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_assessments_student_id_fkey' AND conrelid = 'public.crla_assessments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_assessments
    ADD CONSTRAINT crla_assessments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id)';
  END IF;
END $$;

-- crla_part1_english crla_part1_english_assessment_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_part1_english_assessment_id_fkey' AND conrelid = 'public.crla_part1_english'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_part1_english
    ADD CONSTRAINT crla_part1_english_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.crla_assessments(id) ON DELETE CASCADE';
  END IF;
END $$;

-- crla_part1_standard crla_part1_standard_assessment_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_part1_standard_assessment_id_fkey' AND conrelid = 'public.crla_part1_standard'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_part1_standard
    ADD CONSTRAINT crla_part1_standard_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.crla_assessments(id) ON DELETE CASCADE';
  END IF;
END $$;

-- crla_part2_fluency crla_part2_fluency_assessment_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_part2_fluency_assessment_id_fkey' AND conrelid = 'public.crla_part2_fluency'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_part2_fluency
    ADD CONSTRAINT crla_part2_fluency_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.crla_assessments(id) ON DELETE CASCADE';
  END IF;
END $$;

-- crla_stories crla_stories_region_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_stories_region_id_fkey' AND conrelid = 'public.crla_stories'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_stories
    ADD CONSTRAINT crla_stories_region_id_fkey FOREIGN KEY (region_id) REFERENCES public.regions(id)';
  END IF;
END $$;

-- crla_thresholds crla_thresholds_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_thresholds_school_id_fkey' AND conrelid = 'public.crla_thresholds'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_thresholds
    ADD CONSTRAINT crla_thresholds_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- crla_thresholds crla_thresholds_updated_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'crla_thresholds_updated_by_fkey' AND conrelid = 'public.crla_thresholds'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.crla_thresholds
    ADD CONSTRAINT crla_thresholds_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- enrollments enrollments_section_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'enrollments_section_id_fkey' AND conrelid = 'public.enrollments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(id)';
  END IF;
END $$;

-- enrollments enrollments_student_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'enrollments_student_id_fkey' AND conrelid = 'public.enrollments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id)';
  END IF;
END $$;

-- import_conflicts import_conflicts_existing_student_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'import_conflicts_existing_student_id_fkey' AND conrelid = 'public.import_conflicts'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.import_conflicts
    ADD CONSTRAINT import_conflicts_existing_student_id_fkey FOREIGN KEY (existing_student_id) REFERENCES public.students(id)';
  END IF;
END $$;

-- import_conflicts import_conflicts_section_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'import_conflicts_section_id_fkey' AND conrelid = 'public.import_conflicts'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.import_conflicts
    ADD CONSTRAINT import_conflicts_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(id)';
  END IF;
END $$;

-- login_logs login_logs_user_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'login_logs_user_id_fkey' AND conrelid = 'public.login_logs'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.login_logs
    ADD CONSTRAINT login_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)';
  END IF;
END $$;

-- phil_iri_answers phil_iri_answers_question_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_answers_question_id_fkey' AND conrelid = 'public.phil_iri_answers'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_answers
    ADD CONSTRAINT phil_iri_answers_question_id_fkey FOREIGN KEY (question_id) REFERENCES public.phil_iri_questions(id)';
  END IF;
END $$;

-- phil_iri_answers phil_iri_answers_reading_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_answers_reading_id_fkey' AND conrelid = 'public.phil_iri_answers'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_answers
    ADD CONSTRAINT phil_iri_answers_reading_id_fkey FOREIGN KEY (reading_id) REFERENCES public.phil_iri_readings(id) ON DELETE CASCADE';
  END IF;
END $$;

-- phil_iri_assessments phil_iri_assessments_administered_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_assessments_administered_by_fkey' AND conrelid = 'public.phil_iri_assessments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_assessments
    ADD CONSTRAINT phil_iri_assessments_administered_by_fkey FOREIGN KEY (administered_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- phil_iri_assessments phil_iri_assessments_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_assessments_school_id_fkey' AND conrelid = 'public.phil_iri_assessments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_assessments
    ADD CONSTRAINT phil_iri_assessments_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- phil_iri_assessments phil_iri_assessments_section_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_assessments_section_id_fkey' AND conrelid = 'public.phil_iri_assessments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_assessments
    ADD CONSTRAINT phil_iri_assessments_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(id)';
  END IF;
END $$;

-- phil_iri_assessments phil_iri_assessments_student_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_assessments_student_id_fkey' AND conrelid = 'public.phil_iri_assessments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_assessments
    ADD CONSTRAINT phil_iri_assessments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id)';
  END IF;
END $$;

-- phil_iri_collections phil_iri_collections_created_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_collections_created_by_fkey' AND conrelid = 'public.phil_iri_collections'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_collections
    ADD CONSTRAINT phil_iri_collections_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- phil_iri_collections phil_iri_collections_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_collections_school_id_fkey' AND conrelid = 'public.phil_iri_collections'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_collections
    ADD CONSTRAINT phil_iri_collections_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- phil_iri_gst_results phil_iri_gst_results_administered_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_gst_results_administered_by_fkey' AND conrelid = 'public.phil_iri_gst_results'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_gst_results
    ADD CONSTRAINT phil_iri_gst_results_administered_by_fkey FOREIGN KEY (administered_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- phil_iri_gst_results phil_iri_gst_results_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_gst_results_school_id_fkey' AND conrelid = 'public.phil_iri_gst_results'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_gst_results
    ADD CONSTRAINT phil_iri_gst_results_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- phil_iri_gst_results phil_iri_gst_results_section_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_gst_results_section_id_fkey' AND conrelid = 'public.phil_iri_gst_results'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_gst_results
    ADD CONSTRAINT phil_iri_gst_results_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(id)';
  END IF;
END $$;

-- phil_iri_gst_results phil_iri_gst_results_student_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_gst_results_student_id_fkey' AND conrelid = 'public.phil_iri_gst_results'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_gst_results
    ADD CONSTRAINT phil_iri_gst_results_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id)';
  END IF;
END $$;

-- phil_iri_miscues phil_iri_miscues_reading_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_miscues_reading_id_fkey' AND conrelid = 'public.phil_iri_miscues'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_miscues
    ADD CONSTRAINT phil_iri_miscues_reading_id_fkey FOREIGN KEY (reading_id) REFERENCES public.phil_iri_readings(id) ON DELETE CASCADE';
  END IF;
END $$;

-- phil_iri_passages phil_iri_passages_collection_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_passages_collection_id_fkey' AND conrelid = 'public.phil_iri_passages'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_passages
    ADD CONSTRAINT phil_iri_passages_collection_id_fkey FOREIGN KEY (collection_id) REFERENCES public.phil_iri_collections(id)';
  END IF;
END $$;

-- phil_iri_passages phil_iri_passages_created_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_passages_created_by_fkey' AND conrelid = 'public.phil_iri_passages'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_passages
    ADD CONSTRAINT phil_iri_passages_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- phil_iri_questions phil_iri_questions_passage_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_questions_passage_id_fkey' AND conrelid = 'public.phil_iri_questions'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_questions
    ADD CONSTRAINT phil_iri_questions_passage_id_fkey FOREIGN KEY (passage_id) REFERENCES public.phil_iri_passages(id) ON DELETE CASCADE';
  END IF;
END $$;

-- phil_iri_readings phil_iri_readings_assessment_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_readings_assessment_id_fkey' AND conrelid = 'public.phil_iri_readings'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_readings
    ADD CONSTRAINT phil_iri_readings_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.phil_iri_assessments(id) ON DELETE CASCADE';
  END IF;
END $$;

-- phil_iri_readings phil_iri_readings_passage_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_readings_passage_id_fkey' AND conrelid = 'public.phil_iri_readings'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_readings
    ADD CONSTRAINT phil_iri_readings_passage_id_fkey FOREIGN KEY (passage_id) REFERENCES public.phil_iri_passages(id)';
  END IF;
END $$;

-- phil_iri_rubric_criteria phil_iri_rubric_criteria_collection_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_rubric_criteria_collection_id_fkey' AND conrelid = 'public.phil_iri_rubric_criteria'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_rubric_criteria
    ADD CONSTRAINT phil_iri_rubric_criteria_collection_id_fkey FOREIGN KEY (collection_id) REFERENCES public.phil_iri_collections(id) ON DELETE CASCADE';
  END IF;
END $$;

-- phil_iri_rubric_scores phil_iri_rubric_scores_assessment_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_rubric_scores_assessment_id_fkey' AND conrelid = 'public.phil_iri_rubric_scores'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_rubric_scores
    ADD CONSTRAINT phil_iri_rubric_scores_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES public.phil_iri_assessments(id) ON DELETE CASCADE';
  END IF;
END $$;

-- phil_iri_rubric_scores phil_iri_rubric_scores_criterion_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_rubric_scores_criterion_id_fkey' AND conrelid = 'public.phil_iri_rubric_scores'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_rubric_scores
    ADD CONSTRAINT phil_iri_rubric_scores_criterion_id_fkey FOREIGN KEY (criterion_id) REFERENCES public.phil_iri_rubric_criteria(id)';
  END IF;
END $$;

-- phil_iri_thresholds phil_iri_thresholds_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_thresholds_school_id_fkey' AND conrelid = 'public.phil_iri_thresholds'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_thresholds
    ADD CONSTRAINT phil_iri_thresholds_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- phil_iri_thresholds phil_iri_thresholds_updated_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phil_iri_thresholds_updated_by_fkey' AND conrelid = 'public.phil_iri_thresholds'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.phil_iri_thresholds
    ADD CONSTRAINT phil_iri_thresholds_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- schools schools_region_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'schools_region_id_fkey' AND conrelid = 'public.schools'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.schools
    ADD CONSTRAINT schools_region_id_fkey FOREIGN KEY (region_id) REFERENCES public.regions(id)';
  END IF;
END $$;

-- sections sections_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sections_school_id_fkey' AND conrelid = 'public.sections'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- students students_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'students_school_id_fkey' AND conrelid = 'public.students'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;

-- tutor_section_assignments tutor_section_assignments_assigned_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tutor_section_assignments_assigned_by_fkey' AND conrelid = 'public.tutor_section_assignments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.tutor_section_assignments
    ADD CONSTRAINT tutor_section_assignments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- tutor_section_assignments tutor_section_assignments_section_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tutor_section_assignments_section_id_fkey' AND conrelid = 'public.tutor_section_assignments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.tutor_section_assignments
    ADD CONSTRAINT tutor_section_assignments_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(id)';
  END IF;
END $$;

-- tutor_section_assignments tutor_section_assignments_tutor_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tutor_section_assignments_tutor_id_fkey' AND conrelid = 'public.tutor_section_assignments'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.tutor_section_assignments
    ADD CONSTRAINT tutor_section_assignments_tutor_id_fkey FOREIGN KEY (tutor_id) REFERENCES public.users(id)';
  END IF;
END $$;

-- users users_created_by_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_created_by_fkey' AND conrelid = 'public.users'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)';
  END IF;
END $$;

-- users users_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_id_fkey' AND conrelid = 'public.users'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE';
  END IF;
END $$;

-- users users_school_id_fkey
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_school_id_fkey' AND conrelid = 'public.users'::regclass) THEN
    EXECUTE 'ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)';
  END IF;
END $$;


-- indexs -----------------------------------------------------------------

-- aral_attendance_enrollment
CREATE INDEX IF NOT EXISTS aral_attendance_enrollment ON public.aral_attendance USING btree (enrollment_id);

-- aral_checkins_enrollment
CREATE INDEX IF NOT EXISTS aral_checkins_enrollment ON public.aral_checkins USING btree (enrollment_id, tool_id);

-- aral_enrollments_school
CREATE INDEX IF NOT EXISTS aral_enrollments_school ON public.aral_enrollments USING btree (school_id, school_year);

-- aral_enrollments_section
CREATE INDEX IF NOT EXISTS aral_enrollments_section ON public.aral_enrollments USING btree (section_id, school_year);

-- aral_enrollments_tutor
CREATE INDEX IF NOT EXISTS aral_enrollments_tutor ON public.aral_enrollments USING btree (tutor_id, school_year);

-- aral_irip_weeks_enrollment
CREATE INDEX IF NOT EXISTS aral_irip_weeks_enrollment ON public.aral_irip_weeks USING btree (enrollment_id, cycle_no, week_no);

-- aral_materials_program
CREATE INDEX IF NOT EXISTS aral_materials_program ON public.aral_materials USING btree (key_stage, track);

-- aral_materials_title_key
CREATE UNIQUE INDEX IF NOT EXISTS aral_materials_title_key ON public.aral_materials USING btree (COALESCE(school_id, (0)::bigint), lower(title));

-- aral_sessions_school
CREATE INDEX IF NOT EXISTS aral_sessions_school ON public.aral_sessions USING btree (school_id, school_year, held_on);

-- aral_sessions_tutor
CREATE INDEX IF NOT EXISTS aral_sessions_tutor ON public.aral_sessions USING btree (tutor_id, school_year, held_on);

-- aral_settings_school_key
CREATE UNIQUE INDEX IF NOT EXISTS aral_settings_school_key ON public.aral_settings USING btree (COALESCE(school_id, (0)::bigint));

-- aral_tutor_settings_school
CREATE INDEX IF NOT EXISTS aral_tutor_settings_school ON public.aral_tutor_settings USING btree (school_id);

-- crla_thresholds_school_key
CREATE UNIQUE INDEX IF NOT EXISTS crla_thresholds_school_key ON public.crla_thresholds USING btree (COALESCE(school_id, (0)::bigint));

-- phil_iri_assessments_school_round
CREATE INDEX IF NOT EXISTS phil_iri_assessments_school_round ON public.phil_iri_assessments USING btree (school_id, school_year, round);

-- phil_iri_assessments_student
CREATE INDEX IF NOT EXISTS phil_iri_assessments_student ON public.phil_iri_assessments USING btree (student_id, school_year, round);

-- phil_iri_collections_name_key
CREATE UNIQUE INDEX IF NOT EXISTS phil_iri_collections_name_key ON public.phil_iri_collections USING btree (COALESCE(school_id, (0)::bigint), lower(name));

-- phil_iri_gst_results_student
CREATE INDEX IF NOT EXISTS phil_iri_gst_results_student ON public.phil_iri_gst_results USING btree (student_id, school_year);

-- phil_iri_miscues_reading
CREATE INDEX IF NOT EXISTS phil_iri_miscues_reading ON public.phil_iri_miscues USING btree (reading_id);

-- phil_iri_passages_collection_level
CREATE INDEX IF NOT EXISTS phil_iri_passages_collection_level ON public.phil_iri_passages USING btree (collection_id, level);

-- phil_iri_readings_passage
CREATE INDEX IF NOT EXISTS phil_iri_readings_passage ON public.phil_iri_readings USING btree (passage_id);

-- phil_iri_thresholds_school_key
CREATE UNIQUE INDEX IF NOT EXISTS phil_iri_thresholds_school_key ON public.phil_iri_thresholds USING btree (COALESCE(school_id, (0)::bigint));


-- triggers ---------------------------------------------------------------

-- aral_attendance aral_attendance_check
DROP TRIGGER IF EXISTS aral_attendance_check ON public.aral_attendance;
CREATE TRIGGER aral_attendance_check BEFORE INSERT OR UPDATE ON public.aral_attendance FOR EACH ROW EXECUTE FUNCTION public.check_aral_attendance();

-- aral_checkin_answers aral_checkin_answers_before_write
DROP TRIGGER IF EXISTS aral_checkin_answers_before_write ON public.aral_checkin_answers;
CREATE TRIGGER aral_checkin_answers_before_write BEFORE INSERT OR UPDATE ON public.aral_checkin_answers FOR EACH ROW EXECUTE FUNCTION public.aral_checkin_answers_before_write();

-- aral_checkins aral_checkins_before_write
DROP TRIGGER IF EXISTS aral_checkins_before_write ON public.aral_checkins;
CREATE TRIGGER aral_checkins_before_write BEFORE INSERT OR UPDATE ON public.aral_checkins FOR EACH ROW EXECUTE FUNCTION public.aral_checkins_before_write();

-- aral_enrollments aral_enrollments_before_insert
DROP TRIGGER IF EXISTS aral_enrollments_before_insert ON public.aral_enrollments;
CREATE TRIGGER aral_enrollments_before_insert BEFORE INSERT ON public.aral_enrollments FOR EACH ROW EXECUTE FUNCTION public.aral_enrollments_before_insert();

-- aral_enrollments aral_enrollments_before_update
DROP TRIGGER IF EXISTS aral_enrollments_before_update ON public.aral_enrollments;
CREATE TRIGGER aral_enrollments_before_update BEFORE UPDATE ON public.aral_enrollments FOR EACH ROW EXECUTE FUNCTION public.aral_enrollments_before_update();

-- aral_irip_weeks aral_irip_weeks_before_write
DROP TRIGGER IF EXISTS aral_irip_weeks_before_write ON public.aral_irip_weeks;
CREATE TRIGGER aral_irip_weeks_before_write BEFORE INSERT OR UPDATE ON public.aral_irip_weeks FOR EACH ROW EXECUTE FUNCTION public.aral_irip_weeks_before_write();

-- aral_material_links aral_material_links_stamp
DROP TRIGGER IF EXISTS aral_material_links_stamp ON public.aral_material_links;
CREATE TRIGGER aral_material_links_stamp BEFORE INSERT OR UPDATE ON public.aral_material_links FOR EACH ROW EXECUTE FUNCTION public.aral_material_links_stamp();

-- aral_materials aral_materials_stamp
DROP TRIGGER IF EXISTS aral_materials_stamp ON public.aral_materials;
CREATE TRIGGER aral_materials_stamp BEFORE INSERT OR UPDATE ON public.aral_materials FOR EACH ROW EXECUTE FUNCTION public.aral_materials_stamp();

-- aral_sessions aral_sessions_before_insert
DROP TRIGGER IF EXISTS aral_sessions_before_insert ON public.aral_sessions;
CREATE TRIGGER aral_sessions_before_insert BEFORE INSERT ON public.aral_sessions FOR EACH ROW EXECUTE FUNCTION public.aral_sessions_before_insert();

-- aral_sessions aral_sessions_before_update
DROP TRIGGER IF EXISTS aral_sessions_before_update ON public.aral_sessions;
CREATE TRIGGER aral_sessions_before_update BEFORE UPDATE ON public.aral_sessions FOR EACH ROW EXECUTE FUNCTION public.aral_sessions_before_update();

-- aral_settings aral_settings_stamp
DROP TRIGGER IF EXISTS aral_settings_stamp ON public.aral_settings;
CREATE TRIGGER aral_settings_stamp BEFORE INSERT OR UPDATE ON public.aral_settings FOR EACH ROW EXECUTE FUNCTION public.aral_settings_stamp();

-- aral_tutor_settings aral_tutor_settings_before_write
DROP TRIGGER IF EXISTS aral_tutor_settings_before_write ON public.aral_tutor_settings;
CREATE TRIGGER aral_tutor_settings_before_write BEFORE INSERT OR UPDATE ON public.aral_tutor_settings FOR EACH ROW EXECUTE FUNCTION public.aral_tutor_settings_before_write();

-- crla_assessments crla_assessments_before_insert
DROP TRIGGER IF EXISTS crla_assessments_before_insert ON public.crla_assessments;
CREATE TRIGGER crla_assessments_before_insert BEFORE INSERT ON public.crla_assessments FOR EACH ROW EXECUTE FUNCTION public.crla_assessments_before_insert();

-- crla_part1_english crla_part1_english_check_variant
DROP TRIGGER IF EXISTS crla_part1_english_check_variant ON public.crla_part1_english;
CREATE TRIGGER crla_part1_english_check_variant BEFORE INSERT OR UPDATE ON public.crla_part1_english FOR EACH ROW EXECUTE FUNCTION public.check_crla_part1_variant('eng');

-- crla_part1_english crla_part1_english_refresh_profile
DROP TRIGGER IF EXISTS crla_part1_english_refresh_profile ON public.crla_part1_english;
CREATE TRIGGER crla_part1_english_refresh_profile AFTER INSERT OR DELETE OR UPDATE ON public.crla_part1_english FOR EACH ROW EXECUTE FUNCTION public.crla_refresh_profile_trigger();

-- crla_part1_english crla_part1_english_set_level
DROP TRIGGER IF EXISTS crla_part1_english_set_level ON public.crla_part1_english;
CREATE TRIGGER crla_part1_english_set_level BEFORE INSERT OR UPDATE ON public.crla_part1_english FOR EACH ROW EXECUTE FUNCTION public.crla_part1_set_level();

-- crla_part1_standard crla_part1_standard_check_variant
DROP TRIGGER IF EXISTS crla_part1_standard_check_variant ON public.crla_part1_standard;
CREATE TRIGGER crla_part1_standard_check_variant BEFORE INSERT OR UPDATE ON public.crla_part1_standard FOR EACH ROW EXECUTE FUNCTION public.check_crla_part1_variant('mt', 'fil');

-- crla_part1_standard crla_part1_standard_refresh_profile
DROP TRIGGER IF EXISTS crla_part1_standard_refresh_profile ON public.crla_part1_standard;
CREATE TRIGGER crla_part1_standard_refresh_profile AFTER INSERT OR DELETE OR UPDATE ON public.crla_part1_standard FOR EACH ROW EXECUTE FUNCTION public.crla_refresh_profile_trigger();

-- crla_part1_standard crla_part1_standard_set_level
DROP TRIGGER IF EXISTS crla_part1_standard_set_level ON public.crla_part1_standard;
CREATE TRIGGER crla_part1_standard_set_level BEFORE INSERT OR UPDATE ON public.crla_part1_standard FOR EACH ROW EXECUTE FUNCTION public.crla_part1_set_level();

-- crla_part2_fluency crla_part2_fluency_check_limits
DROP TRIGGER IF EXISTS crla_part2_fluency_check_limits ON public.crla_part2_fluency;
CREATE TRIGGER crla_part2_fluency_check_limits BEFORE INSERT OR UPDATE ON public.crla_part2_fluency FOR EACH ROW EXECUTE FUNCTION public.check_crla_part2_limits();

-- crla_part2_fluency crla_part2_fluency_refresh_profile
DROP TRIGGER IF EXISTS crla_part2_fluency_refresh_profile ON public.crla_part2_fluency;
CREATE TRIGGER crla_part2_fluency_refresh_profile AFTER INSERT OR DELETE OR UPDATE ON public.crla_part2_fluency FOR EACH ROW EXECUTE FUNCTION public.crla_refresh_profile_trigger();

-- crla_thresholds crla_thresholds_stamp
DROP TRIGGER IF EXISTS crla_thresholds_stamp ON public.crla_thresholds;
CREATE TRIGGER crla_thresholds_stamp BEFORE INSERT OR UPDATE ON public.crla_thresholds FOR EACH ROW EXECUTE FUNCTION public.crla_thresholds_stamp();

-- enrollments enrollments_sync_student_school
DROP TRIGGER IF EXISTS enrollments_sync_student_school ON public.enrollments;
CREATE TRIGGER enrollments_sync_student_school AFTER INSERT OR UPDATE ON public.enrollments FOR EACH ROW EXECUTE FUNCTION public.sync_student_school_id();

-- phil_iri_answers phil_iri_answers_check
DROP TRIGGER IF EXISTS phil_iri_answers_check ON public.phil_iri_answers;
CREATE TRIGGER phil_iri_answers_check BEFORE INSERT OR UPDATE ON public.phil_iri_answers FOR EACH ROW EXECUTE FUNCTION public.check_phil_iri_answer();

-- phil_iri_assessments phil_iri_assessments_before_insert
DROP TRIGGER IF EXISTS phil_iri_assessments_before_insert ON public.phil_iri_assessments;
CREATE TRIGGER phil_iri_assessments_before_insert BEFORE INSERT ON public.phil_iri_assessments FOR EACH ROW EXECUTE FUNCTION public.phil_iri_assessments_before_insert();

-- phil_iri_assessments phil_iri_assessments_before_update
DROP TRIGGER IF EXISTS phil_iri_assessments_before_update ON public.phil_iri_assessments;
CREATE TRIGGER phil_iri_assessments_before_update BEFORE UPDATE ON public.phil_iri_assessments FOR EACH ROW EXECUTE FUNCTION public.phil_iri_assessments_before_update();

-- phil_iri_collections phil_iri_collections_created_by
DROP TRIGGER IF EXISTS phil_iri_collections_created_by ON public.phil_iri_collections;
CREATE TRIGGER phil_iri_collections_created_by BEFORE INSERT ON public.phil_iri_collections FOR EACH ROW EXECUTE FUNCTION public.phil_iri_stamp_created_by();

-- phil_iri_collections phil_iri_collections_lock_grading
DROP TRIGGER IF EXISTS phil_iri_collections_lock_grading ON public.phil_iri_collections;
CREATE TRIGGER phil_iri_collections_lock_grading BEFORE UPDATE ON public.phil_iri_collections FOR EACH ROW EXECUTE FUNCTION public.lock_phil_iri_collection_grading();

-- phil_iri_collections phil_iri_collections_updated_at
DROP TRIGGER IF EXISTS phil_iri_collections_updated_at ON public.phil_iri_collections;
CREATE TRIGGER phil_iri_collections_updated_at BEFORE UPDATE ON public.phil_iri_collections FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- phil_iri_gst_results phil_iri_gst_results_before_insert
DROP TRIGGER IF EXISTS phil_iri_gst_results_before_insert ON public.phil_iri_gst_results;
CREATE TRIGGER phil_iri_gst_results_before_insert BEFORE INSERT ON public.phil_iri_gst_results FOR EACH ROW EXECUTE FUNCTION public.phil_iri_gst_results_before_insert();

-- phil_iri_miscues phil_iri_miscues_check
DROP TRIGGER IF EXISTS phil_iri_miscues_check ON public.phil_iri_miscues;
CREATE TRIGGER phil_iri_miscues_check BEFORE INSERT OR UPDATE ON public.phil_iri_miscues FOR EACH ROW EXECUTE FUNCTION public.check_phil_iri_miscue();

-- phil_iri_passages phil_iri_passages_created_by
DROP TRIGGER IF EXISTS phil_iri_passages_created_by ON public.phil_iri_passages;
CREATE TRIGGER phil_iri_passages_created_by BEFORE INSERT ON public.phil_iri_passages FOR EACH ROW EXECUTE FUNCTION public.phil_iri_stamp_created_by();

-- phil_iri_passages phil_iri_passages_level
DROP TRIGGER IF EXISTS phil_iri_passages_level ON public.phil_iri_passages;
CREATE TRIGGER phil_iri_passages_level BEFORE INSERT OR UPDATE OF collection_id, level ON public.phil_iri_passages FOR EACH ROW EXECUTE FUNCTION public.check_phil_iri_passage_level();

-- phil_iri_passages phil_iri_passages_lock_read
DROP TRIGGER IF EXISTS phil_iri_passages_lock_read ON public.phil_iri_passages;
CREATE TRIGGER phil_iri_passages_lock_read BEFORE UPDATE ON public.phil_iri_passages FOR EACH ROW EXECUTE FUNCTION public.lock_phil_iri_read_passage();

-- phil_iri_passages phil_iri_passages_updated_at
DROP TRIGGER IF EXISTS phil_iri_passages_updated_at ON public.phil_iri_passages;
CREATE TRIGGER phil_iri_passages_updated_at BEFORE UPDATE ON public.phil_iri_passages FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- phil_iri_readings phil_iri_readings_check
DROP TRIGGER IF EXISTS phil_iri_readings_check ON public.phil_iri_readings;
CREATE TRIGGER phil_iri_readings_check BEFORE INSERT OR UPDATE ON public.phil_iri_readings FOR EACH ROW EXECUTE FUNCTION public.check_phil_iri_reading();

-- phil_iri_rubric_scores phil_iri_rubric_scores_check
DROP TRIGGER IF EXISTS phil_iri_rubric_scores_check ON public.phil_iri_rubric_scores;
CREATE TRIGGER phil_iri_rubric_scores_check BEFORE INSERT OR UPDATE ON public.phil_iri_rubric_scores FOR EACH ROW EXECUTE FUNCTION public.check_phil_iri_rubric_score();

-- phil_iri_thresholds phil_iri_thresholds_stamp
DROP TRIGGER IF EXISTS phil_iri_thresholds_stamp ON public.phil_iri_thresholds;
CREATE TRIGGER phil_iri_thresholds_stamp BEFORE INSERT OR UPDATE ON public.phil_iri_thresholds FOR EACH ROW EXECUTE FUNCTION public.phil_iri_thresholds_stamp();

-- schools schools_guard_identity
DROP TRIGGER IF EXISTS schools_guard_identity ON public.schools;
CREATE TRIGGER schools_guard_identity BEFORE UPDATE ON public.schools FOR EACH ROW EXECUTE FUNCTION public.guard_school_identity();

-- students students_set_updated_at
DROP TRIGGER IF EXISTS students_set_updated_at ON public.students;
CREATE TRIGGER students_set_updated_at BEFORE UPDATE ON public.students FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- tutor_section_assignments tutor_section_assignments_validate
DROP TRIGGER IF EXISTS tutor_section_assignments_validate ON public.tutor_section_assignments;
CREATE TRIGGER tutor_section_assignments_validate BEFORE INSERT OR UPDATE ON public.tutor_section_assignments FOR EACH ROW EXECUTE FUNCTION public.validate_tutor_section_assignment();


-- policys ----------------------------------------------------------------

-- users Users can read own profile
DROP POLICY IF EXISTS "Users can read own profile" ON public.users;
CREATE POLICY "Users can read own profile" ON public.users FOR SELECT TO authenticated USING ((auth.uid() = id));

-- aral_attendance aral_attendance_select
DROP POLICY IF EXISTS aral_attendance_select ON public.aral_attendance;
CREATE POLICY aral_attendance_select ON public.aral_attendance FOR SELECT TO authenticated USING (public.aral_session_readable(session_id));

-- aral_attendance aral_attendance_write
DROP POLICY IF EXISTS aral_attendance_write ON public.aral_attendance;
CREATE POLICY aral_attendance_write ON public.aral_attendance TO authenticated USING (public.aral_session_writable(session_id)) WITH CHECK (public.aral_session_writable(session_id));

-- aral_checkin_answers aral_checkin_answers_delete
DROP POLICY IF EXISTS aral_checkin_answers_delete ON public.aral_checkin_answers;
CREATE POLICY aral_checkin_answers_delete ON public.aral_checkin_answers FOR DELETE TO authenticated USING (public.aral_checkin_writable(checkin_id));

-- aral_checkin_answers aral_checkin_answers_insert
DROP POLICY IF EXISTS aral_checkin_answers_insert ON public.aral_checkin_answers;
CREATE POLICY aral_checkin_answers_insert ON public.aral_checkin_answers FOR INSERT TO authenticated WITH CHECK (public.aral_checkin_writable(checkin_id));

-- aral_checkin_answers aral_checkin_answers_select
DROP POLICY IF EXISTS aral_checkin_answers_select ON public.aral_checkin_answers;
CREATE POLICY aral_checkin_answers_select ON public.aral_checkin_answers FOR SELECT TO authenticated USING (public.aral_checkin_readable(checkin_id));

-- aral_checkin_answers aral_checkin_answers_update
DROP POLICY IF EXISTS aral_checkin_answers_update ON public.aral_checkin_answers;
CREATE POLICY aral_checkin_answers_update ON public.aral_checkin_answers FOR UPDATE TO authenticated USING (public.aral_checkin_writable(checkin_id)) WITH CHECK (public.aral_checkin_writable(checkin_id));

-- aral_checkin_items aral_checkin_items_select
DROP POLICY IF EXISTS aral_checkin_items_select ON public.aral_checkin_items;
CREATE POLICY aral_checkin_items_select ON public.aral_checkin_items FOR SELECT TO authenticated USING (true);

-- aral_checkin_items aral_checkin_items_write
DROP POLICY IF EXISTS aral_checkin_items_write ON public.aral_checkin_items;
CREATE POLICY aral_checkin_items_write ON public.aral_checkin_items TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());

-- aral_checkin_tools aral_checkin_tools_select
DROP POLICY IF EXISTS aral_checkin_tools_select ON public.aral_checkin_tools;
CREATE POLICY aral_checkin_tools_select ON public.aral_checkin_tools FOR SELECT TO authenticated USING (true);

-- aral_checkin_tools aral_checkin_tools_write
DROP POLICY IF EXISTS aral_checkin_tools_write ON public.aral_checkin_tools;
CREATE POLICY aral_checkin_tools_write ON public.aral_checkin_tools TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());

-- aral_checkins aral_checkins_delete
DROP POLICY IF EXISTS aral_checkins_delete ON public.aral_checkins;
CREATE POLICY aral_checkins_delete ON public.aral_checkins FOR DELETE TO authenticated USING (public.aral_irip_writable(enrollment_id));

-- aral_checkins aral_checkins_insert
DROP POLICY IF EXISTS aral_checkins_insert ON public.aral_checkins;
CREATE POLICY aral_checkins_insert ON public.aral_checkins FOR INSERT TO authenticated WITH CHECK (public.aral_irip_writable(enrollment_id));

-- aral_checkins aral_checkins_select
DROP POLICY IF EXISTS aral_checkins_select ON public.aral_checkins;
CREATE POLICY aral_checkins_select ON public.aral_checkins FOR SELECT TO authenticated USING (public.aral_enrollment_readable(enrollment_id));

-- aral_checkins aral_checkins_update
DROP POLICY IF EXISTS aral_checkins_update ON public.aral_checkins;
CREATE POLICY aral_checkins_update ON public.aral_checkins FOR UPDATE TO authenticated USING (public.aral_irip_writable(enrollment_id)) WITH CHECK (public.aral_irip_writable(enrollment_id));

-- aral_enrollments aral_enrollments_delete
DROP POLICY IF EXISTS aral_enrollments_delete ON public.aral_enrollments;
CREATE POLICY aral_enrollments_delete ON public.aral_enrollments FOR DELETE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- aral_enrollments aral_enrollments_insert
DROP POLICY IF EXISTS aral_enrollments_insert ON public.aral_enrollments;
CREATE POLICY aral_enrollments_insert ON public.aral_enrollments FOR INSERT TO authenticated WITH CHECK (((EXISTS ( SELECT 1
   FROM (public.sections s
     JOIN public.enrollments e ON ((e.section_id = s.id)))
  WHERE ((s.id = aral_enrollments.section_id) AND (s.school_id = aral_enrollments.school_id) AND (s.grade_level = ANY (ARRAY['1'::text, '2'::text, '3'::text, '4'::text, '5'::text, '6'::text, '7'::text, '8'::text, '9'::text, '10'::text])) AND (e.student_id = aral_enrollments.student_id) AND (e.school_year = aral_enrollments.school_year) AND (e.status = 'active'::text)))) AND (public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())))));

-- aral_enrollments aral_enrollments_select
DROP POLICY IF EXISTS aral_enrollments_select ON public.aral_enrollments;
CREATE POLICY aral_enrollments_select ON public.aral_enrollments FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND ((tutor_id = auth.uid()) OR public.tutor_has_section(section_id)))));

-- aral_enrollments aral_enrollments_update
DROP POLICY IF EXISTS aral_enrollments_update ON public.aral_enrollments;
CREATE POLICY aral_enrollments_update ON public.aral_enrollments FOR UPDATE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())))) WITH CHECK (((EXISTS ( SELECT 1
   FROM (public.sections s
     JOIN public.enrollments e ON ((e.section_id = s.id)))
  WHERE ((s.id = aral_enrollments.section_id) AND (s.school_id = aral_enrollments.school_id) AND (s.grade_level = ANY (ARRAY['1'::text, '2'::text, '3'::text, '4'::text, '5'::text, '6'::text, '7'::text, '8'::text, '9'::text, '10'::text])) AND (e.student_id = aral_enrollments.student_id) AND (e.school_year = aral_enrollments.school_year)))) AND (public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())))));

-- aral_irip_targets aral_irip_targets_select
DROP POLICY IF EXISTS aral_irip_targets_select ON public.aral_irip_targets;
CREATE POLICY aral_irip_targets_select ON public.aral_irip_targets FOR SELECT TO authenticated USING (true);

-- aral_irip_targets aral_irip_targets_write
DROP POLICY IF EXISTS aral_irip_targets_write ON public.aral_irip_targets;
CREATE POLICY aral_irip_targets_write ON public.aral_irip_targets TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());

-- aral_irip_weeks aral_irip_weeks_delete
DROP POLICY IF EXISTS aral_irip_weeks_delete ON public.aral_irip_weeks;
CREATE POLICY aral_irip_weeks_delete ON public.aral_irip_weeks FOR DELETE TO authenticated USING (public.aral_irip_writable(enrollment_id));

-- aral_irip_weeks aral_irip_weeks_insert
DROP POLICY IF EXISTS aral_irip_weeks_insert ON public.aral_irip_weeks;
CREATE POLICY aral_irip_weeks_insert ON public.aral_irip_weeks FOR INSERT TO authenticated WITH CHECK (public.aral_irip_writable(enrollment_id));

-- aral_irip_weeks aral_irip_weeks_select
DROP POLICY IF EXISTS aral_irip_weeks_select ON public.aral_irip_weeks;
CREATE POLICY aral_irip_weeks_select ON public.aral_irip_weeks FOR SELECT TO authenticated USING (public.aral_enrollment_readable(enrollment_id));

-- aral_irip_weeks aral_irip_weeks_update
DROP POLICY IF EXISTS aral_irip_weeks_update ON public.aral_irip_weeks;
CREATE POLICY aral_irip_weeks_update ON public.aral_irip_weeks FOR UPDATE TO authenticated USING (public.aral_irip_writable(enrollment_id)) WITH CHECK (public.aral_irip_writable(enrollment_id));

-- aral_material_links aral_material_links_select
DROP POLICY IF EXISTS aral_material_links_select ON public.aral_material_links;
CREATE POLICY aral_material_links_select ON public.aral_material_links FOR SELECT TO authenticated USING ((public.is_superadmin() OR (school_id = public.current_user_school_id())));

-- aral_material_links aral_material_links_write
DROP POLICY IF EXISTS aral_material_links_write ON public.aral_material_links;
CREATE POLICY aral_material_links_write ON public.aral_material_links TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())))) WITH CHECK ((public.aral_material_visible_to_school(material_id, school_id) AND (public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())))));

-- aral_materials aral_materials_delete
DROP POLICY IF EXISTS aral_materials_delete ON public.aral_materials;
CREATE POLICY aral_materials_delete ON public.aral_materials FOR DELETE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id IS NOT NULL) AND (school_id = public.current_user_school_id()))));

-- aral_materials aral_materials_insert
DROP POLICY IF EXISTS aral_materials_insert ON public.aral_materials;
CREATE POLICY aral_materials_insert ON public.aral_materials FOR INSERT TO authenticated WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id IS NOT NULL) AND (school_id = public.current_user_school_id()))));

-- aral_materials aral_materials_select
DROP POLICY IF EXISTS aral_materials_select ON public.aral_materials;
CREATE POLICY aral_materials_select ON public.aral_materials FOR SELECT TO authenticated USING ((public.is_superadmin() OR (school_id IS NULL) OR (school_id = public.current_user_school_id())));

-- aral_materials aral_materials_update
DROP POLICY IF EXISTS aral_materials_update ON public.aral_materials;
CREATE POLICY aral_materials_update ON public.aral_materials FOR UPDATE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id IS NOT NULL) AND (school_id = public.current_user_school_id())))) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id IS NOT NULL) AND (school_id = public.current_user_school_id()))));

-- aral_sessions aral_sessions_delete
DROP POLICY IF EXISTS aral_sessions_delete ON public.aral_sessions;
CREATE POLICY aral_sessions_delete ON public.aral_sessions FOR DELETE TO authenticated USING (public.aral_session_writable(id));

-- aral_sessions aral_sessions_insert
DROP POLICY IF EXISTS aral_sessions_insert ON public.aral_sessions;
CREATE POLICY aral_sessions_insert ON public.aral_sessions FOR INSERT TO authenticated WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND (tutor_id = auth.uid()) AND (school_id = public.current_user_school_id()))));

-- aral_sessions aral_sessions_select
DROP POLICY IF EXISTS aral_sessions_select ON public.aral_sessions;
CREATE POLICY aral_sessions_select ON public.aral_sessions FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND (tutor_id = auth.uid()))));

-- aral_sessions aral_sessions_update
DROP POLICY IF EXISTS aral_sessions_update ON public.aral_sessions;
CREATE POLICY aral_sessions_update ON public.aral_sessions FOR UPDATE TO authenticated USING (public.aral_session_writable(id)) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND (tutor_id = auth.uid()))));

-- aral_settings aral_settings_select
DROP POLICY IF EXISTS aral_settings_select ON public.aral_settings;
CREATE POLICY aral_settings_select ON public.aral_settings FOR SELECT TO authenticated USING ((public.is_superadmin() OR (school_id IS NULL) OR (school_id = public.current_user_school_id())));

-- aral_settings aral_settings_write
DROP POLICY IF EXISTS aral_settings_write ON public.aral_settings;
CREATE POLICY aral_settings_write ON public.aral_settings TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id IS NOT NULL) AND (school_id = public.current_user_school_id())))) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id IS NOT NULL) AND (school_id = public.current_user_school_id()))));

-- aral_tutor_settings aral_tutor_settings_delete
DROP POLICY IF EXISTS aral_tutor_settings_delete ON public.aral_tutor_settings;
CREATE POLICY aral_tutor_settings_delete ON public.aral_tutor_settings FOR DELETE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- aral_tutor_settings aral_tutor_settings_insert
DROP POLICY IF EXISTS aral_tutor_settings_insert ON public.aral_tutor_settings;
CREATE POLICY aral_tutor_settings_insert ON public.aral_tutor_settings FOR INSERT TO authenticated WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- aral_tutor_settings aral_tutor_settings_select
DROP POLICY IF EXISTS aral_tutor_settings_select ON public.aral_tutor_settings;
CREATE POLICY aral_tutor_settings_select ON public.aral_tutor_settings FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND (tutor_id = auth.uid()))));

-- aral_tutor_settings aral_tutor_settings_update
DROP POLICY IF EXISTS aral_tutor_settings_update ON public.aral_tutor_settings;
CREATE POLICY aral_tutor_settings_update ON public.aral_tutor_settings FOR UPDATE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())))) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- crla_assessments crla_assessments_insert_scoped
DROP POLICY IF EXISTS crla_assessments_insert_scoped ON public.crla_assessments;
CREATE POLICY crla_assessments_insert_scoped ON public.crla_assessments FOR INSERT TO authenticated WITH CHECK (((EXISTS ( SELECT 1
   FROM (public.sections s
     JOIN public.enrollments e ON ((e.section_id = s.id)))
  WHERE ((s.id = crla_assessments.section_id) AND (s.school_id = crla_assessments.school_id) AND (s.grade_level = ANY (ARRAY['1'::text, '2'::text, '3'::text])) AND (e.student_id = crla_assessments.student_id) AND (e.school_year = crla_assessments.school_year) AND (e.status = 'active'::text)))) AND (public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND public.tutor_has_section(section_id)))));

-- crla_assessments crla_assessments_select_scoped
DROP POLICY IF EXISTS crla_assessments_select_scoped ON public.crla_assessments;
CREATE POLICY crla_assessments_select_scoped ON public.crla_assessments FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND public.tutor_has_student(student_id))));

-- crla_part1_english crla_part1_english_insert
DROP POLICY IF EXISTS crla_part1_english_insert ON public.crla_part1_english;
CREATE POLICY crla_part1_english_insert ON public.crla_part1_english FOR INSERT TO authenticated WITH CHECK (public.crla_assessment_writable(assessment_id));

-- crla_part1_english crla_part1_english_select
DROP POLICY IF EXISTS crla_part1_english_select ON public.crla_part1_english;
CREATE POLICY crla_part1_english_select ON public.crla_part1_english FOR SELECT TO authenticated USING (public.crla_assessment_readable(assessment_id));

-- crla_part1_english crla_part1_english_update
DROP POLICY IF EXISTS crla_part1_english_update ON public.crla_part1_english;
CREATE POLICY crla_part1_english_update ON public.crla_part1_english FOR UPDATE TO authenticated USING (public.crla_assessment_writable(assessment_id)) WITH CHECK (public.crla_assessment_writable(assessment_id));

-- crla_part1_standard crla_part1_standard_insert
DROP POLICY IF EXISTS crla_part1_standard_insert ON public.crla_part1_standard;
CREATE POLICY crla_part1_standard_insert ON public.crla_part1_standard FOR INSERT TO authenticated WITH CHECK (public.crla_assessment_writable(assessment_id));

-- crla_part1_standard crla_part1_standard_select
DROP POLICY IF EXISTS crla_part1_standard_select ON public.crla_part1_standard;
CREATE POLICY crla_part1_standard_select ON public.crla_part1_standard FOR SELECT TO authenticated USING (public.crla_assessment_readable(assessment_id));

-- crla_part1_standard crla_part1_standard_update
DROP POLICY IF EXISTS crla_part1_standard_update ON public.crla_part1_standard;
CREATE POLICY crla_part1_standard_update ON public.crla_part1_standard FOR UPDATE TO authenticated USING (public.crla_assessment_writable(assessment_id)) WITH CHECK (public.crla_assessment_writable(assessment_id));

-- crla_part2_fluency crla_part2_fluency_insert
DROP POLICY IF EXISTS crla_part2_fluency_insert ON public.crla_part2_fluency;
CREATE POLICY crla_part2_fluency_insert ON public.crla_part2_fluency FOR INSERT TO authenticated WITH CHECK (public.crla_assessment_writable(assessment_id));

-- crla_part2_fluency crla_part2_fluency_select
DROP POLICY IF EXISTS crla_part2_fluency_select ON public.crla_part2_fluency;
CREATE POLICY crla_part2_fluency_select ON public.crla_part2_fluency FOR SELECT TO authenticated USING (public.crla_assessment_readable(assessment_id));

-- crla_part2_fluency crla_part2_fluency_update
DROP POLICY IF EXISTS crla_part2_fluency_update ON public.crla_part2_fluency;
CREATE POLICY crla_part2_fluency_update ON public.crla_part2_fluency FOR UPDATE TO authenticated USING (public.crla_assessment_writable(assessment_id)) WITH CHECK (public.crla_assessment_writable(assessment_id));

-- crla_stories crla_stories_select_all
DROP POLICY IF EXISTS crla_stories_select_all ON public.crla_stories;
CREATE POLICY crla_stories_select_all ON public.crla_stories FOR SELECT TO authenticated USING (true);

-- crla_stories crla_stories_write_superadmin
DROP POLICY IF EXISTS crla_stories_write_superadmin ON public.crla_stories;
CREATE POLICY crla_stories_write_superadmin ON public.crla_stories TO authenticated USING (public.is_superadmin()) WITH CHECK (public.is_superadmin());

-- crla_thresholds crla_thresholds_select
DROP POLICY IF EXISTS crla_thresholds_select ON public.crla_thresholds;
CREATE POLICY crla_thresholds_select ON public.crla_thresholds FOR SELECT TO authenticated USING ((public.is_superadmin() OR (school_id IS NULL) OR (school_id = public.current_user_school_id())));

-- crla_thresholds crla_thresholds_write
DROP POLICY IF EXISTS crla_thresholds_write ON public.crla_thresholds;
CREATE POLICY crla_thresholds_write ON public.crla_thresholds TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id IS NOT NULL) AND (school_id = public.current_user_school_id())))) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id IS NOT NULL) AND (school_id = public.current_user_school_id()))));

-- enrollments enrollments_delete_scoped
DROP POLICY IF EXISTS enrollments_delete_scoped ON public.enrollments;
CREATE POLICY enrollments_delete_scoped ON public.enrollments FOR DELETE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND public.section_in_school(section_id, public.current_user_school_id()))));

-- enrollments enrollments_insert_scoped
DROP POLICY IF EXISTS enrollments_insert_scoped ON public.enrollments;
CREATE POLICY enrollments_insert_scoped ON public.enrollments FOR INSERT TO authenticated WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND public.section_in_school(section_id, public.current_user_school_id()) AND public.student_in_school(student_id, public.current_user_school_id()))));

-- enrollments enrollments_select_scoped
DROP POLICY IF EXISTS enrollments_select_scoped ON public.enrollments;
CREATE POLICY enrollments_select_scoped ON public.enrollments FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND public.section_in_school(section_id, public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND public.tutor_has_section(section_id))));

-- enrollments enrollments_update_scoped
DROP POLICY IF EXISTS enrollments_update_scoped ON public.enrollments;
CREATE POLICY enrollments_update_scoped ON public.enrollments FOR UPDATE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND public.section_in_school(section_id, public.current_user_school_id())))) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND public.section_in_school(section_id, public.current_user_school_id()) AND public.student_in_school(student_id, public.current_user_school_id()))));

-- import_conflicts import_conflicts_delete_scoped
DROP POLICY IF EXISTS import_conflicts_delete_scoped ON public.import_conflicts;
CREATE POLICY import_conflicts_delete_scoped ON public.import_conflicts FOR DELETE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (section_id IS NOT NULL) AND public.section_in_school(section_id, public.current_user_school_id()))));

-- import_conflicts import_conflicts_insert_scoped
DROP POLICY IF EXISTS import_conflicts_insert_scoped ON public.import_conflicts;
CREATE POLICY import_conflicts_insert_scoped ON public.import_conflicts FOR INSERT TO authenticated WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND public.section_in_school(section_id, public.current_user_school_id()))));

-- import_conflicts import_conflicts_select_scoped
DROP POLICY IF EXISTS import_conflicts_select_scoped ON public.import_conflicts;
CREATE POLICY import_conflicts_select_scoped ON public.import_conflicts FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (section_id IS NOT NULL) AND public.section_in_school(section_id, public.current_user_school_id()))));

-- import_conflicts import_conflicts_update_scoped
DROP POLICY IF EXISTS import_conflicts_update_scoped ON public.import_conflicts;
CREATE POLICY import_conflicts_update_scoped ON public.import_conflicts FOR UPDATE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (section_id IS NOT NULL) AND public.section_in_school(section_id, public.current_user_school_id())))) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (section_id IS NOT NULL) AND public.section_in_school(section_id, public.current_user_school_id()))));

-- login_logs login_logs_insert_own
DROP POLICY IF EXISTS login_logs_insert_own ON public.login_logs;
CREATE POLICY login_logs_insert_own ON public.login_logs FOR INSERT TO authenticated, anon WITH CHECK ((((user_id IS NULL) AND (success = false)) OR (user_id = auth.uid())));

-- login_logs login_logs_select_scoped
DROP POLICY IF EXISTS login_logs_select_scoped ON public.login_logs;
CREATE POLICY login_logs_select_scoped ON public.login_logs FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (user_id IS NOT NULL) AND public.user_in_school(user_id, public.current_user_school_id()))));

-- phil_iri_answers phil_iri_answers_select
DROP POLICY IF EXISTS phil_iri_answers_select ON public.phil_iri_answers;
CREATE POLICY phil_iri_answers_select ON public.phil_iri_answers FOR SELECT TO authenticated USING (public.phil_iri_reading_readable(reading_id));

-- phil_iri_answers phil_iri_answers_write
DROP POLICY IF EXISTS phil_iri_answers_write ON public.phil_iri_answers;
CREATE POLICY phil_iri_answers_write ON public.phil_iri_answers TO authenticated USING (public.phil_iri_reading_writable(reading_id)) WITH CHECK (public.phil_iri_reading_writable(reading_id));

-- phil_iri_assessments phil_iri_assessments_delete_in_progress
DROP POLICY IF EXISTS phil_iri_assessments_delete_in_progress ON public.phil_iri_assessments;
CREATE POLICY phil_iri_assessments_delete_in_progress ON public.phil_iri_assessments FOR DELETE TO authenticated USING (((status = 'in_progress'::text) AND public.phil_iri_assessment_writable(id)));

-- phil_iri_assessments phil_iri_assessments_insert
DROP POLICY IF EXISTS phil_iri_assessments_insert ON public.phil_iri_assessments;
CREATE POLICY phil_iri_assessments_insert ON public.phil_iri_assessments FOR INSERT TO authenticated WITH CHECK (((EXISTS ( SELECT 1
   FROM (public.sections s
     JOIN public.enrollments e ON ((e.section_id = s.id)))
  WHERE ((s.id = phil_iri_assessments.section_id) AND (s.school_id = phil_iri_assessments.school_id) AND (s.grade_level = ANY (ARRAY['4'::text, '5'::text, '6'::text, '7'::text, '8'::text, '9'::text, '10'::text])) AND (e.student_id = phil_iri_assessments.student_id) AND (e.school_year = phil_iri_assessments.school_year) AND (e.status = 'active'::text)))) AND (public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND public.tutor_has_section(section_id)))));

-- phil_iri_assessments phil_iri_assessments_select
DROP POLICY IF EXISTS phil_iri_assessments_select ON public.phil_iri_assessments;
CREATE POLICY phil_iri_assessments_select ON public.phil_iri_assessments FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND public.tutor_has_student(student_id))));

-- phil_iri_assessments phil_iri_assessments_update
DROP POLICY IF EXISTS phil_iri_assessments_update ON public.phil_iri_assessments;
CREATE POLICY phil_iri_assessments_update ON public.phil_iri_assessments FOR UPDATE TO authenticated USING (public.phil_iri_assessment_writable(id)) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND public.tutor_has_section(section_id))));

-- phil_iri_collections phil_iri_collections_delete
DROP POLICY IF EXISTS phil_iri_collections_delete ON public.phil_iri_collections;
CREATE POLICY phil_iri_collections_delete ON public.phil_iri_collections FOR DELETE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- phil_iri_collections phil_iri_collections_insert
DROP POLICY IF EXISTS phil_iri_collections_insert ON public.phil_iri_collections;
CREATE POLICY phil_iri_collections_insert ON public.phil_iri_collections FOR INSERT TO authenticated WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()) AND (NOT is_prescribed))));

-- phil_iri_collections phil_iri_collections_select
DROP POLICY IF EXISTS phil_iri_collections_select ON public.phil_iri_collections;
CREATE POLICY phil_iri_collections_select ON public.phil_iri_collections FOR SELECT TO authenticated USING ((public.is_superadmin() OR (school_id IS NULL) OR (school_id = public.current_user_school_id())));

-- phil_iri_collections phil_iri_collections_update
DROP POLICY IF EXISTS phil_iri_collections_update ON public.phil_iri_collections;
CREATE POLICY phil_iri_collections_update ON public.phil_iri_collections FOR UPDATE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())))) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()) AND (NOT is_prescribed))));

-- phil_iri_gst_results phil_iri_gst_results_insert
DROP POLICY IF EXISTS phil_iri_gst_results_insert ON public.phil_iri_gst_results;
CREATE POLICY phil_iri_gst_results_insert ON public.phil_iri_gst_results FOR INSERT TO authenticated WITH CHECK (((EXISTS ( SELECT 1
   FROM (public.sections s
     JOIN public.enrollments e ON ((e.section_id = s.id)))
  WHERE ((s.id = phil_iri_gst_results.section_id) AND (s.school_id = phil_iri_gst_results.school_id) AND (s.grade_level = ANY (ARRAY['4'::text, '5'::text, '6'::text, '7'::text, '8'::text, '9'::text, '10'::text])) AND (e.student_id = phil_iri_gst_results.student_id) AND (e.school_year = phil_iri_gst_results.school_year) AND (e.status = 'active'::text)))) AND (public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND public.tutor_has_section(section_id)))));

-- phil_iri_gst_results phil_iri_gst_results_select
DROP POLICY IF EXISTS phil_iri_gst_results_select ON public.phil_iri_gst_results;
CREATE POLICY phil_iri_gst_results_select ON public.phil_iri_gst_results FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND public.tutor_has_student(student_id))));

-- phil_iri_miscues phil_iri_miscues_select
DROP POLICY IF EXISTS phil_iri_miscues_select ON public.phil_iri_miscues;
CREATE POLICY phil_iri_miscues_select ON public.phil_iri_miscues FOR SELECT TO authenticated USING (public.phil_iri_reading_readable(reading_id));

-- phil_iri_miscues phil_iri_miscues_write
DROP POLICY IF EXISTS phil_iri_miscues_write ON public.phil_iri_miscues;
CREATE POLICY phil_iri_miscues_write ON public.phil_iri_miscues TO authenticated USING (public.phil_iri_reading_writable(reading_id)) WITH CHECK (public.phil_iri_reading_writable(reading_id));

-- phil_iri_passages phil_iri_passages_select
DROP POLICY IF EXISTS phil_iri_passages_select ON public.phil_iri_passages;
CREATE POLICY phil_iri_passages_select ON public.phil_iri_passages FOR SELECT TO authenticated USING (public.phil_iri_collection_readable(collection_id));

-- phil_iri_passages phil_iri_passages_write
DROP POLICY IF EXISTS phil_iri_passages_write ON public.phil_iri_passages;
CREATE POLICY phil_iri_passages_write ON public.phil_iri_passages TO authenticated USING (public.phil_iri_collection_writable(collection_id)) WITH CHECK (public.phil_iri_collection_writable(collection_id));

-- phil_iri_questions phil_iri_questions_select
DROP POLICY IF EXISTS phil_iri_questions_select ON public.phil_iri_questions;
CREATE POLICY phil_iri_questions_select ON public.phil_iri_questions FOR SELECT TO authenticated USING (public.phil_iri_passage_readable(passage_id));

-- phil_iri_questions phil_iri_questions_write
DROP POLICY IF EXISTS phil_iri_questions_write ON public.phil_iri_questions;
CREATE POLICY phil_iri_questions_write ON public.phil_iri_questions TO authenticated USING (public.phil_iri_passage_writable(passage_id)) WITH CHECK (public.phil_iri_passage_writable(passage_id));

-- phil_iri_readings phil_iri_readings_select
DROP POLICY IF EXISTS phil_iri_readings_select ON public.phil_iri_readings;
CREATE POLICY phil_iri_readings_select ON public.phil_iri_readings FOR SELECT TO authenticated USING (public.phil_iri_assessment_readable(assessment_id));

-- phil_iri_readings phil_iri_readings_write
DROP POLICY IF EXISTS phil_iri_readings_write ON public.phil_iri_readings;
CREATE POLICY phil_iri_readings_write ON public.phil_iri_readings TO authenticated USING (public.phil_iri_assessment_writable(assessment_id)) WITH CHECK (public.phil_iri_assessment_writable(assessment_id));

-- phil_iri_rubric_criteria phil_iri_rubric_criteria_select
DROP POLICY IF EXISTS phil_iri_rubric_criteria_select ON public.phil_iri_rubric_criteria;
CREATE POLICY phil_iri_rubric_criteria_select ON public.phil_iri_rubric_criteria FOR SELECT TO authenticated USING (public.phil_iri_collection_readable(collection_id));

-- phil_iri_rubric_criteria phil_iri_rubric_criteria_write
DROP POLICY IF EXISTS phil_iri_rubric_criteria_write ON public.phil_iri_rubric_criteria;
CREATE POLICY phil_iri_rubric_criteria_write ON public.phil_iri_rubric_criteria TO authenticated USING (public.phil_iri_collection_writable(collection_id)) WITH CHECK (public.phil_iri_collection_writable(collection_id));

-- phil_iri_rubric_scores phil_iri_rubric_scores_select
DROP POLICY IF EXISTS phil_iri_rubric_scores_select ON public.phil_iri_rubric_scores;
CREATE POLICY phil_iri_rubric_scores_select ON public.phil_iri_rubric_scores FOR SELECT TO authenticated USING (public.phil_iri_assessment_readable(assessment_id));

-- phil_iri_rubric_scores phil_iri_rubric_scores_write
DROP POLICY IF EXISTS phil_iri_rubric_scores_write ON public.phil_iri_rubric_scores;
CREATE POLICY phil_iri_rubric_scores_write ON public.phil_iri_rubric_scores TO authenticated USING (public.phil_iri_assessment_writable(assessment_id)) WITH CHECK (public.phil_iri_assessment_writable(assessment_id));

-- phil_iri_thresholds phil_iri_thresholds_select
DROP POLICY IF EXISTS phil_iri_thresholds_select ON public.phil_iri_thresholds;
CREATE POLICY phil_iri_thresholds_select ON public.phil_iri_thresholds FOR SELECT TO authenticated USING ((public.is_superadmin() OR (school_id IS NULL) OR (school_id = public.current_user_school_id())));

-- phil_iri_thresholds phil_iri_thresholds_write
DROP POLICY IF EXISTS phil_iri_thresholds_write ON public.phil_iri_thresholds;
CREATE POLICY phil_iri_thresholds_write ON public.phil_iri_thresholds TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id IS NOT NULL) AND (school_id = public.current_user_school_id())))) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id IS NOT NULL) AND (school_id = public.current_user_school_id()))));

-- regions regions_select_all_authenticated
DROP POLICY IF EXISTS regions_select_all_authenticated ON public.regions;
CREATE POLICY regions_select_all_authenticated ON public.regions FOR SELECT TO authenticated USING (true);

-- schools schools_delete_superadmin
DROP POLICY IF EXISTS schools_delete_superadmin ON public.schools;
CREATE POLICY schools_delete_superadmin ON public.schools FOR DELETE TO authenticated USING (public.is_superadmin());

-- schools schools_insert_superadmin
DROP POLICY IF EXISTS schools_insert_superadmin ON public.schools;
CREATE POLICY schools_insert_superadmin ON public.schools FOR INSERT TO authenticated WITH CHECK (public.is_superadmin());

-- schools schools_select_scoped
DROP POLICY IF EXISTS schools_select_scoped ON public.schools;
CREATE POLICY schools_select_scoped ON public.schools FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text, 'tutor'::text])) AND (id = public.current_user_school_id()))));

-- schools schools_update_scoped
DROP POLICY IF EXISTS schools_update_scoped ON public.schools;
CREATE POLICY schools_update_scoped ON public.schools FOR UPDATE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (id = public.current_user_school_id())))) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (id = public.current_user_school_id()))));

-- sections sections_delete_scoped
DROP POLICY IF EXISTS sections_delete_scoped ON public.sections;
CREATE POLICY sections_delete_scoped ON public.sections FOR DELETE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- sections sections_insert_scoped
DROP POLICY IF EXISTS sections_insert_scoped ON public.sections;
CREATE POLICY sections_insert_scoped ON public.sections FOR INSERT TO authenticated WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- sections sections_select_scoped
DROP POLICY IF EXISTS sections_select_scoped ON public.sections;
CREATE POLICY sections_select_scoped ON public.sections FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND public.tutor_has_section(id))));

-- sections sections_update_scoped
DROP POLICY IF EXISTS sections_update_scoped ON public.sections;
CREATE POLICY sections_update_scoped ON public.sections FOR UPDATE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())))) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- students students_delete_scoped
DROP POLICY IF EXISTS students_delete_scoped ON public.students;
CREATE POLICY students_delete_scoped ON public.students FOR DELETE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- students students_insert_scoped
DROP POLICY IF EXISTS students_insert_scoped ON public.students;
CREATE POLICY students_insert_scoped ON public.students FOR INSERT TO authenticated WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- students students_select_scoped
DROP POLICY IF EXISTS students_select_scoped ON public.students;
CREATE POLICY students_select_scoped ON public.students FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())) OR ((public.current_user_role() = 'tutor'::text) AND public.tutor_has_student(id))));

-- students students_update_scoped
DROP POLICY IF EXISTS students_update_scoped ON public.students;
CREATE POLICY students_update_scoped ON public.students FOR UPDATE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())))) WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- tutor_section_assignments tsa_delete_scoped
DROP POLICY IF EXISTS tsa_delete_scoped ON public.tutor_section_assignments;
CREATE POLICY tsa_delete_scoped ON public.tutor_section_assignments FOR DELETE TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND public.section_in_school(section_id, public.current_user_school_id()))));

-- tutor_section_assignments tsa_insert_scoped
DROP POLICY IF EXISTS tsa_insert_scoped ON public.tutor_section_assignments;
CREATE POLICY tsa_insert_scoped ON public.tutor_section_assignments FOR INSERT TO authenticated WITH CHECK ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND public.section_in_school(section_id, public.current_user_school_id()))));

-- tutor_section_assignments tsa_select_scoped
DROP POLICY IF EXISTS tsa_select_scoped ON public.tutor_section_assignments;
CREATE POLICY tsa_select_scoped ON public.tutor_section_assignments FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = 'tutor'::text) AND (tutor_id = auth.uid())) OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND public.section_in_school(section_id, public.current_user_school_id()))));

-- users users_select_scoped
DROP POLICY IF EXISTS users_select_scoped ON public.users;
CREATE POLICY users_select_scoped ON public.users FOR SELECT TO authenticated USING ((public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))));

-- users users_update_scoped
DROP POLICY IF EXISTS users_update_scoped ON public.users;
CREATE POLICY users_update_scoped ON public.users FOR UPDATE TO authenticated USING (((id <> auth.uid()) AND (public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id()))))) WITH CHECK (((id <> auth.uid()) AND (public.is_superadmin() OR ((public.current_user_role() = ANY (ARRAY['admin'::text, 'coordinator'::text])) AND (school_id = public.current_user_school_id())))));


--
-- PostgreSQL database dump complete
--


-- row securitys ----------------------------------------------------------

-- aral_attendance
ALTER TABLE public.aral_attendance ENABLE ROW LEVEL SECURITY;

-- aral_checkin_answers
ALTER TABLE public.aral_checkin_answers ENABLE ROW LEVEL SECURITY;

-- aral_checkin_items
ALTER TABLE public.aral_checkin_items ENABLE ROW LEVEL SECURITY;

-- aral_checkin_tools
ALTER TABLE public.aral_checkin_tools ENABLE ROW LEVEL SECURITY;

-- aral_checkins
ALTER TABLE public.aral_checkins ENABLE ROW LEVEL SECURITY;

-- aral_enrollments
ALTER TABLE public.aral_enrollments ENABLE ROW LEVEL SECURITY;

-- aral_irip_targets
ALTER TABLE public.aral_irip_targets ENABLE ROW LEVEL SECURITY;

-- aral_irip_weeks
ALTER TABLE public.aral_irip_weeks ENABLE ROW LEVEL SECURITY;

-- aral_material_links
ALTER TABLE public.aral_material_links ENABLE ROW LEVEL SECURITY;

-- aral_materials
ALTER TABLE public.aral_materials ENABLE ROW LEVEL SECURITY;

-- aral_sessions
ALTER TABLE public.aral_sessions ENABLE ROW LEVEL SECURITY;

-- aral_settings
ALTER TABLE public.aral_settings ENABLE ROW LEVEL SECURITY;

-- aral_tutor_settings
ALTER TABLE public.aral_tutor_settings ENABLE ROW LEVEL SECURITY;

-- crla_assessments
ALTER TABLE public.crla_assessments ENABLE ROW LEVEL SECURITY;

-- crla_part1_english
ALTER TABLE public.crla_part1_english ENABLE ROW LEVEL SECURITY;

-- crla_part1_standard
ALTER TABLE public.crla_part1_standard ENABLE ROW LEVEL SECURITY;

-- crla_part2_fluency
ALTER TABLE public.crla_part2_fluency ENABLE ROW LEVEL SECURITY;

-- crla_stories
ALTER TABLE public.crla_stories ENABLE ROW LEVEL SECURITY;

-- crla_thresholds
ALTER TABLE public.crla_thresholds ENABLE ROW LEVEL SECURITY;

-- enrollments
ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;

-- import_conflicts
ALTER TABLE public.import_conflicts ENABLE ROW LEVEL SECURITY;

-- login_logs
ALTER TABLE public.login_logs ENABLE ROW LEVEL SECURITY;

-- phil_iri_answers
ALTER TABLE public.phil_iri_answers ENABLE ROW LEVEL SECURITY;

-- phil_iri_assessments
ALTER TABLE public.phil_iri_assessments ENABLE ROW LEVEL SECURITY;

-- phil_iri_collections
ALTER TABLE public.phil_iri_collections ENABLE ROW LEVEL SECURITY;

-- phil_iri_gst_results
ALTER TABLE public.phil_iri_gst_results ENABLE ROW LEVEL SECURITY;

-- phil_iri_miscues
ALTER TABLE public.phil_iri_miscues ENABLE ROW LEVEL SECURITY;

-- phil_iri_passages
ALTER TABLE public.phil_iri_passages ENABLE ROW LEVEL SECURITY;

-- phil_iri_questions
ALTER TABLE public.phil_iri_questions ENABLE ROW LEVEL SECURITY;

-- phil_iri_readings
ALTER TABLE public.phil_iri_readings ENABLE ROW LEVEL SECURITY;

-- phil_iri_rubric_criteria
ALTER TABLE public.phil_iri_rubric_criteria ENABLE ROW LEVEL SECURITY;

-- phil_iri_rubric_scores
ALTER TABLE public.phil_iri_rubric_scores ENABLE ROW LEVEL SECURITY;

-- phil_iri_thresholds
ALTER TABLE public.phil_iri_thresholds ENABLE ROW LEVEL SECURITY;

-- regions
ALTER TABLE public.regions ENABLE ROW LEVEL SECURITY;

-- schools
ALTER TABLE public.schools ENABLE ROW LEVEL SECURITY;

-- sections
ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;

-- students
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

-- tutor_section_assignments
ALTER TABLE public.tutor_section_assignments ENABLE ROW LEVEL SECURITY;

-- users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- privileges ------------------------------------------------------------
-- The GRANT/REVOKE statements of the 2026-10-12..18 migrations, in their order
-- (pg_dump ran with --no-privileges). Defense in depth on top of RLS: anon gets
-- nothing on the module tables; some functions are callable by no client role.
DO $$ BEGIN EXECUTE 'revoke update on public.users from anon, authenticated'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'grant update (is_active) on public.users to authenticated'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.phil_iri_collections, public.phil_iri_rubric_criteria, public.phil_iri_passages, public.phil_iri_questions, public.phil_iri_thresholds from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.phil_iri_gst_results, public.phil_iri_assessments, public.phil_iri_readings, public.phil_iri_miscues, public.phil_iri_answers, public.phil_iri_rubric_scores from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.crla_thresholds from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke execute on function public.crla_effective_thresholds(bigint) from public, anon, authenticated'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke execute on function public.crla_assessment_thresholds(bigint) from public, anon, authenticated'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke execute on function public.crla_refresh_profile(bigint) from public, anon, authenticated'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke execute on function public.crla_regenerate_results(bigint[]) from public, anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'grant execute on function public.crla_regenerate_results(bigint[]) to authenticated'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_enrollments from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_sessions, public.aral_attendance from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on function public.aral_check_section_cap(bigint, bigint, text) from public, anon, authenticated'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_tutor_settings from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on function public.aral_check_session_day(bigint, uuid, date) from public, anon, authenticated'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_irip_targets from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_irip_weeks from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_checkin_tools from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_checkin_items from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_checkins from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_checkin_answers from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_settings from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_materials from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
DO $$ BEGIN EXECUTE 'revoke all on public.aral_material_links from anon'; EXCEPTION WHEN undefined_function OR undefined_table THEN NULL; END $$;
