-- SF1 leavers (part 2): move a learner to another section of the same grade
-- with this school year's records; restore into another section; the old
-- section's tutor's unsent work follows the learner on upload.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261112010000.
-- App update required on all devices: yes (moved records change section on
-- the server; sync_apply re-points or refuses records of moved and archived
-- learners, and returns a note older apps don't know).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Spec: docs/superpowers/specs/2026-11-12-sf1-leavers-design.md (D5-D8,
-- D11, D14).
--
-- Changes:
--  1. sf1_move_learner(enrollment, to section, source): an active enrollment
--     to another section of the same school, school year and grade (D7).
--     The enrollment and this school year's crla_assessments,
--     phil_iri_assessments and phil_iri_gst_results of the learner in the
--     old section get the new section (D5); a CRLA attempt that would
--     collide with one already in the new section makes every moved attempt
--     of that language go after the learner's attempts there, in date then
--     id order (other languages keep their numbers); a Phil-IRI or GST
--     attempt already taken in the new section (the device's SQLite keys)
--     refuses the move instead (owner 2026-11-12); the active ARAL
--     roster entry of that year follows (class and tutor kept); one
--     enrollment_moves row. Refused while a pending upload holds the
--     learner's records (D11). Source: sf1_missing or sf1_incoming; 'return'
--     is written only by sf1_restore_learner.
--  2. sf1_restore_learner: restoring into another section moves the learner
--     (source 'return', same rules); same section as before.
--  3. A finalized Phil-IRI assessment gets a new section only through the
--     move: phil_iri_assessments_before_update lets an update through when
--     the transaction-local flag basa.moving_learner is 'on', the caller
--     manages the school, and nothing but section_id (and row_version)
--     changes. The move sets the flag and clears it before returning.
--  4. tutor_had_moved_learner(student, school_year): a tutor of a section the
--     learner moved away from that year (D14). Added to the tutor branch of
--     the CRLA, Phil-IRI and GST insert policies and the Phil-IRI update
--     policy's WITH CHECK (a completed session's follow-up update); in
--     crla_assessment_writable / phil_iri_assessment_writable (parts,
--     readings, miscues, answers, rubric scores) only for sessions that
--     tutor administered (owner 2026-11-12). Reading:
--     the CRLA, Phil-IRI and GST select policies and the two *_readable
--     helpers let that tutor read the records THEY administered of that
--     learner that year (sync_apply inserts with RETURNING, F14, and the
--     device reads its applied records back); nothing else of the new
--     section. The insert policies' target check (an active enrollment in
--     the row's section of the row's school) moves into the owner-run
--     basa_private.active_learner_grade: as the caller it read enrollments
--     and sections under the caller's RLS, and the old tutor can't see the
--     new section's rows. Same answer for everyone who could.
--  5. sync_apply (as 20261024050000, plus the payload check that version
--     lost, see 6): before an insert of crla_assessments,
--     phil_iri_assessments or phil_iri_gst_results, the learner's
--     enrollment for the row's school year decides: archived = the upload
--     stops with "<last name>, <first initial>. was archived on <date>
--     (<reason>): ..." (nothing applied); active in another section after a
--     move away from the row's section (enrollment_moves, same school and
--     year) = the row gets the current section. No attempt can collide
--     there: the CRLA, Phil-IRI and GST insert triggers always number a new
--     row in its section (max + 1; a sent attempt_no is ignored). The count goes into
--     the new sync_uploads.note ('<n> records followed a section move',
--     '1 record ...', null when none), set by sync_finish on applied only.
--     sync_finish takes the note (the 5-argument version is dropped: only
--     sync_apply called it). Clients can't send a note (insert policy).
--  6. 20261024050000 dropped `reason := basa_private.sync_check_payload(...)`
--     from sync_apply, so a package's shape (synced tables only, known
--     columns, negative device ids for new records, base versions) went
--     unchecked from then on. Restored here.
--
-- RLS: see 4 (insert, update and select policies of crla_assessments,
-- phil_iri_assessments, phil_iri_gst_results; the four helpers) and 5
-- (sync_uploads insert: note is null). No new table.
-- Definer helpers without a caller check (deliberate, like
-- sync_check_payload / sync_key_column): basa_private.active_learner_grade
-- and basa_private.sync_learner_section are SECURITY DEFINER and check no
-- caller. They must be executable by authenticated (the insert policies and
-- the security-invoker sync_apply call them as the signed-in user), never by
-- anon, and basa_private is not exposed by PostgREST (config.toml exposes
-- public and graphql_public only), so no API client can call them.
-- sync_learner_section can name an archived learner (that is its message);
-- active_learner_grade answers only yes/no plus a grade.
-- Grants: sf1_move_learner and tutor_had_moved_learner execute to
-- authenticated (the policies call the helper), nothing to anon;
-- basa_private.move_learner to nobody but its owner;
-- basa_private.active_learner_grade, sync_learner_section and the new
-- sync_finish to authenticated
-- (sync_apply runs as the caller; basa_private is not exposed by PostgREST).

