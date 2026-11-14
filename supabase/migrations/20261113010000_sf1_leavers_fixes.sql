-- SF1 leavers (part 3): fixes from the final review (2026-11-13).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261112020000.
-- App update required on all devices: no (a new read-only function, a
-- clearer refusal text, and more personal data cleared by learner_anonymize;
-- no rule an app applies changes, so an older app keeps working against
-- this server).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Spec: docs/superpowers/specs/2026-11-12-sf1-leavers-design.md (D2, D11);
-- review .superpowers/sdd/2026-11-12-sf1-leavers/final-review.md (I1, M2,
-- M3).
--
-- Changes:
--  1. sync_archived_learners(student ids, school years): of these pairs, the
--     learners whose enrollment that year is archived, with the date, the
--     reason and a short name (I1). The device checks its new CRLA /
--     Phil-IRI / GST records against it before an upload (sync-preview lists
--     them) and lets sync-resolve <table> <key> server drop them. Runs as
--     owner, like basa_private.sync_learner_section: the uploader may no
--     longer read the learner's enrollment (moved, then archived). Rows only
--     for learners the caller may read (superadmin; admin/coordinator of the
--     enrollment's school; a tutor through tutor_has_student or
--     tutor_had_moved_learner).
--  2. basa_private.sync_learner_section: the archived learner's refusal names
--     both ways out: the coordinator restores them, or the device drops
--     the records with sync-resolve <table> <key> server (I1; the old text
--     said "delete these records with sync-resolve", which could not touch
--     new records).
--  3. learner_anonymize also clears enrollments.left_note of the learner, every
--     school year (M2: free text, often personal), and sets the learner's
--     pending import_conflicts rows to resolved_skipped (M3: a pending
--     conflict with empty data could re-enroll an anonymized learner).
--     Conflicts already resolved keep their status.
--  4. A new enrollment of an anonymized learner is refused (M3), whoever
--     writes it (trigger enrollments_refuse_anonymized, BEFORE INSERT, so an
--     upsert that would update the learner's row is refused too).
--
-- Not here (review I3, server part): a client update may still change
-- enrollments.section_id. The superadmin's transfer (import-resolve <id>
-- update for a learner active at another school) does exactly that, so the
-- refusal is in the app only (ImportViewModel.resolve) until the transfer
-- path is decided (review I2).
--
-- RLS: no table, view or policy is added or changed. The new function is
-- SECURITY DEFINER with its own caller check (above), SET search_path =
-- public, execute to authenticated only; the trigger function to nobody.
-- Grants: nothing to grant (no new table or view).

-- ---------------------------------------------------------------------------
-- 1. Which of these learners are archived (I1)
-- ---------------------------------------------------------------------------

create or replace function public.sync_archived_learners(p_student_ids bigint[], p_school_years text[])
  returns table(student_id bigint, school_year text, status text, left_on date, learner text)
  language sql stable security definer
  set search_path = public
as $$
  select e.student_id, e.school_year, e.status, e.left_on,
         format('%s, %s.', s.last_name, left(btrim(s.first_name), 1))
    from unnest(p_student_ids, p_school_years) as q(sid, yr)
    join public.enrollments e on e.student_id = q.sid and e.school_year = q.yr
    join public.sections sec on sec.id = e.section_id
    join public.students s on s.id = e.student_id
   where e.status <> 'active'
     and (basa_private.manages_school(sec.school_id)
          or public.tutor_has_student(e.student_id)
          or public.tutor_had_moved_learner(e.student_id, e.school_year))
   group by e.student_id, e.school_year, e.status, e.left_on, s.last_name, s.first_name
   order by e.student_id, e.school_year;
$$;

