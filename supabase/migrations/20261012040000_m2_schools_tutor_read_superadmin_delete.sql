-- M2 leftovers on public.schools.
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
--
--  1. A tutor could not read their own school's row (only admin/coordinator
--     branches existed), so tutor screens couldn't show the school name.
--     Tutors now see exactly their own school, nothing else.
--  2. No DELETE policy existed, so a mistaken school could only be removed
--     from the SQL Editor. The superadmin may now delete one; the foreign keys
--     (sections, students, users, crla_assessments) still refuse it while
--     anything references the school, so this only removes empty schools.

begin;

drop policy if exists schools_select_scoped on public.schools;
create policy schools_select_scoped on public.schools
  for select to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator', 'tutor')
        and id = current_user_school_id())
  );

drop policy if exists schools_delete_superadmin on public.schools;
create policy schools_delete_superadmin on public.schools
  for delete to authenticated
  using (is_superadmin());

commit;
