-- ARAL classes: 15 active learners per class, one program and grade band,
-- learners from any section of the school, sessions per class.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261023030000.
-- App update required on all devices: yes (columns removed and rules changed:
-- aral_enrollments.tutor_id and aral_tutor_settings are gone, the section cap
-- is replaced by a class cap, and a new session needs a class; an older app
-- can't sync with this server).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Design: docs/superpowers/specs/2026-10-23-aral-classes-design.md (owner
-- decisions 1-12, 2026-10-23; D-T1a..d, 2026-10-24).
--
-- Why: DepEd Memorandum 064 s. 2025 caps a CLASS at 15 learners and groups
-- learners by reading profile, not by section; a tutor teaches several
-- classes. BASA capped a section at 15 and gave each learner a tutor.
--
-- Rules:
--   * aral_classes (new, synced): school + school year + name (unique per
--     school and year, ignoring case and outer spaces), one program
--     (foundational, ks1, ks2_basic, ks2_plus, ks3_basic, ks3_plus), one
--     grade band (1-3, 4-6, 7-10), an optional tutor (an active tutor of the
--     school, checked when set). A class keeps its school and year; program
--     and band change only while no roster entry points at it; a class with
--     roster entries or sessions can't be deleted.
--   * aral_enrollments.class_id (null = waiting for a class). An ACTIVE
--     learner given a class, moved to another, or reactivated in one must
--     match the class's school and year, program (key_stage + track) and
--     grade band (their section's grade), and the class must have fewer than
--     15 other active learners (advisory lock per class). A program change
--     that leaves the learner in the class is not re-checked (decision 7). A
--     placed active learner whose section changes must stay inside the band
--     (D-T1a).
--   * aral_enrollments.tutor_id removed: a learner's tutor is their class's
--     tutor. Existing learners become unplaced (decision 11).
--   * Basis 'referral': referred_by and referral_reason required exactly when
--     the basis is referral; both are locked after enrolment like the basis
--     (D-T1b).
--   * The 15-per-section cap is removed (aral_check_section_cap dropped).
--   * aral_sessions.class_id: every new session needs a class of the same
--     school and year; one session per class per date; session_no counts per
--     class. Sessions from before keep no class and per-tutor numbers, with no
--     day check (D-T1c). A session keeps its class.
--   * aral_tutor_settings (several sessions per day) is dropped.
--
-- RLS (raised in this migration):
--   * aral_classes: read superadmin / admin-coordinator of the school / tutor
--     of the class; write superadmin / admin-coordinator of the school. anon:
--     nothing.
--   * New helpers aral_tutor_has_class(class), aral_tutor_has_student(student)
--     (placed in a class I teach, any status), aral_tutor_has_enrollment
--     (roster entry), aral_tutor_reads_section(section).
--   * Class tutors read their class learners' roster rows, names, enrollments
--     rows and section rows, and assess them (CRLA, Phil-IRI, GST inserts and
--     the writable helpers accept tutor_has_section OR aral_tutor_has_student).
--     tutor_has_student includes class learners (names and results reads).
--   * IRIP, check-ins and readability: written by the class tutor (D-T1d),
--     read by the class tutor or the section tutor.
--   * aral_sessions: a tutor logs sessions for their own classes (as
--     themselves); admin/coordinator for any class of their school. Read and
--     write: sessions the tutor held or of their classes; plus READ of an
--     older session's header where one of their current learners has a mark.
--     aral_attendance read: marks of sessions the tutor can write, plus their
--     current learners' own marks (decision 8).
--   * aral_tutor_settings and its policies are dropped.
--
-- Sync: aral_classes joins the synced tables (row_version, payload check,
-- keyed by id); aral_enrollments.class_id and aral_sessions.class_id are
-- reference columns (an upload may hold a new class and rows pointing at
-- it). aral_tutor_settings leaves the lists.

-- ---------------------------------------------------------------------------
-- 1. aral_classes
-- ---------------------------------------------------------------------------

create table if not exists public.aral_classes (
  id          bigint generated always as identity primary key,
  school_id   bigint not null references public.schools(id),
  school_year text not null,
  class_name  text not null,
  program     text not null,
  grade_band  text not null,
  tutor_id    uuid references public.users(id) on delete set null,
  room        text,
  schedule    text,
  notes       text,
  created_by  uuid references public.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  row_version bigint not null default 1,
  constraint aral_classes_class_name_check check (length(btrim(class_name)) > 0),
  constraint aral_classes_program_check
    check (program in ('foundational', 'ks1', 'ks2_basic', 'ks2_plus', 'ks3_basic', 'ks3_plus')),
  constraint aral_classes_grade_band_check check (grade_band in ('1-3', '4-6', '7-10')),
  constraint aral_classes_school_year_format check (
    case when school_year ~ '^\d{4}-\d{4}$'
         then right(school_year, 4)::integer = left(school_year, 4)::integer + 1
         else false end)
);
create unique index if not exists aral_classes_name_key
  on public.aral_classes (school_id, school_year, lower(btrim(class_name)));
create index if not exists aral_classes_tutor on public.aral_classes (tutor_id, school_year);

create or replace function public.aral_classes_before_write() returns trigger
  language plpgsql security definer set search_path to 'public'
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.created_by := auth.uid();
    end if;
    new.created_at := now();
  else
    if (new.school_id, new.school_year) is distinct from (old.school_id, old.school_year) then
      raise exception 'an ARAL class keeps its school and school year';
    end if;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    if (new.program, new.grade_band) is distinct from (old.program, old.grade_band)
       and exists (select 1 from public.aral_enrollments where class_id = new.id) then
      raise exception 'an ARAL class with learners keeps its program and grade band';
    end if;
  end if;
  new.updated_at := now();
  if new.tutor_id is not null and (tg_op = 'INSERT' or new.tutor_id is distinct from old.tutor_id)
     and not exists (select 1 from public.users
                     where id = new.tutor_id and role = 'tutor' and is_active and school_id = new.school_id) then
    raise exception 'the ARAL class tutor must be an active tutor of the class''s school';
  end if;
  return new;
end;
$$;

drop trigger if exists aral_classes_before_write on public.aral_classes;
create trigger aral_classes_before_write before insert or update on public.aral_classes
  for each row execute function public.aral_classes_before_write();

-- row_version, as on the other synced tables (20261020020000).
drop trigger if exists sync_row_version on public.aral_classes;
create trigger sync_row_version before update on public.aral_classes
  for each row execute function public.basa_bump_row_version();

alter table public.aral_classes enable row level security;
revoke all on public.aral_classes from anon;

-- ---------------------------------------------------------------------------
-- 2. New columns
-- ---------------------------------------------------------------------------

alter table public.aral_enrollments
  add column if not exists class_id bigint,
  add column if not exists referred_by text,
  add column if not exists referral_reason text;
alter table public.aral_sessions add column if not exists class_id bigint;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'aral_enrollments_class_id_fkey'
                 and conrelid = 'public.aral_enrollments'::regclass) then
    alter table public.aral_enrollments add constraint aral_enrollments_class_id_fkey
      foreign key (class_id) references public.aral_classes(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'aral_sessions_class_id_fkey'
                 and conrelid = 'public.aral_sessions'::regclass) then
    alter table public.aral_sessions add constraint aral_sessions_class_id_fkey
      foreign key (class_id) references public.aral_classes(id) on delete restrict;
  end if;
