-- ARAL-Reading roster (piece A1a): aral_enrollments, one row per learner in
-- ARAL for a school year. Idempotent: safe to run in the Supabase SQL Editor
-- more than once. Needs 20261014010000_phil_iri_assessments.sql
-- (phil_iri_section_grade, phil_iri_deny).
--
-- Owner decisions (2026-10-15):
--  * Grades 1-10. Key stage KS1/KS2/KS3; KS2 and KS3 have a track (basic /
--    plus), KS1 has none.
--  * BASA proposes the roster and the track from CRLA / Phil-IRI results and the
--    coordinator confirms or changes it; the suggestion is kept beside the
--    choice. One enrollment per learner per school year. Leaving ARAL is a
--    status change (exited + date + reason); exits are only suggested.
--  * Offline-first like the assessment sessions: devices write locally; this
--    table and its rules wait for the sync.
--
-- Scope:
--  * Write (insert/update/delete): the superadmin, or an admin/coordinator of
--    the learner's school. Tutors don't change the roster.
--  * Insert: the section belongs to school_id, is Grade 1-10, and the learner
--    has an ACTIVE enrollment in it for that school_year. Update: the same, but
--    the enrollment may have ended (to record a transfer-out exit).
--  * Read: superadmin; admin/coordinator of the school; a tutor who is the
--    learner's ARAL tutor or is assigned to the learner's section.
--  * tutor_id, when set, is an active user with role tutor in the same school.
--  * created_by / created_at / updated_at are stamped here; learner, school,
--    year, basis and suggestion never change after insert. A new row starts
--    active.
--
-- RLS: enabled below with select/insert/update/delete policies; anon revoked.

create table if not exists public.aral_enrollments (
  id                   bigint generated always as identity primary key,
  student_id           bigint not null references public.students(id),
  school_id            bigint not null references public.schools(id),
  section_id           bigint not null references public.sections(id),
  school_year          text not null,
  key_stage            text not null check (key_stage in ('ks1', 'ks2', 'ks3')),
  track                text check (track in ('basic', 'plus')),
  tutor_id             uuid references public.users(id),
  status               text not null default 'active' check (status in ('active', 'exited')),
  entered_on           date not null default current_date,
  exited_on            date,
  exit_reason          text check (exit_reason in ('grade_level_ready', 'transferred_out', 'dropped_out', 'other')),
  basis_source         text not null check (basis_source in ('crla', 'phil_iri', 'manual')),
  basis_round          text check (basis_round in ('bosy', 'mosy', 'mosy1', 'mosy2', 'mosy3', 'eosy')),
  basis_level          text,
  basis_assessment_id  bigint,  -- crla_assessments or phil_iri_assessments (by basis_source); no FK
  suggested_key_stage  text check (suggested_key_stage in ('ks1', 'ks2', 'ks3')),
  suggested_track      text check (suggested_track in ('basic', 'plus')),
  notes                text,
  created_by           uuid references public.users(id),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint aral_enrollments_one_per_year unique (student_id, school_year),
  constraint aral_enrollments_school_year_format check (
    case when school_year ~ '^\d{4}-\d{4}$'
         then right(school_year, 4)::int = left(school_year, 4)::int + 1
         else false end),
  constraint aral_enrollments_track check ((key_stage = 'ks1') = (track is null)),
  constraint aral_enrollments_exit check (
    (status = 'exited') = (exited_on is not null and exit_reason is not null)),
  constraint aral_enrollments_exit_after_entry check (exited_on is null or exited_on >= entered_on),
  constraint aral_enrollments_basis check (basis_source = 'manual' or basis_level is not null)
);
create index if not exists aral_enrollments_section on public.aral_enrollments (section_id, school_year);
create index if not exists aral_enrollments_school on public.aral_enrollments (school_id, school_year);
create index if not exists aral_enrollments_tutor on public.aral_enrollments (tutor_id, school_year);

