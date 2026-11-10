-- Phil-IRI: imported readings without a passage ("Untitled") and
-- comprehension-only imported readings.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261110010000.
-- App update required on all devices: yes (a reading without a passage:
-- older apps can't read or score it).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Spec: docs/superpowers/specs/2026-11-10-phil-iri-untitled-readings-design.md
-- Ma (2026-11-09): a workbook row with a word count and a time but no
-- passage is kept as a generic "Untitled" reading. Only sessions imported
-- from ma's workbook (import_source = 'workbook') may have one; live
-- sessions and scoresheet imports keep a required passage.
--
-- Changes:
--  1. phil_iri_readings.passage_id may be null (workbook imports only,
--     trigger below).
--  2. phil_iri_readings.imported_word_count: the typed word count of an
--     Untitled reading; required for whole text / silent without a passage,
--     never beside a passage (the passage's own count wins).
--  3. phil_iri_readings.imported_total: the comprehension maximum an
--     Untitled reading's imported_correct is out of (the workbook block's
--     header maximum); never beside a passage.
--  4. check_phil_iri_reading: a null passage only on a workbook session; it
--     skips the passage lookups (readable, active, grade, no-repeat).
--  5. check_phil_iri_miscue: a reading without a passage takes only miscues
--     without a position (left join: the old inner join found no row and
--     refused every miscue of such a reading).
--  check_phil_iri_answer is unchanged: a question never belongs to a null
--  passage, so an answer on an Untitled reading is already refused.
--
-- Untimed imported readings (comprehension only) need no schema change: the
-- time columns were already nullable; the app scores them.
--
-- RLS: policies unchanged (phil_iri_readings policies go through the
-- session: phil_iri_assessment_readable / _writable). No table or view is
-- created, so no grants.

-- ---------------------------------------------------------------------------
-- 1-3. Columns and checks
-- ---------------------------------------------------------------------------

alter table public.phil_iri_readings alter column passage_id drop not null;
alter table public.phil_iri_readings add column if not exists imported_word_count integer;
alter table public.phil_iri_readings add column if not exists imported_total integer;

alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_untitled_word_count;
alter table public.phil_iri_readings add constraint phil_iri_readings_untitled_word_count
  check (imported_word_count > 0);
alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_untitled_total;
alter table public.phil_iri_readings add constraint phil_iri_readings_untitled_total
  check (imported_total > 0);
alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_untitled_only;
alter table public.phil_iri_readings add constraint phil_iri_readings_untitled_only
  check (passage_id is null or (imported_word_count is null and imported_total is null));
alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_untitled_needs_count;
alter table public.phil_iri_readings add constraint phil_iri_readings_untitled_needs_count
  check (passage_id is not null or method = 'one_minute' or imported_word_count is not null);
alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_untitled_total_correct;
alter table public.phil_iri_readings add constraint phil_iri_readings_untitled_total_correct
  check (imported_total is null or (imported_correct is not null and imported_correct <= imported_total));
alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_untitled_correct_total;
alter table public.phil_iri_readings add constraint phil_iri_readings_untitled_correct_total
  check (passage_id is not null or imported_correct is null or imported_total is not null);

-- ---------------------------------------------------------------------------
-- 4. Readings: a null passage only on a workbook session
-- ---------------------------------------------------------------------------

create or replace function public.check_phil_iri_reading() returns trigger
  language plpgsql security definer
  set search_path = public
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
  v_import text;
  v_questions integer;
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
  select a.import_source into v_import from public.phil_iri_assessments a where a.id = new.assessment_id;

  -- No passage ("Untitled"): workbook imports only; nothing to look up.
  if new.passage_id is null then
    if v_import is distinct from 'workbook' then
      raise exception 'a reading without a passage belongs to a session imported from the workbook';
    end if;
    if new.imported_correct is not null and tg_op = 'UPDATE'
       and exists (select 1 from public.phil_iri_answers where reading_id = new.id) then
      raise exception 'this reading has answers; an imported correct count replaces answers, not both';
    end if;
    return new;
  end if;

  if not phil_iri_passage_readable(new.passage_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select p.level, c.is_grade_leveled, p.is_active and c.is_active, p.test_type
    into v_level, v_graded, v_active, v_test_type
  from public.phil_iri_passages p
  join public.phil_iri_collections c on c.id = p.collection_id
  where p.id = new.passage_id;
  if tg_op = 'INSERT' and not v_active and v_import is null then
    raise exception 'this passage or its collection is not active';
  end if;
  if v_graded then
    select phil_iri_section_grade(a.section_id) into v_grade
    from public.phil_iri_assessments a where a.id = new.assessment_id;
    if v_level is distinct from v_grade then
      raise exception 'a Grade % learner reads a Grade % passage (got a Grade % passage)', v_grade, v_grade, v_level;
    end if;
  end if;
  if new.imported_correct is not null then
    if v_import is distinct from 'workbook' then
      raise exception 'an imported correct count belongs to a reading imported from the workbook';
    end if;
    select count(*) into v_questions from public.phil_iri_questions where passage_id = new.passage_id;
    if new.imported_correct > v_questions then
      raise exception 'imported correct count % is more than the passage''s % questions', new.imported_correct, v_questions;
    end if;
    if tg_op = 'UPDATE' and exists (select 1 from public.phil_iri_answers where reading_id = new.id) then
      raise exception 'this reading has answers; an imported correct count replaces answers, not both';
    end if;
  end if;
  if tg_op = 'INSERT' and v_import is null then
    select a.round, a.school_year, a.student_id into v_round, v_year, v_student
    from public.phil_iri_assessments a where a.id = new.assessment_id;
    if v_test_type is not null
       and v_test_type is distinct from (case v_round when 'bosy' then 'pre' when 'eosy' then 'post' else 'mosy' end) then
      raise exception 'a % session does not read a % passage (BOSY reads pre, MOSY mosy, EOSY post passages)',
        v_round, v_test_type;
    end if;
    -- Untitled readings (no passage) drop out of the inner join: they block nothing.
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

-- ---------------------------------------------------------------------------
-- 5. Miscues: left join, so a reading without a passage is still found
-- ---------------------------------------------------------------------------

create or replace function public.check_phil_iri_miscue() returns trigger
  language plpgsql security definer
  set search_path = public
as $$
declare
  v_words integer;
  v_method text;
  v_import text;
  v_passage bigint;
begin
  if auth.uid() is null then
    return new;
  end if;
  if not phil_iri_reading_writable(new.reading_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select p.word_count, r.method, a.import_source, r.passage_id into v_words, v_method, v_import, v_passage
  from public.phil_iri_readings r
  left join public.phil_iri_passages p on p.id = r.passage_id
  join public.phil_iri_assessments a on a.id = r.assessment_id
  where r.id = new.reading_id;
  if v_method = 'silent' then
    raise exception 'a silent reading has no miscues';
  end if;
  if new.word_index is null then
    if v_import is null then
      raise exception 'a miscue without a position belongs to an imported reading';
    end if;
    return new;
  end if;
  if v_passage is null then
    raise exception 'a reading without a passage takes only miscues without a position';
  end if;
  -- An insertion may sit after the last word (index = word count).
  if new.word_index > v_words or (new.miscue_type <> 'insertion' and new.word_index >= v_words) then
    raise exception 'word % is outside the passage (% words)', new.word_index, v_words;
  end if;
  return new;
end;
$$;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261110020000', 'phil_iri_untitled_readings', true)
on conflict (id) do nothing;
