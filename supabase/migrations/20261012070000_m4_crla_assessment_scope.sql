-- M4: crla_assessments write scoping.
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
--
-- Fixes, each confirmed against the dev project on 2026-10-12 (probe m4_rls):
--  1. INSERT only checked the caller's section (tutor) or school_id (admin).
--     A tutor could stamp another school's school_id; a school admin could
--     point at another school's section and learner. The row must now name
--     a section that belongs to school_id, and the learner must have an
--     active enrollment in that section for that school_year. The check is
--     a plain subquery, so it runs under the caller's own read policies on
--     sections/enrollments (no SECURITY DEFINER helper, no oracle).
--  2. administered_by was taken from the client. It is now stamped with
--     auth.uid() (left as sent only when there is no JWT, e.g. SQL Editor).
--  3. A client-sent attempt_no was kept. It is now always assigned.
--  4. The admin UPDATE policy let an admin repoint an assessment at another
--     school's learner. Assessments are never updated (a retake is a new
--     row), so the policy is dropped.
--  5. check_crla_part1_variant runs before RLS and its error text told any
--     caller the variant of any assessment id. It now answers like RLS for
--     assessments the caller cannot write.

begin;

-- 1. INSERT: same scope as before, plus a consistent section/school/enrollment.
drop policy if exists crla_assessments_insert_scoped on public.crla_assessments;
create policy crla_assessments_insert_scoped on public.crla_assessments
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.sections s
      join public.enrollments e on e.section_id = s.id
      where s.id = crla_assessments.section_id
        and s.school_id = crla_assessments.school_id
        and e.student_id = crla_assessments.student_id
        and e.school_year = crla_assessments.school_year
        and e.status = 'active'
    )
    and (
      is_superadmin()
      or (current_user_role() in ('admin', 'coordinator')
          and school_id = current_user_school_id())
      or (current_user_role() = 'tutor' and tutor_has_section(section_id))
    )
  );

-- 2 + 3. Server-side stamps. Replaces set_crla_attempt_no.
create or replace function public.crla_assessments_before_insert()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
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
  return new;
end;
$$;

drop trigger if exists crla_assessments_attempt_no on public.crla_assessments;
drop trigger if exists crla_assessments_before_insert on public.crla_assessments;
create trigger crla_assessments_before_insert
  before insert on public.crla_assessments
  for each row execute function public.crla_assessments_before_insert();
drop function if exists public.set_crla_attempt_no();

-- 4. No updates.
drop policy if exists crla_assessments_update_scoped on public.crla_assessments;

-- 5. Variant check answers like RLS for assessments the caller can't write.
create or replace function public.check_crla_part1_variant()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
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

commit;