-- tutor_id must be an active tutor of the school. Checked only for callers who
-- may write in that school, so the message reveals nothing to others (RLS
-- rejects their row anyway).
create or replace function public.aral_check_tutor(p_tutor_id uuid, p_school_id bigint)
 returns void language plpgsql stable security definer set search_path to 'public'
as $$
begin
  if p_tutor_id is null or auth.uid() is null then
    return;
  end if;
  if not (is_superadmin() or p_school_id = current_user_school_id()) then
    return;
  end if;
  if not exists (
    select 1 from public.users
    where id = p_tutor_id and role = 'tutor' and is_active and school_id = p_school_id
  ) then
    raise exception 'the ARAL tutor must be an active tutor of the learner''s school';
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
  perform aral_check_tutor(new.tutor_id, new.school_id);
  return new;
end;
$$;

create or replace function public.aral_enrollments_before_update()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if auth.uid() is null then
    return new; -- SQL Editor maintenance
  end if;
  if (new.student_id, new.school_id, new.school_year, new.basis_source, new.basis_round, new.basis_level,
      new.basis_assessment_id, new.suggested_key_stage, new.suggested_track, new.created_by, new.created_at)
     is distinct from
     (old.student_id, old.school_id, old.school_year, old.basis_source, old.basis_round, old.basis_level,
      old.basis_assessment_id, old.suggested_key_stage, old.suggested_track, old.created_by, old.created_at) then
    raise exception 'an ARAL enrollment keeps its learner, school, year and basis; only the placement, tutor, status and notes change';
  end if;
  if new.tutor_id is distinct from old.tutor_id then
    perform aral_check_tutor(new.tutor_id, new.school_id);
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists aral_enrollments_before_insert on public.aral_enrollments;
create trigger aral_enrollments_before_insert
  before insert on public.aral_enrollments
  for each row execute function public.aral_enrollments_before_insert();
drop trigger if exists aral_enrollments_before_update on public.aral_enrollments;
create trigger aral_enrollments_before_update
  before update on public.aral_enrollments
  for each row execute function public.aral_enrollments_before_update();

drop policy if exists aral_enrollments_select on public.aral_enrollments;
create policy aral_enrollments_select on public.aral_enrollments
  for select to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
    or (current_user_role() = 'tutor' and (tutor_id = auth.uid() or tutor_has_section(section_id)))
  );

-- In scope: section of that school, Grade 1-10, learner actively enrolled.
drop policy if exists aral_enrollments_insert on public.aral_enrollments;
create policy aral_enrollments_insert on public.aral_enrollments
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.sections s
      join public.enrollments e on e.section_id = s.id
      where s.id = aral_enrollments.section_id
        and s.school_id = aral_enrollments.school_id
        and s.grade_level in ('1', '2', '3', '4', '5', '6', '7', '8', '9', '10')
        and e.student_id = aral_enrollments.student_id
        and e.school_year = aral_enrollments.school_year
        and e.status = 'active'
    )
    and (
      is_superadmin()
      or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
    )
  );

-- Update: same scope, but the learner's school enrollment may no longer be
-- active (e.g. marking a transferred-out learner as exited).
drop policy if exists aral_enrollments_update on public.aral_enrollments;
create policy aral_enrollments_update on public.aral_enrollments
  for update to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
  )
  with check (
    exists (
      select 1
      from public.sections s
      join public.enrollments e on e.section_id = s.id
      where s.id = aral_enrollments.section_id
        and s.school_id = aral_enrollments.school_id
        and s.grade_level in ('1', '2', '3', '4', '5', '6', '7', '8', '9', '10')
        and e.student_id = aral_enrollments.student_id
        and e.school_year = aral_enrollments.school_year
    )
    and (
      is_superadmin()
      or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
    )
  );

drop policy if exists aral_enrollments_delete on public.aral_enrollments;
create policy aral_enrollments_delete on public.aral_enrollments
  for delete to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
  );

alter table public.aral_enrollments enable row level security;
revoke all on public.aral_enrollments from anon;
