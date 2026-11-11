-- Phil-IRI rules update (R1): comprehension gets a Struggling level.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261109010000.
-- App update required on all devices: yes (a new stored comprehension level
-- older apps can't read, and the rules for who counts as assessed change).
-- Apply only when all work is finalized: every device synced, every upload
-- decided (README "Keeping BASA up to date").
--
-- Spec: docs/superpowers/specs/2026-11-09-phil-iri-rules-update-design.md
-- Comprehension bands (reading coordinator, 2026-11-09): Struggling <= 40%,
-- Frustration 41-58%, Instructional 59-79%, Independent >= 80%. The scoring,
-- the "not assessed" labels and who counts as assessed all live in the app
-- (lib/core/services/phil_iri_rules.dart, phil_iri_results.dart); the
-- database only stores the levels of finalized readings.
--
-- Changes:
--  1. phil_iri_readings: comprehension_level also allows 'struggling'. Rows
--     already stored are not touched (the app recomputes results from the raw
--     readings).
--
-- No table, view or policy is created or changed (no grants needed; RLS as
-- before). Saved thresholds need nothing: the new key
-- comprehension_struggling_max is absent from saved rows, so the default (40)
-- applies.

-- 1. The comprehension level column.
alter table public.phil_iri_readings drop constraint if exists phil_iri_readings_comprehension_level_check;
alter table public.phil_iri_readings add constraint phil_iri_readings_comprehension_level_check
  check (comprehension_level = any (array['independent', 'instructional', 'frustration', 'struggling']));

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261109020000', 'phil_iri_rules_update', true)
on conflict (id) do nothing;
