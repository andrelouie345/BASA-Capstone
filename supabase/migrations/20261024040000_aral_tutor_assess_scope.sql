-- ARAL classes: a class tutor assesses their class learners only in that
-- school year and school; attendance in a class session only for that
-- class's learners.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261024030000.
-- App update required on all devices: no (a tighter server check; the app
-- already keeps to it: tutors work on this year's classes, and
-- AralSessionViewModel.mark refuses another class's learner).
--
-- Why (final review 2026-10-24, C1): 20261023040000 let a tutor write CRLA,
-- Phil-IRI and GST rows when aral_tutor_has_student(student) holds: "placed
-- (any status, any year) in a class I teach". A learner who moved to
-- another school, or went up a year, kept that link, so their former class
-- tutor could still edit the new school's or the next year's assessments
-- through the SECURITY DEFINER helpers crla_assessment_writable and
-- phil_iri_assessment_writable (assessment edits, Part 1/2, readings,
-- answers, rubric scores). Reading those rows stays as it is (decision 8 of
-- the ARAL classes spec: the former class tutor keeps reading).
--
-- Rule (owner 2026-10-24): beyond their assigned sections, a tutor writes
-- assessments for a learner placed in a class they teach in the
-- assessment's school year and school (their own school), active or
-- exited (a learner exited by a round's results can still have that round
-- corrected by the class tutor).
--
-- Attendance (review minor, same piece): check_aral_attendance refused only
-- learners of another school or year. A tutor could mark a learner of
-- another class in their class session, and that mark made the session's
-- header readable to the other class's tutor. Now a tutor marks only the
-- session's class learners (sessions without a class, from before ARAL
-- classes, as before); admins and coordinators may mark anyone of the
-- school, as AralSessionViewModel.mark allows.

-- 1. The tutor's assessing scope.
create or replace function public.aral_tutor_assesses(p_student_id bigint, p_school_id bigint, p_school_year text)
  returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select public.current_user_role() = 'tutor'
     and p_school_id = public.current_user_school_id()
     and exists (
       select 1 from public.aral_enrollments e
       join public.aral_classes c on c.id = e.class_id
       where e.student_id = p_student_id and e.school_id = p_school_id
         and e.school_year = p_school_year and c.tutor_id = auth.uid());
$$;

revoke all on function public.aral_tutor_assesses(bigint, bigint, text) from public, anon;
grant execute on function public.aral_tutor_assesses(bigint, bigint, text) to authenticated;

-- 2. The write helpers the parts, readings, answers and rubric scores use.
create or replace function public.crla_assessment_writable(p_assessment_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.crla_assessments ca
    where ca.id = p_assessment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and ca.school_id = current_user_school_id())
           or (current_user_role() = 'tutor'
               and (tutor_has_section(ca.section_id) or aral_tutor_assesses(ca.student_id, ca.school_id, ca.school_year))))
  );
$$;

create or replace function public.phil_iri_assessment_writable(p_assessment_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.phil_iri_assessments a
    where a.id = p_assessment_id
      and a.status <> 'finalized'
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and a.school_id = current_user_school_id())
           or (current_user_role() = 'tutor'
               and (tutor_has_section(a.section_id) or aral_tutor_assesses(a.student_id, a.school_id, a.school_year))))
  );
$$;

-- 3. The assessment write policies (same as 20261023040000 but the tutor's
-- ARAL branch).
drop policy if exists crla_assessments_insert_scoped on public.crla_assessments;
create policy crla_assessments_insert_scoped on public.crla_assessments for insert to authenticated
  with check (exists (select 1 from public.sections s join public.enrollments e on e.section_id = s.id
                      where s.id = crla_assessments.section_id and s.school_id = crla_assessments.school_id
                        and s.grade_level in ('1', '2', '3')
                        and e.student_id = crla_assessments.student_id
                        and e.school_year = crla_assessments.school_year and e.status = 'active')
              and (is_superadmin()
                   or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
                   or (current_user_role() = 'tutor'
                       and (tutor_has_section(section_id) or aral_tutor_assesses(student_id, school_id, school_year)))));
drop policy if exists phil_iri_assessments_insert on public.phil_iri_assessments;
create policy phil_iri_assessments_insert on public.phil_iri_assessments for insert to authenticated
  with check (exists (select 1 from public.sections s join public.enrollments e on e.section_id = s.id
                      where s.id = phil_iri_assessments.section_id and s.school_id = phil_iri_assessments.school_id
                        and s.grade_level in ('4', '5', '6', '7', '8', '9', '10')
                        and e.student_id = phil_iri_assessments.student_id
                        and e.school_year = phil_iri_assessments.school_year and e.status = 'active')
              and (is_superadmin()
                   or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
                   or (current_user_role() = 'tutor'
                       and (tutor_has_section(section_id) or aral_tutor_assesses(student_id, school_id, school_year)))));
drop policy if exists phil_iri_assessments_update on public.phil_iri_assessments;
create policy phil_iri_assessments_update on public.phil_iri_assessments for update to authenticated
  using (phil_iri_assessment_writable(id))
  with check (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
              or (current_user_role() = 'tutor'
                  and (tutor_has_section(section_id) or aral_tutor_assesses(student_id, school_id, school_year))));
drop policy if exists phil_iri_gst_results_insert on public.phil_iri_gst_results;
create policy phil_iri_gst_results_insert on public.phil_iri_gst_results for insert to authenticated
  with check (exists (select 1 from public.sections s join public.enrollments e on e.section_id = s.id
                      where s.id = phil_iri_gst_results.section_id and s.school_id = phil_iri_gst_results.school_id
                        and s.grade_level in ('4', '5', '6', '7', '8', '9', '10')
                        and e.student_id = phil_iri_gst_results.student_id
                        and e.school_year = phil_iri_gst_results.school_year and e.status = 'active')
              and (is_superadmin()
                   or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
                   or (current_user_role() = 'tutor'
                       and (tutor_has_section(section_id) or aral_tutor_assesses(student_id, school_id, school_year)))));

-- 4. Attendance: a tutor marks only the session's class learners.
create or replace function public.check_aral_attendance() returns trigger
  language plpgsql security definer set search_path to 'public'
as $$
declare
  v_ok boolean;
  v_other_class boolean;
begin
  if auth.uid() is null then
    return new;
  end if;
  if not aral_session_writable(new.session_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  if tg_op = 'UPDATE' then
    if (new.session_id, new.enrollment_id) is distinct from (old.session_id, old.enrollment_id) then
      raise exception 'an attendance mark keeps its session and learner; delete it and add a new one instead';
    end if;
    new.created_at := old.created_at;
    new.updated_at := now();
    return new;
  end if;
  select exists (
    select 1
    from public.aral_sessions s
    join public.aral_enrollments e
      on e.school_id = s.school_id and e.school_year = s.school_year
    where s.id = new.session_id and e.id = new.enrollment_id
      and e.entered_on <= s.held_on
      and (e.exited_on is null or e.exited_on >= s.held_on)
  ) into v_ok;
  if not v_ok then
    raise exception 'that learner was not in ARAL in this school on the session date';
  end if;
  if current_user_role() = 'tutor' then
    select s.class_id is not null and e.class_id is distinct from s.class_id
      from public.aral_sessions s, public.aral_enrollments e
     where s.id = new.session_id and e.id = new.enrollment_id
      into v_other_class;
    if v_other_class then
      raise exception 'only an admin or coordinator can mark a learner of another class';
    end if;
  end if;
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261024040000', 'aral_tutor_assess_scope', false)
on conflict (id) do nothing;
