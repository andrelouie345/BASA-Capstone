-- Phil-IRI assessments (piece 8b): GST results, assessment sessions, passage
-- readings, miscues, comprehension answers, rubric scores.
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
-- Needs 20261014000000_phil_iri_content.sql first.
--
-- Scope (same as CRLA, M4):
--  * Insert: the section belongs to school_id, the learner has an ACTIVE
--    enrollment in that section for that school_year, the section is Grade
--    4-10, and the caller is the superadmin, an admin/coordinator of that
--    school, or a tutor assigned to the section.
--  * Read: superadmin; admin/coordinator of the school; tutors of the learner.
--  * attempt_no is always assigned here (retakes allowed; latest counts) and
--    administered_by is stamped with the caller.
--  * GST results are never updated or deleted by clients (a retake is a new
--    row), like crla_assessments.
-- Lifecycle (owner decisions 2026-10-13/14):
--  * A session is inserted as in_progress, moves to completed (tutor or
--    coordinator) and back, and is finalized only by an admin/coordinator
--    (or the superadmin) from completed, with the thresholds snapshot.
--  * A finalized session and everything under it never change (only SQL
--    Editor maintenance, which has no JWT, can).
-- Integrity:
--  * A reading's passage must be readable by the caller and active; in a
--    grade-leveled collection its level must equal the section's grade (every
--    FLT/BOSY/MOSY/EOSY passage is grade-level). Its passage never changes.
--  * Miscue positions must fall inside the passage; an answer's question must
--    belong to the reading's passage, and is_correct is computed here from
--    the key (a client value is ignored); rubric scores stay in scale.
--  * Once a passage has been read, its text, word count, level and
--    collection are locked (miscue positions depend on them). A collection
--    with passages can no longer switch is_grade_leveled.

begin;

-- Shared helpers ---------------------------------------------------------------

create or replace function public.phil_iri_section_grade(p_section_id bigint)
 returns integer language sql stable security definer set search_path to 'public'
as $$
  select case when grade_level ~ '^[0-9]+$' then grade_level::int end
  from public.sections where id = p_section_id;
$$;

-- Raises the same error RLS raises, so triggers that run before RLS don't
-- reveal anything about rows the caller can't see.
create or replace function public.phil_iri_deny(p_table text)
 returns void language plpgsql
as $$
begin
  raise exception 'new row violates row-level security policy for table "%"', p_table
    using errcode = '42501';
end;
$$;

-- GST results -------------------------------------------------------------------

create table if not exists public.phil_iri_gst_results (
  id                  bigint generated always as identity primary key,
  student_id          bigint not null references public.students(id),
  school_id           bigint not null references public.schools(id),
  section_id          bigint not null references public.sections(id),
  school_year         text not null,
  attempt_no          integer not null default 0,
  max_score           integer not null check (max_score in (20, 40)),
  total_score         integer not null,
  literal_correct     integer check (literal_correct >= 0),
  inferential_correct integer check (inferential_correct >= 0),
  critical_correct    integer check (critical_correct >= 0),
  taken_at            date not null,
  administered_by     uuid references public.users(id),
  created_at          timestamptz not null default now(),
  constraint phil_iri_gst_results_school_year_format check (
    case when school_year ~ '^\d{4}-\d{4}$'
         then right(school_year, 4)::int = left(school_year, 4)::int + 1
         else false end),
  constraint phil_iri_gst_results_score check (total_score between 0 and max_score),
  constraint phil_iri_gst_results_breakdown check (
    literal_correct is null or inferential_correct is null or critical_correct is null
    or literal_correct + inferential_correct + critical_correct = total_score)
);
create index if not exists phil_iri_gst_results_student
  on public.phil_iri_gst_results (student_id, school_year);

create or replace function public.phil_iri_gst_results_before_insert()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_grade integer := phil_iri_section_grade(new.section_id);
begin
  -- Runs before RLS: only check sections of the caller's own school, so the
  -- message can't reveal another school's section grade (RLS rejects those).
  if auth.uid() is not null and not (is_superadmin() or exists (
       select 1 from public.sections where id = new.section_id and school_id = current_user_school_id())) then
    v_grade := null;
  end if;
  if v_grade is not null and new.max_score <> (case when v_grade >= 7 then 40 else 20 end) then
    raise exception 'the GST for Grade % is out of %', v_grade, case when v_grade >= 7 then 40 else 20 end;
  end if;
  select coalesce(max(attempt_no), 0) + 1 into new.attempt_no
  from public.phil_iri_gst_results
  where student_id = new.student_id and school_id = new.school_id
    and section_id = new.section_id and school_year = new.school_year;
  if auth.uid() is not null then
    new.administered_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists phil_iri_gst_results_before_insert on public.phil_iri_gst_results;
