-- CRLA adjustable thresholds (piece C2). Idempotent: safe to run in the
-- Supabase SQL Editor more than once.
--
-- Owner decisions (2026-10-15):
--  * The Part 1 refresher bands and the reading-profile bands are adjustable.
--    Comprehension max, reading-time caps and the Part 1 task structure stay
--    fixed (instrument facts).
--  * Defaults reproduce the DepEd scoresheet formulas exactly, gaps included.
--  * Old results are kept: an assessment snapshots the thresholds that applied
--    when it was recorded; its Part 1 level and reading profile are computed
--    from that snapshot and stored. crla_regenerate_results() re-scores chosen
--    assessments with today's thresholds (admin/coordinator, superadmin).
--  * Settings: one region-wide row (superadmin) and at most one override per
--    school (that school's admin/coordinator). Effective = built-in defaults
--    <- region <- school, key by key (as phil_iri_thresholds). Keys and the
--    defaults match CrlaThresholds.toMap() in lib/core/services/crla_rules.dart.
--
-- Changes:
--  1. crla_thresholds table + RLS.
--  2. Helpers: crla_threshold_defaults(), crla_effective_thresholds(school),
--     crla_part1_std_level / crla_part1_eng_level / crla_reading_profile_t
--     (rules with a thresholds jsonb). The old 5-argument
--     crla_reading_profile() now calls the new one with the defaults.
--  3. crla_assessments gets thresholds_snapshot and reading_profile, stamped
--     by the insert trigger (client values are ignored when signed in).
--  4. Part 1 reading_level stops being a generated column (DROP EXPRESSION
--     keeps the column, its values and the views); a trigger fills it from the
--     assessment's snapshot. total_score and wpm stay generated.
--  5. Triggers on Part 1/Part 2 keep crla_assessments.reading_profile current.
--  6. crla_results reads the stored profile (same columns as before).
--  7. crla_regenerate_results(ids).
--  8. Backfill: existing assessments get the effective thresholds of their
--     school and their stored level/profile.

begin;

-- 1. Settings table -------------------------------------------------------------
create table if not exists public.crla_thresholds (
  id          bigint generated always as identity primary key,
  school_id   bigint references public.schools(id),
  settings    jsonb not null check (jsonb_typeof(settings) = 'object'),
  updated_by  uuid references public.users(id),
  updated_at  timestamptz not null default now()
);
create unique index if not exists crla_thresholds_school_key
  on public.crla_thresholds (coalesce(school_id, 0));

create or replace function public.crla_thresholds_stamp()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  new.updated_at := now();
  if auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists crla_thresholds_stamp on public.crla_thresholds;
create trigger crla_thresholds_stamp
  before insert or update on public.crla_thresholds
  for each row execute function public.crla_thresholds_stamp();

alter table public.crla_thresholds enable row level security;

drop policy if exists crla_thresholds_select on public.crla_thresholds;
create policy crla_thresholds_select on public.crla_thresholds
  for select to authenticated
  using (is_superadmin() or school_id is null or school_id = current_user_school_id());

drop policy if exists crla_thresholds_write on public.crla_thresholds;
create policy crla_thresholds_write on public.crla_thresholds
  for all to authenticated
  using (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id is not null and school_id = current_user_school_id())
  )
  with check (
    is_superadmin()
    or (current_user_role() in ('admin', 'coordinator')
        and school_id is not null and school_id = current_user_school_id())
  );

revoke all on public.crla_thresholds from anon;

-- 2. Helpers --------------------------------------------------------------------

-- Same keys and values as CrlaThresholds.defaults.toMap().
create or replace function public.crla_threshold_defaults()
 returns jsonb language sql immutable set search_path to 'public'
as $$
  select '{
    "part1_std_full_max": 10, "part1_std_light_max": 26,
    "part1_eng_full_max": 0, "part1_eng_moderate_max": 10, "part1_eng_light_max": 16,
    "pct_high_emerging_max": 25, "pct_low_band_max": 50, "pct_mid_band_min": 51,
    "pct_top_band_above": 75, "pct_mid_band_below": 76,
    "g1_h": 0, "g1_d2": 1, "g1_g": 4, "g1_moderate_is_low_emerging": true,
    "g2_h": 0, "g2_d2": 2, "g2_g": 5, "g2_moderate_is_low_emerging": false,
    "g3_mtfil_h": 1, "g3_mtfil_d2": 3, "g3_mtfil_g": 6, "g3_mtfil_moderate_is_low_emerging": false,
    "g3_eng_h": 0, "g3_eng_d2": 2, "g3_eng_g": 5, "g3_eng_moderate_is_low_emerging": false
  }'::jsonb;
