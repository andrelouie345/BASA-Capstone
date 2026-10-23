-- CRLA Part 2: words read follow the CRLA2 scoresheet, story words - miscues
-- (command pass finding F10, owner decision 2026-10-23).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261023010000.
-- App update required on all devices: yes (a rule change: an older app sends
-- the words read a tutor typed; this server replaces them with the story's
-- words - miscues, so the device and the server would disagree until the app
-- is updated).
--
-- Rule (the DepEd CRLA2 scoresheet, column M "words read" = the story's words
-- - miscues; ENG stories are 100 words, the ENG sheet's 100 - miscues):
--   * When a crla_stories row matches the assessment (school's region, the
--     assessment's language, the section's grade, the story number), every
--     insert or update of crla_part2_fluency sets words_read = word_count -
--     miscues; more miscues than words is refused.
--   * When no story matches (regions without stories), the value the client
--     sends is kept, as before.
--   * Rows already stored keep their words_read until they are next updated.
-- The app does the same (lib/core/services/crla_rules.dart crlaWordsRead,
-- CrlaViewModel.savePart2Fluency). wpm is a generated column, computed after
-- this BEFORE trigger, so it follows the new words_read; the reading profile
-- triggers run AFTER.
--
-- RLS: unchanged. The function stays SECURITY DEFINER with search_path public
-- and keeps answering like RLS first, so its other checks don't reveal other
-- schools' rows.

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

  -- Words read = the story's words - miscues, when the story is known (F10).
  select cs.word_count into v_words
  from public.crla_stories cs
  join public.schools sch on sch.region_id = cs.region_id
  where sch.id = v_school and cs.language = v_language and cs.grade = v_grade
    and cs.story_no = new.story_no;
  if found then
    if new.miscues > v_words then
      raise exception '% miscues is more than the % words of the story', new.miscues, v_words
        using errcode = '23514';
    end if;
    new.words_read := v_words - new.miscues;
  end if;

  return new;
end;
$_$;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261023020000', 'crla_words_read_from_story', true)
on conflict (id) do nothing;
