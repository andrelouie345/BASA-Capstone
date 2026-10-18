-- Phil-IRI: silent reading. Idempotent: safe to run in the Supabase SQL Editor
-- more than once.
--
-- Reading coordinator (2026-10-16): any graded passage can be read silently
-- or aloud. A silent reading is timed over the whole text; no miscues are
-- recorded (word reading counts as 100%). A learner whose silent result is
-- Frustration gets an oral follow-up, which may re-read the SAME passage.
--
-- Changes:
--  1. phil_iri_readings.method also allows 'silent' (column CHECK replaced;
--     found by definition, since it was created unnamed), and
--     phil_iri_readings_method_fields lets silent carry reading_seconds.
--  2. check_phil_iri_reading() replaced: body as in
--     20261015030000_phil_iri_no_repeat_passage.sql, plus
--     - a reading keeps its method (UPDATE), so a silent reading can't gain
--       miscues by being switched to oral or the other way round;
--     - no-repeat exception: an ORAL reading may re-read a text this learner
--       read SILENTLY, once, as another attempt (another session) of the same
--       round and school year. Same as the local trigger (SQLite v26).
--  3. check_phil_iri_miscue() replaced: refuses miscues on a silent reading.
--
-- RLS: unchanged. No new table, view or policy; the policies on
-- phil_iri_readings / phil_iri_miscues stay as in 20261014010000. Both
-- functions stay SECURITY DEFINER with search_path = public.

-- 1. method ---------------------------------------------------------------------

do $$
declare
  v_name text;
begin
  for v_name in
    select conname from pg_constraint
    where conrelid = 'public.phil_iri_readings'::regclass and contype = 'c'
      and conname <> 'phil_iri_readings_method_fields'
      and pg_get_constraintdef(oid) like '%method%'
  loop
    execute format('alter table public.phil_iri_readings drop constraint %I', v_name);
  end loop;
end
$$;
alter table public.phil_iri_readings
  add constraint phil_iri_readings_method_check
  check (method in ('whole_text', 'one_minute', 'silent'));

alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_method_fields;
alter table public.phil_iri_readings
  add constraint phil_iri_readings_method_fields check (
    (method in ('whole_text', 'silent') and words_read is null)
    or (method = 'one_minute' and reading_seconds is null));

-- 2. reading trigger -------------------------------------------------------------

create or replace function public.check_phil_iri_reading()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
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

-- 3. miscue trigger --------------------------------------------------------------

create or replace function public.check_phil_iri_miscue()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
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
