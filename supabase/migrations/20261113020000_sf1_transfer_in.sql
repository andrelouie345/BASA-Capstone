-- SF1 leavers (part 4): a same-server transfer from school A to school B
-- (review I2; owner 2026-11-13 accepted i2-design.md q1-q11).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261113010000.
-- App update required on all devices: yes (enrollment_moves gets a new
-- source and columns that an older app's pull would refuse at its local
-- CHECK; sync_archived_learners changes signature; a client update may no
-- longer change enrollments.section_id).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Spec: docs/superpowers/specs/2026-11-12-sf1-leavers-design.md (D15);
-- design .superpowers/sdd/2026-11-12-sf1-leavers/i2-design.md.
--
-- Changes:
--  1. enrollment_moves: source 'transfer_in' and the columns from_school_id,
--     from_school_name, from_section_name (snapshots: school B can't read
--     school A's rows), from_status, from_left_on (A's archive, kept here
--     because the enrollment row is re-used); CHECK enrollment_moves_transfer
--     (the from_* columns exactly on a transfer). SELECT also for the
--     admin/coordinator of from_school_id (row's own columns, F14).
--  2. transferred_out_learners(): an admin/coordinator reads the NAME
--     (id, LRN, names, sex, and the school they were sent to, never their
--     current one) of a learner transferred away
--     from their school, nothing else (review M4: no row policy, which would
--     hand them the whole current row); the pull adds these to the device
--     copy, so school A's own records keep their name.
--  3. sf1_transfer_in(conflict): school B's SF1 import conflict for a
--     learner whose enrollment this school year is at school A, archived
--     (transferred out or dropped out) or, for the superadmin only, still
--     active (then archived at A as transferred out first, ARAL exited as
--     sf1_archive_learner does). Same grade only; the SF1 row's last name,
--     first name and birth date must match the stored learner (normalized;
--     names only when no birth date is stored), whoever calls (review C1:
--     the conflict row is the caller's own; only its LRN and SF1 data are
--     used); refused while a pending upload holds the learner's records; an
--     older SF1 of the school the learner left gets a named refusal while
--     they are still active at the other school (non-superadmins; once
--     archived there they come back under the normal rules, and the
--     superadmin can always undo a transfer). A non-superadmin gets one
--     neutral refusal for every "can't transfer" case (unknown conflict, no
--     section, another school's conflict, not found, not enrolled, other
--     grade, active at A, identity), the superadmin the detailed reason. An
--     identity mismatch has no override, even for the superadmin: the name
--     or birth date is fixed at the learner's school first. Writes the history row, re-uses
--     the enrollment row (B's section, active; students.school_id follows by
--     the existing trigger), updates the learner's details from B's SF1 (a
--     blank cell keeps the stored value), resolves the conflict. A's records
--     of this year stay under A's sections. Callers: the superadmin or an
--     admin/coordinator of school B.
--  4. tutor_had_moved_learner: not for transfers (q4: school A's tutors get
--     no write access to a transferred learner's records).
--  5. Unsent work at school A (q5): basa_private.sync_learner_section refuses
--     a new record of a learner transferred away from the record's school
--     that year with a named message; sync_archived_learners takes the
--     record's school and lists that case too (status/date = A's archive),
--     so sync-preview lists them and sync-resolve ... server drops them;
--     it lists them for every tutor whose record is refused (A's section,
--     ARAL class or earlier-section tutor that year; review I2) and says
--     when the learner was transferred.
--  6. m1 (owner 2026-11-13): sync_archived_learners' tutor check is this
--     school year's: the tutor of the enrollment's section, the learner's
--     ARAL class tutor that year (aral_tutor_assesses), or a tutor of a
--     section of that same school the learner moved away from that year. A
--     past-year tutor, or another school's, gets nothing (was
--     tutor_has_student: any year).
--  7. q11 server rule: a client update may not change enrollments.section_id
--     (trigger enrollments_section_change_guard); only the SECURITY DEFINER
--     functions (sf1_move_learner, sf1_restore_learner, sf1_transfer_in,
--     which run as their owner) do.
--
-- RLS: enrollment_moves select raised (above); students unchanged (the
-- name comes through transferred_out_learners); no
-- client insert/update/delete on enrollment_moves (unchanged). Every
-- function is SECURITY DEFINER with SET search_path = public and its own
-- caller check, execute to authenticated only; the trigger functions and
-- basa_private helpers to nobody.
-- Grants: no new table or view.

