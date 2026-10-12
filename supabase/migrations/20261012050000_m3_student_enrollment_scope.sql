-- M3: students / enrollments scoping.
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
--
-- Fixes, each verified against the dev project on 2026-10-12:
--  1. Cross-school takeover. enrollments insert/update only checked that the
--     SECTION was in the caller's school. Inserting an enrollment fires
--     sync_student_school_id (SECURITY DEFINER), which moves the student to
--     the section's school, so a school admin could enroll another school's
--     student by id and take the record over. The student must now already
--     belong to the caller's school. Moving a learner between schools
--     (transfer) is a superadmin action.
--  2. School admins could not import at all: the importer inserted students
--     with school_id NULL, and the RETURNING row then failed the SELECT
--     policy (42501). The importer now sends the section's school_id, so the
--     "school_id IS NULL" escape in the students insert/update policies is
--     no longer needed and is removed (it also let any school admin update
--     every unassigned student). The dev project has 0 such students.

begin;

create or replace function public.student_in_school(p_student_id bigint, p_school_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.students
    where id = p_student_id and school_id = p_school_id
  );
$$;

-- 1. enrollments: section AND student must be in the caller's school.
drop policy if exists enrollments_insert_scoped on public.enrollments;
create policy enrollments_insert_scoped on public.enrollments
  for insert to authenticated
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and section_in_school(section_id, current_user_school_id())
        and student_in_school(student_id, current_user_school_id()))
  );

drop policy if exists enrollments_update_scoped on public.enrollments;
create policy enrollments_update_scoped on public.enrollments
  for update to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and section_in_school(section_id, current_user_school_id()))
  )
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and section_in_school(section_id, current_user_school_id())
        and student_in_school(student_id, current_user_school_id()))
  );

-- 2. students: no more school_id NULL rows from school-bound users.
drop policy if exists students_insert_scoped on public.students;
create policy students_insert_scoped on public.students
  for insert to authenticated
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id = current_user_school_id())
  );

drop policy if exists students_update_scoped on public.students;
create policy students_update_scoped on public.students
  for update to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id = current_user_school_id())
  )
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id = current_user_school_id())
  );

commit;
