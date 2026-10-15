-- ARAL-Reading Individual Reading Intervention Plan (IRIP), piece A3a:
-- aral_irip_targets (the reading-target lists, content) and aral_irip_weeks
-- (a learner's weekly target, status and notes). Idempotent: safe to run in the
-- Supabase SQL Editor more than once. Needs 20261015070000 (key stage
-- 'foundational'). The target lists are seeded by
-- supabase/seeds/aral_irip_targets.sql.
--
-- Source: IRIP_ARAL-Reading Basic and Plus_v09122025.docx. Owner decisions
-- (2026-10-16):
--  * Three programs have an IRIP: KS2-3 Basic (4 Filipino + 5 English targets:
--    phonological focus, letters, sight words; the two languages run in
--    parallel, each with its own weekly target), KS2 Plus and KS3 Plus (8
--    targets each, every target a group of skills). KS1 and Foundational
--    learners have no IRIP for now.
--  * One IRIP cycle = 8 weeks. Each week the tutor rates the week's target:
--    observed (proceed), partial (more practice), not_observed (reteach), with
--    notes. Only week 1 is pre-assigned; BASA suggests each next target and the
--    tutor may pick another one from the list (app rule, not here).
--  * When a cycle ends and the learner is still in ARAL, a new cycle starts.
--  * Offline-first like the roster: devices write locally; this waits for sync.
--
-- Rules (aral_irip_weeks):
--  * The learner (ARAL enrollment) is active, and the target belongs to the
--    program of the learner's current placement and to the row's strand.
--  * week_no 1-8; a week other than 1 needs the previous week of the same
--    cycle and strand.
--  * status and rated_on go together; the target can change only while the
--    week is unrated. Learner, cycle, week, strand and creator never change.
--
-- RLS: targets: read = any signed-in user; write = superadmin. Weeks: read =
-- whoever can read the ARAL enrollment (superadmin, admin/coordinator of the
-- school, the learner's ARAL tutor or a tutor of the learner's section);
-- write = superadmin, admin/coordinator of the school, or the learner's ARAL
-- tutor. anon revoked on both.

-- Targets ---------------------------------------------------------------------

create table if not exists public.aral_irip_targets (
  id            bigint generated always as identity primary key,
  program       text not null check (program in ('basic_ks23', 'plus_ks2', 'plus_ks3')),
  strand        text not null check (strand in ('filipino', 'english', 'main')),
  seq           integer not null check (seq >= 1),
  focus         text,     -- Basic: phonological awareness focus
  letter_focus  text,     -- Basic
  sight_words   text,     -- Basic
  skills        text,     -- Plus: the target's skills, one per line
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  constraint aral_irip_targets_order unique (program, strand, seq),
  constraint aral_irip_targets_strand check ((program = 'basic_ks23') = (strand in ('filipino', 'english'))),
  constraint aral_irip_targets_content check (
    case when program = 'basic_ks23' then focus is not null else skills is not null end)
);

drop policy if exists aral_irip_targets_select on public.aral_irip_targets;
create policy aral_irip_targets_select on public.aral_irip_targets
  for select to authenticated using (true);
drop policy if exists aral_irip_targets_write on public.aral_irip_targets;
create policy aral_irip_targets_write on public.aral_irip_targets
  for all to authenticated using (is_superadmin()) with check (is_superadmin());
alter table public.aral_irip_targets enable row level security;
revoke all on public.aral_irip_targets from anon;

-- The IRIP program of a placement; null = no IRIP (Foundational, KS1).
create or replace function public.aral_irip_program(p_key_stage text, p_track text)
 returns text language sql immutable set search_path to 'public'
as $$
  select case
    when p_key_stage in ('ks2', 'ks3') and p_track = 'basic' then 'basic_ks23'
    when p_key_stage = 'ks2' and p_track = 'plus' then 'plus_ks2'
    when p_key_stage = 'ks3' and p_track = 'plus' then 'plus_ks3'
  end;
$$;

-- Weeks -----------------------------------------------------------------------

create table if not exists public.aral_irip_weeks (
  id             bigint generated always as identity primary key,
  enrollment_id  bigint not null references public.aral_enrollments(id) on delete cascade,
  cycle_no       integer not null default 1 check (cycle_no >= 1),
  week_no        integer not null check (week_no between 1 and 8),
  strand         text not null check (strand in ('filipino', 'english', 'main')),
  target_id      bigint not null references public.aral_irip_targets(id),
  status         text check (status in ('observed', 'partial', 'not_observed')),
  rated_on       date,
  notes          text,
  created_by     uuid references public.users(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint aral_irip_weeks_one unique (enrollment_id, cycle_no, week_no, strand),
  constraint aral_irip_weeks_rated check ((status is null) = (rated_on is null))
);
create index if not exists aral_irip_weeks_enrollment on public.aral_irip_weeks (enrollment_id, cycle_no, week_no);

create or replace function public.aral_enrollment_readable(p_enrollment_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.aral_enrollments e
    where e.id = p_enrollment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and e.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and (e.tutor_id = auth.uid() or tutor_has_section(e.section_id))))
  );
