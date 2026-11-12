-- SF1 leavers (part 1): archive, restore and anonymize learners; the
-- enrollment_moves history; each section's last imported LRN set.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261110030000.
-- App update required on all devices: yes (enrollments.status gets a CHECK
-- and clients may only write 'active'; archived learners leave every list).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Spec: docs/superpowers/specs/2026-11-12-sf1-leavers-design.md (D1-D4, D9,
-- D10, D12). ma asked (2026-11-12) that a re-imported SF1 flag the learners
-- no longer on it: transferred out or dropped out = archived (never
-- deleted), moved = another section of the school (the move function comes
-- in the next migration).
--
-- Changes:
--  1. enrollments.status CHECK ('active', 'transferred_out', 'dropped_out');
--     new left_on, left_by, left_note, set exactly when archived (CHECK
--     enrollments_left, like aral_enrollments_exit). Stops (changes nothing)
--     when a stored status breaks the CHECK.
--  2. students.anonymized_at: set by learner_anonymize, which clears the
--     personal fields and keeps sex (spec D2), and also empties the
--     learner's import_conflicts rows and removes the old LRN from every
--     sf1_last_imports set (owner 2026-11-12). Eligible (owner 2026-11-12):
--     the learner's latest school year is archived, more than
--     archive_keep_months ago, and that year has ended; earlier years
--     (active or not) don't block.
--  3. report_settings key archive_keep_months: a whole number 1-120 (school
--     row, then the region row, then 6).
--  4. enrollment_moves: one row per section move (history; written only by
--     the functions).
--  5. sf1_last_imports: each section's LRN set from its last SF1 import
--     (owner 2026-11-12, decision b), so every admin device lists the same
--     undecided learners (sf1_missing).
--  6. Functions (SECURITY DEFINER, callers checked: the superadmin or the
--     learner's school's admin/coordinator; tutors refused):
--     sf1_archive_learner, sf1_restore_learner (same section only until the
--     move migration), learner_anonymize, learner_anonymize_eligible,
--     sf1_missing; private helpers in basa_private.
--  7. enrollments_sync_student_school now fires on a change of the
--     enrollment's section or learner only: archiving or restoring a past
--     year's enrollment (every past year is still 'active') must not pull
--     students.school_id back to the old school.
--
-- RLS:
--  - enrollments: insert/update write only status = 'active'; an update or
--    delete touches only active rows (archive and restore go through the
--    functions; an archived enrollment is never deleted, spec D1).
--  - students: clients can't set anonymized_at nor edit an anonymized learner.
--  - enrollment_moves: select for the superadmin, the school's
--    admin/coordinator (school_id) and the tutor of the from or to section
--    (row's own columns, F14); no client insert/update/delete.
--  - sf1_last_imports: select/insert/update for the superadmin and the
--    school's admin/coordinator (school_id); no delete; no tutor access.
-- Grants: both new tables to authenticated and service_role
-- (select/insert/update/delete), nothing to anon. Functions: execute to
-- authenticated only (the trigger function to nobody); the basa_private
-- helpers to nobody but their owner.

-- ---------------------------------------------------------------------------
-- 0. Stop (change nothing) when a stored status breaks the new CHECK
-- ---------------------------------------------------------------------------

do $$
declare
  bad text;
begin
  select string_agg(format('%s (%s rows)', quote_literal(status), n), ', ' order by status)
    into bad
    from (select status, count(*) n from public.enrollments
           where status not in ('active', 'transferred_out', 'dropped_out')
           group by status) s;
  if bad is not null then
    raise exception 'enrollments has statuses outside active/transferred_out/dropped_out: %. Fix them, then run this migration again.', bad;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. enrollments: statuses and who archived when
-- ---------------------------------------------------------------------------

alter table public.enrollments add column if not exists left_on date;
alter table public.enrollments add column if not exists left_by uuid references public.users(id);
alter table public.enrollments add column if not exists left_note text;

alter table public.enrollments drop constraint if exists enrollments_status_check;
alter table public.enrollments add constraint enrollments_status_check
  check (status in ('active', 'transferred_out', 'dropped_out'));
alter table public.enrollments drop constraint if exists enrollments_left;
alter table public.enrollments add constraint enrollments_left check (
  (status <> 'active') = (left_on is not null and left_by is not null)
  and (left_note is null or status <> 'active'));

-- Client writes: only active rows (baseline policies plus the status).
drop policy if exists enrollments_insert_scoped on public.enrollments;
create policy enrollments_insert_scoped on public.enrollments for insert to authenticated
  with check (status = 'active'
              and (is_superadmin()
                   or (current_user_role() in ('admin', 'coordinator')
                       and section_in_school(section_id, current_user_school_id())
                       and student_in_school(student_id, current_user_school_id()))));

drop policy if exists enrollments_update_scoped on public.enrollments;
create policy enrollments_update_scoped on public.enrollments for update to authenticated
  using (status = 'active'
         and (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator')
                  and section_in_school(section_id, current_user_school_id()))))
  with check (status = 'active'
              and (is_superadmin()
                   or (current_user_role() in ('admin', 'coordinator')
                       and section_in_school(section_id, current_user_school_id())
                       and student_in_school(student_id, current_user_school_id()))));