end $$;
create index if not exists aral_enrollments_class on public.aral_enrollments (class_id);
create index if not exists aral_sessions_class on public.aral_sessions (class_id, held_on);

-- Referral basis.
alter table public.aral_enrollments drop constraint if exists aral_enrollments_basis_source_check;
alter table public.aral_enrollments add constraint aral_enrollments_basis_source_check
  check (basis_source in ('crla', 'phil_iri', 'manual', 'referral'));
alter table public.aral_enrollments drop constraint if exists aral_enrollments_basis;
alter table public.aral_enrollments add constraint aral_enrollments_basis
  check (basis_source in ('manual', 'referral') or basis_level is not null);
alter table public.aral_enrollments drop constraint if exists aral_enrollments_referral;
alter table public.aral_enrollments add constraint aral_enrollments_referral
  check ((basis_source = 'referral') = (referred_by is not null and btrim(referred_by) <> ''
                                        and referral_reason is not null and btrim(referral_reason) <> ''));

-- ---------------------------------------------------------------------------
-- 3. Placement
-- ---------------------------------------------------------------------------

-- The learner's section grade is inside the class's band.
create or replace function public.aral_class_band_ok(p_class_id bigint, p_section_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select coalesce((
    select case when s.grade_level ~ '^\d+$' then s.grade_level::integer end
           between split_part(c.grade_band, '-', 1)::integer and split_part(c.grade_band, '-', 2)::integer
    from public.aral_classes c, public.sections s
    where c.id = p_class_id and s.id = p_section_id), false);
$$;

-- Checks an active learner going into a class (insert, class change,
-- reactivation). Serialized per class so two coordinators can't both take
-- the 15th place. Runs inside the definer triggers only.
create or replace function public.aral_check_class_placement(
  p_id bigint, p_class_id bigint, p_student_id bigint, p_section_id bigint, p_school_id bigint,
  p_school_year text, p_key_stage text, p_track text)
 returns void language plpgsql security definer set search_path to 'public'
as $$
declare
  c record;
begin
  perform pg_advisory_xact_lock(hashtext('aral_class:' || p_class_id::text));
  select school_id, school_year, program into c from public.aral_classes where id = p_class_id;
  if not found or c.school_id is distinct from p_school_id or c.school_year is distinct from p_school_year then
    raise exception 'the ARAL class belongs to another school or school year';
  end if;
  if c.program is distinct from p_key_stage || coalesce('_' || p_track, '') then
    raise exception 'the learner''s program does not match the ARAL class';
  end if;
  if not aral_class_band_ok(p_class_id, p_section_id) then
    raise exception 'the learner''s grade is outside the ARAL class''s grade band';
  end if;
  if (select count(*) from public.aral_enrollments
      where class_id = p_class_id and status = 'active' and id is distinct from p_id) >= 15 then
    raise exception 'an ARAL class has at most 15 active learners';
  end if;
end;
$$;

create or replace function public.aral_enrollments_before_insert()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
    new.status := 'active';
    new.exited_on := null;
    new.exit_reason := null;
  end if;
  new.created_at := now();
  new.updated_at := now();
  if new.class_id is not null and new.status = 'active' then
    perform aral_check_class_placement(null, new.class_id, new.student_id, new.section_id, new.school_id,
                                       new.school_year, new.key_stage, new.track);
  end if;
  return new;
end;
$$;

create or replace function public.aral_enrollments_before_update()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  -- Placement rules hold for SQL Editor maintenance too.
  if new.class_id is not null and new.status = 'active' then
    if new.class_id is distinct from old.class_id or old.status <> 'active'
       or (new.school_id, new.school_year) is distinct from (old.school_id, old.school_year) then
      perform aral_check_class_placement(new.id, new.class_id, new.student_id, new.section_id, new.school_id,
                                         new.school_year, new.key_stage, new.track);
    elsif new.section_id is distinct from old.section_id and not aral_class_band_ok(new.class_id, new.section_id) then
      raise exception 'the learner''s grade is outside the ARAL class''s grade band';
    end if;
  end if;
  if auth.uid() is null then
    return new; -- SQL Editor maintenance
  end if;
  if (new.student_id, new.school_id, new.school_year, new.basis_source, new.basis_round, new.basis_level,
      new.basis_assessment_id, new.referred_by, new.referral_reason, new.created_by, new.created_at)
     is distinct from
     (old.student_id, old.school_id, old.school_year, old.basis_source, old.basis_round, old.basis_level,
      old.basis_assessment_id, old.referred_by, old.referral_reason, old.created_by, old.created_at) then
    raise exception 'an ARAL enrollment keeps its learner, school, year and basis; only the placement, class, status and notes change';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Sessions per class
-- ---------------------------------------------------------------------------

drop function if exists public.aral_check_session_day(bigint, uuid, date);
create or replace function public.aral_check_session_day(p_id bigint, p_class_id bigint, p_held_on date)
 returns void language plpgsql security definer set search_path to 'public'
as $$
begin
  if p_class_id is null then
    return; -- sessions from before classes: no day check
  end if;
  if exists (select 1 from public.aral_sessions
             where class_id = p_class_id and held_on = p_held_on and id is distinct from p_id) then
    raise exception 'an ARAL class already has a session on that date';
  end if;
end;
$$;

create or replace function public.aral_sessions_before_insert()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  c record;
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  new.created_at := now();
  new.updated_at := now();
  if new.class_id is null then
    raise exception 'a new ARAL session needs a class';
  end if;
  select school_id, school_year into c from public.aral_classes where id = new.class_id;
  if not found or c.school_id is distinct from new.school_id or c.school_year is distinct from new.school_year then
    raise exception 'the ARAL class belongs to another school or school year';
  end if;
  -- serialize numbering (and the one-per-day check) per class
  perform pg_advisory_xact_lock(hashtext('aral_class_sessions:' || new.class_id::text));
  select coalesce(max(session_no), 0) + 1 into new.session_no
  from public.aral_sessions where class_id = new.class_id;
  perform aral_check_tutor(new.tutor_id, new.school_id);
  perform aral_check_session_day(null, new.class_id, new.held_on);
  return new;
end;
$$;

create or replace function public.aral_sessions_before_update()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  -- The one-per-day rule holds for SQL Editor maintenance too.
  if new.held_on is distinct from old.held_on and new.class_id is not null then
    perform pg_advisory_xact_lock(hashtext('aral_class_sessions:' || new.class_id::text));
    perform aral_check_session_day(new.id, new.class_id, new.held_on);
  end if;
  if auth.uid() is null then
    return new; -- SQL Editor maintenance
  end if;
  if (new.tutor_id, new.class_id, new.school_id, new.school_year, new.session_no, new.created_by, new.created_at)
     is distinct from
     (old.tutor_id, old.class_id, old.school_id, old.school_year, old.session_no, old.created_by, old.created_at) then
    raise exception 'an ARAL session keeps its tutor, class, school, year and number; only the date, minutes, set-up, lesson and remarks change';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Access helpers
-- ---------------------------------------------------------------------------

create or replace function public.aral_tutor_has_class(p_class_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select public.current_user_role() = 'tutor' and exists (
    select 1 from public.aral_classes where id = p_class_id and tutor_id = auth.uid());
$$;

-- The learner is placed (any status) in a class the caller teaches.
create or replace function public.aral_tutor_has_student(p_student_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select public.current_user_role() = 'tutor' and exists (
    select 1 from public.aral_enrollments e
    join public.aral_classes c on c.id = e.class_id
    where e.student_id = p_student_id and c.tutor_id = auth.uid());
$$;

-- The roster entry is in a class the caller teaches.
create or replace function public.aral_tutor_has_enrollment(p_enrollment_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select public.current_user_role() = 'tutor' and exists (
    select 1 from public.aral_enrollments e
    join public.aral_classes c on c.id = e.class_id
    where e.id = p_enrollment_id and c.tutor_id = auth.uid());
$$;

-- A section one of the caller's class learners belongs to (that section's
-- row only, not its other learners).
create or replace function public.aral_tutor_reads_section(p_section_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select public.current_user_role() = 'tutor' and exists (
    select 1 from public.aral_enrollments e
    join public.aral_classes c on c.id = e.class_id
    where e.section_id = p_section_id and c.tutor_id = auth.uid());
$$;

create or replace function public.tutor_has_student(p_student_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select public.current_user_role() = 'tutor' and (
    exists (
      select 1
      from public.enrollments e
      join public.tutor_section_assignments tsa on tsa.section_id = e.section_id
      where e.student_id = p_student_id and tsa.tutor_id = auth.uid())
    or public.aral_tutor_has_student(p_student_id));
$$;

create or replace function public.aral_enrollment_readable(p_enrollment_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.aral_enrollments e
    where e.id = p_enrollment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and e.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and (tutor_has_section(e.section_id) or aral_tutor_has_class(e.class_id))))
  );
$$;

create or replace function public.aral_irip_writable(p_enrollment_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.aral_enrollments e
    where e.id = p_enrollment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and e.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and aral_tutor_has_class(e.class_id)))
  );
$$;

create or replace function public.aral_session_writable(p_session_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.aral_sessions s
    where s.id = p_session_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and s.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and (s.tutor_id = auth.uid() or aral_tutor_has_class(s.class_id))))
  );
