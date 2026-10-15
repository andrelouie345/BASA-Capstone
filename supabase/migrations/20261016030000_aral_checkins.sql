-- ARAL-Reading check-in assessments, piece CI1: the check-in tools (content),
-- a learner's check-ins with per-item answers, and the adjustable cut-off.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Needs
-- 20261016010000 (aral_enrollment_readable, aral_irip_writable). The tools
-- and their items are seeded by supabase/seeds/aral_checkin_tools.sql.
--
-- Source: sample-files/ARAL/[FINAL] Check-Assessment Tools for KS 2-3 (DepEd:
-- a check-in after sessions 16 and 32). There are eight tools: KS2/KS3 x
-- Basic/Plus x sessions 1-16 / 17-32. KS1 and Foundational have none. The
-- "Sessions 1-16 MOSY" Plus KS3 file has the same items as the regular one.
--
-- Owner decisions (2026-10-16):
--  * Per-item marks. A choice item stores the learner's letter and is scored
--    against the key here; an open item (syllabication, word meaning, own
--    answer, picture items) is marked right or wrong by the tutor.
--  * Retakes allowed: attempt_no counts per learner and tool; the latest counts.
--  * Pass = score >= a percentage cut-off (default 75, adjustable per region
--    and per school in aral_settings), judged when read (no snapshot). Same
--    cut-off per section.
--  * Record and report only: no effect on the IRIP, placement or exit.
--
-- Rules:
--  * A check-in needs an active learner whose current placement (key stage and
--    track) is the tool's; taken_on is not before the learner entered ARAL.
--    Learner, tool, attempt and creator never change.
--  * An answer's item belongs to the check-in's tool. Choice: response is a
--    letter A-E or empty (empty = wrong) and is_correct is computed. Open:
--    is_correct is given by the tutor.
--
-- RLS: tools/items: read = any signed-in user; write = superadmin. Check-ins
-- and answers: read = whoever can read the ARAL enrollment; write =
-- superadmin, admin/coordinator of the school, or the learner's ARAL tutor
-- (same as the IRIP). aral_settings: as crla_thresholds (region row =
-- superadmin, school row = that school's admin/coordinator). anon revoked.

-- Tools -------------------------------------------------------------------------

create table if not exists public.aral_checkin_tools (
  id          bigint generated always as identity primary key,
  key_stage   text not null check (key_stage in ('ks2', 'ks3')),
  track       text not null check (track in ('basic', 'plus')),
  checkpoint  integer not null check (checkpoint in (16, 32)),  -- after session 16 / 32
  language    text not null check (language in ('filipino', 'english')),
  title       text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  constraint aral_checkin_tools_one unique (key_stage, track, checkpoint)
);

create table if not exists public.aral_checkin_items (
  id          bigint generated always as identity primary key,
  tool_id     bigint not null references public.aral_checkin_tools(id),
  item_no     integer not null check (item_no >= 1),  -- 1..n across the whole tool
  label       text,      -- the number printed on the sheet when it restarts per part
  section     text,      -- the sheet's part (e.g. 'II. Syllables'); null = no parts
  kind        text not null check (kind in ('choice', 'open')),
  answer_key  text,      -- choice: the letter; open: the expected answer (may be null)
  prompt      text not null,
  created_at  timestamptz not null default now(),
  constraint aral_checkin_items_order unique (tool_id, item_no),
  constraint aral_checkin_items_key check (kind = 'open' or coalesce(answer_key ~ '^[A-E]$', false))
);

drop policy if exists aral_checkin_tools_select on public.aral_checkin_tools;
create policy aral_checkin_tools_select on public.aral_checkin_tools
  for select to authenticated using (true);
drop policy if exists aral_checkin_tools_write on public.aral_checkin_tools;
create policy aral_checkin_tools_write on public.aral_checkin_tools
  for all to authenticated using (is_superadmin()) with check (is_superadmin());
alter table public.aral_checkin_tools enable row level security;
revoke all on public.aral_checkin_tools from anon;

drop policy if exists aral_checkin_items_select on public.aral_checkin_items;
create policy aral_checkin_items_select on public.aral_checkin_items
  for select to authenticated using (true);
drop policy if exists aral_checkin_items_write on public.aral_checkin_items;
create policy aral_checkin_items_write on public.aral_checkin_items
  for all to authenticated using (is_superadmin()) with check (is_superadmin());
alter table public.aral_checkin_items enable row level security;
revoke all on public.aral_checkin_items from anon;

-- Check-ins ---------------------------------------------------------------------

create table if not exists public.aral_checkins (
  id             bigint generated always as identity primary key,
  enrollment_id  bigint not null references public.aral_enrollments(id) on delete cascade,
  tool_id        bigint not null references public.aral_checkin_tools(id),
  attempt_no     integer not null default 0,
  taken_on       date not null,
  notes          text,
  created_by     uuid references public.users(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint aral_checkins_attempt unique (enrollment_id, tool_id, attempt_no)
);
create index if not exists aral_checkins_enrollment on public.aral_checkins (enrollment_id, tool_id);

create or replace function public.aral_checkins_before_write()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  e record;
  t record;
begin
  if tg_op = 'UPDATE' then
    if (new.enrollment_id, new.tool_id, new.attempt_no, new.created_by, new.created_at)
       is distinct from
       (old.enrollment_id, old.tool_id, old.attempt_no, old.created_by, old.created_at) then
      raise exception 'a check-in keeps its learner, tool and attempt; only the date and notes change';
    end if;
  end if;

  -- Locked so two check-ins of one learner get distinct attempt numbers.
  select status, key_stage, track, entered_on into e
  from public.aral_enrollments where id = new.enrollment_id for update;

  if tg_op = 'INSERT' then
    if e.status is distinct from 'active' then
      raise exception 'the learner is not active in ARAL';
    end if;
    select key_stage, track, is_active into t from public.aral_checkin_tools where id = new.tool_id;
    if t.key_stage is distinct from e.key_stage or t.track is distinct from e.track or not t.is_active then
      raise exception 'that check-in tool is not for the learner''s ARAL program';
    end if;
    select coalesce(max(attempt_no), 0) + 1 into new.attempt_no
    from public.aral_checkins
    where enrollment_id = new.enrollment_id and tool_id = new.tool_id;
    if auth.uid() is not null then
      new.created_by := auth.uid();
    end if;
    new.created_at := now();
  end if;

  if new.taken_on < e.entered_on then
    raise exception 'a check-in cannot be dated before the learner entered ARAL';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists aral_checkins_before_write on public.aral_checkins;
create trigger aral_checkins_before_write
  before insert or update on public.aral_checkins
  for each row execute function public.aral_checkins_before_write();

drop policy if exists aral_checkins_select on public.aral_checkins;
create policy aral_checkins_select on public.aral_checkins
  for select to authenticated using (aral_enrollment_readable(enrollment_id));
drop policy if exists aral_checkins_insert on public.aral_checkins;
create policy aral_checkins_insert on public.aral_checkins
  for insert to authenticated with check (aral_irip_writable(enrollment_id));
drop policy if exists aral_checkins_update on public.aral_checkins;
create policy aral_checkins_update on public.aral_checkins
  for update to authenticated using (aral_irip_writable(enrollment_id)) with check (aral_irip_writable(enrollment_id));
drop policy if exists aral_checkins_delete on public.aral_checkins;
create policy aral_checkins_delete on public.aral_checkins
  for delete to authenticated using (aral_irip_writable(enrollment_id));
alter table public.aral_checkins enable row level security;
revoke all on public.aral_checkins from anon;

-- Answers -----------------------------------------------------------------------

create table if not exists public.aral_checkin_answers (
  id          bigint generated always as identity primary key,
  checkin_id  bigint not null references public.aral_checkins(id) on delete cascade,
  item_id     bigint not null references public.aral_checkin_items(id),
  response    text,
  is_correct  boolean not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint aral_checkin_answers_one unique (checkin_id, item_id)
);

create or replace function public.aral_checkin_answers_before_write()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  i record;
begin
  if tg_op = 'UPDATE' and (new.checkin_id, new.item_id, new.created_at)
     is distinct from (old.checkin_id, old.item_id, old.created_at) then
    raise exception 'an answer keeps its check-in and item; only the response and mark change';
  end if;

  select it.kind, it.answer_key into i
  from public.aral_checkin_items it
  join public.aral_checkins c on c.tool_id = it.tool_id
  where it.id = new.item_id and c.id = new.checkin_id;
  if not found then
    raise exception 'that item is not on the check-in''s tool';
  end if;

  if i.kind = 'choice' then
    new.response := nullif(upper(btrim(new.response)), '');
    if new.response is not null and new.response !~ '^[A-E]$' then
      raise exception 'a multiple-choice answer is a letter A-E (or empty)';
    end if;
    new.is_correct := coalesce(new.response = i.answer_key, false);
  elsif new.is_correct is null then
    raise exception 'an open item needs a right/wrong mark';
  end if;

  if tg_op = 'INSERT' then
    new.created_at := now();
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists aral_checkin_answers_before_write on public.aral_checkin_answers;
create trigger aral_checkin_answers_before_write
  before insert or update on public.aral_checkin_answers
  for each row execute function public.aral_checkin_answers_before_write();

create or replace function public.aral_checkin_readable(p_checkin_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (select 1 from public.aral_checkins c
                 where c.id = p_checkin_id and aral_enrollment_readable(c.enrollment_id));
$$;

create or replace function public.aral_checkin_writable(p_checkin_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (select 1 from public.aral_checkins c
                 where c.id = p_checkin_id and aral_irip_writable(c.enrollment_id));
$$;

drop policy if exists aral_checkin_answers_select on public.aral_checkin_answers;
create policy aral_checkin_answers_select on public.aral_checkin_answers
  for select to authenticated using (aral_checkin_readable(checkin_id));
drop policy if exists aral_checkin_answers_insert on public.aral_checkin_answers;
create policy aral_checkin_answers_insert on public.aral_checkin_answers
  for insert to authenticated with check (aral_checkin_writable(checkin_id));
drop policy if exists aral_checkin_answers_update on public.aral_checkin_answers;
create policy aral_checkin_answers_update on public.aral_checkin_answers
  for update to authenticated using (aral_checkin_writable(checkin_id)) with check (aral_checkin_writable(checkin_id));
drop policy if exists aral_checkin_answers_delete on public.aral_checkin_answers;
create policy aral_checkin_answers_delete on public.aral_checkin_answers
  for delete to authenticated using (aral_checkin_writable(checkin_id));
alter table public.aral_checkin_answers enable row level security;
revoke all on public.aral_checkin_answers from anon;

-- Settings ----------------------------------------------------------------------
-- One region-wide row (school_id null) and at most one override per school.
-- Effective = built-in defaults <- region <- school, key by key (in the app).
-- Keys: checkin_pass_pct (1-100, default 75).

create table if not exists public.aral_settings (
  id          bigint generated always as identity primary key,
  school_id   bigint references public.schools(id),
  settings    jsonb not null check (jsonb_typeof(settings) = 'object'),
  updated_by  uuid references public.users(id),
  updated_at  timestamptz not null default now(),
  constraint aral_settings_pass_pct check (
    not settings ? 'checkin_pass_pct'
    or (jsonb_typeof(settings->'checkin_pass_pct') = 'number'
        and (settings->>'checkin_pass_pct')::numeric between 1 and 100))
);
create unique index if not exists aral_settings_school_key
  on public.aral_settings (coalesce(school_id, 0));

create or replace function public.aral_settings_stamp()
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

drop trigger if exists aral_settings_stamp on public.aral_settings;
create trigger aral_settings_stamp
  before insert or update on public.aral_settings
  for each row execute function public.aral_settings_stamp();

drop policy if exists aral_settings_select on public.aral_settings;
create policy aral_settings_select on public.aral_settings
  for select to authenticated
  using (is_superadmin() or school_id is null or school_id = current_user_school_id());
drop policy if exists aral_settings_write on public.aral_settings;
create policy aral_settings_write on public.aral_settings
  for all to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id is not null and school_id = current_user_school_id()))
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id is not null and school_id = current_user_school_id()));
alter table public.aral_settings enable row level security;
revoke all on public.aral_settings from anon;
