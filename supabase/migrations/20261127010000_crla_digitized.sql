-- Digitized CRLA: an attempt marked in BASA item by item and word by word,
-- timed in BASA, with its marks and timing log as evidence (spec
-- docs/superpowers/specs/2026-11-27-crla-digitized-design.md, consultation
-- item M1-02).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261126030000.
-- App update required on all devices: yes (four new synced tables and a new
-- words-read rule: an older app can't pull or upload them).
--
-- 1. Content (read: every signed-in user; write: superadmin): the story text
--    (crla_stories.body, one sentence per line), the Part 1 items of each form
--    (crla_part1_items, with the printed key of a rhyming pair) and each
--    story's comprehension questions with the accepted answers
--    (crla_story_questions). Rows come from supabase/seeds/crla_content_region10.sql.
-- 2. Evidence (synced children of crla_assessments): crla_part1_marks (one
--    row per marked item), crla_part2_word_marks (miscue / self_corrected),
--    crla_part2_answers (correct / incorrect / not_asked) and
--    crla_timer_events (start / pause / resume / stop / reset, insert-only;
--    the rules of lib/core/services/reading_timer.dart and the device's
--    trigger in crla_local_schema.dart, change the three together).
-- 3. Words read (D6): crla_part2_fluency.last_word_reached (0-based; null =
--    the whole story). With it, words read = least(story words, last + 1) -
--    miscues; without it, story words - miscues as before (F10).
-- 4. The evidence check (D9): an attempt with any marks or taps keeps Part 1
--    and Part 2 totals only when they match its marks and timing log
--    (basa_private.crla_digitized_problem). A constraint trigger
--    crla_digitized_check on the three part tables and the four evidence
--    tables; sync_apply defers it to the end of an upload.
-- 5. Sync: the four tables are synced (payload list, ref columns); sync_apply
--    is the 20261126010000 body with crla_digitized_check in its deferred
--    lists, statement_timeout 60s kept.
--
-- RLS: new content tables crla_part1_items, crla_story_questions: select =
-- every signed-in user; insert/update/delete = superadmin (like crla_stories).
-- New evidence tables: select = the attempt is readable (as the part tables
-- since 20261125020000); insert/update/delete = crla_assessment_writable
-- (as the part tables); crla_timer_events insert only. Grants per
-- 20261025010000. No other policy changes.

-- ---------------------------------------------------------------------------
-- 1. Content
-- ---------------------------------------------------------------------------
alter table public.crla_stories add column if not exists body text;

create table if not exists public.crla_part1_items (
  id           bigint generated always as identity primary key,
  region_id    smallint not null references public.regions(id),
  language     text not null,
  grade        smallint not null check (grade between 1 and 3),
  task         text not null check (task in ('task1', 'task2_low', 'task2_high', 'task2')),
  item_no      smallint not null check (item_no >= 1),
  text         text not null,
  sentence_no  smallint check (sentence_no >= 1),
  answer_key   text,
  constraint crla_part1_items_key unique (region_id, language, grade, task, item_no)
);

create table if not exists public.crla_story_questions (
  id               bigint generated always as identity primary key,
  story_id         bigint not null references public.crla_stories(id) on delete cascade,
  question_no      smallint not null check (question_no >= 1),
  after_sentence   smallint not null check (after_sentence >= 1),
  question         text not null,
  accepted_answers text not null,
  constraint crla_story_questions_key unique (story_id, question_no)
);

alter table public.crla_part1_items enable row level security;
alter table public.crla_story_questions enable row level security;

drop policy if exists crla_part1_items_select on public.crla_part1_items;
create policy crla_part1_items_select on public.crla_part1_items for select to authenticated using (true);
drop policy if exists crla_part1_items_insert on public.crla_part1_items;
create policy crla_part1_items_insert on public.crla_part1_items for insert to authenticated
  with check ((select public.is_superadmin()));
drop policy if exists crla_part1_items_update on public.crla_part1_items;
create policy crla_part1_items_update on public.crla_part1_items for update to authenticated
  using ((select public.is_superadmin())) with check ((select public.is_superadmin()));
drop policy if exists crla_part1_items_delete on public.crla_part1_items;
create policy crla_part1_items_delete on public.crla_part1_items for delete to authenticated
  using ((select public.is_superadmin()));

drop policy if exists crla_story_questions_select on public.crla_story_questions;
create policy crla_story_questions_select on public.crla_story_questions for select to authenticated using (true);
drop policy if exists crla_story_questions_insert on public.crla_story_questions;
create policy crla_story_questions_insert on public.crla_story_questions for insert to authenticated
  with check ((select public.is_superadmin()));
drop policy if exists crla_story_questions_update on public.crla_story_questions;
create policy crla_story_questions_update on public.crla_story_questions for update to authenticated
  using ((select public.is_superadmin())) with check ((select public.is_superadmin()));
drop policy if exists crla_story_questions_delete on public.crla_story_questions;
create policy crla_story_questions_delete on public.crla_story_questions for delete to authenticated
  using ((select public.is_superadmin()));

revoke all on public.crla_part1_items from anon;
revoke all on public.crla_story_questions from anon;
grant select, insert, update, delete on public.crla_part1_items to authenticated, service_role;
grant select, insert, update, delete on public.crla_story_questions to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Evidence
-- ---------------------------------------------------------------------------
create table if not exists public.crla_part1_marks (
  id              bigint generated always as identity primary key,
  assessment_id   bigint not null references public.crla_assessments(id) on delete cascade,
  task            text not null check (task in ('task1', 'task2_low', 'task2_high', 'task2')),
  item_no         smallint not null check (item_no >= 1),
  correct         boolean not null,
  self_corrected  boolean not null default false,
  created_by      uuid references public.users(id),
  created_at      timestamptz not null default now(),
  row_version     bigint not null default 1,
  constraint crla_part1_marks_key unique (assessment_id, task, item_no)
);

create table if not exists public.crla_part2_word_marks (
  id             bigint generated always as identity primary key,
  assessment_id  bigint not null references public.crla_assessments(id) on delete cascade,
  story_no       smallint not null check (story_no in (1, 2)),
  word_index     smallint not null check (word_index >= 0),
  kind           text not null check (kind in ('miscue', 'self_corrected')),
  created_by     uuid references public.users(id),
  created_at     timestamptz not null default now(),
  row_version    bigint not null default 1,
  constraint crla_part2_word_marks_key unique (assessment_id, word_index)
);

create table if not exists public.crla_part2_answers (
  id             bigint generated always as identity primary key,
  assessment_id  bigint not null references public.crla_assessments(id) on delete cascade,
  story_no       smallint not null check (story_no in (1, 2)),
  question_no    smallint not null check (question_no >= 1),
  mark           text not null check (mark in ('correct', 'incorrect', 'not_asked')),
  created_by     uuid references public.users(id),
  created_at     timestamptz not null default now(),
  row_version    bigint not null default 1,
  constraint crla_part2_answers_key unique (assessment_id, question_no)
);

create table if not exists public.crla_timer_events (
  id             bigint generated always as identity primary key,
  assessment_id  bigint not null references public.crla_assessments(id) on delete cascade,
  story_no       smallint not null check (story_no in (1, 2)),
  seq            integer not null check (seq >= 1),
  kind           text not null check (kind in ('start', 'pause', 'resume', 'stop', 'reset')),
  at             timestamptz not null,
  created_by     uuid references public.users(id),
  created_at     timestamptz not null default now(),
  row_version    bigint not null default 1,
  constraint crla_timer_events_seq unique (assessment_id, seq)
);

alter table public.crla_part2_fluency add column if not exists last_word_reached smallint
  check (last_word_reached >= 0);

-- Who and when, for every evidence row (as the server's other child rows).
create or replace function public.crla_evidence_stamp() returns trigger
  language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  new.created_at := now();
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['crla_part1_marks', 'crla_part2_word_marks', 'crla_part2_answers'] loop
    execute format('drop trigger if exists crla_evidence_stamp on public.%I', t);
    execute format('create trigger crla_evidence_stamp before insert on public.%I '
                   'for each row execute function public.crla_evidence_stamp()', t);
    execute format('drop trigger if exists sync_row_version on public.%I', t);
    execute format('create trigger sync_row_version before update on public.%I '
                   'for each row execute function public.basa_bump_row_version()', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('create policy %I on public.%I for select to authenticated '
                   'using (exists (select 1 from public.crla_assessments a where a.id = assessment_id))', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('create policy %I on public.%I for insert to authenticated '
                   'with check (public.crla_assessment_writable(assessment_id))', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('create policy %I on public.%I for update to authenticated '
                   'using (public.crla_assessment_writable(assessment_id)) '
                   'with check (public.crla_assessment_writable(assessment_id))', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format('create policy %I on public.%I for delete to authenticated '
                   'using (public.crla_assessment_writable(assessment_id))', t || '_delete', t);
  end loop;
end;
$$;

revoke all on public.crla_part1_marks from anon;
revoke all on public.crla_part2_word_marks from anon;
revoke all on public.crla_part2_answers from anon;
grant select, insert, update, delete on public.crla_part1_marks to authenticated, service_role;
grant select, insert, update, delete on public.crla_part2_word_marks to authenticated, service_role;
grant select, insert, update, delete on public.crla_part2_answers to authenticated, service_role;

-- The timer of an attempt: the current timing's status (the taps after the
-- last reset) and its reading time in milliseconds.
create or replace function basa_private.crla_timer_status(p_assessment_id bigint) returns text
  language sql stable security definer set search_path = public
as $$
  select coalesce((
    select case e.kind when 'stop' then 'stopped' when 'pause' then 'paused' when 'reset' then 'none' else 'running' end
    from public.crla_timer_events e
    where e.assessment_id = p_assessment_id
    order by e.seq desc limit 1), 'none');
$$;

create or replace function basa_private.crla_timer_elapsed_ms(p_assessment_id bigint) returns bigint
  language sql stable security definer set search_path = public
as $$
  with seg as (
    select e.kind, e.at, lead(e.at) over (order by e.seq) as next_at, lead(e.kind) over (order by e.seq) as next_kind
    from public.crla_timer_events e
    where e.assessment_id = p_assessment_id
      and e.seq > coalesce((select max(r.seq) from public.crla_timer_events r
                             where r.assessment_id = p_assessment_id and r.kind = 'reset'), 0)
  )
  select coalesce(sum(floor(extract(epoch from (next_at - at)) * 1000))::bigint, 0)
  from seg where kind in ('start', 'resume') and next_kind in ('pause', 'stop');
$$;

create or replace function public.check_crla_timer_event() returns trigger
  language plpgsql security definer set search_path = public
as $$
declare
  st text;
  last_seq integer;
  last_reset integer;
  last_at timestamptz;
begin
  -- One tap at a time per attempt.
  perform 1 from public.crla_assessments a where a.id = new.assessment_id for update;
  if not found then
    raise exception 'CRLA attempt % not found', new.assessment_id;
  end if;
  select max(e.seq), max(e.seq) filter (where e.kind = 'reset') into last_seq, last_reset
    from public.crla_timer_events e where e.assessment_id = new.assessment_id;
  select max(e.at) into last_at
    from public.crla_timer_events e
   where e.assessment_id = new.assessment_id and e.seq > coalesce(last_reset, 0);
  if new.kind <> 'reset' and last_at is not null and new.at < last_at then
    raise exception 'This time is earlier than the timer''s last tap; check the device clock.';
  end if;
  st := basa_private.crla_timer_status(new.assessment_id);
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
    raise exception 'timer tap seq % does not follow % for CRLA attempt %', new.seq, coalesce(last_seq, 0), new.assessment_id;
  end if;
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  new.created_at := now();
  return new;
end;
$$;

drop trigger if exists check_crla_timer_event on public.crla_timer_events;
create trigger check_crla_timer_event before insert on public.crla_timer_events
  for each row execute function public.check_crla_timer_event();

drop trigger if exists sync_row_version on public.crla_timer_events;
create trigger sync_row_version before update on public.crla_timer_events
  for each row execute function public.basa_bump_row_version();

alter table public.crla_timer_events enable row level security;
drop policy if exists crla_timer_events_select on public.crla_timer_events;
create policy crla_timer_events_select on public.crla_timer_events for select to authenticated
  using (exists (select 1 from public.crla_assessments a where a.id = assessment_id));
drop policy if exists crla_timer_events_insert on public.crla_timer_events;
create policy crla_timer_events_insert on public.crla_timer_events for insert to authenticated
  with check (public.crla_assessment_writable(assessment_id));

revoke all on public.crla_timer_events from anon;
grant select, insert, update, delete on public.crla_timer_events to authenticated, service_role;
revoke all on function basa_private.crla_timer_status(bigint) from public, anon;
revoke all on function basa_private.crla_timer_elapsed_ms(bigint) from public, anon;
grant execute on function basa_private.crla_timer_status(bigint) to authenticated;
grant execute on function basa_private.crla_timer_elapsed_ms(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Words read with the last word reached (D6)
-- ---------------------------------------------------------------------------
create or replace function public.check_crla_part2_limits() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $_$
declare
  v_grade int;
  v_variant text;
  v_school bigint;
  v_language text;
  v_max int;
  v_cap int;
  v_words int;
  v_reached int;
begin
  -- Answer like RLS first, so the limits below don't reveal other schools' rows.
  if auth.uid() is not null and not crla_assessment_writable(new.assessment_id) then
    raise exception 'new row violates row-level security policy for table "%"', tg_table_name
      using errcode = '42501';
  end if;

  select (case when sec.grade_level ~ '^[0-9]+$' then sec.grade_level::int end), ca.subject_variant,
         ca.school_id, ca.language
    into v_grade, v_variant, v_school, v_language
  from public.crla_assessments ca
  join public.sections sec on sec.id = ca.section_id
  where ca.id = new.assessment_id;

  if not found then
    raise exception 'crla_assessments % does not exist', new.assessment_id;
  end if;

  v_max := crla_comprehension_max(v_grade, v_variant);
  if new.comprehension_correct > v_max then
    raise exception 'comprehension_correct % is above the Grade % % maximum of %',
      new.comprehension_correct, v_grade, v_variant, v_max using errcode = '23514';
  end if;

  v_cap := crla_time_cap_seconds(v_grade, v_variant);
  if new.time_minutes * 60 + new.time_seconds > v_cap then
    raise exception 'reading time %:% is over the Grade % % limit of % seconds',
      new.time_minutes, lpad(new.time_seconds::text, 2, '0'), v_grade, v_variant, v_cap
      using errcode = '23514';
  end if;

  -- Words read = the words reached (the story's words, or up to the last
  -- word reached of a reading stopped at the time limit) - miscues (F10, D6).
  select cs.word_count into v_words
  from public.crla_stories cs
  join public.schools sch on sch.region_id = cs.region_id
  where sch.id = v_school and cs.language = v_language and cs.grade = v_grade
    and cs.story_no = new.story_no;
  if found then
    v_reached := case when new.last_word_reached is null then v_words
                      else least(v_words, new.last_word_reached + 1) end;
    if new.miscues > v_reached then
      raise exception '% miscues is more than the % words of the story read', new.miscues, v_reached
        using errcode = '23514';
    end if;
    new.words_read := v_reached - new.miscues;
  end if;

  return new;
end;
$_$;

-- ---------------------------------------------------------------------------
-- 4. The evidence check (D9)
-- ---------------------------------------------------------------------------
-- Null when the attempt's Part 1 / Part 2 totals fit its marks and timing log
-- (or it has none), else the refusal naming the learner.
create or replace function basa_private.crla_digitized_problem(p_assessment_id bigint) returns text
  language plpgsql stable security definer set search_path = public
as $$
declare
  a record;
  p1s record;
  p1e record;
  p2 record;
  t1 int;
  t2low int;
  t2high int;
  t2 int;
  wanted text;
  stories int;
  story int;
  miscues int;
  answers int;
  ms bigint;
  bad text;
begin
  if not exists (select 1 from public.crla_part1_marks m where m.assessment_id = p_assessment_id)
     and not exists (select 1 from public.crla_part2_word_marks m where m.assessment_id = p_assessment_id)
     and not exists (select 1 from public.crla_part2_answers m where m.assessment_id = p_assessment_id)
     and not exists (select 1 from public.crla_timer_events m where m.assessment_id = p_assessment_id) then
    return null; -- typed totals: unchanged rules
  end if;
  select ca.subject_variant, s.last_name, s.first_name,
         (case when sec.grade_level ~ '^[0-9]+$' then sec.grade_level::int end) as grade into a
    from public.crla_assessments ca join public.students s on s.id = ca.student_id
    left join public.sections sec on sec.id = ca.section_id
   where ca.id = p_assessment_id;
  if not found then
    return null; -- the attempt is being deleted with its evidence
  end if;

  -- Part 1: scores = items marked right or self-corrected, capped at 10; a
  -- task with no marks is not given yet (null); Task 2 only the one Task 1
  -- leads to.
  select least(10, count(*) filter (where m.task = 'task1' and (m.correct or m.self_corrected))),
         case when count(*) filter (where m.task = 'task2_low') = 0 then null
              else least(10, count(*) filter (where m.task = 'task2_low' and (m.correct or m.self_corrected))) end,
         case when count(*) filter (where m.task = 'task2_high') = 0 then null
              else least(10, count(*) filter (where m.task = 'task2_high' and (m.correct or m.self_corrected))) end,
         case when count(*) filter (where m.task = 'task2') = 0 then null
              else least(10, count(*) filter (where m.task = 'task2' and (m.correct or m.self_corrected))) end
    into t1, t2low, t2high, t2
    from public.crla_part1_marks m where m.assessment_id = p_assessment_id;
  wanted := case when a.subject_variant = 'eng' then case when t1 = 0 then null else 'task2' end
                 when t1 < 7 then 'task2_low' else 'task2_high' end;
  if exists (select 1 from public.crla_part1_marks m where m.assessment_id = p_assessment_id
               and m.task <> 'task1' and m.task is distinct from wanted) then
    bad := 'Part 1 has marks on a task its Task 1 score does not lead to';
  elsif exists (select 1 from public.crla_part1_marks m where m.assessment_id = p_assessment_id) then
    if a.subject_variant = 'eng' then
      select * into p1e from public.crla_part1_english e where e.assessment_id = p_assessment_id;
      if not found or p1e.task1_score <> t1 or p1e.task2_score is distinct from (case when t1 = 0 then null else t2 end) then
        bad := 'Part 1 totals don''t match its marks';
      end if;
    else
      select * into p1s from public.crla_part1_standard e where e.assessment_id = p_assessment_id;
      if not found or p1s.task1_score <> t1
         or p1s.task2_low_score is distinct from (case when t1 < 7 then t2low end)
         or p1s.task2_high_score is distinct from (case when t1 >= 7 then t2high end) then
        bad := 'Part 1 totals don''t match its marks';
      end if;
    end if;
  elsif exists (select 1 from public.crla_part1_english e where e.assessment_id = p_assessment_id)
     or exists (select 1 from public.crla_part1_standard e where e.assessment_id = p_assessment_id) then
    -- A marked attempt: its Part 1 comes from marks only (final review C1).
    bad := 'Part 1 totals have no marks behind them';
  end if;

  -- Part 2: one story; miscues, time and comprehension from the evidence.
  if bad is null then
    select count(distinct x.story_no), min(x.story_no) into stories, story from (
      select m.story_no from public.crla_part2_word_marks m where m.assessment_id = p_assessment_id
      union all select m.story_no from public.crla_part2_answers m where m.assessment_id = p_assessment_id
      union all select m.story_no from public.crla_timer_events m where m.assessment_id = p_assessment_id) x;
    select * into p2 from public.crla_part2_fluency f where f.assessment_id = p_assessment_id;
    if stories > 1 or (found and stories = 1 and p2.story_no <> story) then
      bad := 'Part 2 marks belong to more than one story';
    elsif found and not exists (select 1 from public.crla_timer_events m where m.assessment_id = p_assessment_id) then
      -- A marked attempt's Part 2 comes from its timing (final review C1).
      bad := 'Part 2 totals have no timing behind them';
    elsif found and stories = 1 then
      if exists (select 1 from public.crla_part2_word_marks m where m.assessment_id = p_assessment_id
                   and p2.last_word_reached is not null and m.word_index > p2.last_word_reached) then
        bad := 'a word is marked after the last word reached';
      else
        select count(*) into miscues from public.crla_part2_word_marks m
         where m.assessment_id = p_assessment_id and m.kind = 'miscue';
        select count(*) into answers from public.crla_part2_answers m
         where m.assessment_id = p_assessment_id and m.mark = 'correct';
        if p2.miscues <> miscues or p2.comprehension_correct <> answers then
          bad := 'Part 2 totals don''t match its marks';
        elsif exists (select 1 from public.crla_timer_events m where m.assessment_id = p_assessment_id) then
          ms := basa_private.crla_timer_elapsed_ms(p_assessment_id);
          if basa_private.crla_timer_status(p_assessment_id) <> 'stopped'
             or p2.time_minutes * 60 + p2.time_seconds <> ms / 1000 then
            bad := 'the reading time doesn''t match its timer';
          elsif ms / 1000 >= crla_time_cap_seconds(a.grade, a.subject_variant) and p2.last_word_reached is null then
            -- Final review I2: else the whole story would count.
            bad := 'a reading stopped at the time limit needs its last word reached';
          end if;
        end if;
      end if;
    end if;
  end if;

  if bad is not null then
    return format('The CRLA attempt of %s, %s: %s.', a.last_name, a.first_name, bad);
  end if;
  return null;
end;
$$;
revoke all on function basa_private.crla_digitized_problem(bigint) from public, anon;
grant execute on function basa_private.crla_digitized_problem(bigint) to authenticated;

create or replace function public.crla_digitized_check() returns trigger
  language plpgsql security definer set search_path = public
as $$
declare
  problem text;
begin
  problem := basa_private.crla_digitized_problem(
    case tg_op when 'DELETE' then old.assessment_id else new.assessment_id end);
  if problem is not null then
    raise exception '%', problem;
  end if;
  return null;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['crla_part1_standard', 'crla_part1_english', 'crla_part2_fluency',
                           'crla_part1_marks', 'crla_part2_word_marks', 'crla_part2_answers', 'crla_timer_events'] loop
    execute format('drop trigger if exists crla_digitized_check on public.%I', t);
    execute format('create constraint trigger crla_digitized_check after insert or update or delete on public.%I '
                   'deferrable initially immediate for each row execute function public.crla_digitized_check()', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Sync: the four evidence tables are synced tables
-- ---------------------------------------------------------------------------
create or replace function basa_private.sync_ref_columns(p_table text) returns text[]
  language sql immutable
as $$
  select case p_table
    when 'crla_part1_standard' then array['assessment_id']
    when 'crla_part1_english' then array['assessment_id']
    when 'crla_part2_fluency' then array['assessment_id']
    when 'crla_part1_marks' then array['assessment_id']
    when 'crla_part2_word_marks' then array['assessment_id']
    when 'crla_part2_answers' then array['assessment_id']
    when 'crla_timer_events' then array['assessment_id']
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
    'crla_part1_marks', 'crla_part2_word_marks', 'crla_part2_answers', 'crla_timer_events',
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
      public.phil_iri_timed_reading_check, public.phil_iri_timer_events_check,
      public.crla_digitized_check deferred;
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
      public.phil_iri_timed_reading_check, public.phil_iri_timer_events_check,
      public.crla_digitized_check immediate;
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
      public.phil_iri_timed_reading_check, public.phil_iri_timer_events_check,
      public.crla_digitized_check immediate;
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
values ('20261127010000', 'crla_digitized', true)
on conflict (id) do nothing;
