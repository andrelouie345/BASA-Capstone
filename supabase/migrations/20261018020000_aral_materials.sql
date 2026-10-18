-- ARAL: learning-material catalog (piece R3a). Idempotent: safe to run in the
-- Supabase SQL Editor more than once.
--
-- Reading coordinator (2026-10-18): material recommendations exist only in
-- ARAL. A learner gets the materials of their ARAL program (the placement
-- bands of aralPhilIriPlacement: Foundational/SHARP, KS1, KS2 Basic/Plus,
-- KS3 Basic/Plus). The ARAL KS1-KS3 materials are for high-school learners
-- (Grades 7-10) only; KS3 can never go below Grade 7. Materials must work
-- offline: the file itself is added in piece R3b (Supabase Storage); the
-- file_* / storage_path columns stay empty until then.
--
-- Ownership like phil_iri_collections: school_id null = region-wide (the
-- superadmin manages it); a school's own materials are managed by its
-- admin/coordinator and are invisible to other schools.
--
-- RLS (raised with the table):
--  * select: everyone signed in sees region-wide rows and their own school's
--    (tutors included: they read recommendations); the superadmin sees all.
--  * insert/update/delete: the superadmin any row; an admin/coordinator only
--    rows of their own school (never region-wide rows); tutors none.
--  * created_by / updated_at are stamped here (SECURITY DEFINER, search_path).

create table if not exists public.aral_materials (
  id            bigint generated always as identity primary key,
  school_id     bigint references public.schools(id),     -- null = region-wide
  title         text not null check (length(btrim(title)) > 0),
  description   text,
  key_stage     text not null check (key_stage in ('foundational', 'ks1', 'ks2', 'ks3')),
  track         text check (track in ('basic', 'plus')),  -- null = any track (KS2/KS3) / none
  kind          text not null default 'learner' check (kind in ('learner', 'tutor', 'supplementary')),
  language      text not null default 'English' check (language in ('English', 'Filipino')),
  min_grade     integer not null default 7,
  max_grade     integer not null default 10,
  file_name     text,
  file_size     bigint check (file_size >= 0),
  file_sha256   text check (file_sha256 ~ '^[0-9a-f]{64}$'),
  storage_path  text,
  is_active     boolean not null default true,
  created_by    uuid references public.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint aral_materials_track check (key_stage in ('ks2', 'ks3') or track is null),
  constraint aral_materials_grades check (min_grade between 1 and 12 and max_grade between min_grade and 12),
  constraint aral_materials_ks3_high_school check (key_stage <> 'ks3' or min_grade >= 7)
);
create unique index if not exists aral_materials_title_key
  on public.aral_materials (coalesce(school_id, 0), lower(title));
create index if not exists aral_materials_program on public.aral_materials (key_stage, track);

create or replace function public.aral_materials_stamp()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.created_at := now();
    if auth.uid() is not null then
      new.created_by := auth.uid();
    end if;
  else
    new.created_by := old.created_by;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

drop trigger if exists aral_materials_stamp on public.aral_materials;
create trigger aral_materials_stamp
  before insert or update on public.aral_materials
  for each row execute function public.aral_materials_stamp();

alter table public.aral_materials enable row level security;
revoke all on public.aral_materials from anon;

drop policy if exists aral_materials_select on public.aral_materials;
create policy aral_materials_select on public.aral_materials
  for select to authenticated
  using (is_superadmin() or school_id is null or school_id = current_user_school_id());

drop policy if exists aral_materials_insert on public.aral_materials;
create policy aral_materials_insert on public.aral_materials
  for insert to authenticated
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id is not null and school_id = current_user_school_id()));

drop policy if exists aral_materials_update on public.aral_materials;
create policy aral_materials_update on public.aral_materials
  for update to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id is not null and school_id = current_user_school_id()))
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id is not null and school_id = current_user_school_id()));

drop policy if exists aral_materials_delete on public.aral_materials;
create policy aral_materials_delete on public.aral_materials
  for delete to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id is not null and school_id = current_user_school_id()));