-- ---------------------------------------------------------------------------
-- 1. enrollment_moves: the transfer history row
-- ---------------------------------------------------------------------------

alter table public.enrollment_moves add column if not exists from_school_id bigint references public.schools(id);
alter table public.enrollment_moves add column if not exists from_school_name text;
alter table public.enrollment_moves add column if not exists from_section_name text;
alter table public.enrollment_moves add column if not exists from_status text;
alter table public.enrollment_moves add column if not exists from_left_on date;

alter table public.enrollment_moves drop constraint if exists enrollment_moves_source_check;
alter table public.enrollment_moves add constraint enrollment_moves_source_check
  check (source in ('sf1_missing', 'sf1_incoming', 'return', 'transfer_in'));
alter table public.enrollment_moves drop constraint if exists enrollment_moves_transfer;
alter table public.enrollment_moves add constraint enrollment_moves_transfer check (
  (source = 'transfer_in') = (from_school_id is not null and from_status is not null and from_left_on is not null)
  and (from_status is null or from_status in ('transferred_out', 'dropped_out')));
create index if not exists enrollment_moves_from_school on public.enrollment_moves (from_school_id, school_year);

drop policy if exists enrollment_moves_select on public.enrollment_moves;
create policy enrollment_moves_select on public.enrollment_moves for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator')
             and (school_id = current_user_school_id() or from_school_id = current_user_school_id()))
         or tutor_has_section(from_section_id)
         or tutor_has_section(to_section_id));

-- ---------------------------------------------------------------------------
-- 2. School A still reads the learner's NAME (q6; review M4: the name only)
-- ---------------------------------------------------------------------------

-- No row policy (RLS would hand A the whole current students row: B's
-- address, guardians, contact). A definer function returns the name
-- columns of the learners transferred away from the caller's school; the
-- pull adds them to the device's students copy.
drop policy if exists students_select_transferred_from on public.students;
create or replace function public.transferred_out_learners()
  returns table(id bigint, lrn text, last_name text, first_name text, middle_name text, sex text, school_id bigint)
  language sql stable security definer
  set search_path = public
as $$
  -- school_id = the school this school sent them to (its latest transfer
  -- row), never their current school: a later B -> C move stays hidden
  -- (fix round 2, n2).
  select s.id, s.lrn, s.last_name, s.first_name, s.middle_name, s.sex, t.to_school
    from public.students s
    join lateral (select m.school_id as to_school from public.enrollment_moves m
                   where m.student_id = s.id and m.source = 'transfer_in'
                     and m.from_school_id = public.current_user_school_id()
                   order by m.id desc limit 1) t on true
   where coalesce(public.current_user_role() in ('admin', 'coordinator'), false)
     and public.current_user_school_id() is not null
   order by s.id;
$$;

revoke all on function public.transferred_out_learners() from public, anon;
grant execute on function public.transferred_out_learners() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. sf1_transfer_in
-- ---------------------------------------------------------------------------

-- A name for comparing: lower case, accents off, spaces trimmed and
-- collapsed; null when blank.
create or replace function basa_private.norm_name(p text) returns text
  language sql immutable
  set search_path = public
as $$
  select nullif(lower(regexp_replace(btrim(translate(coalesce(p, ''),
           'ÁÀÂÄÃÅĀÉÈÊËĒÍÌÎÏĪÓÒÔÖÕŌÚÙÛÜŪÑÇáàâäãåāéèêëēíìîïīóòôöõōúùûüūñç',
           'AAAAAAAEEEEEIIIIIOOOOOOUUUUUNCaaaaaaaeeeeeiiiiioooooouuuuunc')), '\s+', ' ', 'g')), '');
$$;

revoke all on function basa_private.norm_name(text) from public, anon, authenticated;