drop policy if exists enrollments_delete_scoped on public.enrollments;
create policy enrollments_delete_scoped on public.enrollments for delete to authenticated
  using (status = 'active'
         and (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator')
                  and section_in_school(section_id, current_user_school_id()))));

-- The learner's school follows a change of section only (see header, 7).
drop trigger if exists enrollments_sync_student_school on public.enrollments;
create trigger enrollments_sync_student_school after insert or update of section_id, student_id
  on public.enrollments for each row execute function public.sync_student_school_id();

-- ---------------------------------------------------------------------------
-- 2. students: anonymized learners
-- ---------------------------------------------------------------------------

alter table public.students add column if not exists anonymized_at timestamptz;

drop policy if exists students_insert_scoped on public.students;
create policy students_insert_scoped on public.students for insert to authenticated
  with check (anonymized_at is null
              and (is_superadmin()
                   or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())));

drop policy if exists students_update_scoped on public.students;
create policy students_update_scoped on public.students for update to authenticated
  using (anonymized_at is null
         and (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())))
  with check (anonymized_at is null
              and (is_superadmin()
                   or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())));

-- ---------------------------------------------------------------------------
-- 3. report_settings: archive_keep_months
-- ---------------------------------------------------------------------------

do $$
declare
  bad text;
begin
  select string_agg(format('id %s (school %s): %s', id, coalesce(school_id::text, 'region'),
                           settings -> 'archive_keep_months'), '; ' order by id)
    into bad
    from public.report_settings
   where settings ? 'archive_keep_months'
     and not (jsonb_typeof(settings -> 'archive_keep_months') = 'number'
              and (settings ->> 'archive_keep_months')::numeric between 1 and 120
              and (settings ->> 'archive_keep_months')::numeric = trunc((settings ->> 'archive_keep_months')::numeric));
  if bad is not null then
    raise exception 'report_settings has invalid archive_keep_months values: %. Fix them, then run this migration again.', bad;
  end if;
end $$;

alter table public.report_settings drop constraint if exists report_settings_archive_keep_months;
alter table public.report_settings add constraint report_settings_archive_keep_months check (
  not (settings ? 'archive_keep_months')
  or (jsonb_typeof(settings -> 'archive_keep_months') = 'number'
      and (settings ->> 'archive_keep_months')::numeric between 1 and 120
      and (settings ->> 'archive_keep_months')::numeric = trunc((settings ->> 'archive_keep_months')::numeric)));

-- ---------------------------------------------------------------------------
-- 4. enrollment_moves (history)
-- ---------------------------------------------------------------------------

