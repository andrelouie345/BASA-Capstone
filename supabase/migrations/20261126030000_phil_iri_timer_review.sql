-- Phil-IRI timed reading, final review fixes to the timer tap rule (spec
-- docs/superpowers/specs/2026-11-26-phil-iri-timed-reading-design.md).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261126020000.
-- App update required on all devices: no (the server accepts a restart it
-- refused before and refuses taps the app already refuses).
--
-- 1. A restart (reset) is allowed whatever the device clock says, and the
--    other taps are compared only with the taps after the last restart. Before,
--    a phone whose clock jumped back (time zone, network time) could not pause,
--    stop or restart until the clock passed its old time (review I3).
-- 2. Taps need an in-progress session: a completed session is reopened first,
--    so a restart can't clear the time of a completed session (review I5).
-- The same rules are in lib/core/services/phil_iri_timer.dart, the ViewModel
-- and the device trigger (phil_iri_local_schema.dart, SQLite v50).
--
-- RLS: no table, view or policy changes (the trigger only).

create or replace function public.check_phil_iri_timer_event() returns trigger
  language plpgsql security definer set search_path = public
as $$
declare
  st text;
  last_seq integer;
  last_reset integer;
  last_at timestamptz;
  r record;
begin
  -- One tap at a time per reading.
  select rd.id, rd.passage_id, a.status into r
    from public.phil_iri_readings rd
    join public.phil_iri_assessments a on a.id = rd.assessment_id
   where rd.id = new.reading_id
     for update of rd;
  if not found then
    raise exception 'reading % not found', new.reading_id;
  end if;
  if r.passage_id is null then
    raise exception 'This reading was imported without a passage (Untitled) and cannot be timed.';
  end if;
  if r.status is distinct from 'in_progress' then
    raise exception 'Reopen the session to time it again.';
  end if;
  select max(e.seq), max(e.seq) filter (where e.kind = 'reset') into last_seq, last_reset
    from public.phil_iri_reading_timer_events e where e.reading_id = new.reading_id;
  select max(e.at) into last_at
    from public.phil_iri_reading_timer_events e
   where e.reading_id = new.reading_id and e.seq > coalesce(last_reset, 0);
  if new.kind <> 'reset' and last_at is not null and new.at < last_at then
    raise exception 'This time is earlier than the timer''s last tap; check the device clock.';
  end if;
  st := basa_private.phil_iri_timer_status(new.reading_id);
  if new.kind = 'start' and st <> 'none' then
    raise exception 'The timer is already started.';
  elsif new.kind = 'pause' and st <> 'running' then
    raise exception '%', case st when 'paused' then 'The timer is already paused.'
                                  when 'stopped' then 'The timer is already stopped.' else 'Start the timer first.' end;
  elsif new.kind = 'resume' and st <> 'paused' then
    raise exception 'The timer is not paused.';
  elsif new.kind = 'stop' and st not in ('running', 'paused') then
    raise exception '%', case st when 'stopped' then 'The timer is already stopped.' else 'Start the timer first.' end;
  elsif new.kind = 'reset' and st = 'none' then
    raise exception 'Start the timer before restarting it.';
  end if;
  if new.seq <> coalesce(last_seq, 0) + 1 then
    raise exception 'timer tap seq % does not follow % for reading %', new.seq, coalesce(last_seq, 0), new.reading_id;
  end if;
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  new.created_at := now();
  return new;
end;
$$;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261126030000', 'phil_iri_timer_review', false)
on conflict (id) do nothing;
