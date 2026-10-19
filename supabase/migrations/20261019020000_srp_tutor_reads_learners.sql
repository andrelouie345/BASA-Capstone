-- SRP tutors can read the learner rows of their SRP classes. Idempotent: safe
-- to run in the Supabase SQL Editor more than once. Newer than
-- 20261019010000_srp_classes.sql, which it needs.
--
-- Owner 2026-10-19: a summer (SRP) tutor often does not tutor the learners'
-- sections, so students_select_scoped (tutor_has_student = a section
-- assignment) hid their names. This adds a second, permissive SELECT policy
-- on students only: a tutor reads a learner while that learner is in an SRP
-- class the tutor is set on. Nothing else is opened: tutor_has_student (used
-- by the CRLA / Phil-IRI select policies) is unchanged, so the SRP tutor does
-- not see the learners' assessments, enrollments or sections, and cannot
-- write students.

create or replace function public.srp_tutor_has_student(p_student_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select current_user_role() = 'tutor' and exists (
    select 1 from public.srp_class_members m
    join public.srp_classes c on c.id = m.class_id
    where m.student_id = p_student_id and c.tutor_id = auth.uid()
  );
$$;

drop policy if exists students_select_srp_tutor on public.students;
create policy students_select_srp_tutor on public.students
  for select to authenticated using (srp_tutor_has_student(id));
