-- RLS: fast reads of the assessment child tables (found by the demo builder,
-- 2026-11-25: a coordinator's and a tutor's pull timed out on
-- phil_iri_miscues with 7264 miscues in the whole database).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261119010000.
-- App update required on all devices: no (policies and one read-only
-- helper; every user reads and writes the same rows as before, see below).
--
-- Before: each child row ran a chain of lookup functions on every read
-- (phil_iri_reading_readable -> phil_iri_assessment_readable -> the role and
-- school helpers), once per row of the whole table, other schools' rows
-- included. The Phil-IRI children's FOR ALL write policy also applied to
-- SELECT, so the writable chain ran too (first, and for a finalized session
-- both). EXPLAIN as a coordinator: 3.1-3.5 s for 1000 miscues; the API's 8 s
-- statement timeout was hit.
--
-- After:
--   1. A child row is readable when its parent row is: the read policy is
--      "parent id in (the parent rows you can read)". The subquery runs under
--      the parent table's own RLS (miscues/answers -> readings -> assessments),
--      once per query as a hashed set, so the role and school checks run once
--      per assessment, not once per child row. The parents' read policies are
--      the same rule as the *_assessment_readable helpers the children used
--      (checked against the live policies before writing this), so every role
--      reads the same rows.
--   2. The Phil-IRI children's FOR ALL write policies are split into INSERT,
--      UPDATE and DELETE with the same writable helper, so a read uses the
--      read rule only. (The CRLA parts had separate policies already.) The one
--      read this removes: a child row whose parent the reader can't see (a
--      co-tutor of a moved learner's old section, for a session they didn't
--      administer): they couldn't read the session itself either.
--   3. The parents' read policies (phil_iri_assessments, crla_assessments,
--      phil_iri_gst_results) keep their rule word for word, but check it once
--      per query instead of once per row: the role/school helpers are written
--      as (select f()), and "tutor_has_student(student_id)" becomes
--      "student_id in (select tutor_student_ids())", the same learners as one
--      set (new helper below, same joins as tutor_has_student). Measured on a
--      20-school test database: a tutor's first page 1.6 s -> 0.2 s, a
--      coordinator's under 12 ms.
--   F14 (20261024020000) still holds: a row inserted with RETURNING is read
--   back through its parent, which exists before the child is inserted, and
--   the parents' policies still look only at the row's own columns.
--
-- RLS: read policies of phil_iri_assessments, crla_assessments,
-- phil_iri_gst_results; policies of phil_iri_readings,
-- phil_iri_rubric_scores, phil_iri_miscues, phil_iri_answers,
-- crla_part1_standard, crla_part1_english, crla_part2_fluency. New function
-- tutor_student_ids() (execute: authenticated only). No table or view
-- changes; the *_readable / *_writable helpers and tutor_has_student stay
-- (other policies and functions use them).

-- ---------------------------------------------------------------------------
-- 0. The tutor's learners as one set, and the parents' read policies
-- ---------------------------------------------------------------------------
-- The learners tutor_has_student() says yes to, for the caller: enrolled in a
-- section they're assigned to, or placed (any status) in an ARAL class they
-- teach. Empty for anyone who isn't a tutor.
create or replace function public.tutor_student_ids() returns setof bigint
  language sql stable security definer set search_path to 'public'
as $$
  select e.student_id
  from public.enrollments e
  join public.tutor_section_assignments tsa on tsa.section_id = e.section_id
  where tsa.tutor_id = auth.uid() and public.current_user_role() = 'tutor'
  union
  select e.student_id
  from public.aral_enrollments e
  join public.aral_classes c on c.id = e.class_id
  where c.tutor_id = auth.uid() and public.current_user_role() = 'tutor';
$$;
revoke all on function public.tutor_student_ids() from public, anon;
grant execute on function public.tutor_student_ids() to authenticated;

drop policy if exists phil_iri_assessments_select on public.phil_iri_assessments;
create policy phil_iri_assessments_select on public.phil_iri_assessments for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id()))
         or ((select public.current_user_role()) = 'tutor'
             and (student_id in (select public.tutor_student_ids())
                  or (administered_by = (select auth.uid())
                      and public.tutor_had_moved_learner(student_id, school_year)))));

drop policy if exists crla_assessments_select_scoped on public.crla_assessments;
create policy crla_assessments_select_scoped on public.crla_assessments for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id()))
         or ((select public.current_user_role()) = 'tutor'
             and (student_id in (select public.tutor_student_ids())
                  or (administered_by = (select auth.uid())
                      and public.tutor_had_moved_learner(student_id, school_year)))));

drop policy if exists phil_iri_gst_results_select on public.phil_iri_gst_results;
create policy phil_iri_gst_results_select on public.phil_iri_gst_results for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id()))
         or ((select public.current_user_role()) = 'tutor'
             and (student_id in (select public.tutor_student_ids())
                  or (administered_by = (select auth.uid())
                      and public.tutor_had_moved_learner(student_id, school_year)))));

-- ---------------------------------------------------------------------------
-- 1. Phil-IRI: readings and rubric scores (parent: phil_iri_assessments)
-- ---------------------------------------------------------------------------
drop policy if exists phil_iri_readings_select on public.phil_iri_readings;
create policy phil_iri_readings_select on public.phil_iri_readings for select to authenticated
  using (assessment_id in (select a.id from public.phil_iri_assessments a));

