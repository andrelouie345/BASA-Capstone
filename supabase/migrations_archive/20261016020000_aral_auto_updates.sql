-- ARAL-Reading: automatic program updates and grade-level-ready exits from new
-- results (piece A4). Idempotent: safe to run in the Supabase SQL Editor more
-- than once. Needs 20261015070000_aral_foundational_section_cap.sql.
--
-- Reading coordinator (2026-10-15): a new result (MOSY, EOSY) updates the
-- learner's program automatically (like the SRA Reading Laboratory), and a
-- learner who reaches grade level exits ARAL automatically; the coordinator
-- does not override the data. Owner (2026-10-16): the app applies results
-- when an admin/coordinator opens the roster (or runs the update).
--
--  * suggested_key_stage / suggested_track become BASA's CURRENT suggestion
--    (they were fixed at entry). The program changes only when a new result
--    suggests something different from the stored suggestion, so a
--    coordinator's own change stays until the data says otherwise.
--  * New columns record where the current suggestion came from:
--    suggestion_round, suggestion_level, suggestion_assessment_id (CRLA or
--    Phil-IRI by basis_source; no FK) and suggested_on. Null = the entry basis.
--  * The entry basis (basis_*) still never changes.
--
-- RLS: unchanged (20261015050000): only the superadmin and the school's
-- admins/coordinators write the roster, so tutors' devices don't apply
-- updates. The trigger function stays SECURITY DEFINER with search_path public.

alter table public.aral_enrollments
  add column if not exists suggestion_round text
    check (suggestion_round in ('bosy', 'mosy', 'mosy1', 'mosy2', 'mosy3', 'eosy')),
  add column if not exists suggestion_level text,
  add column if not exists suggestion_assessment_id bigint,
  add column if not exists suggested_on date;

-- Same as 20261015070000, minus the suggestion in the fixed columns.
create or replace function public.aral_enrollments_before_update()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  -- The cap holds for SQL Editor maintenance too.
  if new.status = 'active' and (old.status <> 'active' or new.section_id is distinct from old.section_id
                                or new.school_year is distinct from old.school_year) then
    perform aral_check_section_cap(new.id, new.section_id, new.school_year);
  end if;
  if auth.uid() is null then
    return new; -- SQL Editor maintenance
  end if;
  if (new.student_id, new.school_id, new.school_year, new.basis_source, new.basis_round, new.basis_level,
      new.basis_assessment_id, new.created_by, new.created_at)
     is distinct from
     (old.student_id, old.school_id, old.school_year, old.basis_source, old.basis_round, old.basis_level,
      old.basis_assessment_id, old.created_by, old.created_at) then
    raise exception 'an ARAL enrollment keeps its learner, school, year and basis; only the placement, tutor, status and notes change';
  end if;
  if new.tutor_id is distinct from old.tutor_id then
    perform aral_check_tutor(new.tutor_id, new.school_id);
  end if;
  new.updated_at := now();
  return new;
end;
$$;
-- The trigger already points at this function (20261015050000).
