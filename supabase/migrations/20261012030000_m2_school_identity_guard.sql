-- M2: only the superadmin may change a school's DepEd school ID or region.
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
--
-- schools_update_scoped lets a school-bound admin/coordinator update their own
-- school row, which included school_id (the DepEd code the SF1 importer
-- matches on) and region_id (verified against the dev project on 2026-10-12).
-- Name and division stay editable by them.
--
-- A column grant can't do this: superadmin and school admins share the
-- `authenticated` role. The trigger checks is_superadmin() instead.
-- Sessions with no auth user (SQL Editor, service role) are not restricted.

begin;

create or replace function public.guard_school_identity()
 returns trigger language plpgsql set search_path to 'public'
as $$
begin
  if auth.uid() is not null
     and (new.school_id is distinct from old.school_id
          or new.region_id is distinct from old.region_id)
     and not public.is_superadmin() then
    raise exception 'Only the superadmin can change a school''s DepEd school ID or region.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists schools_guard_identity on public.schools;
create trigger schools_guard_identity
  before update on public.schools
  for each row execute function public.guard_school_identity();

commit;
