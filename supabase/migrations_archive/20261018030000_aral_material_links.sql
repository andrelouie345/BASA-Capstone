-- ARAL materials: file name + Google Drive link instead of stored files.
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
--
-- Owner (2026-10-18): BASA stores no material files in Supabase, so any school
-- can run its own Supabase at little or no cost. The reading coordinator
-- distributes the files (Google Drive, or the installation package); a
-- recommendation shows the document. Links can expire, so coordinators keep
-- them up to date themselves.
--
-- Changes:
--  1. aral_materials: drop the storage columns added for the cancelled file
--     storage (file_size, file_sha256, storage_path); keep file_name (the
--     document's file name, to find it in the shared folder or install
--     package); add link (optional http(s) URL, e.g. the Google Drive file).
--  2. aral_material_links: a school's own link for a material it can see
--     (e.g. a region-wide one the coordinator can't edit). Effective link for
--     a school = its own link, else the material's link.
--
-- RLS (raised with the table):
--  * aral_materials: unchanged (20261018020000).
--  * aral_material_links select: the superadmin, or rows of the caller's own
--    school (tutors included: they open the links).
--  * insert/update/delete: the superadmin, or an admin/coordinator for their
--    own school's rows, and only for a material that school can see
--    (region-wide or its own).
--  * updated_by / updated_at stamped (SECURITY DEFINER, search_path = public).

-- 1. aral_materials ---------------------------------------------------------

alter table public.aral_materials drop column if exists file_size;
alter table public.aral_materials drop column if exists file_sha256;
alter table public.aral_materials drop column if exists storage_path;
alter table public.aral_materials add column if not exists link text;
alter table public.aral_materials drop constraint if exists aral_materials_link;
alter table public.aral_materials
  add constraint aral_materials_link check (link is null or link ~* '^https?://[^[:space:]]+$');
alter table public.aral_materials drop constraint if exists aral_materials_file_name;
alter table public.aral_materials
  add constraint aral_materials_file_name check (file_name is null or length(btrim(file_name)) > 0);

-- 2. aral_material_links ----------------------------------------------------

create table if not exists public.aral_material_links (
  id           bigint generated always as identity primary key,
  material_id  bigint not null references public.aral_materials(id) on delete cascade,
  school_id    bigint not null references public.schools(id),
  link         text not null check (link ~* '^https?://[^[:space:]]+$'),
  updated_by   uuid references public.users(id),
  updated_at   timestamptz not null default now(),
  constraint aral_material_links_key unique (material_id, school_id)
);

create or replace function public.aral_material_links_stamp()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  new.updated_at := now();
  if auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists aral_material_links_stamp on public.aral_material_links;
create trigger aral_material_links_stamp
  before insert or update on public.aral_material_links
  for each row execute function public.aral_material_links_stamp();

-- Can [p_school_id] see the material (region-wide or its own)?
create or replace function public.aral_material_visible_to_school(p_material_id bigint, p_school_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.aral_materials m
    where m.id = p_material_id and (m.school_id is null or m.school_id = p_school_id)
  );
$$;

alter table public.aral_material_links enable row level security;
revoke all on public.aral_material_links from anon;

drop policy if exists aral_material_links_select on public.aral_material_links;
create policy aral_material_links_select on public.aral_material_links
  for select to authenticated
  using (is_superadmin() or school_id = current_user_school_id());

drop policy if exists aral_material_links_write on public.aral_material_links;
create policy aral_material_links_write on public.aral_material_links
  for all to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id()))
  with check (
    aral_material_visible_to_school(material_id, school_id)
    and (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())));