$$;

-- Defaults <- region row <- the school's override. Only for the triggers and
-- crla_regenerate_results (EXECUTE is revoked from clients below), so it
-- cannot be used to read another school's override.
create or replace function public.crla_effective_thresholds(p_school_id bigint)
 returns jsonb language sql stable security definer set search_path to 'public'
as $$
  select public.crla_threshold_defaults()
      || coalesce((select settings from public.crla_thresholds where school_id is null), '{}'::jsonb)
      || coalesce((select settings from public.crla_thresholds where school_id = p_school_id), '{}'::jsonb);
$$;

-- t is a full thresholds object (defaults merged in).
create or replace function public.crla_part1_std_level(p_task1 int, p_total int, t jsonb)
 returns text language sql immutable set search_path to 'public'
as $$
  select case
    when p_task1 is null or p_total is null then null
    when p_task1 < 7 then
      case when p_total <= (t->>'part1_std_full_max')::int then 'Full Refresher' else 'Moderate Refresher' end
    else
      case when p_total <= (t->>'part1_std_light_max')::int then 'Light Refresher' else 'Grade Ready' end
  end;
$$;

create or replace function public.crla_part1_eng_level(p_total int, t jsonb)
 returns text language sql immutable set search_path to 'public'
as $$
  select case
    when p_total is null then null
    when p_total <= (t->>'part1_eng_full_max')::int then 'Full Refresher'
    when p_total <= (t->>'part1_eng_moderate_max')::int then 'Moderate Refresher'
    when p_total <= (t->>'part1_eng_light_max')::int then 'Light Refresher'
    else 'Grade Ready'
  end;
$$;

-- The scoresheet a grade/variant is scored with (CrlaSheet.of in Dart).
create or replace function public.crla_sheet_key(p_grade int, p_variant text)
 returns text language sql immutable set search_path to 'public'
as $$
  select case
    when p_grade = 1 then 'g1'
    when p_grade = 3 and p_variant in ('mt', 'fil') then 'g3_mtfil'
    when p_grade = 3 then 'g3_eng'
    else 'g2'
  end;
$$;

-- The scoresheet's row 11 formula (crlaReadingProfile in Dart). p_pct is
-- words_read / word_count, unrounded; NULL when no story matched.
create or replace function public.crla_reading_profile_t(
  p_level text, p_pct numeric, p_comp int, p_grade int, p_variant text, t jsonb)
 returns text language sql immutable set search_path to 'public'
as $$
  select case
    when p_level is null then null
    when p_level = 'Full Refresher'
      or (x.mod_low and p_level = 'Moderate Refresher') then 'Low Emerging Reader'
    when p_pct is null or p_comp is null then null
    when p_pct <= x.a
      or (p_pct > x.a and p_pct <= x.b and p_comp <= x.h) then 'High Emerging Reader'
    when (p_pct > x.a and p_pct < x.mid and p_comp >= x.h + 1)
      or (p_pct > x.b and p_pct < x.below and p_comp <= x.d2) then 'Developing Reader'
    when (p_pct >= x.mid and p_pct < x.below and p_comp >= x.d2 + 1)
      or (p_pct > x.top and p_comp <= x.g - 1) then 'Transitioning Reader'
    when p_pct > x.top and p_comp >= x.g then 'Reading At Grade Level'
  end
  from (
    select (t->>'pct_high_emerging_max')::numeric / 100 as a,
           (t->>'pct_low_band_max')::numeric / 100 as b,
           (t->>'pct_mid_band_min')::numeric / 100 as mid,
           (t->>'pct_top_band_above')::numeric / 100 as top,
           (t->>'pct_mid_band_below')::numeric / 100 as below,
           (t->>(s.k || '_h'))::int as h,
           (t->>(s.k || '_d2'))::int as d2,
           (t->>(s.k || '_g'))::int as g,
           coalesce((t->>(s.k || '_moderate_is_low_emerging'))::boolean, false) as mod_low
    from (select public.crla_sheet_key(p_grade, p_variant) as k) s
  ) x;