-- ---------------------------------------------------------------------------
-- 1. Who may still write a moved learner's records (D14)
-- ---------------------------------------------------------------------------

-- A tutor of a section the learner moved away from in that school year.
create or replace function public.tutor_had_moved_learner(p_student_id bigint, p_school_year text)
  returns boolean
  language sql stable security definer
  set search_path = public
as $$
  select coalesce(public.current_user_role() = 'tutor', false) and exists (
    select 1 from public.enrollment_moves m
     where m.student_id = p_student_id and m.school_year = p_school_year
       and public.tutor_has_section(m.from_section_id));
$$;

revoke all on function public.tutor_had_moved_learner(bigint, text) from public, anon;
grant execute on function public.tutor_had_moved_learner(bigint, text) to authenticated;

-- Write helpers (as 20261024040000, plus the moved learner's sessions the
-- tutor administered).
create or replace function public.crla_assessment_writable(p_assessment_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.crla_assessments ca
    where ca.id = p_assessment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and ca.school_id = current_user_school_id())
           or (current_user_role() = 'tutor'
               and (tutor_has_section(ca.section_id) or aral_tutor_assesses(ca.student_id, ca.school_id, ca.school_year)
                    or (ca.administered_by = auth.uid() and tutor_had_moved_learner(ca.student_id, ca.school_year)))))
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
               and (tutor_has_section(a.section_id) or aral_tutor_assesses(a.student_id, a.school_id, a.school_year)
                    or (a.administered_by = auth.uid() and tutor_had_moved_learner(a.student_id, a.school_year)))))
  );
$$;

-- Read helpers (baseline, plus the moved learner's records the tutor
-- administered).
create or replace function public.crla_assessment_readable(p_assessment_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.crla_assessments ca
    where ca.id = p_assessment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and ca.school_id = current_user_school_id())
           or (current_user_role() = 'tutor'
               and (tutor_has_student(ca.student_id)
                    or (ca.administered_by = auth.uid() and tutor_had_moved_learner(ca.student_id, ca.school_year)))))
  );
$$;

create or replace function public.phil_iri_assessment_readable(p_assessment_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.phil_iri_assessments a
    where a.id = p_assessment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and a.school_id = current_user_school_id())
           or (current_user_role() = 'tutor'
               and (tutor_has_student(a.student_id)
                    or (a.administered_by = auth.uid() and tutor_had_moved_learner(a.student_id, a.school_year)))))
  );
$$;

-- The insert policies' target check (an active enrollment of the learner in
-- the row's section, a section of the row's school) read enrollments and
-- sections as the caller, under their RLS. A tutor writing for a learner who
-- moved away from their section can't see the new section's rows, so the
-- check now runs as owner: same answer for everyone else (they read those
-- rows already), and the caller's role branch still decides who may write.
-- In basa_private (not exposed by PostgREST); policies need execute.
create or replace function basa_private.active_learner_grade(p_student_id bigint, p_section_id bigint,
                                                             p_school_id bigint, p_school_year text)
  returns text
  language sql stable security definer
  set search_path = public
as $$
  select s.grade_level from public.sections s join public.enrollments e on e.section_id = s.id
   where s.id = p_section_id and s.school_id = p_school_id
     and e.student_id = p_student_id and e.school_year = p_school_year and e.status = 'active';
$$;

revoke all on function basa_private.active_learner_grade(bigint, bigint, bigint, text) from public, anon;
grant execute on function basa_private.active_learner_grade(bigint, bigint, bigint, text) to authenticated;

