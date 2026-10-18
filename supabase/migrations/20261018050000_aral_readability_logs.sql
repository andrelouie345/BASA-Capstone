-- ARAL: readability log of the reading materials used in the intervention
-- (piece R4). Idempotent: safe to run in the Supabase SQL Editor more than once.
-- Newer than the 20261018040000 baseline: a new deployment runs it after it.
--
-- Reading coordinator's workbook, sheet "Readability" (2026-10-18): per
-- learner, each selection read in the intervention with its date, title,
-- number of words, sentences and syllables and its source; the app computes
-- the Flesch reading ease and grade level from the counts (not stored, so a
-- corrected count or formula re-scores old rows). Owner: only available while
-- the school's foundational literacy program (SHARP) is switched on
-- (aral_settings.foundational_program, school row over region row, default off).
--
-- Rules (trigger aral_readability_logs_before_write):
--  * INSERT: the learner is active in ARAL, the school's SHARP is on, the date
--    is not before the learner entered ARAL; created_by/created_at stamped.
--  * UPDATE: a row keeps its learner and stamps; the date rule again.
--  * counts: words, sentences, syllables > 0 and syllables >= words.
--
-- RLS (raised with the table), like the IRIP weeks and check-ins:
--  * select: aral_enrollment_readable (superadmin; admin/coordinator of the
--    learner's school; the learner's ARAL tutor or a tutor of the section).
--  * insert/update/delete: aral_irip_writable (superadmin; admin/coordinator of
--    the school; the learner's ARAL tutor).
--  * anon: nothing. SECURITY DEFINER functions set search_path = public.

create or replace function public.aral_foundational_program_on(p_school_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select coalesce(
    (select (settings->>'foundational_program')::boolean from public.aral_settings
      where school_id = p_school_id and settings ? 'foundational_program'),
    (select (settings->>'foundational_program')::boolean from public.aral_settings
      where school_id is null and settings ? 'foundational_program'),
    false);
$$;

create table if not exists public.aral_readability_logs (
  id             bigint generated always as identity primary key,
  enrollment_id  bigint not null references public.aral_enrollments(id) on delete cascade,
  read_on        date not null,
  title          text not null check (length(btrim(title)) > 0),
  words          integer not null check (words > 0),
  sentences      integer not null check (sentences > 0),
  syllables      integer not null check (syllables > 0),
  source         text,
  material_id    bigint references public.aral_materials(id) on delete set null,
  created_by     uuid references public.users(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint aral_readability_logs_syllables check (syllables >= words)
);
create index if not exists aral_readability_logs_enrollment on public.aral_readability_logs (enrollment_id, read_on);

create or replace function public.aral_readability_logs_before_write()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  e record;
begin
  select status, school_id, entered_on into e from public.aral_enrollments where id = new.enrollment_id;
  if tg_op = 'UPDATE' then
    if (new.enrollment_id, new.created_by, new.created_at) is distinct from
       (old.enrollment_id, old.created_by, old.created_at) then
      raise exception 'a readability log entry keeps its learner; only the selection, counts, date and source change';
    end if;
  else
    if e.status is distinct from 'active' then
      raise exception 'the learner is not active in ARAL';
    end if;
    if not aral_foundational_program_on(e.school_id) then
      raise exception 'the readability log is only kept while the school''s foundational literacy program (SHARP) is switched on';
    end if;
    if auth.uid() is not null then
      new.created_by := auth.uid();
    end if;
    new.created_at := now();
  end if;
  if new.read_on < e.entered_on then
    raise exception 'a reading cannot be dated before the learner entered ARAL';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists aral_readability_logs_before_write on public.aral_readability_logs;
create trigger aral_readability_logs_before_write
  before insert or update on public.aral_readability_logs
  for each row execute function public.aral_readability_logs_before_write();

alter table public.aral_readability_logs enable row level security;
revoke all on public.aral_readability_logs from anon;

drop policy if exists aral_readability_logs_select on public.aral_readability_logs;
create policy aral_readability_logs_select on public.aral_readability_logs
  for select to authenticated using (aral_enrollment_readable(enrollment_id));
drop policy if exists aral_readability_logs_insert on public.aral_readability_logs;
create policy aral_readability_logs_insert on public.aral_readability_logs
  for insert to authenticated with check (aral_irip_writable(enrollment_id));
drop policy if exists aral_readability_logs_update on public.aral_readability_logs;
create policy aral_readability_logs_update on public.aral_readability_logs
  for update to authenticated using (aral_irip_writable(enrollment_id)) with check (aral_irip_writable(enrollment_id));
drop policy if exists aral_readability_logs_delete on public.aral_readability_logs;
create policy aral_readability_logs_delete on public.aral_readability_logs
  for delete to authenticated using (aral_irip_writable(enrollment_id));