-- Owner 2026-11-13 (review C1): the conflict row is the caller's (any
-- admin/coordinator may write one into their own section), so nothing in
-- it but the LRN and the SF1 data is used, and the SF1 data must match the
-- stored learner. Only the superadmin transfers a learner still active at
-- the other school; B's admin/coordinator only one the other school already
-- archived. A non-superadmin gets one neutral refusal for every "can't
-- transfer" case, so the function says nothing about another school's
-- learner; the superadmin gets the detailed reason.
create or replace function public.sf1_transfer_in(p_conflict_id bigint)
  returns jsonb
  language plpgsql security definer
  set search_path = public
as $$
declare
  v_super boolean := coalesce(public.is_superadmin(), false);
  v_neutral constant text := 'this learner can''t be transferred in by your school: skip this conflict, or ask the superadmin to decide it';
  v_c public.import_conflicts;
  v_to public.sections;
  v_from public.sections;
  v_st public.students;
  v_in public.students;
  v_data jsonb;
  v_e public.enrollments;
  v_has_e boolean;
  v_move public.enrollment_moves;
  v_moved date;
  v_upload bigint;
  v_aral jsonb;
  v_from_school text;
begin
  -- Only admins and coordinators (a role check: says nothing about data).
  if not v_super and coalesce(public.current_user_role() not in ('admin', 'coordinator'), true) then
    raise exception 'forbidden: only the superadmin or an admin or coordinator of the receiving school transfers a learner in';
  end if;
  -- An unknown conflict, one without a section and another school's give a
  -- non-superadmin the same neutral refusal: no telling whether a conflict
  -- id exists (fix round 2, n3).
  select * into v_c from public.import_conflicts where id = p_conflict_id;
  if not found then
    if not v_super then raise exception '%', v_neutral; end if;
    raise exception 'conflict % not found', p_conflict_id;
  end if;
  select * into v_to from public.sections where id = v_c.section_id;
  if not found then
    if not v_super then raise exception '%', v_neutral; end if;
    raise exception 'conflict % has no section to enroll into', p_conflict_id;
  end if;
  if not basa_private.manages_school(v_to.school_id) then
    raise exception '%', v_neutral;
  end if;
  select * into v_c from public.import_conflicts where id = p_conflict_id for update;
  if v_c.status <> 'pending' then
    raise exception 'conflict % is already %', p_conflict_id, v_c.status;
  end if;
  -- The SF1 row without its blank cells (a blank keeps the stored value).
  select coalesce(jsonb_object_agg(d.key, d.value), '{}'::jsonb) into v_data
    from jsonb_each(case when jsonb_typeof(v_c.incoming_data) = 'object' then v_c.incoming_data
                         else '{}'::jsonb end) d
   where jsonb_typeof(d.value) <> 'null' and btrim(d.value #>> '{}') <> '';

  -- An anonymized learner's LRN is ANON-<id>: never found here (D2).
  select * into v_st from public.students where lrn = v_c.lrn for update;
  if not found then
    if not v_super then raise exception '%', v_neutral; end if;
    raise exception 'no learner with LRN %', v_c.lrn;
  end if;
  if v_c.existing_student_id is not null and v_c.existing_student_id <> v_st.id then
    if not v_super then raise exception '%', v_neutral; end if;
    raise exception 'conflict % names learner % but LRN % belongs to learner %',
      p_conflict_id, v_c.existing_student_id, v_c.lrn, v_st.id;
  end if;
  select * into v_e from public.enrollments
   where student_id = v_st.id and school_year = v_to.school_year for update;
  v_has_e := found;
  if v_has_e then
    select * into v_from from public.sections where id = v_e.section_id;
  end if;

  -- Identity (every caller): last name, first name and birth date of the
  -- SF1 row are the stored learner's (names only when no birth date is
  -- stored). An LRN typo must not merge two children.
  if basa_private.norm_name(v_data ->> 'last_name') is distinct from basa_private.norm_name(v_st.last_name)
     or basa_private.norm_name(v_data ->> 'first_name') is distinct from basa_private.norm_name(v_st.first_name)
     or (v_st.birth_date is not null and left(coalesce(v_data ->> 'birth_date', ''), 10) <> v_st.birth_date::text) then
    if not v_super then raise exception '%', v_neutral; end if;
    raise exception 'the SF1 row doesn''t match the learner with LRN %: the last name, first name or birth date differ',
      v_c.lrn;
  end if;

  -- An older SF1 of the school the learner left (review M3), while they are
  -- still active at the other school: named, for a non-superadmin only
  -- (fix round 2, N1). Once that school archives them they come back under
  -- the normal rules, and the superadmin can always undo a transfer.
  -- After the identity check (fix round 3, m1): a mismatching row gets the
  -- neutral text first, so it can't probe where the learner is.
  select m.moved_on into v_moved from public.enrollment_moves m
   where m.student_id = v_st.id and m.school_year = v_to.school_year
     and m.source = 'transfer_in' and m.from_school_id = v_to.school_id
   order by m.id desc limit 1;
  if not v_super and v_moved is not null and v_has_e and v_e.status = 'active'
     and v_from.school_id <> v_to.school_id then
    raise exception 'this learner was transferred to another school on %: skip this conflict (an older SF1 still lists them)',
      v_moved;
  end if;

  if not v_has_e then
    if not v_super then raise exception '%', v_neutral; end if;
    raise exception 'LRN % has no enrollment in % at another school: nothing to transfer', v_c.lrn, v_to.school_year;
  end if;
  if v_from.school_id = v_to.school_id then
    raise exception 'the learner is already enrolled at this school (%): use sf1-move or sf1-restore', v_from.section_name;
  end if;
  if v_from.grade_level <> v_to.grade_level then
    if not v_super then raise exception '%', v_neutral; end if;
    raise exception 'transfers are same grade only: % is Grade %, the learner is in Grade % at the other school',
      v_to.section_name, v_to.grade_level, v_from.grade_level;
  end if;
  if v_e.status = 'active' and not v_super then
    raise exception '%', v_neutral;
  end if;
  v_upload := basa_private.learner_pending_upload(v_st.id);
  if v_upload is not null then
    if not v_super then
      raise exception 'an upload holds records for this learner: ask the other school or the superadmin to decide it first';
    end if;
    raise exception 'upload % holds records for this learner: approve or reject it first', v_upload;
  end if;

  -- Still active at A (q11, the superadmin only): archived there as
  -- transferred out first, the active ARAL entry exited (as
  -- sf1_archive_learner).
  if v_e.status = 'active' then
    update public.enrollments
       set status = 'transferred_out', left_on = current_date, left_by = auth.uid()
     where id = v_e.id
    returning * into v_e;
    update public.aral_enrollments a
       set status = 'exited', exited_on = greatest(current_date, a.entered_on), exit_reason = 'transferred_out'
     where a.student_id = v_st.id and a.school_year = v_e.school_year and a.status = 'active'
    returning to_jsonb(a) into v_aral;
  end if;

  select school_name into v_from_school from public.schools where id = v_from.school_id;
  insert into public.enrollment_moves (enrollment_id, student_id, school_id, school_year, from_section_id,
                                       to_section_id, moved_by, source, from_school_id, from_school_name,
                                       from_section_name, from_status, from_left_on)
  values (v_e.id, v_st.id, v_to.school_id, v_e.school_year, v_from.id, v_to.id, auth.uid(), 'transfer_in',
          v_from.school_id, v_from_school, v_from.section_name, v_e.status, v_e.left_on)
  returning * into v_move;

  -- The same row (one enrollment per learner per year): B's section,
  -- active. enrollments_sync_student_school moves students.school_id to B.
  update public.enrollments
     set section_id = v_to.id, status = 'active', left_on = null, left_by = null, left_note = null
   where id = v_e.id
  returning * into v_e;

  -- The learner's details from B's SF1 (as resolve update); a blank cell
  -- keeps the stored value (owner decision 3). The names matched above, so
  -- the stored spelling stays.
  v_in := jsonb_populate_record(v_st, v_data - array['id', 'lrn', 'school_id', 'anonymized_at',
                                                     'created_at', 'updated_at']);
  update public.students
     set middle_name = v_in.middle_name,
         sex = v_in.sex, birth_date = v_in.birth_date, mother_tongue = v_in.mother_tongue,
         ip_group = v_in.ip_group, religion = v_in.religion, address_street = v_in.address_street,
         barangay = v_in.barangay, municipality = v_in.municipality, province = v_in.province,
         father_name = v_in.father_name, mother_maiden_name = v_in.mother_maiden_name,
         guardian_name = v_in.guardian_name, guardian_relationship = v_in.guardian_relationship,
         contact_number = v_in.contact_number, learning_modality = v_in.learning_modality, remarks = v_in.remarks
   where id = v_st.id
  returning * into v_st;

  update public.import_conflicts set status = 'resolved_updated' where id = p_conflict_id;

  return jsonb_build_object(
    'enrollment', to_jsonb(v_e),
    'student', to_jsonb(v_st),
    'move', to_jsonb(v_move),
    'from_school', jsonb_build_object('id', v_from.school_id, 'name', v_from_school),
    'from_section', jsonb_build_object('id', v_from.id, 'name', v_from.section_name),
    -- Only on the superadmin's path (an active learner): A's exited ARAL
    -- row, which the superadmin's device holds and mirrors (review M7).
    'aral_enrollment', coalesce(v_aral, 'null'::jsonb));
