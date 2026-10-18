-- Phil-IRI: a session reads only passages of its round. Idempotent: safe to run
-- in the Supabase SQL Editor more than once.
--
-- Rule (reading coordinator, 2026-10-15): BOSY reads 'pre' passages, MOSY #1-#3
-- read 'mosy' passages, EOSY reads 'post' passages; a passage without a test
-- type (levels 2-6, school collections, FRB) fits any round. Same mapping as
-- PhilIriRound.passageTestType in lib/core/models/phil_iri_assessment.dart and
-- the local trigger check_phil_iri_reading_ins (SQLite v16).
--
-- Checked on INSERT only, like the "active" check: an existing reading keeps
-- its passage (it can't be changed anyway) and can still be edited.
--
-- Changes: check_phil_iri_reading() replaced (body as in
-- 20261014010000_phil_iri_assessments.sql plus the round check); the trigger
-- itself is unchanged.
--
-- RLS: unchanged. No table, view or policy changes; the function keeps
-- SECURITY DEFINER with search_path = public and its writability checks.

create or replace function public.check_phil_iri_reading()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
declare
  v_level integer;
  v_graded boolean;
  v_active boolean;
  v_grade integer;
  v_test_type text;
  v_round text;
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
  select p.level, c.is_grade_leveled, p.is_active and c.is_active, p.test_type
    into v_level, v_graded, v_active, v_test_type
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
  if tg_op = 'INSERT' and v_test_type is not null then
    select a.round into v_round from public.phil_iri_assessments a where a.id = new.assessment_id;
    if v_test_type is distinct from (case v_round when 'bosy' then 'pre' when 'eosy' then 'post' else 'mosy' end) then
      raise exception 'a % session does not read a % passage (BOSY reads pre, MOSY mosy, EOSY post passages)',
        v_round, v_test_type;
    end if;
  end if;
  return new;
end;
$$;