$$;

-- Writable, or an older session in which one of the caller's current
-- learners has a mark (its header only; the marks policy shows only theirs).
create or replace function public.aral_session_readable(p_session_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select public.aral_session_writable(p_session_id)
    or (public.current_user_role() = 'tutor' and exists (
          select 1 from public.aral_attendance a
          join public.aral_enrollments e on e.id = a.enrollment_id
          join public.aral_classes c on c.id = e.class_id
          where a.session_id = p_session_id and c.tutor_id = auth.uid()));
$$;

create or replace function public.crla_assessment_writable(p_assessment_id bigint) returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.crla_assessments ca
    where ca.id = p_assessment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and ca.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and (tutor_has_section(ca.section_id) or aral_tutor_has_student(ca.student_id))))
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
           or (current_user_role() = 'tutor' and (tutor_has_section(a.section_id) or aral_tutor_has_student(a.student_id))))
  );
$$;

-- Policies call these four; the placement and band checks run inside the
-- definer triggers only.
revoke all on function public.aral_tutor_has_class(bigint) from public, anon;
revoke all on function public.aral_tutor_has_student(bigint) from public, anon;
revoke all on function public.aral_tutor_has_enrollment(bigint) from public, anon;
revoke all on function public.aral_tutor_reads_section(bigint) from public, anon;
grant execute on function public.aral_tutor_has_class(bigint) to authenticated;
grant execute on function public.aral_tutor_has_student(bigint) to authenticated;
grant execute on function public.aral_tutor_has_enrollment(bigint) to authenticated;
grant execute on function public.aral_tutor_reads_section(bigint) to authenticated;
revoke all on function public.aral_check_class_placement(bigint, bigint, bigint, bigint, bigint, text, text, text)
  from public, anon, authenticated;
