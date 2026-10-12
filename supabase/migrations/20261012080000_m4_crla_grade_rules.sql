-- M4: grade-aware CRLA scoring, from the CRLA2 G1–G3 scoresheets (row 11
-- formulas and the "Max" reading times printed on each sheet).
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
--
-- Until now every grade used the Grade 1 rules. Per (grade, variant):
--   sheet             Low Emerging from        h  d2  g  comp max  time cap
--   G1 MT             Full or Moderate         0  1   4  5         60 s
--   G2 MT/FIL, G3 ENG Full only                0  2   5  6         120 s
--   G3 MT/FIL         Full only                1  3   6  7         180 s
-- where High Emerging needs comp <= h (25–50 % band), Developing comp >= h+1
-- (25–51 %) or <= d2 (50–76 %), Transitioning comp >= d2+1 (51–76 %) or
-- <= g-1 (> 75 %), At Grade Level comp >= g (> 75 %).
-- Variant/grade pairs that have no sheet (e.g. G1 eng) are parked; they fall
-- back to their grade's row.
--
-- Changes:
--  1. Helpers crla_comprehension_max / crla_time_cap_seconds /
--     crla_reading_profile (IMMUTABLE, no table access).
--  2. crla_results.reading_profile uses the section's grade. Like the Excel
--     (outer IF(J<>"")), there is no profile until Part 1 exists.
--  3. Part 2: comprehension CHECK widened to 0..7; a trigger enforces the
--     per-grade comprehension max and reading-time cap.
--  4. CRLA assessments are refused for sections outside grades 1–3.
--  5. Summary views: comprehension is divided by the grade's max, not 5,
--     and Full Refresher learners are left out of the fluency /
--     comprehension / wpm averages (as the Excel class record does).

begin;

-- 1. Helpers --------------------------------------------------------------
create or replace function public.crla_comprehension_max(p_grade int, p_variant text)
 returns int language sql immutable set search_path to 'public'
as $$
  select case
    when p_grade = 1 then 5
    when p_grade = 3 and p_variant in ('mt', 'fil') then 7
    else 6
  end;
$$;

create or replace function public.crla_time_cap_seconds(p_grade int, p_variant text)
 returns int language sql immutable set search_path to 'public'
as $$
  select case
    when p_grade = 1 then 60
    when p_grade = 3 and p_variant in ('mt', 'fil') then 180
    else 120
  end;
$$;

-- p_pct is words_read / word_count (unrounded), NULL when no story matched.
create or replace function public.crla_reading_profile(
  p_level text, p_pct numeric, p_comp int, p_grade int, p_variant text)
 returns text language sql immutable set search_path to 'public'
as $$
  select case
    when p_level is null then null
    when p_level = 'Full Refresher'
      or (p_grade = 1 and p_level = 'Moderate Refresher') then 'Low Emerging Reader'
    when p_pct is null or p_comp is null then null
    when p_pct <= 0.25
      or (p_pct > 0.25 and p_pct <= 0.50 and p_comp <= t.h) then 'High Emerging Reader'
    when (p_pct > 0.25 and p_pct < 0.51 and p_comp >= t.h + 1)
      or (p_pct > 0.50 and p_pct < 0.76 and p_comp <= t.d2) then 'Developing Reader'
    when (p_pct >= 0.51 and p_pct < 0.76 and p_comp >= t.d2 + 1)
      or (p_pct > 0.75 and p_comp <= t.g - 1) then 'Transitioning Reader'
    when p_pct > 0.75 and p_comp >= t.g then 'Reading At Grade Level'
  end
  from (
    select case when m = 7 then 1 else 0 end as h,
           m - 4 as d2,
           m - 1 as g
    from (select public.crla_comprehension_max(p_grade, p_variant) as m) x
  ) t;
$$;