create table if not exists public.enrollment_moves (
  id              bigint generated always as identity primary key,
  enrollment_id   bigint not null references public.enrollments(id),
  student_id      bigint not null references public.students(id),
  school_id       bigint not null references public.schools(id),
  school_year     text not null,
  from_section_id bigint not null references public.sections(id),
  to_section_id   bigint not null references public.sections(id),
  moved_on        date not null default current_date,
  moved_by        uuid references public.users(id),
  source          text not null check (source in ('sf1_missing', 'sf1_incoming', 'return'))
);
create index if not exists enrollment_moves_student on public.enrollment_moves (student_id);
create index if not exists enrollment_moves_school on public.enrollment_moves (school_id, school_year);

alter table public.enrollment_moves enable row level security;

drop policy if exists enrollment_moves_select on public.enrollment_moves;
create policy enrollment_moves_select on public.enrollment_moves for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
         or tutor_has_section(from_section_id)
         or tutor_has_section(to_section_id));

revoke all on public.enrollment_moves from anon;
grant select, insert, update, delete on public.enrollment_moves to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. sf1_last_imports (each section's last imported LRN set)
-- ---------------------------------------------------------------------------

create table if not exists public.sf1_last_imports (
  section_id  bigint primary key references public.sections(id),
  school_id   bigint not null references public.schools(id),
  school_year text not null,
  lrns        text[] not null,
  imported_at timestamptz not null default now(),
  imported_by uuid references public.users(id)
);
alter table public.sf1_last_imports drop constraint if exists sf1_last_imports_no_null_lrn;
alter table public.sf1_last_imports add constraint sf1_last_imports_no_null_lrn
  check (array_position(lrns, null) is null);

-- The row's school and year are the section's; who and when are stamped
-- (runs as the caller: their own sections are readable to them). An
-- anonymization removing an LRN keeps the stamps (transaction-local flag).
create or replace function public.sf1_last_imports_before_write() returns trigger
  language plpgsql
  set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and current_setting('basa.anonymizing', true) = 'on' then
    new.imported_at := old.imported_at;
    new.imported_by := old.imported_by;
    return new;
  end if;
  if not exists (select 1 from public.sections s
                  where s.id = new.section_id and s.school_id = new.school_id
                    and s.school_year = new.school_year) then
    raise exception 'section % is not a section of school % in %', new.section_id, new.school_id, new.school_year;
  end if;
  if auth.uid() is not null then
    new.imported_by := auth.uid();
  end if;
  new.imported_at := now();
  return new;
end;
$$;

revoke all on function public.sf1_last_imports_before_write() from public, anon, authenticated;

drop trigger if exists sf1_last_imports_before_write on public.sf1_last_imports;
create trigger sf1_last_imports_before_write before insert or update on public.sf1_last_imports
  for each row execute function public.sf1_last_imports_before_write();

alter table public.sf1_last_imports enable row level security;

drop policy if exists sf1_last_imports_select on public.sf1_last_imports;
create policy sf1_last_imports_select on public.sf1_last_imports for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id()));

drop policy if exists sf1_last_imports_insert on public.sf1_last_imports;
create policy sf1_last_imports_insert on public.sf1_last_imports for insert to authenticated
  with check (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id()));

drop policy if exists sf1_last_imports_update on public.sf1_last_imports;
create policy sf1_last_imports_update on public.sf1_last_imports for update to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id()))
  with check (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id()));

revoke all on public.sf1_last_imports from anon;
grant select, insert, update, delete on public.sf1_last_imports to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. Private helpers
-- ---------------------------------------------------------------------------

create schema if not exists basa_private;

-- The superadmin, or an admin/coordinator of this school.
create or replace function basa_private.manages_school(p_school_id bigint) returns boolean
  language sql stable security definer
  set search_path = public
as $$
  select is_superadmin()
      or coalesce(current_user_role() in ('admin', 'coordinator')
                  and p_school_id = current_user_school_id(), false);
$$;

