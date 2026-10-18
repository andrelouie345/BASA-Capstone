-- Phil-IRI content and settings (piece 8a): material collections, rubric
-- criteria, passages, comprehension questions, and the adjustable thresholds.
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
--
-- Ownership (owner decisions 2026-10-14):
--  * A collection is region-wide (school_id null, superadmin only) or owned by
--    one school (its admin/coordinator manage it). School-owned collections are
--    invisible to other schools (unpublished research stays in its school).
--    Only region-wide collections can be prescribed; promoting a school
--    collection to region-wide (school_id -> null) is superadmin-only.
--  * Rubric criteria, passages and questions follow their collection.
--  * Thresholds: one region-wide row (school_id null, superadmin) and at most
--    one override row per school (its admin/coordinator). Everyone in the
--    school, tutors included, can read the values that apply to them.
--  * Tutors read; they never write content or settings.
-- Not here yet (piece 8b): assessment tables, and locking a passage's text
-- once readings point at it (miscue word positions depend on it).

begin;

-- Helpers -------------------------------------------------------------------

-- Stamps created_by with the caller (left as sent when there is no JWT,
-- e.g. the SQL Editor or a seed script).
create or replace function public.phil_iri_stamp_created_by()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  return new;
end;
$$;

-- Collections ---------------------------------------------------------------

create table if not exists public.phil_iri_collections (
  id                bigint generated always as identity primary key,
  school_id         bigint references public.schools(id),
  name              text not null check (length(trim(name)) > 0),
  description       text,
  is_prescribed     boolean not null default false,
  is_grade_leveled  boolean not null default true,
  has_comprehension boolean not null default true,
  reading_order     jsonb check (reading_order is null or jsonb_typeof(reading_order) = 'array'),
  is_active         boolean not null default true,
  created_by        uuid references public.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint phil_iri_collections_prescribed_region check (not is_prescribed or school_id is null)
);
create unique index if not exists phil_iri_collections_name_key
  on public.phil_iri_collections (coalesce(school_id, 0), lower(name));

-- Can the caller see / change this collection? Used by the child tables.
create or replace function public.phil_iri_collection_readable(p_collection_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.phil_iri_collections c
    where c.id = p_collection_id
      and (is_superadmin()
           or c.school_id is null
           or c.school_id = current_user_school_id())
  );
$$;

create or replace function public.phil_iri_collection_writable(p_collection_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.phil_iri_collections c
    where c.id = p_collection_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator')
               and c.school_id is not null
               and c.school_id = current_user_school_id()))
  );
$$;

drop policy if exists phil_iri_collections_select on public.phil_iri_collections;
create policy phil_iri_collections_select on public.phil_iri_collections
  for select to authenticated
  using (is_superadmin() or school_id is null or school_id = current_user_school_id());

drop policy if exists phil_iri_collections_insert on public.phil_iri_collections;
create policy phil_iri_collections_insert on public.phil_iri_collections
  for insert to authenticated
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id = current_user_school_id()
        and not is_prescribed)
  );

drop policy if exists phil_iri_collections_update on public.phil_iri_collections;
create policy phil_iri_collections_update on public.phil_iri_collections
  for update to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
  )
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id = current_user_school_id()
        and not is_prescribed)
  );

drop policy if exists phil_iri_collections_delete on public.phil_iri_collections;
create policy phil_iri_collections_delete on public.phil_iri_collections
  for delete to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
  );

drop trigger if exists phil_iri_collections_created_by on public.phil_iri_collections;
create trigger phil_iri_collections_created_by
  before insert on public.phil_iri_collections
  for each row execute function public.phil_iri_stamp_created_by();
drop trigger if exists phil_iri_collections_updated_at on public.phil_iri_collections;
create trigger phil_iri_collections_updated_at
  before update on public.phil_iri_collections
  for each row execute function public.set_updated_at();

-- Rubric criteria -----------------------------------------------------------

create table if not exists public.phil_iri_rubric_criteria (
  id            bigint generated always as identity primary key,
  collection_id bigint not null references public.phil_iri_collections(id) on delete cascade,
  criterion_no  integer not null check (criterion_no > 0),
  name          text not null check (length(trim(name)) > 0),
  scale_min     integer not null default 1,
  scale_max     integer not null,
  constraint phil_iri_rubric_criteria_scale check (scale_min < scale_max),
  constraint phil_iri_rubric_criteria_no_key unique (collection_id, criterion_no)
);

drop policy if exists phil_iri_rubric_criteria_select on public.phil_iri_rubric_criteria;
create policy phil_iri_rubric_criteria_select on public.phil_iri_rubric_criteria
  for select to authenticated using (phil_iri_collection_readable(collection_id));
drop policy if exists phil_iri_rubric_criteria_write on public.phil_iri_rubric_criteria;
create policy phil_iri_rubric_criteria_write on public.phil_iri_rubric_criteria
  for all to authenticated
  using (phil_iri_collection_writable(collection_id))
  with check (phil_iri_collection_writable(collection_id));

-- Passages ------------------------------------------------------------------