-- 2. crla_results ---------------------------------------------------------
create or replace view public.crla_results with (security_invoker = true) as
select ca.id as assessment_id,
    ca.student_id,
    ca.school_id,
    ca.section_id,
    ca.school_year,
    ca.subject_variant,
    ca.language,
    ca.attempt_no,
    ca.assessed_at,
    coalesce(p1s.total_score, p1e.total_score) as part1_total_score,
    coalesce(p1s.reading_level, p1e.reading_level) as part1_reading_level,
    p2.story_no,
    p2.words_read,
    p2.miscues,
    p2.wpm,
    p2.comprehension_correct,
    p2.learner_experience_rating,
    p2.observation_level,
    p2.remarks,
    round(p2.words_read::numeric / nullif(cs.word_count, 0)::numeric, 4) as pct_correct_words_read,
    public.crla_reading_profile(
      coalesce(p1s.reading_level, p1e.reading_level),
      p2.words_read::numeric / nullif(cs.word_count, 0)::numeric,
      p2.comprehension_correct,
      (case when sec.grade_level ~ '^[0-9]+$' then sec.grade_level::int end),
      ca.subject_variant) as reading_profile
from crla_assessments ca
  left join crla_part1_standard p1s on p1s.assessment_id = ca.id
  left join crla_part1_english p1e on p1e.assessment_id = ca.id
  left join crla_part2_fluency p2 on p2.assessment_id = ca.id
  join sections sec on sec.id = ca.section_id
  join schools sch on sch.id = ca.school_id
  left join crla_stories cs on cs.region_id = sch.region_id
    and cs.language = ca.language
    and cs.grade = (case when sec.grade_level ~ '^[0-9]+$' then sec.grade_level::int end)
    and cs.story_no = p2.story_no;

-- 3. Part 2 limits --------------------------------------------------------
alter table public.crla_part2_fluency
  drop constraint if exists crla_part2_fluency_comprehension_correct_check;
alter table public.crla_part2_fluency
  add constraint crla_part2_fluency_comprehension_correct_check
  check (comprehension_correct >= 0 and comprehension_correct <= 7);

create or replace function public.check_crla_part2_limits()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_grade int;
  v_variant text;
  v_max int;
  v_cap int;
begin
  -- Answer like RLS first, so the limits below don't reveal other schools' rows.
  if auth.uid() is not null and not crla_assessment_writable(new.assessment_id) then
    raise exception 'new row violates row-level security policy for table "%"', tg_table_name
      using errcode = '42501';
  end if;

  select (case when sec.grade_level ~ '^[0-9]+$' then sec.grade_level::int end), ca.subject_variant into v_grade, v_variant
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

  return new;
end;
$$;

drop trigger if exists crla_part2_fluency_check_limits on public.crla_part2_fluency;
create trigger crla_part2_fluency_check_limits
  before insert or update on public.crla_part2_fluency
  for each row execute function public.check_crla_part2_limits();

-- 4. Only grade 1–3 sections (same policy as 20261012070000, plus the grade).
drop policy if exists crla_assessments_insert_scoped on public.crla_assessments;
create policy crla_assessments_insert_scoped on public.crla_assessments
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.sections s
      join public.enrollments e on e.section_id = s.id
      where s.id = crla_assessments.section_id
        and s.school_id = crla_assessments.school_id
        and s.grade_level in ('1', '2', '3')
        and e.student_id = crla_assessments.student_id
        and e.school_year = crla_assessments.school_year
        and e.status = 'active'
    )
    and (
      is_superadmin()
      or (current_user_role() in ('admin', 'coordinator')
          and school_id = current_user_school_id())
      or (current_user_role() = 'tutor' and tutor_has_section(section_id))
    )
  );

