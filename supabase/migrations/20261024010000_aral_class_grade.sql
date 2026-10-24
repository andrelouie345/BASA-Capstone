-- ARAL classes: a home grade, and one program or mixed programs.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261023040000.
-- App update required on all devices: yes (aral_classes.grade_band is removed
-- and grade_level is required: an older app can't read or write classes).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Why (owner 2026-10-24, from the reading coordinator): classes are formed by
-- grade level first, then by program; when there are not enough learners, a
-- learner of another grade joins the class that fits them, and a class may
-- mix programs. The fixed grade band (1-3 / 4-6 / 7-10) of 20261023040000
-- does not match that.
--
-- Rules:
--   * aral_classes.grade_level (1-10, required): the class's home grade.
--     Classes from before get the lowest grade of their band (1-3 -> 1,
--     4-6 -> 4, 7-10 -> 7). grade_band is dropped.
--   * aral_classes.program: one program, or null = mixed programs (the
--     coordinator's choice per class).
--   * Placement (aral_check_class_placement): same school and year; the
--     learner's program when the class has one; fewer than 15 other active
--     learners. Grades are NOT checked here: a learner of another grade joins
--     only when the coordinator confirms it, which the app asks for; and a
--     placed learner whose grade changes stays (the app flags it). The band
--     check on a section change is removed with the band.
--   * A class with learners keeps its grade and program (one program <-> mixed
--     included).
--
-- RLS: unchanged (no new table, view or policy; the functions keep their
-- SECURITY DEFINER, search_path public and revoked execute).

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------

alter table public.aral_classes add column if not exists grade_level integer;

do $$
begin
  if exists (select 1 from pg_attribute where attrelid = 'public.aral_classes'::regclass
             and attname = 'grade_band' and not attisdropped) then
    execute 'update public.aral_classes set grade_level = split_part(grade_band, ''-'', 1)::integer
             where grade_level is null';
  end if;
end $$;

alter table public.aral_classes alter column grade_level set not null;
alter table public.aral_classes drop constraint if exists aral_classes_grade_level_check;
alter table public.aral_classes add constraint aral_classes_grade_level_check check (grade_level between 1 and 10);
-- null = mixed programs; aral_classes_program_check still names the six.
alter table public.aral_classes alter column program drop not null;

-- ---------------------------------------------------------------------------
-- 2. Rules
-- ---------------------------------------------------------------------------

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
    if (new.grade_level, new.program) is distinct from (old.grade_level, old.program)
       and exists (select 1 from public.aral_enrollments where class_id = new.id) then
      raise exception 'an ARAL class with learners keeps its grade and program';
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
  if c.program is not null and c.program is distinct from p_key_stage || coalesce('_' || p_track, '') then
    raise exception 'the learner''s program does not match the ARAL class';
  end if;
  if (select count(*) from public.aral_enrollments
      where class_id = p_class_id and status = 'active' and id is distinct from p_id) >= 15 then
    raise exception 'an ARAL class has at most 15 active learners';
  end if;
end;
$$;

create or replace function public.aral_enrollments_before_update()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  -- Placement rules hold for SQL Editor maintenance too.
  if new.class_id is not null and new.status = 'active'
     and (new.class_id is distinct from old.class_id or old.status <> 'active'
          or (new.school_id, new.school_year) is distinct from (old.school_id, old.school_year)) then
    perform aral_check_class_placement(new.id, new.class_id, new.student_id, new.section_id, new.school_id,
                                       new.school_year, new.key_stage, new.track);
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
-- 3. The band goes
-- ---------------------------------------------------------------------------

drop function if exists public.aral_class_band_ok(bigint, bigint);
alter table public.aral_classes drop column if exists grade_band; -- its check goes with it

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261024010000', 'aral_class_grade', true)
on conflict (id) do nothing;