-- Insert policies (as 20261024040000, plus the moved learner).
drop policy if exists crla_assessments_insert_scoped on public.crla_assessments;
create policy crla_assessments_insert_scoped on public.crla_assessments for insert to authenticated
  with check (basa_private.active_learner_grade(student_id, section_id, school_id, school_year) in ('1', '2', '3')
              and (is_superadmin()
                   or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
                   or (current_user_role() = 'tutor'
                       and (tutor_has_section(section_id) or aral_tutor_assesses(student_id, school_id, school_year)
                            or tutor_had_moved_learner(student_id, school_year)))));
drop policy if exists phil_iri_assessments_insert on public.phil_iri_assessments;
create policy phil_iri_assessments_insert on public.phil_iri_assessments for insert to authenticated
  with check (basa_private.active_learner_grade(student_id, section_id, school_id, school_year) in ('4', '5', '6', '7', '8', '9', '10')
              and (is_superadmin()
                   or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
                   or (current_user_role() = 'tutor'
                       and (tutor_has_section(section_id) or aral_tutor_assesses(student_id, school_id, school_year)
                            or tutor_had_moved_learner(student_id, school_year)))));
drop policy if exists phil_iri_assessments_update on public.phil_iri_assessments;
create policy phil_iri_assessments_update on public.phil_iri_assessments for update to authenticated
  using (phil_iri_assessment_writable(id))
  with check (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
              or (current_user_role() = 'tutor'
                  and (tutor_has_section(section_id) or aral_tutor_assesses(student_id, school_id, school_year)
                       or tutor_had_moved_learner(student_id, school_year))));
drop policy if exists phil_iri_gst_results_insert on public.phil_iri_gst_results;
create policy phil_iri_gst_results_insert on public.phil_iri_gst_results for insert to authenticated
  with check (basa_private.active_learner_grade(student_id, section_id, school_id, school_year) in ('4', '5', '6', '7', '8', '9', '10')
              and (is_superadmin()
                   or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
                   or (current_user_role() = 'tutor'
                       and (tutor_has_section(section_id) or aral_tutor_assesses(student_id, school_id, school_year)
                            or tutor_had_moved_learner(student_id, school_year)))));

-- Select policies (baseline, plus the moved learner's records the tutor
-- administered; the row's own columns, F14).
drop policy if exists crla_assessments_select_scoped on public.crla_assessments;
create policy crla_assessments_select_scoped on public.crla_assessments for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
         or (current_user_role() = 'tutor'
             and (tutor_has_student(student_id)
                  or (administered_by = auth.uid() and tutor_had_moved_learner(student_id, school_year)))));
drop policy if exists phil_iri_assessments_select on public.phil_iri_assessments;
create policy phil_iri_assessments_select on public.phil_iri_assessments for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
         or (current_user_role() = 'tutor'
             and (tutor_has_student(student_id)
                  or (administered_by = auth.uid() and tutor_had_moved_learner(student_id, school_year)))));
drop policy if exists phil_iri_gst_results_select on public.phil_iri_gst_results;
create policy phil_iri_gst_results_select on public.phil_iri_gst_results for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
         or (current_user_role() = 'tutor'
             and (tutor_has_student(student_id)
                  or (administered_by = auth.uid() and tutor_had_moved_learner(student_id, school_year)))));

-- ---------------------------------------------------------------------------
-- 2. Phil-IRI sessions: the move may re-point a finalized one (D5)
-- ---------------------------------------------------------------------------

-- As 20261109010000, plus the move's exception first.
create or replace function public.phil_iri_assessments_before_update() returns trigger
  language plpgsql security definer
  set search_path = public
