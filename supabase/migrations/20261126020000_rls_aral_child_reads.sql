-- RLS: read rules checked once per query, not once per row, on every table
-- whose read rule called lookups per row (found by the demo builder,
-- 2026-11-26: a coordinator's pull timed out after one school year of ARAL,
-- about 25,000 attendance marks; policy audit of the whole schema the same
-- day, D:\0_CAPSTONE\verify\rls-perf\policy_audit_2026-11-26.txt).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261126010000.
-- App update required on all devices: no (policies and read-only helpers;
-- every user reads and writes the same rows as before, see below).
--
-- Before: read rules called lookup functions per row (aral_session_writable,
-- aral_enrollment_readable, tutor_has_section, tutor_has_student, ...), each
-- running its own role/school queries; some write policies had no FOR, so
-- they filtered reads too (aral_attendance_write and 13 small tables).
--
-- After: the caller's role, school and id are worked out once per query
-- ((select f()) initplans), and "the rows a tutor may see" are sets built
-- once per query by the basa_private.my_* functions below (plain indexed
-- reads of the caller's own sections, classes and sessions; for a single-row
-- insert with RETURNING, as sync_apply does, they are just as small). Every
-- rule is the same, word for word:
--   1. ARAL: aral_attendance (the caller may write the session, or is the
--      class tutor of the mark's learner: a moved learner's new tutor reads
--      that learner's marks in older sessions, not the other learners'),
--      aral_irip_weeks / aral_checkins / aral_readability_logs (the
--      enrollment is readable), aral_checkin_answers (its check-in's
--      enrollment is), aral_sessions, aral_enrollments.
--   2. students, enrollments, sections, enrollment_moves.
--   3. phil_iri_assessments, crla_assessments, phil_iri_gst_results: the
--      moved-learner part (tutor_had_moved_learner) as a set.
--   4. Content and settings: write policies without FOR split into INSERT /
--      UPDATE / DELETE with the same rule (each write rule is narrower than
--      the table's read rule, so no read changes); helpers wrapped once per
--      query; Phil-IRI passages / questions / rubric criteria and SRP members
--      read through their parent's own read policy.
-- Checked on a test database: every role reads the same rows of every table
-- above (equivalence run), reads and single-row inserts timed at 20 schools.
--
-- RLS: the select policies of every table above; write policies of
-- aral_attendance, aral_checkin_items, aral_checkin_tools, aral_irip_targets,
-- aral_material_links, aral_settings, assessment_calendar, crla_stories,
-- crla_thresholds, phil_iri_thresholds, report_settings, phil_iri_passages,
-- phil_iri_questions, phil_iri_rubric_criteria split (same rules). New
-- helpers in basa_private (execute: authenticated; the schema is not exposed
-- by the API). The public helpers stay (other policies and functions use
-- them).

-- ---------------------------------------------------------------------------
-- 0. The caller's sets
-- ---------------------------------------------------------------------------
-- Sections the caller (a tutor) is assigned to (tutor_has_section).
create or replace function basa_private.my_section_ids() returns setof bigint
  language sql stable security definer set search_path = public
as $$
  select t.section_id from public.tutor_section_assignments t
  where t.tutor_id = auth.uid() and public.current_user_role() = 'tutor';
$$;

-- ARAL classes the caller (a tutor) teaches (aral_tutor_has_class).
create or replace function basa_private.my_aral_class_ids() returns setof bigint
  language sql stable security definer set search_path = public
as $$
  select c.id from public.aral_classes c
  where c.tutor_id = auth.uid() and public.current_user_role() = 'tutor';
$$;

-- Roster entries / learners / their sections in the caller's classes
-- (aral_tutor_has_enrollment, aral_tutor_has_student, aral_tutor_reads_section).
create or replace function basa_private.my_aral_class_enrollment_ids() returns setof bigint
  language sql stable security definer set search_path = public
as $$
  select e.id from public.aral_enrollments e
  join public.aral_classes c on c.id = e.class_id
  where c.tutor_id = auth.uid() and public.current_user_role() = 'tutor';
$$;

create or replace function basa_private.my_aral_class_student_ids() returns setof bigint
  language sql stable security definer set search_path = public
as $$
  select e.student_id from public.aral_enrollments e
  join public.aral_classes c on c.id = e.class_id
  where c.tutor_id = auth.uid() and public.current_user_role() = 'tutor';
$$;

create or replace function basa_private.my_aral_class_section_ids() returns setof bigint
  language sql stable security definer set search_path = public
as $$
  select e.section_id from public.aral_enrollments e
  join public.aral_classes c on c.id = e.class_id
  where c.tutor_id = auth.uid() and public.current_user_role() = 'tutor';
$$;

-- Sessions with a mark of a learner of the caller's class (the tutor part of
-- aral_session_readable).
create or replace function basa_private.my_aral_learner_session_ids() returns setof bigint
  language sql stable security definer set search_path = public