revoke all on function public.aral_class_band_ok(bigint, bigint) from public, anon, authenticated;
revoke all on function public.aral_check_session_day(bigint, bigint, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Policies
-- ---------------------------------------------------------------------------

drop policy if exists aral_classes_select on public.aral_classes;
create policy aral_classes_select on public.aral_classes for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
         or (current_user_role() = 'tutor' and tutor_id = auth.uid()));
drop policy if exists aral_classes_insert on public.aral_classes;
create policy aral_classes_insert on public.aral_classes for insert to authenticated
  with check (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id()));
drop policy if exists aral_classes_update on public.aral_classes;
create policy aral_classes_update on public.aral_classes for update to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id()))
  with check (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id()));
drop policy if exists aral_classes_delete on public.aral_classes;
create policy aral_classes_delete on public.aral_classes for delete to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id()));

-- Roster: the class tutor replaces the learner's own tutor.
drop policy if exists aral_enrollments_select on public.aral_enrollments;
create policy aral_enrollments_select on public.aral_enrollments for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
         or (current_user_role() = 'tutor' and (tutor_has_section(section_id) or aral_tutor_has_class(class_id))));

-- Sessions and attendance.
drop policy if exists aral_sessions_select on public.aral_sessions;
create policy aral_sessions_select on public.aral_sessions for select to authenticated
  using (aral_session_readable(id));
