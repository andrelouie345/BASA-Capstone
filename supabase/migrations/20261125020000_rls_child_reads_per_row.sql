-- RLS: the assessment child tables' read policies look their parent row up by
-- id (found by the demo builder, 2026-11-25: approving one section's Phil-IRI
-- round timed out after 20261125010000).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261125010000.
-- App update required on all devices: no (policies only; every user reads
-- and writes the same rows as with 20261125010000).
--
-- 20261125010000 made a child row readable when "parent id in (the parent
-- rows you can read)". That set is built once per statement: cheap for a
-- pull (one statement per page), but sync_apply inserts an upload one row at
-- a time with RETURNING, and each insert's read check rebuilt the whole set
-- (every reading and session in the database). 300 miscue inserts as a tutor
-- on a 20-school test database: 0.28 s before 20261125010000, 78 s with it.
--
-- Now a child row is readable when "a parent row with this id exists that you
-- can read": an index lookup of one parent row per child row, under the
-- parent table's own RLS (unchanged). Same rows as 20261125010000 for every
-- role (equivalence test, 10 roles). Test database: pull pages as fast as
-- with 20261125010000 (coordinator 4-10 ms, tutor 0.2-0.3 s); 300 inserts
-- 1.2 s as a tutor, 0.54 s as a coordinator. Still slower per row than before
-- 20261125010000 (each insert plans the parent's rules); inserting an upload
-- table by table instead of row by row is a planned follow-up.
-- F14 (20261024020000) holds: the inserted row's parent exists before it.
--
-- RLS: select policies of phil_iri_readings, phil_iri_rubric_scores,
-- phil_iri_miscues, phil_iri_answers, crla_part1_standard,
-- crla_part1_english, crla_part2_fluency. Their write policies, the parents'
-- policies and every function stay as 20261125010000 left them.

drop policy if exists phil_iri_readings_select on public.phil_iri_readings;
create policy phil_iri_readings_select on public.phil_iri_readings for select to authenticated
  using (exists (select 1 from public.phil_iri_assessments a where a.id = assessment_id));

drop policy if exists phil_iri_rubric_scores_select on public.phil_iri_rubric_scores;
create policy phil_iri_rubric_scores_select on public.phil_iri_rubric_scores for select to authenticated
  using (exists (select 1 from public.phil_iri_assessments a where a.id = assessment_id));

drop policy if exists phil_iri_miscues_select on public.phil_iri_miscues;
create policy phil_iri_miscues_select on public.phil_iri_miscues for select to authenticated
  using (exists (select 1 from public.phil_iri_readings r where r.id = reading_id));

drop policy if exists phil_iri_answers_select on public.phil_iri_answers;
create policy phil_iri_answers_select on public.phil_iri_answers for select to authenticated
  using (exists (select 1 from public.phil_iri_readings r where r.id = reading_id));

drop policy if exists crla_part1_standard_select on public.crla_part1_standard;
create policy crla_part1_standard_select on public.crla_part1_standard for select to authenticated
  using (exists (select 1 from public.crla_assessments a where a.id = assessment_id));

drop policy if exists crla_part1_english_select on public.crla_part1_english;
create policy crla_part1_english_select on public.crla_part1_english for select to authenticated
  using (exists (select 1 from public.crla_assessments a where a.id = assessment_id));

drop policy if exists crla_part2_fluency_select on public.crla_part2_fluency;
create policy crla_part2_fluency_select on public.crla_part2_fluency for select to authenticated
  using (exists (select 1 from public.crla_assessments a where a.id = assessment_id));

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261125020000', 'rls_child_reads_per_row', false)
on conflict (id) do nothing;
