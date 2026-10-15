-- ARAL-Reading roster rules revised with the reading coordinator (piece A1c).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Needs
-- 20261015050000_aral_enrollments.sql.
--
--  * New program 'foundational' for non-readers (reading level 0): SHARP or
--    the school's foundational literacy program. Like KS1 it has no track.
--    Allowed in key_stage and suggested_key_stage.
--  * A section has at most 15 ACTIVE ARAL learners per school year. Checked
--    when a row becomes active in a section: insert, reactivation, or a move
--    to another section. Rows already over 15 (none expected) are not touched.
--    Serialized per section and year with a transaction-scoped advisory lock,
--    so two coordinators can't both take the 15th place.
--
-- Not enforceable here: "grade-level-ready exits come only from results" (the
-- app writes those exits too, through the same table); the ViewModel refuses
-- them by hand.
--
-- RLS: unchanged (select/insert/update/delete policies of
-- 20261015050000_aral_enrollments.sql). The trigger functions stay SECURITY
-- DEFINER with search_path public, so the count sees every row of the section,
-- including ones the caller can't read.

-- Replace the key-stage and track checks (inline checks got generated names;
-- find them by definition).
do $$
declare
  c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.aral_enrollments'::regclass and contype = 'c'
      and (pg_get_constraintdef(oid) like '%key_stage%')
  loop
    execute format('alter table public.aral_enrollments drop constraint %I', c.conname);
  end loop;
end;
$$;

alter table public.aral_enrollments
  add constraint aral_enrollments_key_stage_check
    check (key_stage in ('foundational', 'ks1', 'ks2', 'ks3')),
  add constraint aral_enrollments_suggested_key_stage_check
    check (suggested_key_stage in ('foundational', 'ks1', 'ks2', 'ks3')),
  add constraint aral_enrollments_track
    check ((key_stage in ('foundational', 'ks1')) = (track is null));

-- At most 15 active learners per section and year.
create or replace function public.aral_check_section_cap(p_id bigint, p_section_id bigint, p_school_year text)
 returns void language plpgsql security definer set search_path to 'public'
as $$
begin
  perform pg_advisory_xact_lock(hashtext('aral_section_cap:' || p_section_id::text || ':' || p_school_year));
  if (select count(*) from public.aral_enrollments
      where section_id = p_section_id and school_year = p_school_year and status = 'active'
        and id is distinct from p_id) >= 15 then
    raise exception 'an ARAL section has at most 15 active learners';
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
  if new.status = 'active' then
    perform aral_check_section_cap(null, new.section_id, new.school_year);
  end if;
  return new;
end;
$$;

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

-- Triggers already point at these functions (20261015050000); nothing to re-create.
-- The cap check is only for the triggers (which run as the owner): nobody
-- calls it directly, so it can't be used to probe other schools' sections.
revoke all on function public.aral_check_section_cap(bigint, bigint, text) from public, anon, authenticated;