-- A school year has ended after July 31 of its second year: the app's rule
-- for which dates belong to a school year (school_year_dates.dart: June 1 to
-- July 31, generous on both ends).
create or replace function basa_private.school_year_ended(p_school_year text) returns boolean
  language sql stable
  set search_path = public
as $$
  select current_date > make_date(right(p_school_year, 4)::integer, 7, 31);
$$;

-- archive_keep_months: the school's row, then the region row, then 6.
create or replace function basa_private.archive_keep_months(p_school_id bigint) returns integer
  language sql stable security definer
  set search_path = public
as $$
  select coalesce(
    (select (settings ->> 'archive_keep_months')::integer from public.report_settings
      where school_id = p_school_id and settings ? 'archive_keep_months'),
    (select (settings ->> 'archive_keep_months')::integer from public.report_settings
      where school_id is null and settings ? 'archive_keep_months'),
    6);
$$;

create or replace function basa_private.to_bigint(p text) returns bigint
  language sql immutable
as $$
  select case when p ~ '^-?[0-9]{1,18}$' then p::bigint end;
$$;

-- The learner a sync record belongs to, or null (a record of a row that is
-- new in the same upload is found through its parent's record). Covers the
-- learner tables (student_id in the row, or the server row the key names)
-- and their child tables (through the server parent row).
create or replace function basa_private.sync_record_student(r jsonb) returns bigint
  language plpgsql stable security definer
  set search_path = public
as $$
declare
  t text := r ->> 'table';
  k jsonb := coalesce(r -> 'key', '{}'::jsonb);
  w jsonb := coalesce(r -> 'row', '{}'::jsonb);
  v_id bigint;
  v_parent bigint;
  v_student bigint;
begin
  if jsonb_typeof(k) <> 'object' then k := '{}'::jsonb; end if;
  if jsonb_typeof(w) <> 'object' then w := '{}'::jsonb; end if;
  if t in ('crla_assessments', 'phil_iri_assessments', 'phil_iri_gst_results', 'aral_enrollments') then
    v_student := basa_private.to_bigint(w ->> 'student_id');
    if v_student is not null then return v_student; end if;
    v_id := basa_private.to_bigint(k ->> 'id');
    if v_id is null or v_id <= 0 then return null; end if;
    execute format('select student_id from public.%I where id = $1', t) into v_student using v_id;
    return v_student;
  elsif t in ('crla_part1_standard', 'crla_part1_english', 'crla_part2_fluency') then
    v_parent := coalesce(basa_private.to_bigint(w ->> 'assessment_id'), basa_private.to_bigint(k ->> 'assessment_id'));
    return (select student_id from public.crla_assessments where id = v_parent);
  elsif t in ('phil_iri_readings', 'phil_iri_rubric_scores') then
    v_parent := basa_private.to_bigint(w ->> 'assessment_id');
    v_id := basa_private.to_bigint(k ->> 'id');
    if v_parent is null and v_id > 0 then
      execute format('select assessment_id from public.%I where id = $1', t) into v_parent using v_id;
    end if;
    return (select student_id from public.phil_iri_assessments where id = v_parent);
  elsif t in ('phil_iri_miscues', 'phil_iri_answers') then
    v_parent := basa_private.to_bigint(w ->> 'reading_id');
    v_id := basa_private.to_bigint(k ->> 'id');
    if v_parent is null and v_id > 0 then
      execute format('select reading_id from public.%I where id = $1', t) into v_parent using v_id;
    end if;
    return (select a.student_id from public.phil_iri_readings rd
              join public.phil_iri_assessments a on a.id = rd.assessment_id
             where rd.id = v_parent);
  elsif t in ('aral_attendance', 'aral_irip_weeks', 'aral_checkins', 'aral_readability_logs') then
    v_parent := basa_private.to_bigint(w ->> 'enrollment_id');
    v_id := basa_private.to_bigint(k ->> 'id');
    if v_parent is null and v_id > 0 then
      execute format('select enrollment_id from public.%I where id = $1', t) into v_parent using v_id;
    end if;
    return (select student_id from public.aral_enrollments where id = v_parent);
  elsif t = 'aral_checkin_answers' then
    v_parent := basa_private.to_bigint(w ->> 'checkin_id');
    v_id := basa_private.to_bigint(k ->> 'id');
    if v_parent is null and v_id > 0 then
      select checkin_id into v_parent from public.aral_checkin_answers where id = v_id;
    end if;
    return (select e.student_id from public.aral_checkins c
              join public.aral_enrollments e on e.id = c.enrollment_id
             where c.id = v_parent);
  end if;
  return null;
end;
$$;

-- The oldest pending upload holding records of this learner, or null.
create or replace function basa_private.learner_pending_upload(p_student_id bigint) returns bigint
  language sql stable security definer
  set search_path = public
as $$
  select min(u.id)
    from public.sync_uploads u
   cross join lateral jsonb_array_elements(
           case when jsonb_typeof(u.payload -> 'records') = 'array' then u.payload -> 'records'
                else '[]'::jsonb end) rec
   where u.status = 'pending'
     and basa_private.sync_record_student(rec) = p_student_id;
$$;

-- Why this learner can't be anonymized now, or null when they can
-- (spec D3, owner 2026-11-12): the learner's latest enrollment (by school
-- year) is archived, more than archive_keep_months ago, and that school year
-- has ended. Earlier years, active or not, don't block.
create or replace function basa_private.learner_anonymize_refusal(p_student_id bigint) returns text
  language plpgsql stable security definer
  set search_path = public