as $$
begin
  if auth.uid() is null then
    return new; -- SQL Editor maintenance
  end if;
  -- sf1_move_learner: the section only, any status (a finalized round too).
  if current_setting('basa.moving_learner', true) = 'on' and basa_private.manages_school(old.school_id) then
    if (to_jsonb(new) - 'section_id' - 'row_version') is distinct from (to_jsonb(old) - 'section_id' - 'row_version') then
      raise exception 'a section move changes only the section of a Phil-IRI assessment';
    end if;
    return new;
  end if;
  if old.status = 'finalized' then
    raise exception 'a finalized Phil-IRI assessment cannot be changed';
  end if;
  if (new.student_id, new.school_id, new.section_id, new.school_year, new.round,
      new.attempt_no, new.administered_by, new.assessed_at, new.import_source)
     is distinct from
     (old.student_id, old.school_id, old.section_id, old.school_year, old.round,
      old.attempt_no, old.administered_by, old.assessed_at, old.import_source) then
    raise exception 'only the status of a Phil-IRI assessment can change';
  end if;

  if new.status = 'finalized' then
    if not (is_superadmin() or current_user_role() in ('admin', 'coordinator')) then
      raise exception 'only an admin or coordinator can finalize a Phil-IRI assessment';
    end if;
    if old.status <> 'completed' then
      raise exception 'only a completed Phil-IRI assessment can be finalized';
    end if;
    if new.thresholds_snapshot is null then
      raise exception 'finalizing needs the thresholds snapshot';
    end if;
    new.finalized_at := now();
    new.completed_at := old.completed_at;
  else
    new.thresholds_snapshot := null;
    new.finalized_at := null;
    if new.status = 'completed' and old.status = 'in_progress' then
      new.completed_at := now();
    elsif new.status = 'in_progress' then
      new.completed_at := null;
    else
      new.completed_at := old.completed_at;
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The move
-- ---------------------------------------------------------------------------

-- The move itself; callers check who may (sf1_move_learner,
-- sf1_restore_learner).
create or replace function basa_private.move_learner(p_enrollment_id bigint, p_to_section_id bigint, p_source text)
  returns jsonb
  language plpgsql security definer
  set search_path = public
as $$
declare
  v_e public.enrollments;
  v_from public.sections;
  v_to public.sections;
  v_upload bigint;
  v_crla jsonb := '[]';
  v_phil jsonb;
  v_gst jsonb;
  v_aral jsonb;
  v_move jsonb;
  c record;
  v_no integer;
  v_renumber text[];
