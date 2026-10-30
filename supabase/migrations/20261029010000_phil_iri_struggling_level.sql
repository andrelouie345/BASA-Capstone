-- Phil-IRI: the Struggling word recognition level and DepEd's new bands.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261025010000.
-- App update required on all devices: yes (a new stored level older apps
-- can't read, and new default bands change how readings are scored).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Spec: docs/superpowers/specs/2026-10-29-phil-iri-word-recognition-bands-design.md
-- Word recognition bands (DepEd): Non-Reader <= 35%, Struggling 36-55%,
-- Frustration 56-89%. The word reading profile and the reading profile
-- follow the fixed "Table 8. Student's Reading Profile Per Passage". The
-- scoring itself lives in the app (lib/core/services/phil_iri_rules.dart);
-- the database only stores the levels of finalized readings.
--
-- Changes:
--  1. phil_iri_readings: accuracy_level, word_reading_level and profile also
--     allow 'struggling' (comprehension_level is unchanged: comprehension has
--     no Struggling level). Rows already stored are not touched: finalized
--     rows keep their stored levels (the app recomputes results; spec D8).
--  2. phil_iri_thresholds: a saved non_reader_max is removed from every row,
--     so the new default (35) applies everywhere (spec D3: the saved values
--     were dev data).
--
-- No table, view or policy is created or changed (no grants needed; RLS as
-- before).

-- 1. The three level columns.
alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_accuracy_level_check;
alter table public.phil_iri_readings add constraint phil_iri_readings_accuracy_level_check
  check (accuracy_level = any (array['independent', 'instructional', 'frustration', 'struggling', 'nonReader']));

alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_word_reading_level_check;
alter table public.phil_iri_readings add constraint phil_iri_readings_word_reading_level_check
  check (word_reading_level = any (array['independent', 'instructional', 'frustration', 'struggling', 'nonReader']));

alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_profile_check;
alter table public.phil_iri_readings add constraint phil_iri_readings_profile_check
  check (profile = any (array['independent', 'instructional', 'frustration', 'struggling', 'nonReader']));

-- 2. Saved non-reader cut-offs.
update public.phil_iri_thresholds
   set settings = settings - 'non_reader_max'
 where settings ? 'non_reader_max';

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261029010000', 'phil_iri_struggling_level', true)
on conflict (id) do nothing;
