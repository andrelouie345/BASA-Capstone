-- ARAL classes: a duplicate class name is refused with a readable message.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261024020000.
-- App update required on all devices: no (the same names are refused as
-- before; only the message changes).
--
-- Why (command pass r6, finding F15): two coordinators may create classes
-- with the same name offline. The second upload was refused by the unique
-- index aral_classes_name_key, and sync_apply showed the raw "duplicate key
-- value violates unique constraint" text. The trigger now checks the name
-- first and names the class, like the 15-learner cap does. The index stays
-- as the backstop.
--
-- Rule (unchanged): a class name is unique per school and school year,
-- ignoring case and surrounding spaces.

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
  if tg_op = 'INSERT' or lower(btrim(new.class_name)) is distinct from lower(btrim(old.class_name)) then
    if exists (select 1 from public.aral_classes
               where school_id = new.school_id and school_year = new.school_year
                 and lower(btrim(class_name)) = lower(btrim(new.class_name))
                 and id is distinct from new.id) then
      raise exception 'an ARAL class named "%" already exists in this school for %',
        btrim(new.class_name), new.school_year;
    end if;
  end if;
  if new.tutor_id is not null and (tg_op = 'INSERT' or new.tutor_id is distinct from old.tutor_id)
     and not exists (select 1 from public.users
                     where id = new.tutor_id and role = 'tutor' and is_active and school_id = new.school_id) then
    raise exception 'the ARAL class tutor must be an active tutor of the class''s school';
  end if;
  return new;
end;
$$;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261024030000', 'aral_class_name_message', false)
on conflict (id) do nothing;
