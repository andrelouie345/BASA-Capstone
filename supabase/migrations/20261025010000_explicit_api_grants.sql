-- Explicit Data API grants for every table, view and sequence in public.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261024050000.
-- App update required on all devices: no (the same access the app has today;
-- only who grants it changes).
--
-- Why: from 2026-10-30 Supabase stops granting anon / authenticated /
-- service_role access to new tables in public automatically
-- (github.com/orgs/supabase/discussions/45329). That covers every database
-- built from these migrations: a new cloud project, a school's LAN instance,
-- `supabase db reset`. The baseline and the later migrations relied on those
-- automatic grants (they only revoke), so a fresh database would refuse every
-- table ("permission denied", 42501). Self-hosted images are not mentioned by
-- Supabase; explicit grants work either way.
--
-- Rule from here on: a migration that creates a table or view grants it in
-- the same file (test/supabase/migration_grants_test.dart checks it).
--
-- Who gets what (RLS still decides which rows):
--  * authenticated: select, insert, update, delete on every table, select on
--    every view (a view is a relation, `all tables` covers it; writes through
--    the five crla_* views fail anyway). Then the narrower limits that exist
--    today are re-applied: users UPDATE only on is_active, basa_migrations
--    select only, sync_uploads select and insert only.
--  * service_role: select, insert, update, delete on every table and view
--    (the create-user and bootstrap-admin Edge Functions write users; the
--    service role bypasses RLS but still needs the grants).
--  * anon: INSERT on login_logs only (failed sign-ins, policy
--    login_logs_insert_own). Every other policy is `to authenticated`.
--  * sequences: usage, select to authenticated and service_role. Every id is
--    an identity column today (inserts need no sequence grant); this covers a
--    future serial column.
--  * No TRUNCATE, REFERENCES or TRIGGER for anon or authenticated (TRUNCATE
--    skips RLS). An existing project still holds them from Supabase's old
--    defaults; they are revoked so it matches a fresh database.
--  * Functions are untouched: Postgres lets PUBLIC execute a new function by
--    default, and the migrations already revoke/grant the restricted ones.
--
-- Dev only: "testTable" (not in any migration, used by `db-use` with
-- anonymous clients until the DB-switching redesign) keeps select, insert,
-- delete for anon when it exists.

-- 1. authenticated and service_role: every table and view.
grant select, insert, update, delete on all tables in schema public to authenticated, service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;
revoke truncate, references, trigger on all tables in schema public from authenticated;

-- 2. anon: nothing but the failed sign-in log.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
grant insert on public.login_logs to anon;

-- 3. The narrower limits, re-applied after the bulk grant (same statements as
-- the baseline and 20261020010000 / 20261020020000). Revoking the table-level
-- UPDATE also drops the column grant, so the column grant comes after it.
revoke update on public.users from authenticated;
grant update (is_active) on public.users to authenticated;
revoke insert, update, delete on public.basa_migrations from authenticated;
revoke update, delete on public.sync_uploads from authenticated;

-- 4. Dev only: keep db-use working on testTable.
do $$
begin
  if to_regclass('public."testTable"') is not null then
    execute 'grant select, insert, delete on public."testTable" to anon';
    -- its id may be a serial column (unknown: the table is not in a migration)
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'testTable' and column_name = 'id') then
      if pg_get_serial_sequence('public."testTable"', 'id') is not null then
        execute format('grant usage, select on sequence %s to anon',
                       pg_get_serial_sequence('public."testTable"', 'id'));
      end if;
    end if;
  end if;
end $$;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261025010000', 'explicit_api_grants', false)
on conflict (id) do nothing;