drop policy if exists aral_sessions_insert on public.aral_sessions;
create policy aral_sessions_insert on public.aral_sessions for insert to authenticated
  with check (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
              or (current_user_role() = 'tutor' and tutor_id = auth.uid() and school_id = current_user_school_id()
                  and aral_tutor_has_class(class_id)));
drop policy if exists aral_sessions_update on public.aral_sessions;
create policy aral_sessions_update on public.aral_sessions for update to authenticated
  using (aral_session_writable(id))
  with check (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
              or (current_user_role() = 'tutor' and (tutor_id = auth.uid() or aral_tutor_has_class(class_id))));
drop policy if exists aral_attendance_select on public.aral_attendance;
create policy aral_attendance_select on public.aral_attendance for select to authenticated
  using (aral_session_writable(session_id) or aral_tutor_has_enrollment(enrollment_id));

-- Class learners' own enrollments and section rows (to assess and to pull).
drop policy if exists enrollments_select_scoped on public.enrollments;
create policy enrollments_select_scoped on public.enrollments for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and section_in_school(section_id, current_user_school_id()))
         or (current_user_role() = 'tutor' and (tutor_has_section(section_id) or aral_tutor_has_student(student_id))));
drop policy if exists sections_select_scoped on public.sections;
create policy sections_select_scoped on public.sections for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
         or (current_user_role() = 'tutor' and (tutor_has_section(id) or aral_tutor_reads_section(id))));