create trigger phil_iri_gst_results_before_insert
  before insert on public.phil_iri_gst_results
  for each row execute function public.phil_iri_gst_results_before_insert();

drop policy if exists phil_iri_gst_results_select on public.phil_iri_gst_results;
create policy phil_iri_gst_results_select on public.phil_iri_gst_results
  for select to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
    or (current_user_role() = 'tutor' and tutor_has_student(student_id))
  );

drop policy if exists phil_iri_gst_results_insert on public.phil_iri_gst_results;
create policy phil_iri_gst_results_insert on public.phil_iri_gst_results
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.sections s
      join public.enrollments e on e.section_id = s.id
      where s.id = phil_iri_gst_results.section_id
        and s.school_id = phil_iri_gst_results.school_id
        and s.grade_level in ('4', '5', '6', '7', '8', '9', '10')
        and e.student_id = phil_iri_gst_results.student_id
        and e.school_year = phil_iri_gst_results.school_year
        and e.status = 'active'
    )
    and (
      is_superadmin()
      or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
      or (current_user_role() = 'tutor' and tutor_has_section(section_id))
    )
  );

-- Assessment sessions -------------------------------------------------------------

create table if not exists public.phil_iri_assessments (
  id                  bigint generated always as identity primary key,
  student_id          bigint not null references public.students(id),
  school_id           bigint not null references public.schools(id),
  section_id          bigint not null references public.sections(id),
  school_year         text not null,
  attempt_no          integer not null default 0,
  round               text not null check (round in ('bosy', 'mosy1', 'mosy2', 'mosy3', 'eosy')),
  status              text not null default 'in_progress'
                        check (status in ('in_progress', 'completed', 'finalized')),
  assessed_at         date not null,
  completed_at        timestamptz,
  finalized_at        timestamptz,
  administered_by     uuid references public.users(id),
  thresholds_snapshot jsonb check (thresholds_snapshot is null or jsonb_typeof(thresholds_snapshot) = 'object'),
  created_at          timestamptz not null default now(),
  constraint phil_iri_assessments_school_year_format check (
    case when school_year ~ '^\d{4}-\d{4}$'
         then right(school_year, 4)::int = left(school_year, 4)::int + 1
         else false end),
  constraint phil_iri_assessments_finalized_snapshot check (
    (status = 'finalized') = (finalized_at is not null and thresholds_snapshot is not null))
);
create index if not exists phil_iri_assessments_student
  on public.phil_iri_assessments (student_id, school_year, round);
create index if not exists phil_iri_assessments_school_round
  on public.phil_iri_assessments (school_id, school_year, round);

create or replace function public.phil_iri_assessment_readable(p_assessment_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.phil_iri_assessments a
    where a.id = p_assessment_id
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and a.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and tutor_has_student(a.student_id)))
  );
$$;

-- Writable = in scope AND not finalized.
create or replace function public.phil_iri_assessment_writable(p_assessment_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.phil_iri_assessments a
    where a.id = p_assessment_id
      and a.status <> 'finalized'
      and (is_superadmin()
           or (current_user_role() in ('admin', 'coordinator') and a.school_id = current_user_school_id())
           or (current_user_role() = 'tutor' and tutor_has_section(a.section_id)))
  );
$$;

create or replace function public.phil_iri_assessments_before_insert()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  select coalesce(max(attempt_no), 0) + 1 into new.attempt_no
  from public.phil_iri_assessments
  where student_id = new.student_id and school_id = new.school_id
    and section_id = new.section_id and round = new.round
    and school_year = new.school_year;
  if auth.uid() is not null then
    new.administered_by := auth.uid();
    new.status := 'in_progress';
    new.completed_at := null;
    new.finalized_at := null;
    new.thresholds_snapshot := null;
  end if;
  return new;
end;
$$;

create or replace function public.phil_iri_assessments_before_update()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if auth.uid() is null then
    return new; -- SQL Editor maintenance
  end if;
  if old.status = 'finalized' then
    raise exception 'a finalized Phil-IRI assessment cannot be changed';
  end if;
  if (new.student_id, new.school_id, new.section_id, new.school_year, new.round,
      new.attempt_no, new.administered_by, new.assessed_at)
     is distinct from
     (old.student_id, old.school_id, old.section_id, old.school_year, old.round,
      old.attempt_no, old.administered_by, old.assessed_at) then
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

