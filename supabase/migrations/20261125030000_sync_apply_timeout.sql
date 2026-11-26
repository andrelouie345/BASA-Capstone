-- Sync: applying an upload may run for up to 60 s (found by the demo builder,
-- 2026-11-25: approving one section's Phil-IRI round, about 1000 rows, ran
-- past the API's 8 s statement timeout even after 20261125020000).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261125020000.
-- App update required on all devices: no (a function setting only; the
-- function's body, rules and grants stay as 20261112020000 left them).
--
-- sync_apply inserts an upload one row at a time, each checked by RLS, inside
-- one transaction. A large upload (a whole section's round) needs more than
-- 8 s. PostgREST (12 and later) applies a called function's own
-- statement_timeout setting to that call's transaction, so only sync_apply
-- gets the longer limit; every other API call keeps 8 s.
-- Inserting an upload table by table instead of row by row (the real fix) is
-- a planned follow-up.
--
-- Note: a later "create or replace function public.sync_apply" REPLACES the
-- function's settings with the ones it lists. Any migration that redefines
-- sync_apply must list "set statement_timeout = '60s'" again (or re-run the
-- alter below), or the 8 s limit comes back.
--
-- RLS: no table, view or policy changes.

alter function public.sync_apply(bigint) set statement_timeout = '60s';

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261125030000', 'sync_apply_timeout', false)
on conflict (id) do nothing;
