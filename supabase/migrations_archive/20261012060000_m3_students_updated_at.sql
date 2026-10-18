-- M3: keep students.updated_at current.
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
--
-- students.updated_at defaults to now() on insert but nothing touched it on
-- update (no trigger, and the app doesn't send it), so every row still showed
-- its creation time. The server now stamps it on every update; clients never
-- need to send it. No RLS change: trigger only.

begin;

create or replace function public.set_updated_at()
 returns trigger language plpgsql set search_path to 'public'
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists students_set_updated_at on public.students;
create trigger students_set_updated_at
  before update on public.students
  for each row execute function public.set_updated_at();

commit;
