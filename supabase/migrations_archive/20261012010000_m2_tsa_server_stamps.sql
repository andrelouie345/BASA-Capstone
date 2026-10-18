-- M2: tutor_section_assignments provenance.
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
--
-- Fixes, each verified against the dev project on 2026-10-12:
--  1. assigned_by / assigned_at were taken from the client, so an admin could
--     record an assignment as made by someone else, at any time (the console
--     also sent naive local time, which timestamptz stored 8 hours off).
--     The server now stamps both on insert and keeps them on update.
--  2. An inactive tutor could still be assigned to a section.
--
-- The function stays SECURITY INVOKER on purpose: its lookups run under the
-- caller's RLS, so the error text never reveals another school's users or
-- sections. The existing trigger (BEFORE INSERT OR UPDATE) keeps pointing at it.

begin;

create or replace function public.validate_tutor_section_assignment()
 returns trigger language plpgsql set search_path to 'public'
as $$
declare
  v_tutor_role text;
  v_tutor_school bigint;
  v_tutor_active boolean;
  v_section_school bigint;
begin
  if tg_op = 'INSERT' then
    new.assigned_by := auth.uid();
    new.assigned_at := now();
  else
    new.assigned_by := old.assigned_by;
    new.assigned_at := old.assigned_at;
  end if;

  select role, school_id, is_active into v_tutor_role, v_tutor_school, v_tutor_active
  from public.users where id = new.tutor_id;

  if v_tutor_role is distinct from 'tutor' then
    raise exception 'tutor_id % is not a tutor visible to you', new.tutor_id;
  end if;

  if not v_tutor_active then
    raise exception 'tutor % is inactive', new.tutor_id;
  end if;

  select school_id into v_section_school
  from public.sections where id = new.section_id;

  if v_section_school is null or v_tutor_school is distinct from v_section_school then
    raise exception 'tutor % and section % are not in the same school (or the section is not visible to you)',
      new.tutor_id, new.section_id;
  end if;

  return new;
end;
$$;

commit;
