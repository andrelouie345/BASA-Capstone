-- Digitized Phil-IRI oral reading: a reading timed in BASA, with its timing
-- log as evidence (spec docs/superpowers/specs/2026-11-26-phil-iri-timed-reading-design.md,
-- consultation item M1-01).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261125030000.
-- App update required on all devices: yes (a new synced table: an older app
-- can't pull or upload it).
--
-- 1. phil_iri_reading_timer_events: one row per tap of a reading's timer
--    (start, pause, resume, stop, reset), only ever added. The taps after the
--    last reset count: start, pause/resume pairs, stop. The same order and
--    time rules are in lib/core/services/phil_iri_timer.dart and the device's
--    trigger (phil_iri_local_schema.dart); change the three together.
-- 2. The evidence check (D8): a reading with a timing log keeps a recorded
--    time only when it matches the log. Whole text / silent: reading_seconds,
--    when set, = the log's seconds (stop - start - pauses, rounded down) of a
--    stopped log; one minute: no reading_seconds, and a stopped log is exactly
--    60 s of reading time. A constraint trigger on both tables; sync_apply
--    defers it to the end of an upload like the ARAL end-state checks, so a
--    mismatch refuses the upload ("the upload as a whole: ...").
-- 3. Sync: the table is synced (payload list, ref columns); sync_apply is the
--    20261112020000 body with the two new constraints in its deferred lists,
--    statement_timeout 60s kept (20261125030000).
--
-- RLS: new table phil_iri_reading_timer_events: select = its reading is
-- readable (the reading's own read policy, as 20261125020000); insert = its
-- reading is writable (phil_iri_reading_writable, as miscues); no update or
-- delete policy (insert-only). Grants per 20261025010000. No other policy
-- changes.

-- ---------------------------------------------------------------------------
-- 1. The timing log
-- ---------------------------------------------------------------------------
create table if not exists public.phil_iri_reading_timer_events (
  id           bigint generated always as identity primary key,
  reading_id   bigint not null references public.phil_iri_readings(id) on delete cascade,
  seq          integer not null check (seq >= 1),
  kind         text not null check (kind in ('start', 'pause', 'resume', 'stop', 'reset')),
  at           timestamptz not null,
  created_by   uuid references public.users(id),
  created_at   timestamptz not null default now(),
  row_version  bigint not null default 1,
  constraint phil_iri_reading_timer_events_seq unique (reading_id, seq)
);

-- The current segment's status of a reading's log: none / running / paused /
-- stopped (the taps after the last reset).
create or replace function basa_private.phil_iri_timer_status(p_reading_id bigint) returns text
  language sql stable security definer set search_path = public
as $$
  select coalesce((
    select case e.kind when 'stop' then 'stopped' when 'pause' then 'paused' when 'reset' then 'none' else 'running' end
    from public.phil_iri_reading_timer_events e
    where e.reading_id = p_reading_id
    order by e.seq desc limit 1), 'none');
$$;

-- The reading time of the current segment in milliseconds, up to its last
-- pause or stop.
create or replace function basa_private.phil_iri_timer_elapsed_ms(p_reading_id bigint) returns bigint
  language sql stable security definer set search_path = public
as $$
  with seg as (
    select e.kind, e.at, lead(e.at) over (order by e.seq) as next_at, lead(e.kind) over (order by e.seq) as next_kind
    from public.phil_iri_reading_timer_events e
    where e.reading_id = p_reading_id
      and e.seq > coalesce((select max(r.seq) from public.phil_iri_reading_timer_events r
                             where r.reading_id = p_reading_id and r.kind = 'reset'), 0)
  )
  select coalesce(sum(floor(extract(epoch from (next_at - at)) * 1000))::bigint, 0)
  from seg where kind in ('start', 'resume') and next_kind in ('pause', 'stop');
$$;

create or replace function public.check_phil_iri_timer_event() returns trigger
  language plpgsql security definer set search_path = public
as $$
declare
  st text;
  last_seq integer;
  last_at timestamptz;
  r record;
begin
  -- One tap at a time per reading.
  select rd.id, rd.passage_id into r from public.phil_iri_readings rd where rd.id = new.reading_id for update;
  if not found then
    raise exception 'reading % not found', new.reading_id;
  end if;
  if r.passage_id is null then
    raise exception 'This reading was imported without a passage (Untitled) and cannot be timed.';
  end if;
  select max(e.seq), max(e.at) into last_seq, last_at
    from public.phil_iri_reading_timer_events e where e.reading_id = new.reading_id;
  if last_at is not null and new.at < last_at then
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

drop trigger if exists check_phil_iri_timer_event on public.phil_iri_reading_timer_events;
create trigger check_phil_iri_timer_event before insert on public.phil_iri_reading_timer_events
  for each row execute function public.check_phil_iri_timer_event();

drop trigger if exists sync_row_version on public.phil_iri_reading_timer_events;
create trigger sync_row_version before update on public.phil_iri_reading_timer_events
  for each row execute function public.basa_bump_row_version();

alter table public.phil_iri_reading_timer_events enable row level security;

drop policy if exists phil_iri_reading_timer_events_select on public.phil_iri_reading_timer_events;
create policy phil_iri_reading_timer_events_select on public.phil_iri_reading_timer_events for select to authenticated
  using (exists (select 1 from public.phil_iri_readings r where r.id = reading_id));

drop policy if exists phil_iri_reading_timer_events_insert on public.phil_iri_reading_timer_events;
create policy phil_iri_reading_timer_events_insert on public.phil_iri_reading_timer_events for insert to authenticated
  with check (public.phil_iri_reading_writable(reading_id));

revoke all on public.phil_iri_reading_timer_events from anon;
grant select, insert, update, delete on public.phil_iri_reading_timer_events to authenticated, service_role;
revoke all on function basa_private.phil_iri_timer_status(bigint) from public, anon;
revoke all on function basa_private.phil_iri_timer_elapsed_ms(bigint) from public, anon;
grant execute on function basa_private.phil_iri_timer_status(bigint) to authenticated;
grant execute on function basa_private.phil_iri_timer_elapsed_ms(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The evidence check (D8)
-- ---------------------------------------------------------------------------
-- Null when the reading's recorded time fits its timing log (or it has none),
-- else the refusal naming the learner and the passage.
create or replace function basa_private.phil_iri_timed_reading_problem(p_reading_id bigint) returns text
  language plpgsql stable security definer set search_path = public
as $$
declare
  r record;
  st text;
  ms bigint;
  bad boolean;
begin
  if not exists (select 1 from public.phil_iri_reading_timer_events e where e.reading_id = p_reading_id) then
    return null; -- typed timing: unchanged rules
  end if;
  select rd.method, rd.reading_seconds, s.last_name, s.first_name, p.title into r
    from public.phil_iri_readings rd
    join public.phil_iri_assessments a on a.id = rd.assessment_id
    join public.students s on s.id = a.student_id
    left join public.phil_iri_passages p on p.id = rd.passage_id
   where rd.id = p_reading_id;
  if not found then
    return null; -- the reading is being deleted with its log
  end if;
  st := basa_private.phil_iri_timer_status(p_reading_id);
  ms := basa_private.phil_iri_timer_elapsed_ms(p_reading_id);
  if r.method = 'one_minute' then
    bad := r.reading_seconds is not null or (st = 'stopped' and ms / 1000 <> 60);
  else
    bad := r.reading_seconds is not null and (st <> 'stopped' or r.reading_seconds <> ms / 1000);
  end if;
  if bad then
    return format('The reading of %s, %s (%s) has a time that doesn''t match its timer.',
                  r.last_name, r.first_name, coalesce(r.title, 'Untitled'));
  end if;
  return null;
end;
$$;
revoke all on function basa_private.phil_iri_timed_reading_problem(bigint) from public, anon;
grant execute on function basa_private.phil_iri_timed_reading_problem(bigint) to authenticated;

create or replace function public.phil_iri_timed_reading_check() returns trigger
  language plpgsql security definer set search_path = public
as $$
declare
  problem text;
  rid bigint;
begin
  -- Two tables share this check: a reading row has no reading_id.
  if tg_table_name = 'phil_iri_readings' then
    rid := new.id;
  else
    rid := new.reading_id;
  end if;
  problem := basa_private.phil_iri_timed_reading_problem(rid);
  if problem is not null then
    raise exception '%', problem;
  end if;
  return null;
end;
$$;

drop trigger if exists phil_iri_timed_reading_check on public.phil_iri_readings;
create constraint trigger phil_iri_timed_reading_check
  after insert or update of reading_seconds, words_read on public.phil_iri_readings
  deferrable initially immediate
  for each row execute function public.phil_iri_timed_reading_check();

drop trigger if exists phil_iri_timer_events_check on public.phil_iri_reading_timer_events;
create constraint trigger phil_iri_timer_events_check
  after insert on public.phil_iri_reading_timer_events
  deferrable initially immediate
  for each row execute function public.phil_iri_timed_reading_check();

-- ---------------------------------------------------------------------------
-- 3. Sync: the timing log is a synced table
-- ---------------------------------------------------------------------------
create or replace function basa_private.sync_ref_columns(p_table text) returns text[]
  language sql immutable
as $$
  select case p_table
    when 'crla_part1_standard' then array['assessment_id']
    when 'crla_part1_english' then array['assessment_id']
    when 'crla_part2_fluency' then array['assessment_id']
    when 'phil_iri_readings' then array['assessment_id']
    when 'phil_iri_rubric_scores' then array['assessment_id']
    when 'phil_iri_miscues' then array['reading_id']
    when 'phil_iri_answers' then array['reading_id']
    when 'phil_iri_reading_timer_events' then array['reading_id']
    when 'aral_attendance' then array['session_id', 'enrollment_id']
    when 'aral_irip_weeks' then array['enrollment_id']
    when 'aral_checkins' then array['enrollment_id']
    when 'aral_checkin_answers' then array['checkin_id']
    when 'aral_readability_logs' then array['enrollment_id']
    when 'aral_enrollments' then array['basis_assessment_id', 'suggestion_assessment_id', 'class_id']
    when 'aral_sessions' then array['class_id']
    else array[]::text[] end;
$$;


create or replace function basa_private.sync_check_payload(p jsonb) returns text
  language plpgsql stable
  set search_path = public
as $$
declare
  synced constant text[] := array[
    'crla_assessments', 'crla_part1_standard', 'crla_part1_english', 'crla_part2_fluency',
    'phil_iri_gst_results', 'phil_iri_assessments', 'phil_iri_readings', 'phil_iri_miscues',
    'phil_iri_answers', 'phil_iri_rubric_scores', 'phil_iri_workbook_imports',
    'phil_iri_reading_timer_events',
    'aral_classes', 'aral_enrollments', 'aral_sessions', 'aral_attendance',
    'aral_irip_weeks', 'aral_checkins', 'aral_checkin_answers', 'aral_readability_logs'];
  r jsonb;
  n int := 0;
  t text;
  op text;
  kc text;
  bad text;
  followup boolean;
  seen text[] := array[]::text[];
  written text[] := array[]::text[];  -- 'table:key' of inserts and updates so far
begin
  if jsonb_typeof(p -> 'format') is distinct from 'number' or p ->> 'format' <> '1' then
    return 'unknown package format ' || coalesce(p ->> 'format', 'none');
  end if;
  if jsonb_typeof(p -> 'records') is distinct from 'array' then
    return 'the package has no record list';
  end if;
  for r in select value from jsonb_array_elements(p -> 'records') loop
    n := n + 1;
    if jsonb_typeof(r) <> 'object' then
      return format('record %s is not an object', n);
    end if;
    t := r ->> 'table';
    op := r ->> 'op';
    if t is null or not (t = any (synced)) then
      return format('record %s: table %s is not synced', n, coalesce(t, 'none'));
    end if;
    if op is null or op not in ('insert', 'update', 'delete') then
      return format('record %s (%s): unknown operation %s', n, t, coalesce(op, 'none'));
    end if;
    kc := basa_private.sync_key_column(t);
    if jsonb_typeof(r -> 'key') is distinct from 'object'
       or (select array_agg(k) from jsonb_object_keys(r -> 'key') k) is distinct from array[kc] then
      return format('record %s (%s): the key must be {%s}', n, t, kc);
    end if;
    -- Follow-up: an update without base_version of a record written earlier
    -- in this package.
    followup := op = 'update' and not (r ? 'base_version');
    if followup and not (t || ':' || (r -> 'key' ->> kc)) = any (written) then
      return format('record %s (%s): an update without base_version must follow the same record in this upload', n, t);
    end if;
    if kc = 'tutor_id' then
      if jsonb_typeof(r -> 'key' -> kc) <> 'string' then
        return format('record %s (%s): %s must be a text id', n, t, kc);
      end if;
    elsif jsonb_typeof(r -> 'key' -> kc) <> 'number'
          or (r -> 'key' ->> kc)::numeric <> trunc((r -> 'key' ->> kc)::numeric) then
      return format('record %s (%s): %s must be a whole number', n, t, kc);
    elsif kc = 'id' and op = 'insert' and (r -> 'key' ->> 'id')::numeric >= 0 then
      return format('record %s (%s): a new record needs a negative device id', n, t);
    elsif kc = 'id' and op <> 'insert' and not followup and (r -> 'key' ->> 'id')::numeric <= 0 then
      return format('record %s (%s): only uploaded records can be changed or deleted', n, t);
    end if;
    if kc = 'id' and op = 'insert' then
      if (r -> 'key' ->> 'id') = any (seen) then
        return format('record %s (%s): device id %s is used twice in this upload', n, t, r -> 'key' ->> 'id');
      end if;
      seen := seen || (r -> 'key' ->> 'id');
    end if;
    if op = 'delete' or (op = 'update' and not followup) then
      if jsonb_typeof(r -> 'base_version') is distinct from 'number'
         or (r ->> 'base_version')::numeric <> trunc((r ->> 'base_version')::numeric) then
        return format('record %s (%s): base_version is missing', n, t);
      end if;
    end if;
    if op in ('insert', 'update') then
      if jsonb_typeof(r -> 'row') is distinct from 'object' then
        return format('record %s (%s): the row is not an object', n, t);
      end if;
      select string_agg(k, ', ') into bad
        from jsonb_object_keys(r -> 'row') k
       where not exists (select 1 from pg_attribute a
                          where a.attrelid = format('public.%I', t)::regclass
                            and a.attname = k and a.attnum > 0 and not a.attisdropped);
      if bad is not null then
        return format('record %s (%s): unknown column(s) %s', n, t, bad);
      end if;
      if r -> 'row' ? kc and r -> 'row' -> kc <> r -> 'key' -> kc then
        return format('record %s (%s): the row''s %s differs from its key', n, t, kc);
      end if;
      written := written || (t || ':' || (r -> 'key' ->> kc));
    end if;
  end loop;
  return null;
end;
$$;


create or replace function public.sync_apply(p_id bigint) returns jsonb
  language plpgsql security invoker
  set search_path = public
  set statement_timeout = '60s'
as $$
declare
  u public.sync_uploads;
  r jsonb;
  t text;
  op text;
  kc text;
  k jsonb;            -- the record's key, its references rewritten
  rw jsonb;           -- the row to write
  col text;
  cols text;
  v text;
  new_id bigint;
  n int;
  server jsonb;
  ref_map jsonb := '{}';    -- "-5" -> 812, all tables (one device countdown)
  id_map jsonb := '{}';     -- {table: {"-5": 812}}
  conflicts jsonb := '[]';
  at text := '';
  outcome text;
  reason text;
  my_sub text;
  my_claims text;
  sec bigint;
  followed int := 0;        -- records re-pointed to a moved learner's section
  note text;
begin
  u := basa_private.sync_claim(p_id);

  -- Release guard: rules changed since the device's release; status stays
  -- pending so the tutor can withdraw it and send it again after updating.
  if exists (select 1 from public.basa_migrations
              where app_update_required and id > u.release) then
    raise exception 'Upload % was made by an older BASA release (%); update the device and sync again',
      p_id, u.release;
  end if;

  if not exists (select 1 from public.basa_migrations where id = u.release) then
    raise exception 'Upload % was made by BASA release %, which this server does not have',
      p_id, u.release;
  end if;

  reason := basa_private.sync_check_payload(u.payload);
  if reason is not null then
    perform basa_private.sync_finish(p_id, 'error', reason, null, null, null);
    return jsonb_build_object('status', 'error', 'reason', reason);
  end if;

  -- The approval is a permission to apply, not a grant of the approver's
  -- rights (owner 2026-10-20): the writes run as the UPLOADER, so a package
  -- can only do what its uploader could do directly, created_by stamps the
  -- uploader, and conflicts only show rows the uploader may read. auth.uid()
  -- reads request.jwt.claim.sub, else the sub in request.jwt.claims
  -- (PostgREST 12+); both are switched for this transaction and restored
  -- before the outcome is recorded (decided_by = the approver).
  my_sub := current_setting('request.jwt.claim.sub', true);
  my_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claim.sub', u.uploader_id::text, true);
  perform set_config('request.jwt.claims',
    jsonb_set(coalesce(nullif(my_claims, '')::jsonb, '{}'), '{sub}', to_jsonb(u.uploader_id::text))::text, true);

  begin
    -- The class cap and the one-session-per-date rule hold for the upload's
    -- end state (C2): checked after the last record, below.
    set constraints public.aral_enrollments_class_cap, public.aral_sessions_one_per_day,
      public.phil_iri_timed_reading_check, public.phil_iri_timer_events_check deferred;
    for r in select value from jsonb_array_elements(u.payload -> 'records') loop
      t := r ->> 'table';
      op := r ->> 'op';
      kc := basa_private.sync_key_column(t);
      k := r -> 'key';
      rw := coalesce(r -> 'row', '{}');
      at := format('%s %s', t, k);

      -- Follow-up update of a record inserted earlier in this upload: its
      -- key is the device id; use the server's.
      if kc = 'id' and op = 'update' and (k ->> 'id')::bigint < 0 then
        v := k ->> 'id';
        if not ref_map ? v then
          raise exception '%.id = % is not in this upload', t, v;
        end if;
        k := jsonb_build_object('id', (ref_map ->> v)::bigint);
      end if;

      -- Rewrite references to records of this upload (negative ids).
      foreach col in array basa_private.sync_ref_columns(t) loop
        if col = kc and (k ->> kc)::bigint < 0 then
          v := k ->> kc;
          if not ref_map ? v then
            raise exception '%.% = % is not in this upload', t, col, v;
          end if;
          k := jsonb_build_object(kc, (ref_map ->> v)::bigint);
        end if;
        if jsonb_typeof(rw -> col) = 'number' and (rw ->> col)::bigint < 0 then
          v := rw ->> col;
          if not ref_map ? v then
            raise exception '%.% = % is not in this upload', t, col, v;
          end if;
          rw := rw || jsonb_build_object(col, (ref_map ->> v)::bigint);
        end if;
      end loop;

      -- Never written by a device: the key (from k), the version, generated columns.
      rw := rw - kc - 'row_version';
      rw := rw - coalesce((select array_agg(attname::text) from pg_attribute
                            where attrelid = format('public.%I', t)::regclass
                              and attnum > 0 and attgenerated <> ''), array[]::text[]);

      -- A learner who moved or was archived since the device's copy (D11):
      -- this year's new records follow them to their current section; an
      -- archived learner stops the upload.
      if op = 'insert' and t in ('crla_assessments', 'phil_iri_assessments', 'phil_iri_gst_results') then
        sec := basa_private.sync_learner_section(rw);
        if sec is not null then
          rw := rw || jsonb_build_object('section_id', sec);
          followed := followed + 1;
        end if;
      end if;

      if op = 'insert' then
        if kc <> 'id' then
          rw := rw || k;
        end if;
        select string_agg(format('%I', c), ', ') into cols from jsonb_object_keys(rw) c;
        if kc = 'id' then
          execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1) returning id',
                         t, cols, cols, t)
            into new_id using rw;
          ref_map := ref_map || jsonb_build_object(k ->> 'id', new_id);
          id_map := id_map || jsonb_build_object(t, coalesce(id_map -> t, '{}') || jsonb_build_object(k ->> 'id', new_id));
        else
          execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1)',
                         t, cols, cols, t)
            using rw;
        end if;
      else
        if op = 'update' then
          select string_agg(format('%I', c), ', ') into cols from jsonb_object_keys(rw) c;
          if cols is null then
            raise exception 'nothing to change';
          end if;
          -- $3 null = follow-up (no version check; see the header).
          execute format('update public.%I set (%s) = (select %s from jsonb_populate_record(null::public.%I, $1)) '
                         'where %I = (select %I from jsonb_populate_record(null::public.%I, $2)) '
                         'and ($3::bigint is null or row_version = $3)',
                         t, cols, cols, t, kc, kc, t)
            using rw, k, (r ->> 'base_version')::bigint;
        else
          execute format('delete from public.%I where %I = (select %I from jsonb_populate_record(null::public.%I, $1)) '
                         'and row_version = $2', t, kc, kc, t)
            using k, (r ->> 'base_version')::bigint;
        end if;
        get diagnostics n = row_count;
        if n = 0 and op = 'update' and not (r ? 'base_version') then
          raise exception 'follow-up update found no row';
        elsif n = 0 then
          -- Version moved on, deleted, or no longer visible to the caller.
          execute format('select to_jsonb(x) from public.%I x where %I = (select %I from jsonb_populate_record(null::public.%I, $1))',
                         t, kc, kc, t)
            into server using k;
          conflicts := conflicts || jsonb_build_array(jsonb_build_object(
            'table', t, 'key', r -> 'key', 'base_version', r -> 'base_version',
            'server_version', server -> 'row_version', 'server_row', server));
        end if;
      end if;
    end loop;

    if jsonb_array_length(conflicts) > 0 then
      raise exception 'sync conflict' using errcode = 'BSY01';
    end if;
    at := 'the upload as a whole';
    set constraints public.aral_enrollments_class_cap, public.aral_sessions_one_per_day,
      public.phil_iri_timed_reading_check, public.phil_iri_timer_events_check immediate;
    outcome := 'applied';
  exception
    when sqlstate 'BSY01' then
      outcome := 'conflict';
    when others then
      outcome := 'error';
      reason := at || ': ' || sqlerrm;
  end;

  -- Back to immediate for the rest of the caller's transaction (nothing is
  -- pending here: applied rows were checked, refused ones rolled back).
  set constraints public.aral_enrollments_class_cap, public.aral_sessions_one_per_day,
      public.phil_iri_timed_reading_check, public.phil_iri_timer_events_check immediate;
  perform set_config('request.jwt.claim.sub', coalesce(my_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(my_claims, ''), true);

  if outcome = 'applied' and followed > 0 then
    note := case when followed = 1 then '1 record followed a section move'
                 else followed || ' records followed a section move' end;
  end if;
  perform basa_private.sync_finish(p_id, outcome, reason,
    case when outcome = 'conflict' then conflicts end,
    case when outcome = 'applied' then id_map end,
    note);
  return jsonb_build_object('status', outcome, 'reason', reason,
    'conflicts', case when outcome = 'conflict' then conflicts end,
    'id_map', case when outcome = 'applied' then id_map end,
    'note', note);
end;
$$;


revoke all on function basa_private.sync_check_payload(jsonb) from public, anon;
grant execute on function basa_private.sync_check_payload(jsonb) to authenticated;
revoke all on function public.sync_apply(bigint) from public, anon;
grant execute on function public.sync_apply(bigint) to authenticated;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261126010000', 'phil_iri_timed_reading', true)
on conflict (id) do nothing;
