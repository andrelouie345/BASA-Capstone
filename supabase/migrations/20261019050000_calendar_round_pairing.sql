-- Assessment calendar: each instrument only its own rounds (dashboard D2).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261019030000 (which created the table).
--
-- 20261019030000 only checked that round is one of the six names, so a row
-- such as Phil-IRI 'mosy' or CRLA 'mosy2' could be stored outside the app.
-- This adds the pairing, using exactly the rounds the assessment tables accept:
--  * phil_iri: bosy, mosy1, mosy2, mosy3, eosy (phil_iri_assessments_round_check)
--  * crla:     bosy, mosy, eosy                 (crla_assessments_round_check)
--
-- Rule (also in lib/core/CLAUDE.md): changing an instrument's rounds is ONE
-- migration that swaps the assessment table's round check and this constraint
-- together, converting existing calendar rows first; the app side is the
-- PhilIriRound / CrlaRound enum, from which calendarRounds is built.
--
-- Stops (changes nothing) when invalid rows already exist, listing them, so
-- nothing is deleted silently. RLS: unchanged (a constraint only).

do $$
declare
  bad text;
begin
  select string_agg(format('id %s (school %s, %s, %s %s)', id, coalesce(school_id::text, 'region'),
                           school_year, instrument, round), '; ' order by id)
    into bad
    from public.assessment_calendar
   where not ((instrument = 'phil_iri' and round in ('bosy', 'mosy1', 'mosy2', 'mosy3', 'eosy'))
           or (instrument = 'crla' and round in ('bosy', 'mosy', 'eosy')));
  if bad is not null then
    raise exception 'assessment_calendar has rows whose round its instrument does not hold: %. '
                    'Fix or delete them, then run this migration again.', bad;
  end if;
end $$;

alter table public.assessment_calendar drop constraint if exists assessment_calendar_round_pairing;
alter table public.assessment_calendar add constraint assessment_calendar_round_pairing check (
  (instrument = 'phil_iri' and round in ('bosy', 'mosy1', 'mosy2', 'mosy3', 'eosy'))
  or (instrument = 'crla' and round in ('bosy', 'mosy', 'eosy')));