revoke all on function public.sync_archived_learners(bigint[], text[]) from public, anon;
grant execute on function public.sync_archived_learners(bigint[], text[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The archived learner's refusal at upload (I1)
-- ---------------------------------------------------------------------------

-- As 20261112020000, only the message changes.
create or replace function basa_private.sync_learner_section(p_row jsonb)
  returns bigint
  language plpgsql stable security definer
  set search_path = public
as $$
declare
  p_student_id bigint := basa_private.to_bigint(p_row ->> 'student_id');
  p_school_id bigint := basa_private.to_bigint(p_row ->> 'school_id');
  p_school_year text := p_row ->> 'school_year';
  p_section_id bigint := basa_private.to_bigint(p_row ->> 'section_id');
  v_e public.enrollments;
  v_name text;
begin
  if p_student_id is null or p_school_year is null or p_section_id is null then
    return null;
  end if;
  select * into v_e from public.enrollments where student_id = p_student_id and school_year = p_school_year;
  if not found then
    return null;
  end if;
  if v_e.status <> 'active' then
    select format('%s, %s.', s.last_name, left(btrim(s.first_name), 1)) into v_name
      from public.students s where s.id = p_student_id;
    raise exception '% was archived on % (%): ask the coordinator to restore them, or drop these records with sync-resolve <table> <key> server (sync-preview lists them)',
      v_name, v_e.left_on, replace(v_e.status, '_', ' ');
  end if;
  if v_e.section_id <> p_section_id
     and exists (select 1 from public.enrollment_moves m
                  where m.student_id = p_student_id and m.school_year = p_school_year
                    and m.from_section_id = p_section_id and m.school_id = p_school_id)
     and exists (select 1 from public.sections s where s.id = v_e.section_id and s.school_id = p_school_id) then
    return v_e.section_id;
  end if;
  return null;
end;
$$;

revoke all on function basa_private.sync_learner_section(jsonb) from public, anon;
grant execute on function basa_private.sync_learner_section(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. learner_anonymize clears left_note and closes pending conflicts (M2, M3)
-- ---------------------------------------------------------------------------

-- As 20261112010000, plus the two updates marked M2 and M3.
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

  -- M2: the archive note is free text (often personal), every school year.
  update public.enrollments set left_note = null
   where student_id = p_student_id and left_note is not null;

  -- Personal data left elsewhere (owner 2026-11-12): SF1 import conflicts
  -- about the learner, and the old LRN in the sections' last imported sets.
  -- M3: a pending conflict is closed (skipped), so nobody resolves it into
  -- a new enrollment. Columns added to import_conflicts later that hold
  -- personal data must be cleared here too.
  update public.import_conflicts
     set incoming_data = '{}'::jsonb, lrn = v_st.lrn,
         status = case when status = 'pending' then 'resolved_skipped' else status end
   where existing_student_id = p_student_id or lrn = v_old_lrn;
  perform set_config('basa.anonymizing', 'on', true);
  update public.sf1_last_imports
     set lrns = array_remove(lrns, v_old_lrn)
   where v_old_lrn = any (lrns);
  perform set_config('basa.anonymizing', 'off', true);

  return jsonb_build_object('student', to_jsonb(v_st));
end;
$$;

revoke all on function public.learner_anonymize(bigint) from public, anon;
grant execute on function public.learner_anonymize(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. No new enrollment of an anonymized learner (M3)
-- ---------------------------------------------------------------------------

create or replace function public.enrollments_refuse_anonymized() returns trigger
  language plpgsql security definer
  set search_path = public
as $$
begin
  if exists (select 1 from public.students where id = new.student_id and anonymized_at is not null) then
    raise exception 'this learner was anonymized: enroll them again as a new learner'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.enrollments_refuse_anonymized() from public, anon, authenticated;

drop trigger if exists enrollments_refuse_anonymized on public.enrollments;
create trigger enrollments_refuse_anonymized before insert on public.enrollments
  for each row execute function public.enrollments_refuse_anonymized();

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261113010000', 'sf1_leavers_fixes', false)
on conflict (id) do nothing;