as $$
declare
  v_st public.students;
  v_latest public.enrollments;
  v_left date;
  v_year text;
  v_keep integer;
begin
  select * into v_st from public.students where id = p_student_id;
  if not found then
    return format('learner %s not found', p_student_id);
  end if;
  if v_st.anonymized_at is not null then
    return 'this learner is already anonymized';
  end if;
  select * into v_latest from public.enrollments
   where student_id = p_student_id order by school_year desc limit 1;
  if not found then
    return 'this learner has no enrollment';
  end if;
  v_year := v_latest.school_year;
  v_left := v_latest.left_on;
  if v_latest.status = 'active' then
    return format('this learner is still active in %s (their latest school year)', v_year);
  end if;
  if not basa_private.school_year_ended(v_year) then
    return format('school year %s has not ended', v_year);
  end if;
  v_keep := basa_private.archive_keep_months(v_st.school_id);
  if v_left >= current_date - make_interval(months => v_keep) then
    return format('archived on %s: kept %s months, until after %s', v_left, v_keep,
                  (v_left + make_interval(months => v_keep))::date);
  end if;
  return null;
end;
$$;

revoke all on function basa_private.manages_school(bigint) from public, anon, authenticated;
revoke all on function basa_private.school_year_ended(text) from public, anon, authenticated;
revoke all on function basa_private.archive_keep_months(bigint) from public, anon, authenticated;
revoke all on function basa_private.to_bigint(text) from public, anon, authenticated;
revoke all on function basa_private.sync_record_student(jsonb) from public, anon, authenticated;
revoke all on function basa_private.learner_pending_upload(bigint) from public, anon, authenticated;
revoke all on function basa_private.learner_anonymize_refusal(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. The actions
-- ---------------------------------------------------------------------------

-- Archive: transferred out or dropped out (spec D1). The learner's active
-- ARAL enrollment that year is exited with the same reason.
create or replace function public.sf1_archive_learner(p_enrollment_id bigint, p_reason text, p_note text default null)
  returns jsonb
  language plpgsql security definer
  set search_path = public
as $$
declare
  v_e public.enrollments;
  v_school bigint;
  v_upload bigint;
  v_aral jsonb;
begin
  select * into v_e from public.enrollments where id = p_enrollment_id;
  if not found then
    raise exception 'enrollment % not found', p_enrollment_id;
  end if;
  select school_id into v_school from public.sections where id = v_e.section_id;
  if not basa_private.manages_school(v_school) then
    raise exception 'forbidden: only the superadmin or an admin or coordinator of the learner''s school archives a learner';
  end if;
  select * into v_e from public.enrollments where id = p_enrollment_id for update;
  if p_reason is null or p_reason not in ('transferred_out', 'dropped_out') then
    raise exception 'the reason must be transferred_out or dropped_out';
  end if;
  if v_e.status <> 'active' then
    raise exception 'enrollment % is not an active enrollment (%)', p_enrollment_id, v_e.status;
  end if;
  v_upload := basa_private.learner_pending_upload(v_e.student_id);
  if v_upload is not null then
    raise exception 'upload % holds records for this learner: approve or reject it first', v_upload;
  end if;

  update public.enrollments
     set status = p_reason, left_on = current_date, left_by = auth.uid(),
         left_note = nullif(btrim(p_note), '')
   where id = p_enrollment_id
  returning * into v_e;

  update public.aral_enrollments a
     set status = 'exited', exited_on = greatest(current_date, a.entered_on), exit_reason = p_reason
   where a.student_id = v_e.student_id and a.school_year = v_e.school_year and a.status = 'active'
  returning to_jsonb(a) into v_aral;

  return jsonb_build_object('enrollment', to_jsonb(v_e), 'aral_enrollment', coalesce(v_aral, 'null'::jsonb));
end;
$$;

-- Restore an archived, not anonymized enrollment into its own section.
-- Another section needs the move (next migration). ARAL is not restored
-- (spec D8).
create or replace function public.sf1_restore_learner(p_enrollment_id bigint, p_to_section_id bigint default null)
  returns jsonb
  language plpgsql security definer
  set search_path = public
as $$
declare
  v_e public.enrollments;
  v_school bigint;
begin
  select * into v_e from public.enrollments where id = p_enrollment_id;
  if not found then
    raise exception 'enrollment % not found', p_enrollment_id;
  end if;
  select school_id into v_school from public.sections where id = v_e.section_id;
  if not basa_private.manages_school(v_school) then
    raise exception 'forbidden: only the superadmin or an admin or coordinator of the learner''s school restores a learner';
  end if;
  select * into v_e from public.enrollments where id = p_enrollment_id for update;
  if v_e.status = 'active' then
    raise exception 'enrollment % is not an archived enrollment', p_enrollment_id;
  end if;
  if exists (select 1 from public.students where id = v_e.student_id and anonymized_at is not null) then
    raise exception 'this learner was anonymized: enroll them again as a new learner';
  end if;
  if p_to_section_id is not null and p_to_section_id <> v_e.section_id then
    raise exception 'restoring into another section: moving needs the move migration';
  end if;

  update public.enrollments
     set status = 'active', left_on = null, left_by = null, left_note = null
   where id = p_enrollment_id
  returning * into v_e;

  return jsonb_build_object('enrollment', to_jsonb(v_e));
end;
$$;

-- Learners of the school who may be anonymized now (spec D3).
create or replace function public.learner_anonymize_eligible(p_school_id bigint)
  returns table(student_id bigint, left_on date, school_year text)
  language plpgsql stable security definer
  set search_path = public
as $$
begin
  if not basa_private.manages_school(p_school_id) then
    raise exception 'forbidden: only the superadmin or an admin or coordinator of the school lists learners to anonymize';
  end if;
  return query
    select s.id, e.left_on, e.school_year
      from public.students s
      join lateral (select x.left_on, x.school_year from public.enrollments x
                     where x.student_id = s.id order by x.school_year desc limit 1) e on true
     where s.school_id = p_school_id
       and s.anonymized_at is null
       and basa_private.learner_anonymize_refusal(s.id) is null
     order by s.id;
end;
$$;

-- Anonymize one learner (spec D2): personal fields cleared, sex kept,
-- records kept. Never automatic: the app previews and confirms first.
create or replace function public.learner_anonymize(p_student_id bigint)
  returns jsonb
  language plpgsql security definer
  set search_path = public
as $$
declare
  v_st public.students;
  v_why text;
  v_old_lrn text;
begin
  select * into v_st from public.students where id = p_student_id;
  if not found then
    raise exception 'learner % not found', p_student_id;
  end if;
  if not basa_private.manages_school(v_st.school_id) then
    raise exception 'forbidden: only the superadmin or an admin or coordinator of the learner''s school anonymizes a learner';
  end if;
  select * into v_st from public.students where id = p_student_id for update;
  v_old_lrn := v_st.lrn;
  v_why := basa_private.learner_anonymize_refusal(p_student_id);
  if v_why is not null then
    raise exception 'learner % can''t be anonymized: %', p_student_id, v_why;
  end if;

  update public.students
     set lrn = 'ANON-' || id, last_name = 'Anonymized', first_name = '—',
         middle_name = null, birth_date = null, mother_tongue = null, ip_group = null, religion = null,
         address_street = null, barangay = null, municipality = null, province = null,
         father_name = null, mother_maiden_name = null, guardian_name = null, guardian_relationship = null,
         contact_number = null, learning_modality = null, remarks = null,
         anonymized_at = now()
   where id = p_student_id
  returning * into v_st;

  -- Personal data left elsewhere (owner 2026-11-12): SF1 import conflicts
  -- about the learner, and the old LRN in the sections' last imported sets.
  update public.import_conflicts
     set incoming_data = '{}'::jsonb, lrn = v_st.lrn
   where existing_student_id = p_student_id or lrn = v_old_lrn;
  perform set_config('basa.anonymizing', 'on', true);
  update public.sf1_last_imports
     set lrns = array_remove(lrns, v_old_lrn)
   where v_old_lrn = any (lrns);
  perform set_config('basa.anonymizing', 'off', true);

  return jsonb_build_object('student', to_jsonb(v_st));
end;
$$;

-- Learners still active in a section (or every section of the school) with
-- an sf1_last_imports row, in that row's school year, whose LRN is not in the
-- last imported set (spec D9). Sections without a row list nothing.
create or replace function public.sf1_missing(p_school_id bigint, p_section_id bigint default null)
  returns table(enrollment_id bigint, student_id bigint, lrn text, last_name text, first_name text,
                section_id bigint, section_name text)
  language plpgsql stable security definer
  set search_path = public
as $$
begin
  if not basa_private.manages_school(p_school_id) then
    raise exception 'forbidden: only the superadmin or an admin or coordinator of the school lists missing learners';
  end if;
  return query
    select e.id, s.id, s.lrn, s.last_name, s.first_name, sec.id, sec.section_name
      from public.sf1_last_imports li
      join public.sections sec on sec.id = li.section_id
      join public.enrollments e on e.section_id = sec.id and e.school_year = li.school_year and e.status = 'active'
      join public.students s on s.id = e.student_id
     where li.school_id = p_school_id and sec.school_id = p_school_id
       and (p_section_id is null or li.section_id = p_section_id)
       and not (s.lrn = any (array_remove(li.lrns, null)))
     order by sec.section_name, s.last_name, s.first_name, e.id;
end;
$$;

revoke all on function public.sf1_archive_learner(bigint, text, text) from public, anon;
revoke all on function public.sf1_restore_learner(bigint, bigint) from public, anon;
revoke all on function public.learner_anonymize_eligible(bigint) from public, anon;
revoke all on function public.learner_anonymize(bigint) from public, anon;
revoke all on function public.sf1_missing(bigint, bigint) from public, anon;
grant execute on function public.sf1_archive_learner(bigint, text, text) to authenticated;
grant execute on function public.sf1_restore_learner(bigint, bigint) to authenticated;
grant execute on function public.learner_anonymize_eligible(bigint) to authenticated;
grant execute on function public.learner_anonymize(bigint) to authenticated;
grant execute on function public.sf1_missing(bigint, bigint) to authenticated;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261112010000', 'sf1_leavers', true)
on conflict (id) do nothing;
