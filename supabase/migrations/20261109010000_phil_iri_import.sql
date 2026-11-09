-- Phil-IRI import: imported sessions, miscues without a position, the
-- workbook's correct count, and a one-time workbook import lock.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261029010000.
-- App update required on all devices: yes (miscues without a word position
-- and the new lock table: older apps can't read or sync them).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Spec: docs/superpowers/specs/2026-11-09-phil-iri-import-design.md
-- Results are imported as raw data only (ma's workbook, BASA scoresheet
-- files) and written on a coordinator's device; they arrive here through the
-- normal upload (sync_apply).
--
-- Changes:
--  1. phil_iri_assessments.import_source: 'workbook' | 'scoresheet', null =
--     live. Set at insert only by an admin/coordinator of the school or the
--     superadmin; never changed afterwards.
--  2. Imported sessions skip the reading checks for the round's passages,
--     the no-repeat rule and the active passage; the own-grade check stays
--     (spec D8). Their readings still count for the no-repeat rule of later
--     live readings.
--  3. phil_iri_miscues.word_index may be null ("position not recorded"),
--     only on a reading of an imported session (spec D3).
--  4. phil_iri_readings.imported_correct: the workbook's comprehension count
--     (0..the passage's questions), only on a workbook session, never
--     together with answer rows.
--  5. phil_iri_workbook_imports: one row per section and school year whose
--     workbook was imported (the one-time switch, spec D10). Synced: it
--     travels in the same upload as the section's sessions, so the unique key
--     refuses a second coordinator's upload in one transaction.
--
-- RLS: phil_iri_workbook_imports select/insert for the superadmin and the
-- school's own admin/coordinator (checked on the row's own columns, F14);
-- no update or delete for anyone through the API. Other tables: policies
-- unchanged; the new rules live in their triggers.
-- Grants: phil_iri_workbook_imports to authenticated and service_role
-- (select/insert/update/delete), nothing to anon.

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------

alter table public.phil_iri_assessments add column if not exists import_source text;
alter table public.phil_iri_assessments drop constraint if exists phil_iri_assessments_import_source_check;
alter table public.phil_iri_assessments add constraint phil_iri_assessments_import_source_check
  check (import_source in ('workbook', 'scoresheet'));

alter table public.phil_iri_readings add column if not exists imported_correct integer;
alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_imported_correct_check;
alter table public.phil_iri_readings add constraint phil_iri_readings_imported_correct_check
  check (imported_correct >= 0);

alter table public.phil_iri_miscues alter column word_index drop not null;

-- ---------------------------------------------------------------------------
-- 2. Sessions: who may import, and the mark never changes
-- ---------------------------------------------------------------------------

create or replace function public.phil_iri_assessments_before_insert() returns trigger
  language plpgsql security definer
  set search_path = public
as $$
begin
  select coalesce(max(attempt_no), 0) + 1 into new.attempt_no
  from public.phil_iri_assessments
  where student_id = new.student_id and school_id = new.school_id
    and section_id = new.section_id and round = new.round
    and school_year = new.school_year;
  if auth.uid() is not null then
    if new.import_source is not null
       and not (is_superadmin()
                or (current_user_role() in ('admin', 'coordinator') and new.school_id = current_user_school_id())) then
      raise exception 'only an admin or coordinator of the school imports Phil-IRI results';
    end if;
    new.administered_by := auth.uid();
    new.status := 'in_progress';
    new.completed_at := null;
    new.finalized_at := null;
    new.thresholds_snapshot := null;
  end if;
  return new;
end;
$$;

create or replace function public.phil_iri_assessments_before_update() returns trigger
  language plpgsql security definer
  set search_path = public
as $$
begin
  if auth.uid() is null then
    return new; -- SQL Editor maintenance
  end if;
  if old.status = 'finalized' then
    raise exception 'a finalized Phil-IRI assessment cannot be changed';
  end if;
  if (new.student_id, new.school_id, new.section_id, new.school_year, new.round,
      new.attempt_no, new.administered_by, new.assessed_at, new.import_source)
     is distinct from
     (old.student_id, old.school_id, old.section_id, old.school_year, old.round,
      old.attempt_no, old.administered_by, old.assessed_at, old.import_source) then
    raise exception 'only the status of a Phil-IRI assessment can change';
  end if;

  if new.status = 'finalized' then
    if not (is_superadmin() or current_user_role() in ('admin', 'coordinator')) then
      raise exception 'only an admin or coordinator can finalize a Phil-IRI assessment';
    end if;
    if old.status <> 'completed' then
      raise exception 'only a completed Phil-IRI assessment can be finalized';
    end if;
    if new.thresholds_snapshot is null then
      raise exception 'finalizing needs the thresholds snapshot';
    end if;
    new.finalized_at := now();
    new.completed_at := old.completed_at;
  else
    new.thresholds_snapshot := null;
    new.finalized_at := null;
    if new.status = 'completed' and old.status = 'in_progress' then
      new.completed_at := now();
    elsif new.status = 'in_progress' then
      new.completed_at := null;
    else
      new.completed_at := old.completed_at;
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Readings: imported sessions skip the round, active and no-repeat checks
-- ---------------------------------------------------------------------------

create or replace function public.check_phil_iri_reading() returns trigger
  language plpgsql security definer
  set search_path = public
as $$
declare
  v_level integer;
  v_graded boolean;
  v_active boolean;
  v_grade integer;
  v_test_type text;
  v_round text;
  v_year text;
  v_student bigint;
  v_read_title text;
  v_import text;
  v_questions integer;
begin
  if auth.uid() is null then
    return new;
  end if;
  if not phil_iri_assessment_writable(new.assessment_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  if tg_op = 'UPDATE' and (new.assessment_id, new.passage_id, new.method)
                          is distinct from (old.assessment_id, old.passage_id, old.method) then
    raise exception 'a reading keeps its session, passage and method; delete it and add a new one instead';
  end if;
  if not phil_iri_passage_readable(new.passage_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select a.import_source into v_import from public.phil_iri_assessments a where a.id = new.assessment_id;
  select p.level, c.is_grade_leveled, p.is_active and c.is_active, p.test_type
    into v_level, v_graded, v_active, v_test_type
  from public.phil_iri_passages p
  join public.phil_iri_collections c on c.id = p.collection_id
  where p.id = new.passage_id;
  if tg_op = 'INSERT' and not v_active and v_import is null then
    raise exception 'this passage or its collection is not active';
  end if;
  if v_graded then
    select phil_iri_section_grade(a.section_id) into v_grade
    from public.phil_iri_assessments a where a.id = new.assessment_id;
    if v_level is distinct from v_grade then
      raise exception 'a Grade % learner reads a Grade % passage (got a Grade % passage)', v_grade, v_grade, v_level;
    end if;
  end if;
  if new.imported_correct is not null then
    if v_import is distinct from 'workbook' then
      raise exception 'an imported correct count belongs to a reading imported from the workbook';
    end if;
    select count(*) into v_questions from public.phil_iri_questions where passage_id = new.passage_id;
    if new.imported_correct > v_questions then
      raise exception 'imported correct count % is more than the passage''s % questions', new.imported_correct, v_questions;
    end if;
    if tg_op = 'UPDATE' and exists (select 1 from public.phil_iri_answers where reading_id = new.id) then
      raise exception 'this reading has answers; an imported correct count replaces answers, not both';
    end if;
  end if;
  if tg_op = 'INSERT' and v_import is null then
    select a.round, a.school_year, a.student_id into v_round, v_year, v_student
    from public.phil_iri_assessments a where a.id = new.assessment_id;
    if v_test_type is not null
       and v_test_type is distinct from (case v_round when 'bosy' then 'pre' when 'eosy' then 'post' else 'mosy' end) then
      raise exception 'a % session does not read a % passage (BOSY reads pre, MOSY mosy, EOSY post passages)',
        v_round, v_test_type;
    end if;
    select p.title into v_read_title
    from public.phil_iri_readings r
    join public.phil_iri_assessments a on a.id = r.assessment_id
    join public.phil_iri_passages p on p.id = r.passage_id
    where a.student_id = v_student
      and (r.passage_id = new.passage_id
           or phil_iri_text_key(p.body) = (select phil_iri_text_key(body) from public.phil_iri_passages
                                          where id = new.passage_id))
      -- Oral follow-up of a silent reading: same round and year, another session.
      and not (new.method <> 'silent' and r.method = 'silent'
               and r.assessment_id <> new.assessment_id
               and a.round = v_round and a.school_year = v_year)
    limit 1;
    if v_read_title is not null then
      raise exception 'this learner has already read "%"; a learner never reads the same passage twice', v_read_title;
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Miscues without a position; answers never beside a correct count
-- ---------------------------------------------------------------------------

create or replace function public.check_phil_iri_miscue() returns trigger
  language plpgsql security definer
  set search_path = public
as $$
declare
  v_words integer;
  v_method text;
  v_import text;
begin
  if auth.uid() is null then
    return new;
  end if;
  if not phil_iri_reading_writable(new.reading_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select p.word_count, r.method, a.import_source into v_words, v_method, v_import
  from public.phil_iri_readings r
  join public.phil_iri_passages p on p.id = r.passage_id
  join public.phil_iri_assessments a on a.id = r.assessment_id
  where r.id = new.reading_id;
  if v_method = 'silent' then
    raise exception 'a silent reading has no miscues';
  end if;
  if new.word_index is null then
    if v_import is null then
      raise exception 'a miscue without a position belongs to an imported reading';
    end if;
    return new;
  end if;
  -- An insertion may sit after the last word (index = word count).
  if new.word_index > v_words or (new.miscue_type <> 'insertion' and new.word_index >= v_words) then
    raise exception 'word % is outside the passage (% words)', new.word_index, v_words;
  end if;
  return new;
end;
$$;

create or replace function public.check_phil_iri_answer() returns trigger
  language plpgsql security definer
  set search_path = public
as $$
declare
  v_key text;
  v_ok boolean;
  v_imported integer;
begin
  if auth.uid() is not null and not phil_iri_reading_writable(new.reading_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select q.answer_key, q.passage_id = r.passage_id, r.imported_correct into v_key, v_ok, v_imported
  from public.phil_iri_questions q, public.phil_iri_readings r
  where q.id = new.question_id and r.id = new.reading_id;
  if not coalesce(v_ok, false) then
    raise exception 'question % is not a question of this reading''s passage', new.question_id;
  end if;
  if v_imported is not null then
    raise exception 'this reading has an imported correct count; it takes no answers';
  end if;
  new.is_correct := new.chosen is not null and new.chosen = v_key;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The one-time workbook import lock
-- ---------------------------------------------------------------------------

create table if not exists public.phil_iri_workbook_imports (
  id           bigint generated always as identity primary key,
  school_id    bigint not null references public.schools(id),
  section_id   bigint not null references public.sections(id),
  school_year  text not null,
  imported_by  uuid references public.users(id),
  imported_at  timestamptz not null default now(),
  row_version  bigint not null default 1,
  constraint phil_iri_workbook_imports_once unique (section_id, school_year)
);

create or replace function public.phil_iri_workbook_imports_before_insert() returns trigger
  language plpgsql security definer
  set search_path = public
as $$
begin
  if not exists (select 1 from public.sections s
                  where s.id = new.section_id and s.school_id = new.school_id
                    and s.school_year = new.school_year) then
    raise exception 'section % is not a % section of school %', new.section_id, new.school_year, new.school_id;
  end if;
  if auth.uid() is not null then
    new.imported_by := auth.uid();
    new.imported_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists phil_iri_workbook_imports_before_insert on public.phil_iri_workbook_imports;
create trigger phil_iri_workbook_imports_before_insert before insert on public.phil_iri_workbook_imports
  for each row execute function public.phil_iri_workbook_imports_before_insert();

drop trigger if exists sync_row_version on public.phil_iri_workbook_imports;
create trigger sync_row_version before update on public.phil_iri_workbook_imports
  for each row execute function public.basa_bump_row_version();

alter table public.phil_iri_workbook_imports enable row level security;

drop policy if exists phil_iri_workbook_imports_select on public.phil_iri_workbook_imports;
create policy phil_iri_workbook_imports_select on public.phil_iri_workbook_imports
  for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id()));

drop policy if exists phil_iri_workbook_imports_insert on public.phil_iri_workbook_imports;
create policy phil_iri_workbook_imports_insert on public.phil_iri_workbook_imports
  for insert to authenticated
  with check (is_superadmin()
              or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id()));

revoke all on public.phil_iri_workbook_imports from anon;
grant select, insert, update, delete on public.phil_iri_workbook_imports to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. Sync: the lock is the 19th synced table
-- ---------------------------------------------------------------------------

-- Checks a package's shape before anything is written. Returns null when it
-- is fine, else the problem. Table and column names are checked against the
-- 19 synced tables and the catalog, so sync_apply never builds SQL from an
-- unchecked name. (As 20261023040000, plus phil_iri_workbook_imports.)
create or replace function basa_private.sync_check_payload(p jsonb) returns text
  language plpgsql stable
  set search_path = public
as $$
declare
  synced constant text[] := array[
    'crla_assessments', 'crla_part1_standard', 'crla_part1_english', 'crla_part2_fluency',
    'phil_iri_gst_results', 'phil_iri_assessments', 'phil_iri_readings', 'phil_iri_miscues',
    'phil_iri_answers', 'phil_iri_rubric_scores', 'phil_iri_workbook_imports',
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

revoke all on function basa_private.sync_check_payload(jsonb) from public, anon;
grant execute on function basa_private.sync_check_payload(jsonb) to authenticated;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261109010000', 'phil_iri_import', true)
on conflict (id) do nothing;