as $$
  select a.session_id from public.aral_attendance a
  join public.aral_enrollments e on e.id = a.enrollment_id
  join public.aral_classes c on c.id = e.class_id
  where c.tutor_id = auth.uid() and public.current_user_role() = 'tutor';
$$;

-- Sessions the caller may write (aral_session_writable, superadmin apart).
-- One branch per role, so a single-row insert with RETURNING (sync_apply)
-- reads only the caller's own sessions through an index.
create or replace function basa_private.my_aral_writable_session_ids() returns setof bigint
  language plpgsql stable security definer set search_path = public
as $$
declare
  r text := public.current_user_role();
begin
  if r in ('admin', 'coordinator') then
    return query select s.id from public.aral_sessions s where s.school_id = public.current_user_school_id();
  elsif r = 'tutor' then
    return query
      select s.id from public.aral_sessions s where s.tutor_id = auth.uid()
      union
      select s.id from public.aral_classes c join public.aral_sessions s on s.class_id = c.id where c.tutor_id = auth.uid();
  end if;
end;
$$;

-- Roster entries the caller may read (aral_enrollment_readable, superadmin apart).
create or replace function basa_private.my_aral_readable_enrollment_ids() returns setof bigint
  language plpgsql stable security definer set search_path = public
as $$
declare
  r text := public.current_user_role();
begin
  if r in ('admin', 'coordinator') then
    return query select e.id from public.aral_enrollments e where e.school_id = public.current_user_school_id();
  elsif r = 'tutor' then
    return query
      select e.id from public.tutor_section_assignments t
      join public.aral_enrollments e on e.section_id = t.section_id where t.tutor_id = auth.uid()
      union
      select e.id from public.aral_classes c join public.aral_enrollments e on e.class_id = c.id where c.tutor_id = auth.uid();
  end if;
end;
$$;

-- Check-ins whose roster entry the caller may read (aral_checkin_readable).
create or replace function basa_private.my_aral_readable_checkin_ids() returns setof bigint
  language sql stable security definer set search_path = public
as $$
  select k.id from public.aral_checkins k
  where k.enrollment_id in (select basa_private.my_aral_readable_enrollment_ids());
$$;

-- Sections of the caller's school, for an admin/coordinator (section_in_school).
create or replace function basa_private.my_school_section_ids() returns setof bigint
  language sql stable security definer set search_path = public
as $$
  select s.id from public.sections s
  where s.school_id = public.current_user_school_id()
    and public.current_user_role() in ('admin', 'coordinator');
$$;

-- Learners (and years) a tutor had before a section move (tutor_had_moved_learner).
create or replace function basa_private.my_moved_learner_years() returns table (student_id bigint, school_year text)
  language sql stable security definer set search_path = public
as $$
  select m.student_id, m.school_year from public.enrollment_moves m
  join public.tutor_section_assignments t on t.section_id = m.from_section_id
  where t.tutor_id = auth.uid() and m.source <> 'transfer_in' and public.current_user_role() = 'tutor';
$$;

-- Learners of the caller's SRP classes (srp_tutor_has_student).
create or replace function basa_private.my_srp_student_ids() returns setof bigint
  language sql stable security definer set search_path = public
