-- ARAL: the foundational literacy program switch (SHARP). Idempotent: safe to
-- run in the Supabase SQL Editor more than once.
--
-- Reading coordinator (2026-10-18): a school may run SHARP (or another
-- foundational literacy program) for learners reading at adjusted levels 0-1;
-- it is optional and the coordinator switches it. Off (the default) follows
-- the current ARAL program guidelines: those learners go to KS1. The setting
-- lives in aral_settings like the check-in cut-off (defaults <- region <-
-- school, merged in the app).
--
-- Changes:
--  1. aral_settings: settings.foundational_program, when present, must be a
--     JSON boolean.
--
-- RLS: unchanged and re-checked for this key: aral_settings_select (superadmin,
-- the region row, or the caller's own school) and aral_settings_write
-- (superadmin, or an admin/coordinator for their own school's row only; the
-- region row is the superadmin's) from 20261016030000_aral_checkins.sql. A
-- tutor cannot switch it. No table, view or function added.

alter table public.aral_settings drop constraint if exists aral_settings_foundational_program;
alter table public.aral_settings
  add constraint aral_settings_foundational_program check (
    not settings ? 'foundational_program'
    or jsonb_typeof(settings->'foundational_program') = 'boolean');
