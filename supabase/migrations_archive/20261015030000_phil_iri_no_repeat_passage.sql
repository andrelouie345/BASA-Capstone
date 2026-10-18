-- Phil-IRI: a learner never reads the same passage twice. Idempotent: safe to
-- run in the Supabase SQL Editor more than once.
--
-- Rule (reading coordinator via owner, 2026-10-15): no learner reads the same
-- passage again, in any round or school year (retakes included). "Same" means
-- the same text, from any collection: copies such as the 2018 and 2024
-- "Anansi's Web" count as one. When a grade runs out of unread passages, the
-- coordinator adds passages. A discarded in-progress session has no readings
-- left, so it doesn't count.
--
-- Changes:
--  1. phil_iri_text_key(text): lower-case, with whitespace and punctuation
--     removed. The characters are the same as philIriTextKeyStrip in
--     lib/core/models/phil_iri_passage.dart and the local trigger (SQLite v17);
--     keep the three in step.
--  2. check_phil_iri_reading() replaced: body as in
--     20261015020000_phil_iri_round_passages.sql plus the no-repeat check
--     (INSERT only). SECURITY DEFINER, so it sees the learner's readings from
--     every tutor and section, not just the caller's.
--
-- RLS: unchanged. No table, view or policy changes; phil_iri_text_key is a
-- plain IMMUTABLE function over its argument (reads no table).

create or replace function public.phil_iri_text_key(p_body text)
 returns text language sql immutable set search_path to 'public'
as $$
  select translate(lower(p_body), E' \n\r\t.,!?;:''"`-—–()[]‘’“”…/', '');
$$;

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
  v_student bigint;
  v_read_title text;
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
  if tg_op = 'INSERT' then
    select a.round, a.student_id into v_round, v_student
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
    limit 1;
    if v_read_title is not null then
      raise exception 'this learner has already read "%"; a learner never reads the same passage twice', v_read_title;
    end if;
  end if;
  return new;
end;
$$;
