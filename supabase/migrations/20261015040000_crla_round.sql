-- CRLA: an assessment belongs to a round (BOSY / MOSY / EOSY). Idempotent: safe
-- to run in the Supabase SQL Editor more than once.
--
-- Why (owner, 2026-10-15): ARAL-Reading enrolls Grade 1 learners on their MOSY
-- CRLA result and Grades 2-3 on BOSY, and suggests exits from later rounds; the
-- summaries should also not mix BOSY and EOSY results.
--
-- Changes:
--  1. crla_assessments.round text not null default 'bosy', CHECK bosy/mosy/eosy.
--     Existing rows become BOSY. attempt_no keeps counting across rounds (the
--     unique key and crla_assessments_before_insert are unchanged); the latest
--     attempt of a round is the highest attempt_no within it.
--  2. Views (security_invoker kept): crla_results gains round; crla_latest_attempts
--     keeps the latest attempt PER ROUND; crla_section_summary, crla_school_summary
--     and crla_school_summary_weighted are per round. Each view gets round as its
--     LAST column, so CREATE OR REPLACE keeps the existing columns as they are.
--     Bodies are the current ones (from the schema dump) plus round.
--
-- RLS: unchanged. crla_assessments keeps its policies (the insert policy does not
-- look at round; there is still no update policy); every view stays
-- security_invoker = true, so callers see only the rows RLS allows.

alter table public.crla_assessments
  add column if not exists round text not null default 'bosy';
alter table public.crla_assessments drop constraint if exists crla_assessments_round_check;
alter table public.crla_assessments
  add constraint crla_assessments_round_check check (round in ('bosy', 'mosy', 'eosy'));

create or replace view public.crla_results with (security_invoker = true) as
 SELECT ca.id AS assessment_id,
    ca.student_id,
    ca.school_id,
    ca.section_id,
    ca.school_year,
    ca.subject_variant,
    ca.language,
    ca.attempt_no,
    ca.assessed_at,
    COALESCE(p1s.total_score, p1e.total_score) AS part1_total_score,
    COALESCE(p1s.reading_level, p1e.reading_level) AS part1_reading_level,
    p2.story_no,
    p2.words_read,
    p2.miscues,
    p2.wpm,
    p2.comprehension_correct,
    p2.learner_experience_rating,
    p2.observation_level,
    p2.remarks,
    round(p2.words_read::numeric / NULLIF(cs.word_count, 0)::numeric, 4) AS pct_correct_words_read,
    ca.reading_profile,
    ca.round
   FROM crla_assessments ca
     LEFT JOIN crla_part1_standard p1s ON p1s.assessment_id = ca.id
     LEFT JOIN crla_part1_english p1e ON p1e.assessment_id = ca.id
     LEFT JOIN crla_part2_fluency p2 ON p2.assessment_id = ca.id
     JOIN sections sec ON sec.id = ca.section_id
     JOIN schools sch ON sch.id = ca.school_id
     LEFT JOIN crla_stories cs ON cs.region_id = sch.region_id AND cs.language = ca.language AND cs.grade =
        CASE
            WHEN sec.grade_level ~ '^[0-9]+$'::text THEN sec.grade_level::integer
            ELSE NULL::integer
        END AND cs.story_no = p2.story_no;

create or replace view public.crla_latest_attempts with (security_invoker = true) as
 SELECT DISTINCT ON (student_id, section_id, subject_variant, school_year, round) assessment_id,
    student_id,
    school_id,
    section_id,
    school_year,
    subject_variant,
    language,
    attempt_no,
    assessed_at,
    part1_total_score,
    part1_reading_level,
    story_no,
    words_read,
    miscues,
    wpm,
    comprehension_correct,
    learner_experience_rating,
    observation_level,
    remarks,
    pct_correct_words_read,
    reading_profile,
    round
   FROM crla_results cr
  ORDER BY student_id, section_id, subject_variant, school_year, round, attempt_no DESC;

create or replace view public.crla_section_summary with (security_invoker = true) as
 WITH enrolled AS (
         SELECT e.section_id,
            e.school_year,
            st_1.sex,
            count(*) AS learners_enrolled
           FROM enrollments e
             JOIN students st_1 ON st_1.id = e.student_id
          WHERE e.status = 'active'::text
          GROUP BY e.section_id, e.school_year, st_1.sex
        )
 SELECT la.section_id,
    la.school_id,
    la.school_year,
    la.subject_variant,
    la.language,
    st.sex,
    en.learners_enrolled,
    count(*) AS learners_assessed,
    count(*) FILTER (WHERE la.part1_reading_level = 'Full Refresher'::text) AS full_refresher,
    count(*) FILTER (WHERE la.part1_reading_level = 'Moderate Refresher'::text) AS moderate_refresher,
    count(*) FILTER (WHERE la.part1_reading_level = 'Light Refresher'::text) AS light_refresher,
    count(*) FILTER (WHERE la.part1_reading_level = 'Grade Ready'::text) AS grade_ready,
    round(avg(la.pct_correct_words_read) FILTER (WHERE la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text), 4) AS avg_reading_fluency,
    round(avg(la.comprehension_correct::numeric / crla_comprehension_max(
        CASE
            WHEN sec.grade_level ~ '^[0-9]+$'::text THEN sec.grade_level::integer
            ELSE NULL::integer
        END, la.subject_variant)::numeric) FILTER (WHERE la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text), 4) AS avg_reading_comprehension,
    round(avg(la.wpm) FILTER (WHERE la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text), 1) AS avg_wpm,
    count(*) FILTER (WHERE la.reading_profile = 'Low Emerging Reader'::text) AS low_emerging_reader,
    count(*) FILTER (WHERE la.reading_profile = 'High Emerging Reader'::text) AS high_emerging_reader,
    count(*) FILTER (WHERE la.reading_profile = 'Developing Reader'::text) AS developing_reader,
    count(*) FILTER (WHERE la.reading_profile = 'Transitioning Reader'::text) AS transitioning_reader,
    count(*) FILTER (WHERE la.reading_profile = 'Reading At Grade Level'::text) AS reading_at_grade_level,
    la.round
   FROM crla_latest_attempts la
     JOIN students st ON st.id = la.student_id
     JOIN sections sec ON sec.id = la.section_id
     LEFT JOIN enrolled en ON en.section_id = la.section_id AND en.school_year = la.school_year AND en.sex = st.sex
  GROUP BY la.section_id, la.school_id, la.school_year, la.subject_variant, la.language, st.sex, en.learners_enrolled, la.round;