-- 5. Summary views --------------------------------------------------------
create or replace view public.crla_section_summary with (security_invoker = true) as
with enrolled as (
  select e.section_id, e.school_year, st_1.sex, count(*) as learners_enrolled
  from enrollments e
    join students st_1 on st_1.id = e.student_id
  where e.status = 'active'
  group by e.section_id, e.school_year, st_1.sex
)
select la.section_id,
    la.school_id,
    la.school_year,
    la.subject_variant,
    la.language,
    st.sex,
    en.learners_enrolled,
    count(*) as learners_assessed,
    count(*) filter (where la.part1_reading_level = 'Full Refresher') as full_refresher,
    count(*) filter (where la.part1_reading_level = 'Moderate Refresher') as moderate_refresher,
    count(*) filter (where la.part1_reading_level = 'Light Refresher') as light_refresher,
    count(*) filter (where la.part1_reading_level = 'Grade Ready') as grade_ready,
    round(avg(la.pct_correct_words_read)
      filter (where la.part1_reading_level is distinct from 'Full Refresher'), 4) as avg_reading_fluency,
    round(avg(la.comprehension_correct::numeric
              / public.crla_comprehension_max((case when sec.grade_level ~ '^[0-9]+$' then sec.grade_level::int end), la.subject_variant))
      filter (where la.part1_reading_level is distinct from 'Full Refresher'), 4) as avg_reading_comprehension,
    round(avg(la.wpm)
      filter (where la.part1_reading_level is distinct from 'Full Refresher'), 1) as avg_wpm,
    count(*) filter (where la.reading_profile = 'Low Emerging Reader') as low_emerging_reader,
    count(*) filter (where la.reading_profile = 'High Emerging Reader') as high_emerging_reader,
    count(*) filter (where la.reading_profile = 'Developing Reader') as developing_reader,
    count(*) filter (where la.reading_profile = 'Transitioning Reader') as transitioning_reader,
    count(*) filter (where la.reading_profile = 'Reading At Grade Level') as reading_at_grade_level
from crla_latest_attempts la
  join students st on st.id = la.student_id
  join sections sec on sec.id = la.section_id
  left join enrolled en on en.section_id = la.section_id
    and en.school_year = la.school_year and en.sex = st.sex
group by la.section_id, la.school_id, la.school_year, la.subject_variant, la.language,
         st.sex, en.learners_enrolled;

create or replace view public.crla_school_summary_weighted with (security_invoker = true) as
with enrolled as (
  select sec_1.school_id, sec_1.grade_level, e.school_year, st_1.sex, count(*) as learners_enrolled
  from enrollments e
    join sections sec_1 on sec_1.id = e.section_id
    join students st_1 on st_1.id = e.student_id
  where e.status = 'active'
  group by sec_1.school_id, sec_1.grade_level, e.school_year, st_1.sex
)
select la.school_id,
    sec.grade_level,
    la.school_year,
    la.subject_variant,
    la.language,
    st.sex,
    en.learners_enrolled,
    count(*) as learners_assessed,
    count(*) filter (where la.part1_reading_level = 'Full Refresher') as full_refresher,
    count(*) filter (where la.part1_reading_level = 'Moderate Refresher') as moderate_refresher,
    count(*) filter (where la.part1_reading_level = 'Light Refresher') as light_refresher,
    count(*) filter (where la.part1_reading_level = 'Grade Ready') as grade_ready,
    round(avg(la.pct_correct_words_read)
      filter (where la.part1_reading_level is distinct from 'Full Refresher'), 4) as avg_reading_fluency,
    round(avg(la.comprehension_correct::numeric
              / public.crla_comprehension_max((case when sec.grade_level ~ '^[0-9]+$' then sec.grade_level::int end), la.subject_variant))
      filter (where la.part1_reading_level is distinct from 'Full Refresher'), 4) as avg_reading_comprehension,
    round(avg(la.wpm)
      filter (where la.part1_reading_level is distinct from 'Full Refresher'), 1) as avg_wpm,
    count(*) filter (where la.reading_profile = 'Low Emerging Reader') as low_emerging_reader,
    count(*) filter (where la.reading_profile = 'High Emerging Reader') as high_emerging_reader,
    count(*) filter (where la.reading_profile = 'Developing Reader') as developing_reader,
    count(*) filter (where la.reading_profile = 'Transitioning Reader') as transitioning_reader,
    count(*) filter (where la.reading_profile = 'Reading At Grade Level') as reading_at_grade_level
from crla_latest_attempts la
  join sections sec on sec.id = la.section_id
  join students st on st.id = la.student_id
  left join enrolled en on en.school_id = la.school_id and en.grade_level = sec.grade_level
    and en.school_year = la.school_year and en.sex = st.sex
group by la.school_id, sec.grade_level, la.school_year, la.subject_variant, la.language,
         st.sex, en.learners_enrolled;

-- crla_school_summary reads crla_section_summary and needs no change.

commit;