drop policy if exists phil_iri_readings_write on public.phil_iri_readings;
drop policy if exists phil_iri_readings_insert on public.phil_iri_readings;
create policy phil_iri_readings_insert on public.phil_iri_readings for insert to authenticated
  with check (public.phil_iri_assessment_writable(assessment_id));
drop policy if exists phil_iri_readings_update on public.phil_iri_readings;
create policy phil_iri_readings_update on public.phil_iri_readings for update to authenticated
  using (public.phil_iri_assessment_writable(assessment_id))
  with check (public.phil_iri_assessment_writable(assessment_id));
drop policy if exists phil_iri_readings_delete on public.phil_iri_readings;
create policy phil_iri_readings_delete on public.phil_iri_readings for delete to authenticated
  using (public.phil_iri_assessment_writable(assessment_id));

drop policy if exists phil_iri_rubric_scores_select on public.phil_iri_rubric_scores;
create policy phil_iri_rubric_scores_select on public.phil_iri_rubric_scores for select to authenticated
  using (assessment_id in (select a.id from public.phil_iri_assessments a));

drop policy if exists phil_iri_rubric_scores_write on public.phil_iri_rubric_scores;
drop policy if exists phil_iri_rubric_scores_insert on public.phil_iri_rubric_scores;
create policy phil_iri_rubric_scores_insert on public.phil_iri_rubric_scores for insert to authenticated
  with check (public.phil_iri_assessment_writable(assessment_id));
drop policy if exists phil_iri_rubric_scores_update on public.phil_iri_rubric_scores;
create policy phil_iri_rubric_scores_update on public.phil_iri_rubric_scores for update to authenticated
  using (public.phil_iri_assessment_writable(assessment_id))
  with check (public.phil_iri_assessment_writable(assessment_id));
drop policy if exists phil_iri_rubric_scores_delete on public.phil_iri_rubric_scores;
create policy phil_iri_rubric_scores_delete on public.phil_iri_rubric_scores for delete to authenticated
  using (public.phil_iri_assessment_writable(assessment_id));

-- ---------------------------------------------------------------------------
-- 2. Phil-IRI: miscues and answers (parent: phil_iri_readings)
-- ---------------------------------------------------------------------------
drop policy if exists phil_iri_miscues_select on public.phil_iri_miscues;
create policy phil_iri_miscues_select on public.phil_iri_miscues for select to authenticated
  using (reading_id in (select r.id from public.phil_iri_readings r));

drop policy if exists phil_iri_miscues_write on public.phil_iri_miscues;
drop policy if exists phil_iri_miscues_insert on public.phil_iri_miscues;
create policy phil_iri_miscues_insert on public.phil_iri_miscues for insert to authenticated
  with check (public.phil_iri_reading_writable(reading_id));
drop policy if exists phil_iri_miscues_update on public.phil_iri_miscues;
create policy phil_iri_miscues_update on public.phil_iri_miscues for update to authenticated
  using (public.phil_iri_reading_writable(reading_id))
  with check (public.phil_iri_reading_writable(reading_id));
drop policy if exists phil_iri_miscues_delete on public.phil_iri_miscues;
create policy phil_iri_miscues_delete on public.phil_iri_miscues for delete to authenticated
  using (public.phil_iri_reading_writable(reading_id));

drop policy if exists phil_iri_answers_select on public.phil_iri_answers;
create policy phil_iri_answers_select on public.phil_iri_answers for select to authenticated
  using (reading_id in (select r.id from public.phil_iri_readings r));

drop policy if exists phil_iri_answers_write on public.phil_iri_answers;
drop policy if exists phil_iri_answers_insert on public.phil_iri_answers;
create policy phil_iri_answers_insert on public.phil_iri_answers for insert to authenticated
  with check (public.phil_iri_reading_writable(reading_id));
drop policy if exists phil_iri_answers_update on public.phil_iri_answers;
create policy phil_iri_answers_update on public.phil_iri_answers for update to authenticated
  using (public.phil_iri_reading_writable(reading_id))
  with check (public.phil_iri_reading_writable(reading_id));
drop policy if exists phil_iri_answers_delete on public.phil_iri_answers;
create policy phil_iri_answers_delete on public.phil_iri_answers for delete to authenticated
  using (public.phil_iri_reading_writable(reading_id));

-- ---------------------------------------------------------------------------
-- 3. CRLA parts (parent: crla_assessments); their write policies stay
-- ---------------------------------------------------------------------------
drop policy if exists crla_part1_standard_select on public.crla_part1_standard;
create policy crla_part1_standard_select on public.crla_part1_standard for select to authenticated
  using (assessment_id in (select a.id from public.crla_assessments a));

drop policy if exists crla_part1_english_select on public.crla_part1_english;
create policy crla_part1_english_select on public.crla_part1_english for select to authenticated
  using (assessment_id in (select a.id from public.crla_assessments a));

drop policy if exists crla_part2_fluency_select on public.crla_part2_fluency;
create policy crla_part2_fluency_select on public.crla_part2_fluency for select to authenticated
  using (assessment_id in (select a.id from public.crla_assessments a));

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261125010000', 'rls_child_tables_fast_reads', false)
on conflict (id) do nothing;
