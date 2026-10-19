-- Summer Remediation Program (SRP) classes (piece SRP part 2). Idempotent: safe
-- to run in the Supabase SQL Editor more than once. Newer than the
-- 20261018040000 baseline: a new deployment runs it after it.
--
-- Reading coordinator's workbook, sheet "SRP Masterlist" (owner 2026-10-19):
-- the learners recommended for SRP are grouped by the grade level they were
-- assessed at (0 = Non-Reader), in classes of at most 15 (7-3A, 7-3B, ...;
-- non-readers 7A-SHARP), each with a room, a schedule and a tutor. The app
-- builds the classes; the coordinator sets tutor, room and schedule and moves
-- learners. Written online and mirrored to the device (like the materials).
--
-- Rules (triggers):
--  * srp_classes: the tutor is an active user with the tutor role of the same
--    school (or none); a class keeps its school and school year; stamps.
--  * srp_class_members: the learner has an enrollment in a section of the
--    class's school for that school year; school_year is copied from the class
--    so a learner is in at most one SRP class per school year.
--
-- RLS (raised with the tables):
--  * srp_classes select: superadmin; admin/coordinator of the school; the
--    class's tutor. insert/update/delete: superadmin; admin/coordinator of the
--    school.
--  * srp_class_members: the same, through the class (srp_class_readable /
--    srp_class_writable).
--  * anon: nothing. SECURITY DEFINER functions set search_path = public.

create table if not exists public.srp_classes (
  id              bigint generated always as identity primary key,
  school_id       bigint not null references public.schools(id) on delete cascade,
  school_year     text not null check (school_year ~ '^\d{4}-\d{4}$'
                    and right(school_year, 4)::integer = left(school_year, 4)::integer + 1),
  assessed_grade  integer not null check (assessed_grade between 0 and 12),
  class_name      text not null check (length(btrim(class_name)) > 0),
  room            text,
  schedule        text,
  tutor_id        uuid references public.users(id) on delete set null,
  created_by      uuid references public.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index if not exists srp_classes_name_key on public.srp_classes (school_id, school_year, lower(class_name));
create index if not exists srp_classes_tutor on public.srp_classes (tutor_id);

create table if not exists public.srp_class_members (
  id           bigint generated always as identity primary key,
  class_id     bigint not null references public.srp_classes(id) on delete cascade,
  student_id   bigint not null references public.students(id) on delete cascade,
  school_year  text not null,
  created_at   timestamptz not null default now(),
  constraint srp_class_members_one_class unique (student_id, school_year)
);
create index if not exists srp_class_members_class on public.srp_class_members (class_id);

create or replace function public.srp_classes_before_write()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if tg_op = 'UPDATE' then
    if (new.school_id, new.school_year, new.created_by, new.created_at) is distinct from
       (old.school_id, old.school_year, old.created_by, old.created_at) then
      raise exception 'an SRP class keeps its school and school year';
    end if;
  else
    if auth.uid() is not null then
      new.created_by := auth.uid();
    end if;
    new.created_at := now();
  end if;
  if new.tutor_id is not null and not exists (
    select 1 from public.users
    where id = new.tutor_id and role = 'tutor' and is_active and school_id = new.school_id
  ) then
    raise exception 'the SRP tutor must be an active tutor of the same school';
  end if;
  new.class_name := btrim(new.class_name);
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists srp_classes_before_write on public.srp_classes;
create trigger srp_classes_before_write
  before insert or update on public.srp_classes
  for each row execute function public.srp_classes_before_write();

create or replace function public.srp_class_members_before_write()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  c record;
begin
  select school_id, school_year into c from public.srp_classes where id = new.class_id;
  if tg_op = 'UPDATE' and new.student_id is distinct from old.student_id then
    raise exception 'an SRP class member keeps its learner; move them by changing the class';
  end if;
  if not exists (
    select 1 from public.enrollments e
    join public.sections s on s.id = e.section_id
    where e.student_id = new.student_id and e.school_year = c.school_year and s.school_id = c.school_id
  ) then
    raise exception 'the learner has no enrollment in that school for that school year';
  end if;
  new.school_year := c.school_year;
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

drop trigger if exists srp_class_members_before_write on public.srp_class_members;
create trigger srp_class_members_before_write
  before insert or update on public.srp_class_members
  for each row execute function public.srp_class_members_before_write();

-- The caller may manage SRP classes of the school.
create or replace function public.srp_school_writable(p_school_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select is_superadmin()
      or (current_user_role() in ('admin', 'coordinator') and p_school_id = current_user_school_id());
$$;

create or replace function public.srp_class_readable(p_class_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.srp_classes c
    where c.id = p_class_id
      and (srp_school_writable(c.school_id)
           or (current_user_role() = 'tutor' and c.tutor_id = auth.uid()))
  );
$$;

create or replace function public.srp_class_writable(p_class_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (select 1 from public.srp_classes c where c.id = p_class_id and srp_school_writable(c.school_id));
$$;

alter table public.srp_classes enable row level security;
alter table public.srp_class_members enable row level security;
revoke all on public.srp_classes from anon;
revoke all on public.srp_class_members from anon;

drop policy if exists srp_classes_select on public.srp_classes;
create policy srp_classes_select on public.srp_classes
  for select to authenticated
  using (srp_school_writable(school_id) or (current_user_role() = 'tutor' and tutor_id = auth.uid()));
drop policy if exists srp_classes_insert on public.srp_classes;
create policy srp_classes_insert on public.srp_classes
  for insert to authenticated with check (srp_school_writable(school_id));
drop policy if exists srp_classes_update on public.srp_classes;
create policy srp_classes_update on public.srp_classes
  for update to authenticated using (srp_school_writable(school_id)) with check (srp_school_writable(school_id));
drop policy if exists srp_classes_delete on public.srp_classes;
create policy srp_classes_delete on public.srp_classes
  for delete to authenticated using (srp_school_writable(school_id));

drop policy if exists srp_class_members_select on public.srp_class_members;
create policy srp_class_members_select on public.srp_class_members
  for select to authenticated using (srp_class_readable(class_id));
drop policy if exists srp_class_members_insert on public.srp_class_members;
create policy srp_class_members_insert on public.srp_class_members
  for insert to authenticated with check (srp_class_writable(class_id));
drop policy if exists srp_class_members_update on public.srp_class_members;
create policy srp_class_members_update on public.srp_class_members
  for update to authenticated using (srp_class_writable(class_id)) with check (srp_class_writable(class_id));
drop policy if exists srp_class_members_delete on public.srp_class_members;
create policy srp_class_members_delete on public.srp_class_members
  for delete to authenticated using (srp_class_writable(class_id));
