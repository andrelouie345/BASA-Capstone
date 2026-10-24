-- ARAL classes: an upload is checked against the 15-learner cap and one
-- session per class per date as a whole, not record by record.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261024040000.
-- App update required on all devices: no (the same rules; only when the
-- server checks them inside an upload changes).
--
-- Why (final review 2026-10-24, C2): an upload carries each row's final
-- state, and sync_apply writes the records one by one. Work done offline in
-- several steps (take learner A out of full class X, put B in X, put A in
-- Y; or move a session off a date and log another on it) arrives as records
-- whose order can't satisfy a check made after every statement (a swap
-- between two full classes fails in every order), so the whole upload was
-- refused although its end state keeps every rule.
--
-- Change: the two checks that count rows of a class (15 active learners,
-- one session per date) move from the BEFORE triggers into AFTER constraint
-- triggers, DEFERRABLE INITIALLY IMMEDIATE: every write outside an upload
-- (the app's direct writes, the SQL Editor) is checked at once, as before,
-- with the same messages. sync_apply defers just these two while it writes
-- the records, then makes them immediate again inside its own error
-- handler, so a real violation is still the upload's error with a readable
-- reason (never a raw error at commit). The per-row checks (school and
-- year, program, a session needs a class) stay in the BEFORE triggers.

-- 1. Placement keeps its per-row checks; the cap moves to the constraint trigger.
create or replace function public.aral_check_class_placement(
  p_id bigint, p_class_id bigint, p_student_id bigint, p_section_id bigint, p_school_id bigint,
  p_school_year text, p_key_stage text, p_track text)
 returns void language plpgsql security definer set search_path to 'public'
as $$
declare
  c record;
begin
  perform pg_advisory_xact_lock(hashtext('aral_class:' || p_class_id::text));
  select school_id, school_year, program into c from public.aral_classes where id = p_class_id;
  if not found or c.school_id is distinct from p_school_id or c.school_year is distinct from p_school_year then
    raise exception 'the ARAL class belongs to another school or school year';
  end if;
  if c.program is not null and c.program is distinct from p_key_stage || coalesce('_' || p_track, '') then
    raise exception 'the learner''s program does not match the ARAL class';
  end if;
end;
$$;

-- An active learner who took a place (insert, class change, reactivation,
-- school or year change): the class holds at most 15 active learners.
-- Serialized per class, like placement.
create or replace function public.aral_enrollments_class_cap()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.class_id is null or new.status <> 'active' then
    return null;
  end if;
  if tg_op = 'UPDATE' and new.class_id is not distinct from old.class_id and old.status = 'active'
     and (new.school_id, new.school_year) is not distinct from (old.school_id, old.school_year) then
    return null; -- kept their place
  end if;
  perform pg_advisory_xact_lock(hashtext('aral_class:' || new.class_id::text));
  if (select count(*) from public.aral_enrollments where class_id = new.class_id and status = 'active') > 15 then
    raise exception 'an ARAL class has at most 15 active learners';
  end if;
  return null;
end;
$$;

drop trigger if exists aral_enrollments_class_cap on public.aral_enrollments;
create constraint trigger aral_enrollments_class_cap
  after insert or update on public.aral_enrollments
  deferrable initially immediate
  for each row execute function public.aral_enrollments_class_cap();

-- 2. Sessions: numbering stays in the BEFORE trigger; the date check moves.
create or replace function public.aral_sessions_before_insert()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  c record;
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  new.created_at := now();
  new.updated_at := now();
  if new.class_id is null then
    raise exception 'a new ARAL session needs a class';
  end if;
  select school_id, school_year into c from public.aral_classes where id = new.class_id;
  if not found or c.school_id is distinct from new.school_id or c.school_year is distinct from new.school_year then
    raise exception 'the ARAL class belongs to another school or school year';
  end if;
  -- serialize numbering per class
  perform pg_advisory_xact_lock(hashtext('aral_class_sessions:' || new.class_id::text));
  select coalesce(max(session_no), 0) + 1 into new.session_no
  from public.aral_sessions where class_id = new.class_id;
  perform aral_check_tutor(new.tutor_id, new.school_id);
  return new;
end;
$$;

create or replace function public.aral_sessions_before_update()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if auth.uid() is null then
    return new; -- SQL Editor maintenance
  end if;
  if (new.tutor_id, new.class_id, new.school_id, new.school_year, new.session_no, new.created_by, new.created_at)
     is distinct from
     (old.tutor_id, old.class_id, old.school_id, old.school_year, old.session_no, old.created_by, old.created_at) then
    raise exception 'an ARAL session keeps its tutor, class, school, year and number; only the date, minutes, set-up, lesson and remarks change';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- One session per class per date (inserts and date changes; SQL Editor
-- maintenance too). Sessions from before classes have no class: no check.
create or replace function public.aral_sessions_one_per_day()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.class_id is null then
    return null;
  end if;
  if tg_op = 'UPDATE' and new.held_on is not distinct from old.held_on then
    return null;
  end if;
  perform pg_advisory_xact_lock(hashtext('aral_class_sessions:' || new.class_id::text));
  perform aral_check_session_day(new.id, new.class_id, new.held_on);
  return null;
end;
$$;

drop trigger if exists aral_sessions_one_per_day on public.aral_sessions;
create constraint trigger aral_sessions_one_per_day
  after insert or update on public.aral_sessions
  deferrable initially immediate
  for each row execute function public.aral_sessions_one_per_day();

-- 3. sync_apply (as in 20261021010000) defers the two checks while it writes.
create or replace function public.sync_apply(p_id bigint) returns jsonb
  language plpgsql security invoker
  set search_path = public
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

  if reason is not null then
    perform basa_private.sync_finish(p_id, 'error', reason, null, null);
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
    set constraints public.aral_enrollments_class_cap, public.aral_sessions_one_per_day deferred;
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
    set constraints public.aral_enrollments_class_cap, public.aral_sessions_one_per_day immediate;
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
  set constraints public.aral_enrollments_class_cap, public.aral_sessions_one_per_day immediate;
  perform set_config('request.jwt.claim.sub', coalesce(my_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(my_claims, ''), true);

  perform basa_private.sync_finish(p_id, outcome, reason,
    case when outcome = 'conflict' then conflicts end,
    case when outcome = 'applied' then id_map end);
  return jsonb_build_object('status', outcome, 'reason', reason,
    'conflicts', case when outcome = 'conflict' then conflicts end,
    'id_map', case when outcome = 'applied' then id_map end);
end;
$$;

revoke all on function public.sync_apply(bigint) from public, anon;
grant execute on function public.sync_apply(bigint) to authenticated;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261024050000', 'aral_upload_end_state_checks', false)
on conflict (id) do nothing;
