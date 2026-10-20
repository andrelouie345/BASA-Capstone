-- Sync: uploads from devices, reviewed and applied on the server.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261020010000.
-- App update required on all devices: yes (devices must run the sync release;
-- an older app's local work can only be uploaded by a sync-aware app).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Design: docs/superpowers/specs/2026-10-20-sync-design.md (section 2).
--
--  1. row_version on the 18 synced tables, bumped by a BEFORE UPDATE trigger.
--     A device sends the version each edit was based on; a moved-on version
--     is a conflict, never a silent overwrite.
--  2. report_settings keys sync_auto_approve (boolean) and
--     offline_signin_days (whole number 1-60).
--  3. sync_uploads: one row per device upload (the whole package as jsonb).
--  4. sync_withdraw / sync_reject / sync_apply. sync_apply is SECURITY
--     INVOKER and writes as the UPLOADER (the approver's approval is a
--     permission to apply, not a grant of their rights): every row passes the
--     uploader's RLS and the existing CHECKs and triggers. Status changes go through two SECURITY DEFINER
--     helpers in schema basa_private, which PostgREST does not expose.
--
-- RLS:
--  * sync_uploads insert: your own upload, your school, status pending,
--    no decision columns. select: the uploader, admins/coordinators of that
--    school, the superadmin. No update/delete for anyone through the API.
--  * sync_withdraw: the uploader, while pending or in conflict (a resolved
--    conflict is sent again as a new upload). sync_reject: admin/
--    coordinator of the school or superadmin, reason required. sync_apply:
--    those approvers, or the uploader when the school auto-approves or the
--    uploader is an admin/coordinator.
--  * anon: nothing on any object here.

-- ---------------------------------------------------------------------------
-- 1. row_version
-- ---------------------------------------------------------------------------

create or replace function public.basa_bump_row_version() returns trigger
  language plpgsql
  set search_path = public
as $$
begin
  new.row_version := old.row_version + 1;
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'crla_assessments', 'crla_part1_standard', 'crla_part1_english', 'crla_part2_fluency',
    'phil_iri_gst_results', 'phil_iri_assessments', 'phil_iri_readings', 'phil_iri_miscues',
    'phil_iri_answers', 'phil_iri_rubric_scores',
    'aral_enrollments', 'aral_sessions', 'aral_attendance', 'aral_tutor_settings',
    'aral_irip_weeks', 'aral_checkins', 'aral_checkin_answers', 'aral_readability_logs']
  loop
    execute format('alter table public.%I add column if not exists row_version bigint not null default 1', t);
    execute format('drop trigger if exists sync_row_version on public.%I', t);
    execute format('create trigger sync_row_version before update on public.%I '
                   'for each row execute function public.basa_bump_row_version()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 2. report_settings keys
-- ---------------------------------------------------------------------------

-- Stops (changes nothing) when a stored value already breaks a rule.
do $$
declare
  bad text;
begin
  select string_agg(format('id %s (school %s): %s', id, coalesce(school_id::text, 'region'), v), '; ' order by id)
    into bad
    from (
      select id, school_id, 'sync_auto_approve ' || (settings -> 'sync_auto_approve')::text as v
        from public.report_settings
       where settings ? 'sync_auto_approve'
         and jsonb_typeof(settings -> 'sync_auto_approve') <> 'boolean'
      union all
      select id, school_id, 'offline_signin_days ' || (settings -> 'offline_signin_days')::text
        from public.report_settings
       where settings ? 'offline_signin_days'
         and not (jsonb_typeof(settings -> 'offline_signin_days') = 'number'
                  and (settings ->> 'offline_signin_days')::numeric between 1 and 60
                  and (settings ->> 'offline_signin_days')::numeric = trunc((settings ->> 'offline_signin_days')::numeric))
    ) x;
  if bad is not null then
    raise exception 'report_settings has invalid sync values: %. Fix them, then run this migration again.', bad;
  end if;
end $$;

alter table public.report_settings drop constraint if exists report_settings_sync_auto_approve;
alter table public.report_settings add constraint report_settings_sync_auto_approve check (
  not (settings ? 'sync_auto_approve')
  or jsonb_typeof(settings -> 'sync_auto_approve') = 'boolean');

alter table public.report_settings drop constraint if exists report_settings_offline_signin_days;
alter table public.report_settings add constraint report_settings_offline_signin_days check (
  not (settings ? 'offline_signin_days')
  or (jsonb_typeof(settings -> 'offline_signin_days') = 'number'
      and (settings ->> 'offline_signin_days')::numeric between 1 and 60
      and (settings ->> 'offline_signin_days')::numeric = trunc((settings ->> 'offline_signin_days')::numeric)));

-- ---------------------------------------------------------------------------
-- 3. sync_uploads
-- ---------------------------------------------------------------------------

create table if not exists public.sync_uploads (
  id               bigint generated always as identity primary key,
  client_upload_id uuid not null unique,          -- made by the device; a retry finds the row
  uploader_id      uuid not null default auth.uid() references public.users(id),
  school_id        bigint references public.schools(id),  -- null only for a superadmin's upload
  device_id        uuid not null,
  release          text not null,                 -- the device's latest migration id
  status           text not null default 'pending'
    check (status in ('pending', 'applied', 'rejected', 'withdrawn', 'conflict', 'error')),
  payload          jsonb not null check (jsonb_typeof(payload) = 'object'),
  summary          jsonb not null default '{}' check (jsonb_typeof(summary) = 'object'),
  reason           text,                          -- reject reason or error message
  conflicts        jsonb,                         -- [{table, key, base_version, server_version, server_row}]
  id_map           jsonb,                         -- {table: {"-5": 812}}
  created_at       timestamptz not null default now(),
  decided_at       timestamptz,
  decided_by       uuid references public.users(id)
);
-- release = a migration id (14 digits), so the guard's comparison is sound.
alter table public.sync_uploads drop constraint if exists sync_uploads_release_format;
alter table public.sync_uploads add constraint sync_uploads_release_format check (release ~ '^[0-9]{14}$');
create index if not exists sync_uploads_school_status on public.sync_uploads (school_id, status);
create index if not exists sync_uploads_uploader on public.sync_uploads (uploader_id);

alter table public.sync_uploads enable row level security;
revoke all on public.sync_uploads from anon;
grant select, insert on public.sync_uploads to authenticated;
revoke update, delete, truncate on public.sync_uploads from authenticated;

drop policy if exists sync_uploads_insert on public.sync_uploads;
create policy sync_uploads_insert on public.sync_uploads
  for insert to authenticated
  with check (uploader_id = auth.uid()
              and current_user_role() is not null
              and school_id is not distinct from current_user_school_id()
              and status = 'pending'
              and reason is null and conflicts is null and id_map is null
              and decided_at is null and decided_by is null);

drop policy if exists sync_uploads_select on public.sync_uploads;
create policy sync_uploads_select on public.sync_uploads
  for select to authenticated
  using (uploader_id = auth.uid()
         or is_superadmin()
         or (current_user_role() in ('admin', 'coordinator')
             and school_id = current_user_school_id()));

-- May the signed-in user approve/reject uploads of this school?
create or replace function public.sync_is_approver(p_school_id bigint) returns boolean
  language sql stable security definer
  set search_path = public
as $$
  select is_superadmin()
      or coalesce(current_user_role() in ('admin', 'coordinator')
                  and p_school_id = current_user_school_id(), false);
$$;

-- Does this school auto-approve uploads? School row, else the region-wide
-- row (school_id null), else false.
create or replace function public.sync_auto_approve(p_school_id bigint) returns boolean
  language sql stable security definer
  set search_path = public
as $$
  select coalesce(
    (select (settings ->> 'sync_auto_approve')::boolean from public.report_settings
      where school_id = p_school_id and settings ? 'sync_auto_approve'),
    (select (settings ->> 'sync_auto_approve')::boolean from public.report_settings
      where school_id is null and settings ? 'sync_auto_approve'),
    false);
$$;

-- ---------------------------------------------------------------------------
-- 4. Status changes
-- ---------------------------------------------------------------------------

-- basa_private is not in PostgREST's exposed schemas, so clients cannot call
-- these helpers directly; sync_apply (running as the caller) can.
create schema if not exists basa_private;
revoke all on schema basa_private from public, anon;
grant usage on schema basa_private to authenticated;

-- Locks a pending upload for applying (the lock lasts until the caller's
-- transaction ends, so two approvers cannot both apply it) and returns it.
create or replace function basa_private.sync_claim(p_id bigint) returns public.sync_uploads
  language plpgsql security definer
  set search_path = public
as $$
declare
  u public.sync_uploads;
begin
  select * into u from public.sync_uploads where id = p_id for update;
  if not found then
    raise exception 'Upload % not found', p_id using errcode = 'P0002';
  end if;
  if u.status <> 'pending' then
    raise exception 'Upload % is %, not pending', p_id, u.status;
  end if;
  if not (sync_is_approver(u.school_id)
          or (u.uploader_id = auth.uid()
              and (current_user_role() in ('admin', 'coordinator') or sync_auto_approve(u.school_id)))) then
    raise exception 'Not allowed to apply upload %', p_id using errcode = '42501';
  end if;
  return u;
end;
$$;

-- Records the outcome of sync_apply. Same rights as sync_claim.
create or replace function basa_private.sync_finish(p_id bigint, p_status text, p_reason text,
                                                    p_conflicts jsonb, p_id_map jsonb) returns void
  language plpgsql security definer
  set search_path = public
as $$
begin
  if p_status not in ('applied', 'conflict', 'error') then
    raise exception 'Invalid outcome %', p_status;
  end if;
  perform basa_private.sync_claim(p_id);
  update public.sync_uploads
     set status = p_status, reason = p_reason, conflicts = p_conflicts, id_map = p_id_map,
         decided_at = now(), decided_by = auth.uid()
   where id = p_id;
end;
$$;

revoke all on function basa_private.sync_claim(bigint) from public, anon;
revoke all on function basa_private.sync_finish(bigint, text, text, jsonb, jsonb) from public, anon;
grant execute on function basa_private.sync_claim(bigint) to authenticated;
grant execute on function basa_private.sync_finish(bigint, text, text, jsonb, jsonb) to authenticated;

create or replace function public.sync_withdraw(p_id bigint) returns void
  language plpgsql security definer
  set search_path = public
as $$
declare
  u public.sync_uploads;
begin
  select * into u from public.sync_uploads where id = p_id for update;
  if not found or u.uploader_id is distinct from auth.uid() or current_user_role() is null then
    raise exception 'Only the uploader can withdraw upload %', p_id using errcode = '42501';
  end if;
  if u.status not in ('pending', 'conflict') then
    raise exception 'Upload % is %, not pending', p_id, u.status;
  end if;
  update public.sync_uploads
     set status = 'withdrawn', decided_at = now(), decided_by = auth.uid()
   where id = p_id;
end;
$$;

create or replace function public.sync_reject(p_id bigint, p_reason text) returns void
  language plpgsql security definer
  set search_path = public
as $$
declare
  u public.sync_uploads;
begin
  select * into u from public.sync_uploads where id = p_id for update;
  if not found or not sync_is_approver(u.school_id) then
    raise exception 'Not allowed to reject upload %', p_id using errcode = '42501';
  end if;
  if nullif(trim(p_reason), '') is null then
    raise exception 'A reason is required to reject an upload';
  end if;
  if u.status not in ('pending', 'conflict') then
    raise exception 'Upload % is %, not pending', p_id, u.status;
  end if;
  update public.sync_uploads
     set status = 'rejected', reason = trim(p_reason), decided_at = now(), decided_by = auth.uid()
   where id = p_id;
end;
$$;

revoke all on function public.sync_is_approver(bigint) from public, anon;
revoke all on function public.sync_auto_approve(bigint) from public, anon;
revoke all on function public.sync_withdraw(bigint) from public, anon;
revoke all on function public.sync_reject(bigint, text) from public, anon;
grant execute on function public.sync_is_approver(bigint) to authenticated;
grant execute on function public.sync_auto_approve(bigint) to authenticated;
grant execute on function public.sync_withdraw(bigint) to authenticated;
grant execute on function public.sync_reject(bigint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. sync_apply
-- ---------------------------------------------------------------------------

-- Key column of each synced table that is not keyed by id.
create or replace function basa_private.sync_key_column(p_table text) returns text
  language sql immutable
as $$
  select case p_table
    when 'crla_part1_standard' then 'assessment_id'
    when 'crla_part1_english' then 'assessment_id'
    when 'crla_part2_fluency' then 'assessment_id'
    when 'aral_tutor_settings' then 'tutor_id'
    else 'id' end;
$$;

-- Columns that may hold a device's negative id (a record in the same
-- upload), from the baseline's foreign keys. aral_enrollments' basis and
-- suggestion ids are polymorphic (CRLA or Phil-IRI); one device countdown
-- makes every negative id unique, so the map resolves them without the source.
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
    when 'aral_attendance' then array['session_id', 'enrollment_id']
    when 'aral_irip_weeks' then array['enrollment_id']
    when 'aral_checkins' then array['enrollment_id']
    when 'aral_checkin_answers' then array['checkin_id']
    when 'aral_readability_logs' then array['enrollment_id']
    when 'aral_enrollments' then array['basis_assessment_id', 'suggestion_assessment_id']
    else array[]::text[] end;
$$;

-- Checks a package's shape before anything is written. Returns null when it
-- is fine, else the problem. Table and column names are checked against the
-- 18 synced tables and the catalog, so sync_apply never builds SQL from an
-- unchecked name.
create or replace function basa_private.sync_check_payload(p jsonb) returns text
  language plpgsql stable
  set search_path = public
as $$
declare
  synced constant text[] := array[
    'crla_assessments', 'crla_part1_standard', 'crla_part1_english', 'crla_part2_fluency',
    'phil_iri_gst_results', 'phil_iri_assessments', 'phil_iri_readings', 'phil_iri_miscues',
    'phil_iri_answers', 'phil_iri_rubric_scores',
    'aral_enrollments', 'aral_sessions', 'aral_attendance', 'aral_tutor_settings',
    'aral_irip_weeks', 'aral_checkins', 'aral_checkin_answers', 'aral_readability_logs'];
  r jsonb;
  n int := 0;
  t text;
  op text;
  kc text;
  bad text;
  seen text[] := array[]::text[];
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
    if kc = 'tutor_id' then
      if jsonb_typeof(r -> 'key' -> kc) <> 'string' then
        return format('record %s (%s): %s must be a text id', n, t, kc);
      end if;
    elsif jsonb_typeof(r -> 'key' -> kc) <> 'number'
          or (r -> 'key' ->> kc)::numeric <> trunc((r -> 'key' ->> kc)::numeric) then
      return format('record %s (%s): %s must be a whole number', n, t, kc);
    elsif kc = 'id' and op = 'insert' and (r -> 'key' ->> 'id')::numeric >= 0 then
      return format('record %s (%s): a new record needs a negative device id', n, t);
    elsif kc = 'id' and op <> 'insert' and (r -> 'key' ->> 'id')::numeric <= 0 then
      return format('record %s (%s): only uploaded records can be changed or deleted', n, t);
    end if;
    if kc = 'id' and op = 'insert' then
      if (r -> 'key' ->> 'id') = any (seen) then
        return format('record %s (%s): device id %s is used twice in this upload', n, t, r -> 'key' ->> 'id');
      end if;
      seen := seen || (r -> 'key' ->> 'id');
    end if;
    if op in ('update', 'delete')
       and (jsonb_typeof(r -> 'base_version') is distinct from 'number'
            or (r ->> 'base_version')::numeric <> trunc((r ->> 'base_version')::numeric)) then
      return format('record %s (%s): base_version is missing', n, t);
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
    end if;
  end loop;
  return null;
end;
$$;

-- Applies a pending upload in one go. SECURITY INVOKER, with the signed-in
-- identity switched to the uploader for the writes (see below): every write
-- passes the uploader's RLS and the tables' CHECKs and triggers. Either
-- everything is written (applied) or nothing is (conflict / error).
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

  reason := basa_private.sync_check_payload(u.payload);
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
    for r in select value from jsonb_array_elements(u.payload -> 'records') loop
      t := r ->> 'table';
      op := r ->> 'op';
      kc := basa_private.sync_key_column(t);
      k := r -> 'key';
      rw := coalesce(r -> 'row', '{}');
      at := format('%s %s', t, k);

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
          execute format('update public.%I set (%s) = (select %s from jsonb_populate_record(null::public.%I, $1)) '
                         'where %I = (select %I from jsonb_populate_record(null::public.%I, $2)) and row_version = $3',
                         t, cols, cols, t, kc, kc, t)
            using rw, k, (r ->> 'base_version')::bigint;
        else
          execute format('delete from public.%I where %I = (select %I from jsonb_populate_record(null::public.%I, $1)) '
                         'and row_version = $2', t, kc, kc, t)
            using k, (r ->> 'base_version')::bigint;
        end if;
        get diagnostics n = row_count;
        if n = 0 then
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
    outcome := 'applied';
  exception
    when sqlstate 'BSY01' then
      outcome := 'conflict';
    when others then
      outcome := 'error';
      reason := at || ': ' || sqlerrm;
  end;

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

revoke all on function basa_private.sync_key_column(text) from public, anon;
revoke all on function basa_private.sync_ref_columns(text) from public, anon;
revoke all on function basa_private.sync_check_payload(jsonb) from public, anon;
revoke all on function public.sync_apply(bigint) from public, anon;
grant execute on function basa_private.sync_key_column(text) to authenticated;
grant execute on function basa_private.sync_ref_columns(text) to authenticated;
grant execute on function basa_private.sync_check_payload(jsonb) to authenticated;
grant execute on function public.sync_apply(bigint) to authenticated;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261020020000', 'sync_uploads', true)
on conflict (id) do nothing;