-- Assessing (decision 10): a class tutor assesses their class learners.
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
                       and (tutor_has_section(section_id) or aral_tutor_has_student(student_id)))));
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
                       and (tutor_has_section(section_id) or aral_tutor_has_student(student_id)))));
drop policy if exists phil_iri_assessments_update on public.phil_iri_assessments;
create policy phil_iri_assessments_update on public.phil_iri_assessments for update to authenticated
  using (phil_iri_assessment_writable(id))
  with check (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
              or (current_user_role() = 'tutor'
                  and (tutor_has_section(section_id) or aral_tutor_has_student(student_id))));
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
                       and (tutor_has_section(section_id) or aral_tutor_has_student(student_id)))));

-- ---------------------------------------------------------------------------
-- 7. Removed: learner's own tutor, section cap, per-tutor session settings
-- ---------------------------------------------------------------------------

alter table public.aral_enrollments drop column if exists tutor_id;
drop function if exists public.aral_check_section_cap(bigint, bigint, text);
drop table if exists public.aral_tutor_settings;
drop function if exists public.aral_tutor_settings_before_write();

-- ---------------------------------------------------------------------------
-- 8. Sync lists
-- ---------------------------------------------------------------------------

create or replace function basa_private.sync_key_column(p_table text) returns text
  language sql immutable
as $$
  select case p_table
    when 'crla_part1_standard' then 'assessment_id'
    when 'crla_part1_english' then 'assessment_id'
    when 'crla_part2_fluency' then 'assessment_id'
    else 'id' end;
$$;

-- Columns that may hold a device's negative id (a record in the same
-- upload). aral_enrollments' basis and suggestion ids are polymorphic (CRLA
-- or Phil-IRI); one device countdown makes every negative id unique, so the
-- map resolves them without the source. A new class comes before the roster
-- entries and sessions that point at it.
create or replace function basa_private.sync_ref_columns(p_table text) returns text[]
  language sql immutable
as $$
  select case p_table
    when 'crla_part1_standard' then array['assessment_id']
    when 'crla_part1_english' then array['assessment_id']
    when 'crla_part2_fluency' then array['assessment_id']
    when 'phil_iri_readings' then array['assessment_id']
    when 'phil_iri_rubric_scores' then array['assessment_id']
    when 'phil_iri_miscues' then array['reading_id']
    when 'phil_iri_answers' then array['reading_id']
    when 'aral_attendance' then array['session_id', 'enrollment_id']
    when 'aral_irip_weeks' then array['enrollment_id']
    when 'aral_checkins' then array['enrollment_id']
    when 'aral_checkin_answers' then array['checkin_id']
    when 'aral_readability_logs' then array['enrollment_id']
    when 'aral_enrollments' then array['basis_assessment_id', 'suggestion_assessment_id', 'class_id']
    when 'aral_sessions' then array['class_id']
    else array[]::text[] end;
$$;

-- Checks a package's shape before anything is written. Returns null when it
-- is fine, else the problem. Table and column names are checked against the
-- 18 synced tables and the catalog, so sync_apply never builds SQL from an
-- unchecked name.
create or replace function basa_private.sync_check_payload(p jsonb) returns text
  language plpgsql stable
  set search_path = public
as $$
declare
  synced constant text[] := array[
    'crla_assessments', 'crla_part1_standard', 'crla_part1_english', 'crla_part2_fluency',
    'phil_iri_gst_results', 'phil_iri_assessments', 'phil_iri_readings', 'phil_iri_miscues',
    'phil_iri_answers', 'phil_iri_rubric_scores',
    'aral_classes', 'aral_enrollments', 'aral_sessions', 'aral_attendance',
    'aral_irip_weeks', 'aral_checkins', 'aral_checkin_answers', 'aral_readability_logs'];
  r jsonb;
  n int := 0;
  t text;
  op text;
  kc text;
  bad text;
  followup boolean;
  seen text[] := array[]::text[];
  written text[] := array[]::text[];  -- 'table:key' of inserts and updates so far