as $$
  select m.student_id from public.srp_class_members m
  join public.srp_classes c on c.id = m.class_id
  where c.tutor_id = auth.uid() and public.current_user_role() = 'tutor';
$$;

do $$
declare f text;
begin
  foreach f in array array['my_section_ids()', 'my_aral_class_ids()', 'my_aral_class_enrollment_ids()',
                           'my_aral_class_student_ids()', 'my_aral_class_section_ids()', 'my_aral_learner_session_ids()',
                           'my_aral_writable_session_ids()', 'my_aral_readable_enrollment_ids()',
                           'my_aral_readable_checkin_ids()', 'my_school_section_ids()', 'my_moved_learner_years()',
                           'my_srp_student_ids()'] loop
    execute format('revoke all on function basa_private.%s from public, anon', f);
    execute format('grant execute on function basa_private.%s to authenticated', f);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 1. ARAL
-- ---------------------------------------------------------------------------
drop policy if exists aral_sessions_select on public.aral_sessions;
create policy aral_sessions_select on public.aral_sessions for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id()))
         or ((select public.current_user_role()) = 'tutor'
             and (tutor_id = (select auth.uid())
                  or class_id in (select basa_private.my_aral_class_ids())
                  or id in (select basa_private.my_aral_learner_session_ids()))));

drop policy if exists aral_enrollments_select on public.aral_enrollments;
create policy aral_enrollments_select on public.aral_enrollments for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id()))
         or ((select public.current_user_role()) = 'tutor'
             and (section_id in (select basa_private.my_section_ids())
                  or class_id in (select basa_private.my_aral_class_ids()))));

drop policy if exists aral_attendance_select on public.aral_attendance;
create policy aral_attendance_select on public.aral_attendance for select to authenticated
  using ((select public.is_superadmin())
         or session_id in (select basa_private.my_aral_writable_session_ids())
         or enrollment_id in (select basa_private.my_aral_class_enrollment_ids()));

drop policy if exists aral_attendance_write on public.aral_attendance;
drop policy if exists aral_attendance_insert on public.aral_attendance;
create policy aral_attendance_insert on public.aral_attendance for insert to authenticated
  with check (public.aral_session_writable(session_id));
drop policy if exists aral_attendance_update on public.aral_attendance;
create policy aral_attendance_update on public.aral_attendance for update to authenticated
  using (public.aral_session_writable(session_id))
  with check (public.aral_session_writable(session_id));
drop policy if exists aral_attendance_delete on public.aral_attendance;
create policy aral_attendance_delete on public.aral_attendance for delete to authenticated
  using (public.aral_session_writable(session_id));

drop policy if exists aral_irip_weeks_select on public.aral_irip_weeks;
create policy aral_irip_weeks_select on public.aral_irip_weeks for select to authenticated
  using ((select public.is_superadmin()) or enrollment_id in (select basa_private.my_aral_readable_enrollment_ids()));

drop policy if exists aral_checkins_select on public.aral_checkins;
create policy aral_checkins_select on public.aral_checkins for select to authenticated
  using ((select public.is_superadmin()) or enrollment_id in (select basa_private.my_aral_readable_enrollment_ids()));

drop policy if exists aral_readability_logs_select on public.aral_readability_logs;
create policy aral_readability_logs_select on public.aral_readability_logs for select to authenticated
  using ((select public.is_superadmin()) or enrollment_id in (select basa_private.my_aral_readable_enrollment_ids()));

drop policy if exists aral_checkin_answers_select on public.aral_checkin_answers;
create policy aral_checkin_answers_select on public.aral_checkin_answers for select to authenticated
  using ((select public.is_superadmin()) or checkin_id in (select basa_private.my_aral_readable_checkin_ids()));

-- ---------------------------------------------------------------------------
-- 2. Learners, enrollments, sections, moves
-- ---------------------------------------------------------------------------
drop policy if exists students_select_scoped on public.students;
create policy students_select_scoped on public.students for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id()))
         or ((select public.current_user_role()) = 'tutor' and id in (select public.tutor_student_ids())));