drop trigger if exists phil_iri_assessments_before_insert on public.phil_iri_assessments;
create trigger phil_iri_assessments_before_insert
  before insert on public.phil_iri_assessments
  for each row execute function public.phil_iri_assessments_before_insert();
drop trigger if exists phil_iri_assessments_before_update on public.phil_iri_assessments;
create trigger phil_iri_assessments_before_update
  before update on public.phil_iri_assessments
  for each row execute function public.phil_iri_assessments_before_update();

drop policy if exists phil_iri_assessments_select on public.phil_iri_assessments;
create policy phil_iri_assessments_select on public.phil_iri_assessments
  for select to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
    or (current_user_role() = 'tutor' and tutor_has_student(student_id))
  );

drop policy if exists phil_iri_assessments_insert on public.phil_iri_assessments;
create policy phil_iri_assessments_insert on public.phil_iri_assessments
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.sections s
      join public.enrollments e on e.section_id = s.id
      where s.id = phil_iri_assessments.section_id
        and s.school_id = phil_iri_assessments.school_id
        and s.grade_level in ('4', '5', '6', '7', '8', '9', '10')
        and e.student_id = phil_iri_assessments.student_id
        and e.school_year = phil_iri_assessments.school_year
        and e.status = 'active'
    )
    and (
      is_superadmin()
      or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
      or (current_user_role() = 'tutor' and tutor_has_section(section_id))
    )
  );

drop policy if exists phil_iri_assessments_update on public.phil_iri_assessments;
create policy phil_iri_assessments_update on public.phil_iri_assessments
  for update to authenticated
  using (phil_iri_assessment_writable(id))
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
    or (current_user_role() = 'tutor' and tutor_has_section(section_id))
  );

-- Readings ---------------------------------------------------------------------

create table if not exists public.phil_iri_readings (
  id                          bigint generated always as identity primary key,
  assessment_id               bigint not null references public.phil_iri_assessments(id) on delete cascade,
  sequence_no                 integer not null check (sequence_no > 0),
  passage_id                  bigint not null references public.phil_iri_passages(id),
  method                      text not null default 'whole_text' check (method in ('whole_text', 'one_minute')),
  reading_seconds             integer check (reading_seconds > 0),
  words_read                  integer check (words_read > 0),
  obs_word_by_word            boolean not null default false,
  obs_lacks_expression        boolean not null default false,
  obs_voice_inaudible         boolean not null default false,
  obs_disregards_punctuation  boolean not null default false,
  obs_points_to_words         boolean not null default false,
  obs_little_analysis         boolean not null default false,
  obs_other                   text,
  -- Results: written at finalization only (null while live).
  word_reading_score          numeric check (word_reading_score between 0 and 1),
  words_per_minute            numeric check (words_per_minute >= 0),
  accuracy_level              text check (accuracy_level in ('independent', 'instructional', 'frustration', 'nonReader')),
  speed                       text check (speed in ('struggling', 'slow', 'average', 'fast')),
  word_reading_level          text check (word_reading_level in ('independent', 'instructional', 'frustration', 'nonReader')),
  comprehension_score         numeric check (comprehension_score between 0 and 1),
  comprehension_level         text check (comprehension_level in ('independent', 'instructional', 'frustration')),
  profile                     text check (profile in ('independent', 'instructional', 'frustration', 'nonReader')),
  created_at                  timestamptz not null default now(),
  constraint phil_iri_readings_seq_key unique (assessment_id, sequence_no),
  constraint phil_iri_readings_method_fields check (
    (method = 'whole_text' and words_read is null)
    or (method = 'one_minute' and reading_seconds is null))
);
create index if not exists phil_iri_readings_passage on public.phil_iri_readings (passage_id);

create or replace function public.phil_iri_reading_readable(p_reading_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.phil_iri_readings r
    where r.id = p_reading_id and phil_iri_assessment_readable(r.assessment_id)
  );
$$;

create or replace function public.phil_iri_reading_writable(p_reading_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.phil_iri_readings r
    where r.id = p_reading_id and phil_iri_assessment_writable(r.assessment_id)
  );
$$;

create or replace function public.check_phil_iri_reading()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_level integer;
  v_graded boolean;
  v_active boolean;
  v_grade integer;