begin
  select * into v_e from public.enrollments where id = p_enrollment_id for update;
  if not found then
    raise exception 'enrollment % not found', p_enrollment_id;
  end if;
  if v_e.status <> 'active' then
    raise exception 'enrollment % is not an active enrollment (%)', p_enrollment_id, v_e.status;
  end if;
  select * into v_from from public.sections where id = v_e.section_id;
  select * into v_to from public.sections where id = p_to_section_id;
  if not found then
    raise exception 'section % not found', p_to_section_id;
  end if;
  if v_to.school_id <> v_from.school_id then
    raise exception 'forbidden: section % belongs to another school', p_to_section_id;
  end if;
  if v_to.id = v_from.id then
    raise exception 'the learner is already in that section';
  end if;
  if v_to.school_year <> v_e.school_year then
    raise exception 'section % is in another school year (%), the enrollment is in %',
      p_to_section_id, v_to.school_year, v_e.school_year;
  end if;
  if v_to.grade_level <> v_from.grade_level then
    raise exception 'moves are same grade only: % is Grade %, the learner is in Grade %',
      v_to.section_name, v_to.grade_level, v_from.grade_level;
  end if;
  v_upload := basa_private.learner_pending_upload(v_e.student_id);
  if v_upload is not null then
    raise exception 'upload % holds records for this learner: approve or reject it first', v_upload;
  end if;
  -- Phil-IRI and GST attempts keep their numbers (a finalized round can't be
  -- renumbered); one already taken in the new section refuses the move
  -- (owner 2026-11-12): the device's SQLite keys on them, so a duplicate
  -- would stop its pull.
  select a.id, a.round, a.attempt_no into c
    from public.phil_iri_assessments a
   where a.student_id = v_e.student_id and a.school_year = v_e.school_year and a.section_id = v_from.id
     and exists (select 1 from public.phil_iri_assessments x
                  where x.student_id = a.student_id and x.school_id = v_to.school_id and x.section_id = v_to.id
                    and x.round = a.round and x.school_year = a.school_year and x.attempt_no = a.attempt_no)
   order by a.assessed_at, a.id limit 1;
  if found then
    raise exception 'cannot move: the learner''s Phil-IRI % attempt % (assessment %) is already taken in %; nothing was changed',
      upper(c.round), c.attempt_no, c.id, v_to.section_name;
  end if;
  select g.id, g.attempt_no into c
    from public.phil_iri_gst_results g
   where g.student_id = v_e.student_id and g.school_year = v_e.school_year and g.section_id = v_from.id
     and exists (select 1 from public.phil_iri_gst_results x
                  where x.student_id = g.student_id and x.school_id = v_to.school_id and x.section_id = v_to.id
                    and x.school_year = g.school_year and x.attempt_no = g.attempt_no)
   order by g.taken_at, g.id limit 1;
  if found then
    raise exception 'cannot move: the learner''s GST attempt % (result %) is already taken in %; nothing was changed',
      c.attempt_no, c.id, v_to.section_name;
  end if;

  update public.enrollments set section_id = v_to.id where id = p_enrollment_id returning * into v_e;

  -- CRLA (crla_assessments_unique_attempt): when any moved attempt of a
  -- language would take a number already used in the new section, every
  -- moved attempt of that language is numbered after the learner's attempts
  -- there, in date then id order; otherwise they keep their numbers. (Only
  -- the colliding ones renumbered could break the order when the new
  -- section has gaps: 1 and 5 there, 1 and 2 moving -> 6 and 2.)
  select coalesce(array_agg(distinct m.subject_variant), array[]::text[]) into v_renumber
    from public.crla_assessments m
   where m.student_id = v_e.student_id and m.school_year = v_e.school_year and m.section_id = v_from.id
     and exists (select 1 from public.crla_assessments x
                  where x.student_id = m.student_id and x.school_id = v_to.school_id and x.section_id = v_to.id
                    and x.subject_variant = m.subject_variant and x.school_year = m.school_year
                    and x.attempt_no = m.attempt_no);
  for c in select id, subject_variant, attempt_no from public.crla_assessments
            where student_id = v_e.student_id and school_year = v_e.school_year and section_id = v_from.id
            order by assessed_at, id loop
    v_no := c.attempt_no;
    if c.subject_variant = any (v_renumber) then
      select coalesce(max(x.attempt_no), 0) + 1 into v_no from public.crla_assessments x
       where x.student_id = v_e.student_id and x.school_id = v_to.school_id and x.section_id = v_to.id
         and x.subject_variant = c.subject_variant and x.school_year = v_e.school_year;
    end if;
    update public.crla_assessments set section_id = v_to.id, attempt_no = v_no where id = c.id;
    v_crla := v_crla || jsonb_build_array(jsonb_build_object('id', c.id, 'section_id', v_to.id, 'attempt_no', v_no));
  end loop;

  -- Phil-IRI sessions, finalized ones included (the trigger's exception).
  perform set_config('basa.moving_learner', 'on', true);
  with u as (
    update public.phil_iri_assessments set section_id = v_to.id
     where student_id = v_e.student_id and school_year = v_e.school_year and section_id = v_from.id
    returning id)
  select coalesce(jsonb_agg(id order by id), '[]'::jsonb) into v_phil from u;
  perform set_config('basa.moving_learner', 'off', true);

  with u as (
    update public.phil_iri_gst_results set section_id = v_to.id
     where student_id = v_e.student_id and school_year = v_e.school_year and section_id = v_from.id
    returning id)
  select coalesce(jsonb_agg(id order by id), '[]'::jsonb) into v_gst from u;

  -- ARAL: the roster entry follows; class and tutor stay (the class tutor
  -- is the learner's tutor).
  update public.aral_enrollments a set section_id = v_to.id
   where a.student_id = v_e.student_id and a.school_id = v_to.school_id
     and a.school_year = v_e.school_year and a.status = 'active'
  returning to_jsonb(a) into v_aral;

  insert into public.enrollment_moves (enrollment_id, student_id, school_id, school_year,
                                       from_section_id, to_section_id, moved_by, source)
  values (v_e.id, v_e.student_id, v_to.school_id, v_e.school_year, v_from.id, v_to.id, auth.uid(), p_source)
  returning to_jsonb(enrollment_moves.*) into v_move;

  return jsonb_build_object(
    'enrollment', to_jsonb(v_e),
    'moved', jsonb_build_object('crla_assessments', v_crla, 'phil_iri_assessments', v_phil,
                                'phil_iri_gst_results', v_gst),
    'aral_enrollment', coalesce(v_aral, 'null'::jsonb),
    'move', v_move);
end;
$$;

revoke all on function basa_private.move_learner(bigint, bigint, text) from public, anon, authenticated;

-- Move a learner to another section of the same grade (spec section 3).
create or replace function public.sf1_move_learner(p_enrollment_id bigint, p_to_section_id bigint, p_source text)
  returns jsonb
  language plpgsql security definer
  set search_path = public
as $$
declare
  v_school bigint;
begin
  select s.school_id into v_school
    from public.enrollments e join public.sections s on s.id = e.section_id
   where e.id = p_enrollment_id;
  if not found then
    raise exception 'enrollment % not found', p_enrollment_id;
  end if;
  if not basa_private.manages_school(v_school) then
    raise exception 'forbidden: only the superadmin or an admin or coordinator of the learner''s school moves a learner';
  end if;
  if p_source is null or p_source not in ('sf1_missing', 'sf1_incoming') then
    raise exception 'the source must be sf1_missing or sf1_incoming (a return goes through sf1_restore_learner)';
  end if;
  return basa_private.move_learner(p_enrollment_id, p_to_section_id, p_source);
end;
$$;

-- Restore an archived, not anonymized enrollment; into another section of
-- the same grade it is moved there (source 'return'). ARAL is not restored
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

  update public.enrollments
     set status = 'active', left_on = null, left_by = null, left_note = null
   where id = p_enrollment_id
  returning * into v_e;

  if p_to_section_id is not null and p_to_section_id <> v_e.section_id then
    return basa_private.move_learner(p_enrollment_id, p_to_section_id, 'return');
  end if;
  return jsonb_build_object('enrollment', to_jsonb(v_e));
end;
$$;

revoke all on function public.sf1_move_learner(bigint, bigint, text) from public, anon;
revoke all on function public.sf1_restore_learner(bigint, bigint) from public, anon;
grant execute on function public.sf1_move_learner(bigint, bigint, text) to authenticated;
grant execute on function public.sf1_restore_learner(bigint, bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Sync: the note, the learner check, sync_apply
-- ---------------------------------------------------------------------------

alter table public.sync_uploads add column if not exists note text;

-- As 20261020020000, plus: no note from a client.
drop policy if exists sync_uploads_insert on public.sync_uploads;
create policy sync_uploads_insert on public.sync_uploads
  for insert to authenticated
  with check (uploader_id = auth.uid()
              and current_user_role() is not null
              and school_id is not distinct from current_user_school_id()
              and status = 'pending'
              and reason is null and conflicts is null and id_map is null and note is null
              and decided_at is null and decided_by is null);

-- Where an incoming CRLA / Phil-IRI / GST row of a learner goes (D11): the
-- learner's current section when they moved away from the row's section in
-- that school year (same school); null = leave the row as it is. An
-- archived learner stops the upload. Runs as owner: the uploader may no
-- longer read the learner's enrollment.
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
    raise exception '% was archived on % (%): ask the coordinator to restore them, or delete these records with sync-resolve',
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

-- Records the outcome of sync_apply (as 20261020020000, plus the note, kept
-- only on applied). Same rights as sync_claim.
drop function if exists basa_private.sync_finish(bigint, text, text, jsonb, jsonb);
create or replace function basa_private.sync_finish(p_id bigint, p_status text, p_reason text,
                                                    p_conflicts jsonb, p_id_map jsonb, p_note text)
  returns void
  language plpgsql security definer
  set search_path = public
as $$
begin
  if p_status not in ('applied', 'conflict', 'error') then
    raise exception 'Invalid outcome %', p_status;
  end if;
  perform basa_private.sync_claim(p_id);
  update public.sync_uploads
     set status = p_status, reason = p_reason, conflicts = p_conflicts, id_map = p_id_map,
         note = case when p_status = 'applied' then p_note end,
         decided_at = now(), decided_by = auth.uid()
   where id = p_id;
end;
$$;

revoke all on function basa_private.sync_finish(bigint, text, text, jsonb, jsonb, text) from public, anon;
grant execute on function basa_private.sync_finish(bigint, text, text, jsonb, jsonb, text) to authenticated;

-- As 20261024050000, plus the payload check again (see header, 6) and the
-- moved / archived learner (header, 5).
create or replace function public.sync_apply(p_id bigint) returns jsonb
  language plpgsql security invoker
  set search_path = public
as $$
declare
  u public.sync_uploads;
  r jsonb;
  t text;
  op text;
  kc text;
  k jsonb;            -- the record's key, its references rewritten
  rw jsonb;           -- the row to write
  col text;
  cols text;
  v text;
  new_id bigint;
  n int;
  server jsonb;
  ref_map jsonb := '{}';    -- "-5" -> 812, all tables (one device countdown)
  id_map jsonb := '{}';     -- {table: {"-5": 812}}
  conflicts jsonb := '[]';
  at text := '';
  outcome text;
  reason text;
  my_sub text;
  my_claims text;
  sec bigint;
  followed int := 0;        -- records re-pointed to a moved learner's section
  note text;
begin
  u := basa_private.sync_claim(p_id);

  -- Release guard: rules changed since the device's release; status stays
  -- pending so the tutor can withdraw it and send it again after updating.
  if exists (select 1 from public.basa_migrations
              where app_update_required and id > u.release) then
    raise exception 'Upload % was made by an older BASA release (%); update the device and sync again',
      p_id, u.release;
  end if;

  if not exists (select 1 from public.basa_migrations where id = u.release) then
    raise exception 'Upload % was made by BASA release %, which this server does not have',
      p_id, u.release;
  end if;

  reason := basa_private.sync_check_payload(u.payload);
  if reason is not null then
    perform basa_private.sync_finish(p_id, 'error', reason, null, null, null);
    return jsonb_build_object('status', 'error', 'reason', reason);
  end if;

  -- The approval is a permission to apply, not a grant of the approver's
  -- rights (owner 2026-10-20): the writes run as the UPLOADER, so a package
  -- can only do what its uploader could do directly, created_by stamps the
  -- uploader, and conflicts only show rows the uploader may read. auth.uid()
  -- reads request.jwt.claim.sub, else the sub in request.jwt.claims
  -- (PostgREST 12+); both are switched for this transaction and restored
  -- before the outcome is recorded (decided_by = the approver).
  my_sub := current_setting('request.jwt.claim.sub', true);
  my_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claim.sub', u.uploader_id::text, true);
  perform set_config('request.jwt.claims',
    jsonb_set(coalesce(nullif(my_claims, '')::jsonb, '{}'), '{sub}', to_jsonb(u.uploader_id::text))::text, true);

  begin
    -- The class cap and the one-session-per-date rule hold for the upload's
    -- end state (C2): checked after the last record, below.
    set constraints public.aral_enrollments_class_cap, public.aral_sessions_one_per_day deferred;
    for r in select value from jsonb_array_elements(u.payload -> 'records') loop
      t := r ->> 'table';
      op := r ->> 'op';
      kc := basa_private.sync_key_column(t);
      k := r -> 'key';
      rw := coalesce(r -> 'row', '{}');
      at := format('%s %s', t, k);

      -- Follow-up update of a record inserted earlier in this upload: its
      -- key is the device id; use the server's.
      if kc = 'id' and op = 'update' and (k ->> 'id')::bigint < 0 then
        v := k ->> 'id';
        if not ref_map ? v then
          raise exception '%.id = % is not in this upload', t, v;
        end if;
        k := jsonb_build_object('id', (ref_map ->> v)::bigint);
      end if;

      -- Rewrite references to records of this upload (negative ids).
      foreach col in array basa_private.sync_ref_columns(t) loop
        if col = kc and (k ->> kc)::bigint < 0 then
          v := k ->> kc;
          if not ref_map ? v then
            raise exception '%.% = % is not in this upload', t, col, v;
          end if;
          k := jsonb_build_object(kc, (ref_map ->> v)::bigint);
        end if;
        if jsonb_typeof(rw -> col) = 'number' and (rw ->> col)::bigint < 0 then
          v := rw ->> col;
          if not ref_map ? v then
            raise exception '%.% = % is not in this upload', t, col, v;
          end if;
          rw := rw || jsonb_build_object(col, (ref_map ->> v)::bigint);
        end if;
      end loop;

      -- Never written by a device: the key (from k), the version, generated columns.
      rw := rw - kc - 'row_version';
      rw := rw - coalesce((select array_agg(attname::text) from pg_attribute
                            where attrelid = format('public.%I', t)::regclass
                              and attnum > 0 and attgenerated <> ''), array[]::text[]);

      -- A learner who moved or was archived since the device's copy (D11):
      -- this year's new records follow them to their current section; an
      -- archived learner stops the upload.
      if op = 'insert' and t in ('crla_assessments', 'phil_iri_assessments', 'phil_iri_gst_results') then
        sec := basa_private.sync_learner_section(rw);
        if sec is not null then
          rw := rw || jsonb_build_object('section_id', sec);
          followed := followed + 1;
        end if;
      end if;

      if op = 'insert' then
        if kc <> 'id' then
          rw := rw || k;
        end if;
        select string_agg(format('%I', c), ', ') into cols from jsonb_object_keys(rw) c;
        if kc = 'id' then
          execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1) returning id',
                         t, cols, cols, t)
            into new_id using rw;
          ref_map := ref_map || jsonb_build_object(k ->> 'id', new_id);
          id_map := id_map || jsonb_build_object(t, coalesce(id_map -> t, '{}') || jsonb_build_object(k ->> 'id', new_id));
        else
          execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1)',
                         t, cols, cols, t)
            using rw;
        end if;
      else
        if op = 'update' then
          select string_agg(format('%I', c), ', ') into cols from jsonb_object_keys(rw) c;
          if cols is null then
            raise exception 'nothing to change';
          end if;
          -- $3 null = follow-up (no version check; see the header).
          execute format('update public.%I set (%s) = (select %s from jsonb_populate_record(null::public.%I, $1)) '
                         'where %I = (select %I from jsonb_populate_record(null::public.%I, $2)) '
                         'and ($3::bigint is null or row_version = $3)',
                         t, cols, cols, t, kc, kc, t)
            using rw, k, (r ->> 'base_version')::bigint;
        else
          execute format('delete from public.%I where %I = (select %I from jsonb_populate_record(null::public.%I, $1)) '
                         'and row_version = $2', t, kc, kc, t)
            using k, (r ->> 'base_version')::bigint;
        end if;
        get diagnostics n = row_count;
        if n = 0 and op = 'update' and not (r ? 'base_version') then
          raise exception 'follow-up update found no row';
        elsif n = 0 then
          -- Version moved on, deleted, or no longer visible to the caller.
          execute format('select to_jsonb(x) from public.%I x where %I = (select %I from jsonb_populate_record(null::public.%I, $1))',
                         t, kc, kc, t)
            into server using k;
          conflicts := conflicts || jsonb_build_array(jsonb_build_object(
            'table', t, 'key', r -> 'key', 'base_version', r -> 'base_version',
            'server_version', server -> 'row_version', 'server_row', server));
        end if;
      end if;
    end loop;

    if jsonb_array_length(conflicts) > 0 then
      raise exception 'sync conflict' using errcode = 'BSY01';
    end if;
    at := 'the upload as a whole';
    set constraints public.aral_enrollments_class_cap, public.aral_sessions_one_per_day immediate;
    outcome := 'applied';
  exception
    when sqlstate 'BSY01' then
      outcome := 'conflict';
    when others then
      outcome := 'error';
      reason := at || ': ' || sqlerrm;
  end;

  -- Back to immediate for the rest of the caller's transaction (nothing is
  -- pending here: applied rows were checked, refused ones rolled back).
  set constraints public.aral_enrollments_class_cap, public.aral_sessions_one_per_day immediate;
  perform set_config('request.jwt.claim.sub', coalesce(my_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(my_claims, ''), true);

  if outcome = 'applied' and followed > 0 then
    note := case when followed = 1 then '1 record followed a section move'
                 else followed || ' records followed a section move' end;
  end if;
  perform basa_private.sync_finish(p_id, outcome, reason,
    case when outcome = 'conflict' then conflicts end,
    case when outcome = 'applied' then id_map end,
    note);
  return jsonb_build_object('status', outcome, 'reason', reason,
    'conflicts', case when outcome = 'conflict' then conflicts end,
    'id_map', case when outcome = 'applied' then id_map end,
    'note', note);
end;
$$;

revoke all on function public.sync_apply(bigint) from public, anon;
grant execute on function public.sync_apply(bigint) to authenticated;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261112020000', 'sf1_leaver_moves_sync', true)
on conflict (id) do nothing;