create or replace view public.crla_school_summary with (security_invoker = true) as
 SELECT css.school_id,
    sec.grade_level,
    css.school_year,
    css.subject_variant,
    css.language,
    css.sex,
    sum(css.learners_enrolled) AS learners_enrolled,
    sum(css.learners_assessed) AS learners_assessed,
    sum(css.full_refresher) AS full_refresher,
    sum(css.moderate_refresher) AS moderate_refresher,
    sum(css.light_refresher) AS light_refresher,
    sum(css.grade_ready) AS grade_ready,
    round(avg(css.avg_reading_fluency), 4) AS avg_reading_fluency,
    round(avg(css.avg_reading_comprehension), 4) AS avg_reading_comprehension,
    round(avg(css.avg_wpm), 1) AS avg_wpm,
    sum(css.low_emerging_reader) AS low_emerging_reader,
    sum(css.high_emerging_reader) AS high_emerging_reader,
    sum(css.developing_reader) AS developing_reader,
    sum(css.transitioning_reader) AS transitioning_reader,
    sum(css.reading_at_grade_level) AS reading_at_grade_level,
    css.round
   FROM crla_section_summary css
     JOIN sections sec ON sec.id = css.section_id
  GROUP BY css.school_id, sec.grade_level, css.school_year, css.subject_variant, css.language, css.sex, css.round;

create or replace view public.crla_school_summary_weighted with (security_invoker = true) as
 WITH enrolled AS (
         SELECT sec_1.school_id,
            sec_1.grade_level,
            e.school_year,
            st_1.sex,
            count(*) AS learners_enrolled
           FROM enrollments e
             JOIN sections sec_1 ON sec_1.id = e.section_id
             JOIN students st_1 ON st_1.id = e.student_id
          WHERE e.status = 'active'::text
          GROUP BY sec_1.school_id, sec_1.grade_level, e.school_year, st_1.sex
        )
 SELECT la.school_id,
    sec.grade_level,
    la.school_year,
    la.subject_variant,
    la.language,
    st.sex,
    en.learners_enrolled,
    count(*) AS learners_assessed,
    count(*) FILTER (WHERE la.part1_reading_level = 'Full Refresher'::text) AS full_refresher,
    count(*) FILTER (WHERE la.part1_reading_level = 'Moderate Refresher'::text) AS moderate_refresher,
    count(*) FILTER (WHERE la.part1_reading_level = 'Light Refresher'::text) AS light_refresher,
    count(*) FILTER (WHERE la.part1_reading_level = 'Grade Ready'::text) AS grade_ready,
    round(avg(la.pct_correct_words_read) FILTER (WHERE la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text), 4) AS avg_reading_fluency,
    round(avg(la.comprehension_correct::numeric / crla_comprehension_max(
        CASE
            WHEN sec.grade_level ~ '^[0-9]+$'::text THEN sec.grade_level::integer
            ELSE NULL::integer
        END, la.subject_variant)::numeric) FILTER (WHERE la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text), 4) AS avg_reading_comprehension,
    round(avg(la.wpm) FILTER (WHERE la.part1_reading_level IS DISTINCT FROM 'Full Refresher'::text), 1) AS avg_wpm,
    count(*) FILTER (WHERE la.reading_profile = 'Low Emerging Reader'::text) AS low_emerging_reader,
    count(*) FILTER (WHERE la.reading_profile = 'High Emerging Reader'::text) AS high_emerging_reader,
    count(*) FILTER (WHERE la.reading_profile = 'Developing Reader'::text) AS developing_reader,
    count(*) FILTER (WHERE la.reading_profile = 'Transitioning Reader'::text) AS transitioning_reader,
    count(*) FILTER (WHERE la.reading_profile = 'Reading At Grade Level'::text) AS reading_at_grade_level,
    la.round
   FROM crla_latest_attempts la
     JOIN sections sec ON sec.id = la.section_id
     JOIN students st ON st.id = la.student_id
     LEFT JOIN enrolled en ON en.school_id = la.school_id AND en.grade_level = sec.grade_level AND en.school_year = la.school_year AND en.sex = st.sex
  GROUP BY la.school_id, sec.grade_level, la.school_year, la.subject_variant, la.language, st.sex, en.learners_enrolled, la.round;