begin
  if auth.uid() is null then
    return new;
  end if;
  if not phil_iri_assessment_writable(new.assessment_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  if tg_op = 'UPDATE' and (new.assessment_id, new.passage_id) is distinct from (old.assessment_id, old.passage_id) then
    raise exception 'a reading keeps its session and passage; delete it and add a new one instead';
  end if;
  if not phil_iri_passage_readable(new.passage_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select p.level, c.is_grade_leveled, p.is_active and c.is_active
    into v_level, v_graded, v_active
  from public.phil_iri_passages p
  join public.phil_iri_collections c on c.id = p.collection_id
  where p.id = new.passage_id;
  if tg_op = 'INSERT' and not v_active then
    raise exception 'this passage or its collection is not active';
  end if;
  if v_graded then
    select phil_iri_section_grade(a.section_id) into v_grade
    from public.phil_iri_assessments a where a.id = new.assessment_id;
    if v_level is distinct from v_grade then
      raise exception 'a Grade % learner reads a Grade % passage (got a Grade % passage)', v_grade, v_grade, v_level;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists phil_iri_readings_check on public.phil_iri_readings;
create trigger phil_iri_readings_check
  before insert or update on public.phil_iri_readings
  for each row execute function public.check_phil_iri_reading();

drop policy if exists phil_iri_readings_select on public.phil_iri_readings;
create policy phil_iri_readings_select on public.phil_iri_readings
  for select to authenticated using (phil_iri_assessment_readable(assessment_id));
drop policy if exists phil_iri_readings_write on public.phil_iri_readings;
create policy phil_iri_readings_write on public.phil_iri_readings
  for all to authenticated
  using (phil_iri_assessment_writable(assessment_id))
  with check (phil_iri_assessment_writable(assessment_id));

-- Miscues ----------------------------------------------------------------------

create table if not exists public.phil_iri_miscues (
  id              bigint generated always as identity primary key,
  reading_id      bigint not null references public.phil_iri_readings(id) on delete cascade,
  word_index      integer not null check (word_index >= 0),
  miscue_type     text not null check (miscue_type in ('mispronunciation', 'omission', 'substitution',
                    'insertion', 'repetition', 'transposition', 'reversal')),
  spoken_text     text,
  self_corrected  boolean not null default false,
  created_at      timestamptz not null default now()
);
create index if not exists phil_iri_miscues_reading on public.phil_iri_miscues (reading_id);

create or replace function public.check_phil_iri_miscue()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_words integer;
begin
  if auth.uid() is null then
    return new;
  end if;
  if not phil_iri_reading_writable(new.reading_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select p.word_count into v_words
  from public.phil_iri_readings r join public.phil_iri_passages p on p.id = r.passage_id
  where r.id = new.reading_id;
  -- An insertion may sit after the last word (index = word count).
  if new.word_index > v_words or (new.miscue_type <> 'insertion' and new.word_index >= v_words) then
    raise exception 'word % is outside the passage (% words)', new.word_index, v_words;
  end if;
  return new;
end;
$$;

drop trigger if exists phil_iri_miscues_check on public.phil_iri_miscues;
create trigger phil_iri_miscues_check
  before insert or update on public.phil_iri_miscues
  for each row execute function public.check_phil_iri_miscue();

drop policy if exists phil_iri_miscues_select on public.phil_iri_miscues;
create policy phil_iri_miscues_select on public.phil_iri_miscues
  for select to authenticated using (phil_iri_reading_readable(reading_id));
drop policy if exists phil_iri_miscues_write on public.phil_iri_miscues;
create policy phil_iri_miscues_write on public.phil_iri_miscues
  for all to authenticated
  using (phil_iri_reading_writable(reading_id))
  with check (phil_iri_reading_writable(reading_id));

-- Answers ----------------------------------------------------------------------

create table if not exists public.phil_iri_answers (
  id           bigint generated always as identity primary key,
  reading_id   bigint not null references public.phil_iri_readings(id) on delete cascade,
  question_id  bigint not null references public.phil_iri_questions(id),
  chosen       text check (chosen ~ '^[a-z]$'),
  is_correct   boolean not null default false,
  looked_back  boolean not null default false,
  created_at   timestamptz not null default now(),
  constraint phil_iri_answers_question_key unique (reading_id, question_id)
);

create or replace function public.check_phil_iri_answer()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_key text;
  v_ok boolean;
begin
  if auth.uid() is not null and not phil_iri_reading_writable(new.reading_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select q.answer_key, q.passage_id = r.passage_id into v_key, v_ok
  from public.phil_iri_questions q, public.phil_iri_readings r
  where q.id = new.question_id and r.id = new.reading_id;
  if not coalesce(v_ok, false) then
    raise exception 'question % is not a question of this reading''s passage', new.question_id;
  end if;
  new.is_correct := new.chosen is not null and new.chosen = v_key;
  return new;
end;
$$;

drop trigger if exists phil_iri_answers_check on public.phil_iri_answers;
create trigger phil_iri_answers_check
  before insert or update on public.phil_iri_answers
  for each row execute function public.check_phil_iri_answer();

drop policy if exists phil_iri_answers_select on public.phil_iri_answers;
create policy phil_iri_answers_select on public.phil_iri_answers
  for select to authenticated using (phil_iri_reading_readable(reading_id));
drop policy if exists phil_iri_answers_write on public.phil_iri_answers;
create policy phil_iri_answers_write on public.phil_iri_answers
  for all to authenticated
  using (phil_iri_reading_writable(reading_id))
  with check (phil_iri_reading_writable(reading_id));

-- Rubric scores ----------------------------------------------------------------

create table if not exists public.phil_iri_rubric_scores (
  id            bigint generated always as identity primary key,
  assessment_id bigint not null references public.phil_iri_assessments(id) on delete cascade,
  criterion_id  bigint not null references public.phil_iri_rubric_criteria(id),
  score         integer not null,
  created_at    timestamptz not null default now(),
  constraint phil_iri_rubric_scores_key unique (assessment_id, criterion_id)
);

create or replace function public.check_phil_iri_rubric_score()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_min integer;
  v_max integer;
begin
  if auth.uid() is not null and not phil_iri_assessment_writable(new.assessment_id) then
    perform phil_iri_deny(tg_table_name);
  end if;
  select scale_min, scale_max into v_min, v_max
  from public.phil_iri_rubric_criteria where id = new.criterion_id;
  if new.score < v_min or new.score > v_max then
    raise exception 'score % is outside %..%', new.score, v_min, v_max;
  end if;
  return new;
end;
$$;

drop trigger if exists phil_iri_rubric_scores_check on public.phil_iri_rubric_scores;
create trigger phil_iri_rubric_scores_check
  before insert or update on public.phil_iri_rubric_scores
  for each row execute function public.check_phil_iri_rubric_score();

drop policy if exists phil_iri_rubric_scores_select on public.phil_iri_rubric_scores;
create policy phil_iri_rubric_scores_select on public.phil_iri_rubric_scores
  for select to authenticated using (phil_iri_assessment_readable(assessment_id));
drop policy if exists phil_iri_rubric_scores_write on public.phil_iri_rubric_scores;
create policy phil_iri_rubric_scores_write on public.phil_iri_rubric_scores
  for all to authenticated
  using (phil_iri_assessment_writable(assessment_id))
  with check (phil_iri_assessment_writable(assessment_id));

-- Content locks (now that readings exist) ----------------------------------------

create or replace function public.lock_phil_iri_read_passage()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if (new.body, new.word_count, new.level, new.collection_id)
     is distinct from (old.body, old.word_count, old.level, old.collection_id)
     and exists (select 1 from public.phil_iri_readings where passage_id = old.id) then
    raise exception 'this passage has already been read; its text, word count, level and collection are locked (add a new passage instead)';
  end if;
  return new;
end;
$$;

drop trigger if exists phil_iri_passages_lock_read on public.phil_iri_passages;
create trigger phil_iri_passages_lock_read
  before update on public.phil_iri_passages
  for each row execute function public.lock_phil_iri_read_passage();

create or replace function public.lock_phil_iri_collection_grading()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.is_grade_leveled is distinct from old.is_grade_leveled
     and exists (select 1 from public.phil_iri_passages where collection_id = old.id) then
    raise exception 'a collection with passages cannot change whether it is grade-leveled';
  end if;
  return new;
end;
$$;

drop trigger if exists phil_iri_collections_lock_grading on public.phil_iri_collections;
create trigger phil_iri_collections_lock_grading
  before update on public.phil_iri_collections
  for each row execute function public.lock_phil_iri_collection_grading();

-- RLS on and no anon access.
alter table public.phil_iri_gst_results enable row level security;
alter table public.phil_iri_assessments enable row level security;
alter table public.phil_iri_readings enable row level security;
alter table public.phil_iri_miscues enable row level security;
alter table public.phil_iri_answers enable row level security;
alter table public.phil_iri_rubric_scores enable row level security;
revoke all on public.phil_iri_gst_results, public.phil_iri_assessments, public.phil_iri_readings,
  public.phil_iri_miscues, public.phil_iri_answers, public.phil_iri_rubric_scores
  from anon;

commit;