$$;

-- The learner's ARAL tutor writes the IRIP; so do the school's managers.
create or replace function public.aral_irip_writable(p_enrollment_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.aral_enrollments e
    where e.id = p_enrollment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and e.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and e.tutor_id = auth.uid()))
  );
$$;

create or replace function public.aral_irip_weeks_before_write()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_program text;
  v_active  boolean;
  t         record;
begin
  if tg_op = 'UPDATE' then
    if (new.enrollment_id, new.cycle_no, new.week_no, new.strand, new.created_by, new.created_at)
       is distinct from
       (old.enrollment_id, old.cycle_no, old.week_no, old.strand, old.created_by, old.created_at) then
      raise exception 'an IRIP week keeps its learner, cycle, week and strand; only the target, status and notes change';
    end if;
    if new.target_id is distinct from old.target_id and old.status is not null then
      raise exception 'a rated IRIP week keeps its target';
    end if;
  else
    if auth.uid() is not null then
      new.created_by := auth.uid();
    end if;
    new.created_at := now();
    if new.week_no > 1 and not exists (
      select 1 from public.aral_irip_weeks
      where enrollment_id = new.enrollment_id and cycle_no = new.cycle_no
        and week_no = new.week_no - 1 and strand = new.strand) then
      raise exception 'an IRIP week needs the previous week of its cycle';
    end if;
  end if;
  new.updated_at := now();

  if tg_op = 'INSERT' or new.target_id is distinct from old.target_id then
    select aral_irip_program(key_stage, track), status = 'active' into v_program, v_active
    from public.aral_enrollments where id = new.enrollment_id;
    if not coalesce(v_active, false) then
      raise exception 'the learner is not active in ARAL';
    end if;
    select program, strand, is_active into t from public.aral_irip_targets where id = new.target_id;
    if v_program is null then
      raise exception 'the learner''s ARAL program has no IRIP (Foundational and KS1)';
    end if;
    if t.program is distinct from v_program or t.strand is distinct from new.strand or not t.is_active then
      raise exception 'that reading target is not in the learner''s IRIP list';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists aral_irip_weeks_before_write on public.aral_irip_weeks;
create trigger aral_irip_weeks_before_write
  before insert or update on public.aral_irip_weeks
  for each row execute function public.aral_irip_weeks_before_write();

drop policy if exists aral_irip_weeks_select on public.aral_irip_weeks;
create policy aral_irip_weeks_select on public.aral_irip_weeks
  for select to authenticated using (aral_enrollment_readable(enrollment_id));
drop policy if exists aral_irip_weeks_insert on public.aral_irip_weeks;
create policy aral_irip_weeks_insert on public.aral_irip_weeks
  for insert to authenticated with check (aral_irip_writable(enrollment_id));
drop policy if exists aral_irip_weeks_update on public.aral_irip_weeks;
create policy aral_irip_weeks_update on public.aral_irip_weeks
  for update to authenticated using (aral_irip_writable(enrollment_id)) with check (aral_irip_writable(enrollment_id));
drop policy if exists aral_irip_weeks_delete on public.aral_irip_weeks;
create policy aral_irip_weeks_delete on public.aral_irip_weeks
  for delete to authenticated using (aral_irip_writable(enrollment_id));
alter table public.aral_irip_weeks enable row level security;
revoke all on public.aral_irip_weeks from anon;