drop policy if exists students_select_srp_tutor on public.students;
create policy students_select_srp_tutor on public.students for select to authenticated
  using (id in (select basa_private.my_srp_student_ids()));

drop policy if exists enrollments_select_scoped on public.enrollments;
create policy enrollments_select_scoped on public.enrollments for select to authenticated
  using ((select public.is_superadmin())
         or section_id in (select basa_private.my_school_section_ids())
         or ((select public.current_user_role()) = 'tutor'
             and (section_id in (select basa_private.my_section_ids())
                  or student_id in (select basa_private.my_aral_class_student_ids()))));

drop policy if exists sections_select_scoped on public.sections;
create policy sections_select_scoped on public.sections for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id()))
         or ((select public.current_user_role()) = 'tutor'
             and (id in (select basa_private.my_section_ids())
                  or id in (select basa_private.my_aral_class_section_ids()))));

drop policy if exists enrollment_moves_select on public.enrollment_moves;
create policy enrollment_moves_select on public.enrollment_moves for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and (school_id = (select public.current_user_school_id())
                  or from_school_id = (select public.current_user_school_id())))
         or from_section_id in (select basa_private.my_section_ids())
         or to_section_id in (select basa_private.my_section_ids()));

-- ---------------------------------------------------------------------------
-- 3. Assessment parents: the moved-learner part as a set (else as 20261125010000)
-- ---------------------------------------------------------------------------
drop policy if exists phil_iri_assessments_select on public.phil_iri_assessments;
create policy phil_iri_assessments_select on public.phil_iri_assessments for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id()))
         or ((select public.current_user_role()) = 'tutor'
             and (student_id in (select public.tutor_student_ids())
                  or (administered_by = (select auth.uid())
                      and (student_id, school_year) in (select * from basa_private.my_moved_learner_years())))));

drop policy if exists crla_assessments_select_scoped on public.crla_assessments;
create policy crla_assessments_select_scoped on public.crla_assessments for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id()))
         or ((select public.current_user_role()) = 'tutor'
             and (student_id in (select public.tutor_student_ids())
                  or (administered_by = (select auth.uid())
                      and (student_id, school_year) in (select * from basa_private.my_moved_learner_years())))));

drop policy if exists phil_iri_gst_results_select on public.phil_iri_gst_results;
create policy phil_iri_gst_results_select on public.phil_iri_gst_results for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id()))
         or ((select public.current_user_role()) = 'tutor'
             and (student_id in (select public.tutor_student_ids())
                  or (administered_by = (select auth.uid())
                      and (student_id, school_year) in (select * from basa_private.my_moved_learner_years())))));

-- ---------------------------------------------------------------------------
-- 4. Content and settings
-- ---------------------------------------------------------------------------
-- Superadmin-only writes (tables everyone reads).
do $$
declare
  t text;
  p text;
begin
  foreach t in array array['aral_checkin_items', 'aral_checkin_tools', 'aral_irip_targets', 'crla_stories'] loop
    p := case t when 'crla_stories' then 'crla_stories_write_superadmin' else t || '_write' end;
    execute format('drop policy if exists %I on public.%I', p, t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select public.is_superadmin()))', t || '_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using ((select public.is_superadmin())) with check ((select public.is_superadmin()))', t || '_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using ((select public.is_superadmin()))', t || '_delete', t);
  end loop;
end $$;

-- School settings: read = superadmin, the region row, or the caller's school;
-- write = superadmin, or an admin/coordinator of that school.
do $$
declare
  t text;
  w constant text := '((select public.is_superadmin()) or ((select public.current_user_role()) in (''admin'', ''coordinator'')'
                     ' and school_id is not null and school_id = (select public.current_user_school_id())))';
