-- Lock down the dev-only "testTable" (created by hand in the cloud project,
-- no migration). Its policy testTable_authenticated_only was ALL / true / true,
-- so any signed-in user (any tutor) could read, insert and delete every row.
-- The only client of the cloud table is the console's `db-use cloud|lan`
-- demo, which uses an anonymous client and was already refused by that policy.
--
-- Fix: drop the policy and keep RLS on with no policies = deny all for
-- anon/authenticated. Skipped entirely where the table doesn't exist.

DO $$
BEGIN
  IF to_regclass('public."testTable"') IS NOT NULL THEN
    DROP POLICY IF EXISTS "testTable_authenticated_only" ON public."testTable";
    ALTER TABLE public."testTable" ENABLE ROW LEVEL SECURITY;
  END IF;
END
$$;