$$;

-- Kept for anything still calling the old signature: the defaults.
create or replace function public.crla_reading_profile(
  p_level text, p_pct numeric, p_comp int, p_grade int, p_variant text)
 returns text language sql immutable set search_path to 'public'
as $$
  select public.crla_reading_profile_t(p_level, p_pct, p_comp, p_grade, p_variant,
                                       public.crla_threshold_defaults());
$$;

-- 3. Snapshot and stored profile on the assessment ----------------------------------
alter table public.crla_assessments add column if not exists thresholds_snapshot jsonb;
alter table public.crla_assessments add column if not exists reading_profile text;

-- Replaces the M4 function: attempt_no and administered_by as before, plus
-- the snapshot. A signed-in client cannot choose its snapshot or profile.
create or replace function public.crla_assessments_before_insert()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  select coalesce(max(attempt_no), 0) + 1 into new.attempt_no
  from public.crla_assessments
  where student_id = new.student_id
    and school_id = new.school_id
    and section_id = new.section_id
    and subject_variant = new.subject_variant
    and school_year = new.school_year;

  if auth.uid() is not null then
    new.administered_by := auth.uid();
  end if;
  if auth.uid() is not null or new.thresholds_snapshot is null then
    new.thresholds_snapshot := public.crla_effective_thresholds(new.school_id);
  else
    -- No JWT (SQL Editor, seed): a given snapshot is completed with defaults.
    new.thresholds_snapshot := public.crla_threshold_defaults() || new.thresholds_snapshot;
  end if;
  new.reading_profile := null; -- filled once Part 1 exists
  return new;
end;
$$;

-- The thresholds an assessment is scored with (its snapshot, defaults merged in).
create or replace function public.crla_assessment_thresholds(p_assessment_id bigint)
 returns jsonb language sql stable security definer set search_path to 'public'
as $$
  select public.crla_threshold_defaults() || coalesce(ca.thresholds_snapshot, '{}'::jsonb)
  from public.crla_assessments ca where ca.id = p_assessment_id;
$$;

-- 4. Part 1 reading_level from the snapshot -----------------------------------------
alter table public.crla_part1_standard alter column reading_level drop expression if exists;
alter table public.crla_part1_english alter column reading_level drop expression if exists;

create or replace function public.crla_part1_set_level()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  t jsonb := public.crla_assessment_thresholds(new.assessment_id);
begin
  if tg_table_name = 'crla_part1_standard' then
    new.reading_level := public.crla_part1_std_level(
      new.task1_score,
      case when new.task1_score < 7 then new.task1_score + coalesce(new.task2_low_score, 0)
           else new.task1_score + 10 + coalesce(new.task2_high_score, 0) end,
      t);
  else
    new.reading_level := public.crla_part1_eng_level(
      new.task1_score + coalesce(new.task2_score, 0), t);
  end if;
  return new;
end;
$$;

-- Named after *_check_variant so it runs after it (BEFORE triggers fire in
-- name order).
drop trigger if exists crla_part1_standard_set_level on public.crla_part1_standard;
create trigger crla_part1_standard_set_level
  before insert or update on public.crla_part1_standard
  for each row execute function public.crla_part1_set_level();
drop trigger if exists crla_part1_english_set_level on public.crla_part1_english;
create trigger crla_part1_english_set_level
  before insert or update on public.crla_part1_english
  for each row execute function public.crla_part1_set_level();

-- 5. Stored reading profile ----------------------------------------------------------
create or replace function public.crla_refresh_profile(p_assessment_id bigint)
 returns void language sql security definer set search_path to 'public'