begin
  foreach t in array array['aral_settings', 'assessment_calendar', 'crla_thresholds', 'phil_iri_thresholds', 'report_settings'] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.is_superadmin()) or school_id is null or school_id = (select public.current_user_school_id()))', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (%s)', t || '_insert', t, w);
    execute format('create policy %I on public.%I for update to authenticated using (%s) with check (%s)', t || '_update', t, w, w);
    execute format('create policy %I on public.%I for delete to authenticated using (%s)', t || '_delete', t, w);
  end loop;
end $$;

drop policy if exists aral_material_links_select on public.aral_material_links;
create policy aral_material_links_select on public.aral_material_links for select to authenticated
  using ((select public.is_superadmin()) or school_id = (select public.current_user_school_id()));
drop policy if exists aral_material_links_write on public.aral_material_links;
drop policy if exists aral_material_links_insert on public.aral_material_links;
create policy aral_material_links_insert on public.aral_material_links for insert to authenticated
  with check (public.aral_material_visible_to_school(material_id, school_id)
              and ((select public.is_superadmin())
                   or ((select public.current_user_role()) in ('admin', 'coordinator')
                       and school_id = (select public.current_user_school_id()))));
drop policy if exists aral_material_links_update on public.aral_material_links;
create policy aral_material_links_update on public.aral_material_links for update to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id())))
  with check (public.aral_material_visible_to_school(material_id, school_id)
              and ((select public.is_superadmin())
                   or ((select public.current_user_role()) in ('admin', 'coordinator')
                       and school_id = (select public.current_user_school_id()))));
drop policy if exists aral_material_links_delete on public.aral_material_links;
create policy aral_material_links_delete on public.aral_material_links for delete to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id())));

-- Phil-IRI content: a passage / rubric criterion is readable when its
-- collection is (phil_iri_collection_readable = the collections' read
-- policy), a question when its passage is.
drop policy if exists phil_iri_collections_select on public.phil_iri_collections;
create policy phil_iri_collections_select on public.phil_iri_collections for select to authenticated
  using ((select public.is_superadmin()) or school_id is null or school_id = (select public.current_user_school_id()));

drop policy if exists phil_iri_passages_select on public.phil_iri_passages;
create policy phil_iri_passages_select on public.phil_iri_passages for select to authenticated
  using (collection_id in (select c.id from public.phil_iri_collections c));
drop policy if exists phil_iri_rubric_criteria_select on public.phil_iri_rubric_criteria;
create policy phil_iri_rubric_criteria_select on public.phil_iri_rubric_criteria for select to authenticated
  using (collection_id in (select c.id from public.phil_iri_collections c));
drop policy if exists phil_iri_questions_select on public.phil_iri_questions;
create policy phil_iri_questions_select on public.phil_iri_questions for select to authenticated
  using (passage_id in (select p.id from public.phil_iri_passages p));

do $$
declare
  t text;
  w text;
begin
  foreach t in array array['phil_iri_passages', 'phil_iri_rubric_criteria', 'phil_iri_questions'] loop
    w := case t when 'phil_iri_questions' then 'public.phil_iri_passage_writable(passage_id)'
                else 'public.phil_iri_collection_writable(collection_id)' end;
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (%s)', t || '_insert', t, w);
    execute format('create policy %I on public.%I for update to authenticated using (%s) with check (%s)', t || '_update', t, w, w);
    execute format('create policy %I on public.%I for delete to authenticated using (%s)', t || '_delete', t, w);
  end loop;
end $$;

-- SRP: classes (srp_school_writable written out) and members through them.
drop policy if exists srp_classes_select on public.srp_classes;
create policy srp_classes_select on public.srp_classes for select to authenticated
  using ((select public.is_superadmin())
         or ((select public.current_user_role()) in ('admin', 'coordinator')
             and school_id = (select public.current_user_school_id()))
         or ((select public.current_user_role()) = 'tutor' and tutor_id = (select auth.uid())));
drop policy if exists srp_class_members_select on public.srp_class_members;
create policy srp_class_members_select on public.srp_class_members for select to authenticated
  using (class_id in (select c.id from public.srp_classes c));

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261126020000', 'rls_aral_child_reads', false)
on conflict (id) do nothing;
