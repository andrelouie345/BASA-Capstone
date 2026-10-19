-- Assessment round calendar (dashboard piece D1). Idempotent: safe to run in
-- the Supabase SQL Editor more than once. Newer than the 20261018040000
-- baseline: a new deployment runs it after it.
--
-- The windows in which each assessment round is held, per school year and
-- instrument: one region-wide default row per round (school_id null, set by
-- the superadmin) and, per school, an override row with other dates or
-- skipped = true (the school does not hold that round). A round is scheduled
-- for a school only when its effective row (school row over region row)
-- exists and is not skipped; reminders (D2/D3) follow the scheduled rounds.
-- Written online and mirrored to the device (like aral_settings).
--
-- Rules:
--  * instrument phil_iri or crla; round one of bosy, mosy, mosy1-3, eosy. Which
--    rounds each instrument has (Phil-IRI bosy/mosy1-3/eosy, CRLA
--    bosy/mosy/eosy) is checked by the app (calendarRounds), not here.
--  * a row is either skipped (school rows only, no dates) or has both dates
--    with closes_on >= opens_on.
--  * one row per (school or region, school year, instrument, round).
--  * updated_by/updated_at stamped by aral_settings_stamp() (same columns).
--
-- RLS (raised with the table, copy of aral_settings):
--  * select: superadmin; everyone signed in reads the region rows and their
--    own school's rows (tutors included).
--  * insert/update/delete: superadmin; admin/coordinator for their own school's
--    rows only. Tutors never write.
--  * anon: nothing.

create table if not exists public.assessment_calendar (
  id           bigint generated always as identity primary key,
  school_id    bigint references public.schools(id) on delete cascade,
  school_year  text not null check (school_year ~ '^\d{4}-\d{4}$'
                 and right(school_year, 4)::integer = left(school_year, 4)::integer + 1),
  instrument   text not null check (instrument in ('phil_iri', 'crla')),
  round        text not null check (round in ('bosy', 'mosy', 'mosy1', 'mosy2', 'mosy3', 'eosy')),
  opens_on     date,
  closes_on    date,
  skipped      boolean not null default false,
  updated_by   uuid references public.users(id),
  updated_at   timestamptz not null default now(),
  constraint assessment_calendar_window check (
    (skipped and school_id is not null and opens_on is null and closes_on is null)
    or (not skipped and opens_on is not null and closes_on is not null and closes_on >= opens_on))
);
create unique index if not exists assessment_calendar_key
  on public.assessment_calendar (coalesce(school_id, 0), school_year, instrument, round);

drop trigger if exists assessment_calendar_stamp on public.assessment_calendar;
create trigger assessment_calendar_stamp
  before insert or update on public.assessment_calendar
  for each row execute function public.aral_settings_stamp();

alter table public.assessment_calendar enable row level security;
revoke all on public.assessment_calendar from anon;

drop policy if exists assessment_calendar_select on public.assessment_calendar;
create policy assessment_calendar_select on public.assessment_calendar
  for select to authenticated
  using (is_superadmin() or school_id is null or school_id = current_user_school_id());

drop policy if exists assessment_calendar_write on public.assessment_calendar;
create policy assessment_calendar_write on public.assessment_calendar
  to authenticated
  using (is_superadmin() or (current_user_role() in ('admin', 'coordinator')
         and school_id is not null and school_id = current_user_school_id()))
  with check (is_superadmin() or (current_user_role() in ('admin', 'coordinator')
              and school_id is not null and school_id = current_user_school_id()));
