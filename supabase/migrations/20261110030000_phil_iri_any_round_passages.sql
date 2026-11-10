-- Phil-IRI: any grade-level passage may be read in any round.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261110020000.
-- App update required on all devices: yes (a rule change: older apps refuse
-- a passage from another round that the server now accepts).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Spec: docs/superpowers/specs/2026-11-10-phil-iri-any-round-passages-design.md
-- Ma (2026-11-09): any grade-level passage may be read in any round; each
-- passage once per learner.
--
-- Changes:
--  1. check_phil_iri_reading: the round check is gone (a BOSY session no
--     longer refuses a 'mosy' or 'post' passage, and so on). Everything else
--     is unchanged: Untitled exemptions, readable/active passage, own grade,
--     imported correct count, no-repeat with the silent follow-up exception.
--     phil_iri_passages.test_type stays as the booklet label (it only orders
--     the app's passage list). No table, view or policy changes, no grants.

-- ---------------------------------------------------------------------------
-- 1. Readings: no round check
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
  select p.level, c.is_grade_leveled, p.is_active and c.is_active
    into v_level, v_graded, v_active
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

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261110030000', 'phil_iri_any_round_passages', true)
on conflict (id) do nothing;