end;
$$;

revoke all on function public.sf1_transfer_in(bigint) from public, anon;
grant execute on function public.sf1_transfer_in(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. No write access for school A's tutors after a transfer (q4)
-- ---------------------------------------------------------------------------

-- As 20261112020000, plus: not a transfer row.
create or replace function public.tutor_had_moved_learner(p_student_id bigint, p_school_year text)
  returns boolean
  language sql stable security definer
  set search_path = public
as $$
  select coalesce(public.current_user_role() = 'tutor', false) and exists (
    select 1 from public.enrollment_moves m
     where m.student_id = p_student_id and m.school_year = p_school_year
       and m.source <> 'transfer_in'
       and public.tutor_has_section(m.from_section_id));
$$;

revoke all on function public.tutor_had_moved_learner(bigint, text) from public, anon;
grant execute on function public.tutor_had_moved_learner(bigint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Unsent work at school A: the upload's refusal (q5)
-- ---------------------------------------------------------------------------

-- As 20261113010000, plus the transferred-away learner.
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
  v_moved date;
begin
  if p_student_id is null or p_school_year is null or p_section_id is null then
    return null;
  end if;
  select * into v_e from public.enrollments where student_id = p_student_id and school_year = p_school_year;
  if not found then
    return null;
  end if;
  select format('%s, %s.', s.last_name, left(btrim(s.first_name), 1)) into v_name
    from public.students s where s.id = p_student_id;
  select m.moved_on into v_moved from public.enrollment_moves m
   where m.student_id = p_student_id and m.school_year = p_school_year
     and m.source = 'transfer_in' and m.from_school_id = p_school_id
   order by m.id desc limit 1;
  if v_moved is not null
     and exists (select 1 from public.sections s where s.id = v_e.section_id and s.school_id <> p_school_id) then
    raise exception '% was transferred to another school on %: drop these records with sync-resolve <table> <key> server (sync-preview lists them)',
      v_name, v_moved;
  end if;
  if v_e.status <> 'active' then
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
-- 6. m1: a tutor's view of an enrollment's archive is this school year's
-- ---------------------------------------------------------------------------

-- The tutor of the enrollment's section (a section belongs to one school
-- year), the learner's ARAL class tutor that school year, or a tutor of a
-- section of that school the learner moved away from that year (a section
-- move, not a transfer; scoped to the school, fix round 2 n4: a tutor at B
-- never reads A's archive through a move inside B).
create or replace function basa_private.sync_tutor_sees_enrollment(p_student_id bigint, p_section_id bigint,
                                                                   p_school_id bigint, p_school_year text)
  returns boolean
  language sql stable security definer
  set search_path = public
as $$
  select public.tutor_has_section(p_section_id)
      or public.aral_tutor_assesses(p_student_id, p_school_id, p_school_year)
      or (coalesce(public.current_user_role() = 'tutor', false)
          and exists (select 1 from public.enrollment_moves m
                       where m.student_id = p_student_id and m.school_year = p_school_year
                         and m.school_id = p_school_id and m.source <> 'transfer_in'
                         and public.tutor_has_section(m.from_section_id)));
$$;

revoke all on function basa_private.sync_tutor_sees_enrollment(bigint, bigint, bigint, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5/6. sync_archived_learners takes the record's school (q5, m1)
-- ---------------------------------------------------------------------------

drop function if exists public.sync_archived_learners(bigint[], text[]);
drop function if exists public.sync_archived_learners(bigint[], text[], bigint[]);
create or replace function public.sync_archived_learners(p_student_ids bigint[], p_school_years text[],
                                                         p_school_ids bigint[])
  returns table(student_id bigint, school_year text, school_id bigint, status text, left_on date, learner text,
                transferred_on date)
  language sql stable security definer
  set search_path = public
as $$
  select distinct on (q.sid, q.yr, q.sch)
         q.sid, q.yr, q.sch, x.status, x.left_on,
         format('%s, %s.', s.last_name, left(btrim(s.first_name), 1)), x.transferred_on
    from unnest(p_student_ids, p_school_years, p_school_ids) as q(sid, yr, sch)
    join public.students s on s.id = q.sid
    join lateral (
      -- Transferred away from the record's school that year: A's archive.
      -- Every tutor whose record sync_learner_section refuses sees it
      -- (review I2): the m1 rule on A's side (the section the learner left
      -- A from, A's ARAL class tutor that year, a tutor of an earlier A
      -- section that year), or A's admin/coordinator.
      select 0 as k, m.from_status as status, m.from_left_on as left_on, m.moved_on as transferred_on
        from public.enrollment_moves m
        join public.enrollments e on e.id = m.enrollment_id
        join public.sections sec on sec.id = e.section_id
       where m.student_id = q.sid and m.school_year = q.yr and m.source = 'transfer_in'
         and m.from_school_id = q.sch and sec.school_id <> q.sch
         and (basa_private.manages_school(q.sch)
              or basa_private.sync_tutor_sees_enrollment(q.sid, m.from_section_id, q.sch, q.yr))
      union all
      -- Archived that year.
      select 1, e.status, e.left_on, null::date
        from public.enrollments e
        join public.sections sec on sec.id = e.section_id
       where e.student_id = q.sid and e.school_year = q.yr and e.status <> 'active'
         and (basa_private.manages_school(sec.school_id)
              or basa_private.sync_tutor_sees_enrollment(e.student_id, e.section_id, sec.school_id, e.school_year))
    ) x on true
   order by q.sid, q.yr, q.sch, x.k;
$$;

revoke all on function public.sync_archived_learners(bigint[], text[], bigint[]) from public, anon;
grant execute on function public.sync_archived_learners(bigint[], text[], bigint[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Only the functions change an enrollment's section (q11)
-- ---------------------------------------------------------------------------

-- SECURITY INVOKER on purpose: inside sf1_move_learner / sf1_restore_learner
-- / sf1_transfer_in (SECURITY DEFINER) current_user is their owner, for a
-- client (PostgREST) it is authenticated or anon.
create or replace function public.enrollments_section_change_guard() returns trigger
  language plpgsql
  set search_path = public
as $$
begin
  if new.section_id is distinct from old.section_id and current_user in ('authenticated', 'anon') then
    raise exception 'a learner changes section only through sf1-move, sf1-restore or a transfer (resolve-conflict <id> update)';
  end if;
  return new;
end;
$$;

revoke all on function public.enrollments_section_change_guard() from public, anon, authenticated;

drop trigger if exists enrollments_section_change_guard on public.enrollments;
create trigger enrollments_section_change_guard before update of section_id on public.enrollments
  for each row execute function public.enrollments_section_change_guard();

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261113020000', 'sf1_transfer_in', true)
on conflict (id) do nothing;
