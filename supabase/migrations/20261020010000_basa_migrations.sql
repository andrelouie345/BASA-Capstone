-- Migrations ledger: basa_migrations (version check at sign-in).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261019060000.
-- App update required on all devices: no (a new table; apps without the
-- version check never read it).
--
-- One row per migration applied to this database. At sign-in the app compares
-- these ids with the list it was built for (lib/core/release.dart) and refuses
-- or warns when they differ (docs/superpowers/specs/2026-10-20-version-check-design.md).
--
-- Rule for every later migration: its LAST statement inserts its own row,
--   insert into public.basa_migrations (id, name, app_update_required)
--   values ('<id>', '<name>', <true|false>) on conflict (id) do nothing;
-- with app_update_required matching its "App update required" header line.
--
-- Backfill: a row for an earlier migration is inserted only when that
-- migration's object exists, so a half-migrated server (e.g. a LAN instance
-- that skipped some files) is reported as missing them instead of passing.
-- None of the earlier migrations changed rules an older app relied on, so all
-- are app_update_required = false.
--
-- RLS:
--  * select: every signed-in user. `using (true)` is deliberate, not a
--    leftover placeholder: the table holds release metadata only, no school
--    data, and every role (tutors included) runs the check at sign-in.
--  * insert/update/delete: nobody through the API (no policy, and the
--    privileges are revoked). Only migrations run in the SQL editor write it.
--  * anon: nothing.

create table if not exists public.basa_migrations (
  id                  text primary key,
  name                text not null,
  app_update_required boolean not null,
  applied_at          timestamptz not null default now()
);

alter table public.basa_migrations enable row level security;

drop policy if exists basa_migrations_select on public.basa_migrations;
create policy basa_migrations_select on public.basa_migrations
  for select to authenticated using (true);

revoke insert, update, delete on public.basa_migrations from anon, authenticated;

-- Backfill (each only when the migration's object exists).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261018040000', 'baseline', false)
on conflict (id) do nothing;

insert into public.basa_migrations (id, name, app_update_required)
select '20261018050000', 'aral_readability_logs', false
where to_regclass('public.aral_readability_logs') is not null
on conflict (id) do nothing;

insert into public.basa_migrations (id, name, app_update_required)
select '20261019010000', 'srp_classes', false
where to_regclass('public.srp_class_members') is not null
on conflict (id) do nothing;

insert into public.basa_migrations (id, name, app_update_required)
select '20261019020000', 'srp_tutor_reads_learners', false
where exists (select 1 from pg_policies
               where schemaname = 'public' and tablename = 'students'
                 and policyname = 'students_select_srp_tutor')
on conflict (id) do nothing;

insert into public.basa_migrations (id, name, app_update_required)
select '20261019030000', 'assessment_calendar', false
where to_regclass('public.assessment_calendar') is not null
on conflict (id) do nothing;

insert into public.basa_migrations (id, name, app_update_required)
select '20261019040000', 'report_settings', false
where to_regclass('public.report_settings') is not null
on conflict (id) do nothing;

insert into public.basa_migrations (id, name, app_update_required)
select '20261019050000', 'calendar_round_pairing', false
where exists (select 1 from pg_constraint
               where conname = 'assessment_calendar_round_pairing'
                 and conrelid = to_regclass('public.assessment_calendar'))
on conflict (id) do nothing;

insert into public.basa_migrations (id, name, app_update_required)
select '20261019060000', 'aral_idle_session_days', false
where exists (select 1 from pg_constraint
               where conname = 'aral_settings_idle_session_days'
                 and conrelid = to_regclass('public.aral_settings'))
on conflict (id) do nothing;

-- This migration's own row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261020010000', 'basa_migrations', false)
on conflict (id) do nothing;