as $$
  -- Same joins as crla_results (story by region, language, grade, story_no).
  update public.crla_assessments ca
  set reading_profile = (
    select public.crla_reading_profile_t(
             coalesce(p1s.reading_level, p1e.reading_level),
             p2.words_read::numeric / nullif(cs.word_count, 0)::numeric,
             p2.comprehension_correct,
             g.grade,
             ca.subject_variant,
             public.crla_threshold_defaults() || coalesce(ca.thresholds_snapshot, '{}'::jsonb))
    from public.sections sec
    join public.schools sch on sch.id = ca.school_id
    cross join lateral (
      select case when sec.grade_level ~ '^[0-9]+$' then sec.grade_level::int end as grade) g
    left join public.crla_part1_standard p1s on p1s.assessment_id = ca.id
    left join public.crla_part1_english p1e on p1e.assessment_id = ca.id
    left join public.crla_part2_fluency p2 on p2.assessment_id = ca.id
    left join public.crla_stories cs on cs.region_id = sch.region_id
      and cs.language = ca.language
      and cs.grade = g.grade
      and cs.story_no = p2.story_no
    where sec.id = ca.section_id)
  where ca.id = p_assessment_id;
$$;

create or replace function public.crla_refresh_profile_trigger()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  perform public.crla_refresh_profile(coalesce(new.assessment_id, old.assessment_id));
  return null;
end;
$$;

drop trigger if exists crla_part1_standard_refresh_profile on public.crla_part1_standard;
create trigger crla_part1_standard_refresh_profile
  after insert or update or delete on public.crla_part1_standard
  for each row execute function public.crla_refresh_profile_trigger();
drop trigger if exists crla_part1_english_refresh_profile on public.crla_part1_english;
create trigger crla_part1_english_refresh_profile
  after insert or update or delete on public.crla_part1_english
  for each row execute function public.crla_refresh_profile_trigger();
drop trigger if exists crla_part2_fluency_refresh_profile on public.crla_part2_fluency;
create trigger crla_part2_fluency_refresh_profile
  after insert or update or delete on public.crla_part2_fluency
  for each row execute function public.crla_refresh_profile_trigger();

-- 6. crla_results reads the stored profile -----------------------------------------
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
    ca.reading_profile
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

-- 7. Regenerate with today's thresholds ----------------------------------------------
-- All-or-nothing: refused when any id is missing or not the caller's to manage
-- (superadmin: any; admin/coordinator: own school). Returns how many were
-- re-scored. Tutors cannot regenerate.
create or replace function public.crla_regenerate_results(p_assessment_ids bigint[])
 returns int language plpgsql security definer set search_path to 'public'
as $$
declare
  v_missing int;
  v_denied int;
  v_id bigint;
  v_count int := 0;
begin
  select count(*) into v_missing
  from unnest(p_assessment_ids) as u(id)
  where not exists (select 1 from public.crla_assessments ca where ca.id = u.id);
  if v_missing > 0 then
    raise exception 'no CRLA assessment with % of the given ids', v_missing;
  end if;

  if auth.uid() is not null and not is_superadmin() then
    select count(*) into v_denied
    from public.crla_assessments ca
    where ca.id = any(p_assessment_ids)
      and not (current_user_role() in ('admin', 'coordinator')
               and ca.school_id = current_user_school_id());
    if v_denied > 0 then
      raise exception 'only an admin or coordinator of the school can regenerate CRLA results'
        using errcode = '42501';
    end if;
  end if;

  for v_id in select distinct u.id from unnest(p_assessment_ids) as u(id) loop
    update public.crla_assessments
    set thresholds_snapshot = public.crla_effective_thresholds(school_id)
    where id = v_id;
    -- Re-run the level triggers (they read the new snapshot).
    update public.crla_part1_standard set task1_score = task1_score where assessment_id = v_id;
    update public.crla_part1_english set task1_score = task1_score where assessment_id = v_id;
    perform public.crla_refresh_profile(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Internal helpers are not callable by clients; regenerate is.
revoke execute on function public.crla_effective_thresholds(bigint) from public, anon, authenticated;
revoke execute on function public.crla_assessment_thresholds(bigint) from public, anon, authenticated;
revoke execute on function public.crla_refresh_profile(bigint) from public, anon, authenticated;
revoke execute on function public.crla_regenerate_results(bigint[]) from public, anon;
grant execute on function public.crla_regenerate_results(bigint[]) to authenticated;

-- 8. Backfill existing rows ------------------------------------------------------------
update public.crla_assessments
set thresholds_snapshot = public.crla_effective_thresholds(school_id)
where thresholds_snapshot is null;
update public.crla_part1_standard set task1_score = task1_score;
update public.crla_part1_english set task1_score = task1_score;
do $$
begin
  perform public.crla_refresh_profile(id) from public.crla_assessments;
end;
$$;

commit;
