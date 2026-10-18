-- Phil-IRI: let whoever can write a session discard it while it is still
-- in progress (owner decision 2026-10-14), e.g. a session started for the
-- wrong learner. Completed and finalized sessions cannot be deleted; a
-- completed one has to be reopened first. Its readings, miscues, answers and
-- rubric scores go with it (on delete cascade).
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
-- Needs 20261014010000_phil_iri_assessments.sql first.

begin;

drop policy if exists phil_iri_assessments_delete_in_progress on public.phil_iri_assessments;
create policy phil_iri_assessments_delete_in_progress on public.phil_iri_assessments
  for delete to authenticated
  using (status = 'in_progress' and phil_iri_assessment_writable(id));

commit;