begin
  if jsonb_typeof(p -> 'format') is distinct from 'number' or p ->> 'format' <> '1' then
    return 'unknown package format ' || coalesce(p ->> 'format', 'none');
  end if;
  if jsonb_typeof(p -> 'records') is distinct from 'array' then
    return 'the package has no record list';
  end if;
  for r in select value from jsonb_array_elements(p -> 'records') loop
    n := n + 1;
    if jsonb_typeof(r) <> 'object' then
      return format('record %s is not an object', n);
    end if;
    t := r ->> 'table';
    op := r ->> 'op';
    if t is null or not (t = any (synced)) then
      return format('record %s: table %s is not synced', n, coalesce(t, 'none'));
    end if;
    if op is null or op not in ('insert', 'update', 'delete') then
      return format('record %s (%s): unknown operation %s', n, t, coalesce(op, 'none'));
    end if;
    kc := basa_private.sync_key_column(t);
    if jsonb_typeof(r -> 'key') is distinct from 'object'
       or (select array_agg(k) from jsonb_object_keys(r -> 'key') k) is distinct from array[kc] then
      return format('record %s (%s): the key must be {%s}', n, t, kc);
    end if;
    -- Follow-up: an update without base_version of a record written earlier
    -- in this package.
    followup := op = 'update' and not (r ? 'base_version');
    if followup and not (t || ':' || (r -> 'key' ->> kc)) = any (written) then
      return format('record %s (%s): an update without base_version must follow the same record in this upload', n, t);
    end if;
    if kc = 'tutor_id' then
      if jsonb_typeof(r -> 'key' -> kc) <> 'string' then
        return format('record %s (%s): %s must be a text id', n, t, kc);
      end if;
    elsif jsonb_typeof(r -> 'key' -> kc) <> 'number'
          or (r -> 'key' ->> kc)::numeric <> trunc((r -> 'key' ->> kc)::numeric) then
      return format('record %s (%s): %s must be a whole number', n, t, kc);
    elsif kc = 'id' and op = 'insert' and (r -> 'key' ->> 'id')::numeric >= 0 then
      return format('record %s (%s): a new record needs a negative device id', n, t);
    elsif kc = 'id' and op <> 'insert' and not followup and (r -> 'key' ->> 'id')::numeric <= 0 then
      return format('record %s (%s): only uploaded records can be changed or deleted', n, t);
    end if;
    if kc = 'id' and op = 'insert' then
      if (r -> 'key' ->> 'id') = any (seen) then
        return format('record %s (%s): device id %s is used twice in this upload', n, t, r -> 'key' ->> 'id');
      end if;
      seen := seen || (r -> 'key' ->> 'id');
    end if;
    if op = 'delete' or (op = 'update' and not followup) then
      if jsonb_typeof(r -> 'base_version') is distinct from 'number'
         or (r ->> 'base_version')::numeric <> trunc((r ->> 'base_version')::numeric) then
        return format('record %s (%s): base_version is missing', n, t);
      end if;
    end if;
    if op in ('insert', 'update') then
      if jsonb_typeof(r -> 'row') is distinct from 'object' then
        return format('record %s (%s): the row is not an object', n, t);
      end if;
      select string_agg(k, ', ') into bad
        from jsonb_object_keys(r -> 'row') k
       where not exists (select 1 from pg_attribute a
                          where a.attrelid = format('public.%I', t)::regclass
                            and a.attname = k and a.attnum > 0 and not a.attisdropped);
      if bad is not null then
        return format('record %s (%s): unknown column(s) %s', n, t, bad);
      end if;
      if r -> 'row' ? kc and r -> 'row' -> kc <> r -> 'key' -> kc then
        return format('record %s (%s): the row''s %s differs from its key', n, t, kc);
      end if;
      written := written || (t || ':' || (r -> 'key' ->> kc));
    end if;
  end loop;
  return null;
end;
$$;

revoke all on function basa_private.sync_key_column(text) from public, anon;
revoke all on function basa_private.sync_ref_columns(text) from public, anon;
revoke all on function basa_private.sync_check_payload(jsonb) from public, anon;
grant execute on function basa_private.sync_key_column(text) to authenticated;
grant execute on function basa_private.sync_ref_columns(text) to authenticated;
grant execute on function basa_private.sync_check_payload(jsonb) to authenticated;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261023040000', 'aral_classes', true)
on conflict (id) do nothing;