create table if not exists public.phil_iri_passages (
  id            bigint generated always as identity primary key,
  collection_id bigint not null references public.phil_iri_collections(id),
  language      text not null default 'English' check (language = 'English'),
  test_type     text check (test_type in ('pre', 'post')),
  set_code      text,
  level         integer check (level between 1 and 12),
  selection_no  integer check (selection_no > 0),
  title         text not null check (length(trim(title)) > 0),
  motivation    text,
  body          text not null check (length(trim(body)) > 0),
  word_count    integer not null check (word_count > 0),
  is_active     boolean not null default true,
  created_by    uuid references public.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists phil_iri_passages_collection_level
  on public.phil_iri_passages (collection_id, level);

-- A passage in a grade-leveled collection must have a level (the grade that
-- reads it); a non-graded collection (FRB) must not.
create or replace function public.check_phil_iri_passage_level()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_graded boolean;
begin
  if auth.uid() is not null and not phil_iri_collection_writable(new.collection_id) then
    raise exception 'new row violates row-level security policy for table "%"', tg_table_name
      using errcode = '42501';
  end if;
  select is_grade_leveled into v_graded
  from public.phil_iri_collections where id = new.collection_id;
  if v_graded and new.level is null then
    raise exception 'a passage in a grade-leveled collection needs a level';
  end if;
  if not v_graded and new.level is not null then
    raise exception 'a passage in a non-graded collection has no level';
  end if;
  return new;
end;
$$;

drop policy if exists phil_iri_passages_select on public.phil_iri_passages;
create policy phil_iri_passages_select on public.phil_iri_passages
  for select to authenticated using (phil_iri_collection_readable(collection_id));
drop policy if exists phil_iri_passages_write on public.phil_iri_passages;
create policy phil_iri_passages_write on public.phil_iri_passages
  for all to authenticated
  using (phil_iri_collection_writable(collection_id))
  with check (phil_iri_collection_writable(collection_id));

drop trigger if exists phil_iri_passages_level on public.phil_iri_passages;
create trigger phil_iri_passages_level
  before insert or update of collection_id, level on public.phil_iri_passages
  for each row execute function public.check_phil_iri_passage_level();
drop trigger if exists phil_iri_passages_created_by on public.phil_iri_passages;
create trigger phil_iri_passages_created_by
  before insert on public.phil_iri_passages
  for each row execute function public.phil_iri_stamp_created_by();
drop trigger if exists phil_iri_passages_updated_at on public.phil_iri_passages;
create trigger phil_iri_passages_updated_at
  before update on public.phil_iri_passages
  for each row execute function public.set_updated_at();

-- Questions -----------------------------------------------------------------

create table if not exists public.phil_iri_questions (
  id            bigint generated always as identity primary key,
  passage_id    bigint not null references public.phil_iri_passages(id) on delete cascade,
  question_no   integer not null check (question_no > 0),
  question_type text check (question_type in ('L', 'I', 'C')),
  prompt        text not null check (length(trim(prompt)) > 0),
  choices       jsonb not null check (jsonb_typeof(choices) = 'array' and jsonb_array_length(choices) >= 2),
  answer_key    text not null check (answer_key ~ '^[a-z]$'),
  constraint phil_iri_questions_key_in_choices
    check (ascii(answer_key) - ascii('a') < jsonb_array_length(choices)),
  constraint phil_iri_questions_no_key unique (passage_id, question_no)
);

create or replace function public.phil_iri_passage_readable(p_passage_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.phil_iri_passages p
    where p.id = p_passage_id and phil_iri_collection_readable(p.collection_id)
  );
$$;

create or replace function public.phil_iri_passage_writable(p_passage_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.phil_iri_passages p
    where p.id = p_passage_id and phil_iri_collection_writable(p.collection_id)
  );
$$;

drop policy if exists phil_iri_questions_select on public.phil_iri_questions;
create policy phil_iri_questions_select on public.phil_iri_questions
  for select to authenticated using (phil_iri_passage_readable(passage_id));
drop policy if exists phil_iri_questions_write on public.phil_iri_questions;
create policy phil_iri_questions_write on public.phil_iri_questions
  for all to authenticated
  using (phil_iri_passage_writable(passage_id))
  with check (phil_iri_passage_writable(passage_id));

-- Thresholds ----------------------------------------------------------------
-- settings holds PhilIriThresholds.toMap(). Effective values in the app:
-- built-in defaults <- region row <- school row (key by key).

create table if not exists public.phil_iri_thresholds (
  id          bigint generated always as identity primary key,
  school_id   bigint references public.schools(id),
  settings    jsonb not null check (jsonb_typeof(settings) = 'object'),
  updated_by  uuid references public.users(id),
  updated_at  timestamptz not null default now()
);
create unique index if not exists phil_iri_thresholds_school_key
  on public.phil_iri_thresholds (coalesce(school_id, 0));

create or replace function public.phil_iri_thresholds_stamp()
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

drop policy if exists phil_iri_thresholds_select on public.phil_iri_thresholds;
create policy phil_iri_thresholds_select on public.phil_iri_thresholds
  for select to authenticated
  using (is_superadmin() or school_id is null or school_id = current_user_school_id());

drop policy if exists phil_iri_thresholds_write on public.phil_iri_thresholds;
create policy phil_iri_thresholds_write on public.phil_iri_thresholds
  for all to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id is not null and school_id = current_user_school_id())
  )
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id is not null and school_id = current_user_school_id())
  );

drop trigger if exists phil_iri_thresholds_stamp on public.phil_iri_thresholds;
create trigger phil_iri_thresholds_stamp
  before insert or update on public.phil_iri_thresholds
  for each row execute function public.phil_iri_thresholds_stamp();

-- RLS on (rls_auto_enable also does this for new tables) and no anon access.
alter table public.phil_iri_collections enable row level security;
alter table public.phil_iri_rubric_criteria enable row level security;
alter table public.phil_iri_passages enable row level security;
alter table public.phil_iri_questions enable row level security;
alter table public.phil_iri_thresholds enable row level security;
revoke all on public.phil_iri_collections, public.phil_iri_rubric_criteria,
  public.phil_iri_passages, public.phil_iri_questions, public.phil_iri_thresholds
  from anon;

commit;
