# Sync S1 (server migration) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One idempotent Supabase migration that gives the server everything sync needs: `row_version` on the 18 synced tables, the `sync_uploads` table with RLS, the `sync_withdraw` / `sync_reject` / `sync_apply` functions, the release guard and the two new `report_settings` keys.

**Architecture:** `sync_apply` is `SECURITY INVOKER`, so every row write passes the caller's RLS and the existing CHECKs and triggers. Bookkeeping on `sync_uploads` (claim with a row lock, final status) goes through two `SECURITY DEFINER` helpers in a new schema `basa_private` that PostgREST does not expose, so clients cannot call them directly; they also re-check the caller's rights. All data writes of one upload run in a plpgsql sub-block: conflicts or errors roll the sub-block back and the status is written afterwards.

**Tech Stack:** Postgres (Supabase), plpgsql, a throwaway local Postgres 18 harness (bash + psql), Dart (`lib/core/release.dart` only).

**Spec:** `docs/superpowers/specs/2026-10-20-sync-design.md` (sections 1, 2, 8, 9, 11, 12-S1).

## Global Constraints

- New file `supabase/migrations/20261020020000_sync_uploads.sql`; never edit the baseline. Idempotent (runs twice cleanly).
- Header lines: `App update required on all devices: yes` plus one line: "Apply only when all work is finalized: every device synced, every upload decided (README *Keeping BASA up to date*)."
- LAST statement: `insert into public.basa_migrations (id, name, app_update_required) values ('20261020020000', 'sync_uploads', true) on conflict (id) do nothing;`
- `lib/core/release.dart` gets `'20261020020000': 'sync_uploads',` in the same commit; README 2b lists the migration with "app update required: yes".
- Every `SECURITY DEFINER` function: `SET search_path = public`. No view is added. anon gets nothing on any new object.
- Role helpers to use (baseline): `is_superadmin()`, `current_user_role()`, `current_user_school_id()` (all return null/false for inactive users).
- Synced tables (exactly 18): `crla_assessments`, `crla_part1_standard`, `crla_part1_english`, `crla_part2_fluency`, `phil_iri_gst_results`, `phil_iri_assessments`, `phil_iri_readings`, `phil_iri_miscues`, `phil_iri_answers`, `phil_iri_rubric_scores`, `aral_enrollments`, `aral_sessions`, `aral_attendance`, `aral_tutor_settings`, `aral_irip_weeks`, `aral_checkins`, `aral_checkin_answers`, `aral_readability_logs`.
- Key column per table: `assessment_id` for the three `crla_part*` tables, `tutor_id` for `aral_tutor_settings`, `id` for the rest.
- Device negative ids come from ONE countdown per device (spec 3.1), so a negative id is unique across all tables of one package. `sync_apply` keeps one flat map `old negative id -> new id` for lookups and writes `id_map` per table (`{"aral_sessions": {"-5": 812}}`).
- Columns rewritten through the map when their value is negative (taken from the baseline's foreign keys; nothing else):
  `crla_part1_standard.assessment_id`, `crla_part1_english.assessment_id`, `crla_part2_fluency.assessment_id`, `phil_iri_readings.assessment_id`, `phil_iri_rubric_scores.assessment_id`, `phil_iri_miscues.reading_id`, `phil_iri_answers.reading_id`, `aral_attendance.session_id`, `aral_attendance.enrollment_id`, `aral_irip_weeks.enrollment_id`, `aral_checkins.enrollment_id`, `aral_checkin_answers.checkin_id`, `aral_readability_logs.enrollment_id`, `aral_enrollments.basis_assessment_id`, `aral_enrollments.suggestion_assessment_id` (the last two are polymorphic; the flat map resolves them without knowing the source table).

## Review Focus

1. A hostile or corrupt payload (table not in the 18, column not in the table, non-object row, missing key, `format` not 1) → `error` status with a message, never dynamic SQL built from unchecked names. Test in Task 3.
2. Two approvers calling `sync_apply` on the same upload → only one applies; the other gets "not pending". Pinned by "applied upload cannot be applied again" in Task 3 (the row lock makes the concurrent case the same as the sequential one).
3. An update to a row the caller can no longer see (tutor unassigned) → reported as a conflict with `server_row = null`, not as a silent 0-row success. Test in Task 3.
4. A package that updates a parent then its child, where the child's server trigger bumps the parent's `row_version` → no false conflict (parents are processed first). Test in Task 3 with `crla_assessments` + `crla_part2_fluency`.
5. A negative FK value with no entry in the map (parent not in this package) → `error` naming the table, column and value, not a raw FK violation or a write to the wrong row. Test in Task 3.

---

### Task 1: Harness, `row_version`, settings keys, ledger

**Files:**
- Create: `supabase/migrations/20261020020000_sync_uploads.sql` (this task writes the header, `row_version` section, `report_settings` CHECKs and the final ledger insert; later tasks insert their sections above the ledger insert)
- Modify: `lib/core/release.dart` (add the line), `README.md` section 2b (one line)
- Test: `D:/0_CAPSTONE/verify/sync-s1/` — `run.sh`, `stubs.sql`, `fixture.sql`, `steps_1.sql` (the harness doubles as the owner's verify kit)

**Interfaces:**
- Produces: column `row_version bigint not null default 1` on the 18 tables; function `public.basa_bump_row_version()` (trigger, sets `new.row_version := old.row_version + 1`); trigger `sync_row_version` BEFORE UPDATE on each of the 18; `report_settings` CHECKs `report_settings_sync_auto_approve` (absent or JSON boolean) and `report_settings_offline_signin_days` (absent or a JSON number that is a whole number 1-60, same pattern as `aral_settings_idle_session_days`, so `7.0` passes and `7.5` / `"7"` fail).
- Produces (harness): `run.sh` = the d3pg recipe (copy from session d9ceb2e5 scratchpad `d3pg/`: `stubs.sql`, `fixture.sql`, `run.sh`): init PG18 on port 54329 with trap cleanup, stubs, baseline, regions seed, migrations `20261018050000` … `20261020010000` in order, `fixture.sql` (grants + `t()` + `expect_true()` + data), then the new migration TWICE, then `steps_*.sql`, then prints `select name, ok, want, msg from results where ok <> want` and a PASS/FAIL count.
- Fixture data to add (literal ids, `overriding system value`): schools 1-2 (region 13); users SA, C1 (coord school 1), C2 (coord school 2), A1 (admin school 1), T1, T4 (tutors school 1), T2 (tutor school 2), T3 inactive; sections 10 (school 1, grade '7'), 12 (school 1, grade '2'), 20 (school 2, grade '7'); students and enrollments in those sections; `tutor_section_assignments` T1→10 and 12, T2→20; one pulled `aral_enrollments` row id 100 (student in section 10, tutor T1), one `aral_sessions` row id 200 (T1), one `crla_assessments` row id 300 (section 12, T1) with its `crla_part2_fluency` row. Use whatever columns the baseline requires; check them in the baseline, don't guess.

- [ ] **Step 1: Copy the harness and write `steps_1.sql` (failing)**

```sql
-- row_version
call t('rv default 1', :'SA', $q$select expect_true((select row_version = 1 from aral_sessions where id = 200), 'not 1')$q$, true);
call t('rv bump', :'SA', $q$update aral_sessions set remarks = 'x' where id = 200; select expect_true((select row_version = 2 from aral_sessions where id = 200), 'not 2')$q$, true);
call t('rv all 18', :'SA', $q$select expect_true((select count(*) = 18 from information_schema.columns where table_schema = 'public' and column_name = 'row_version'), 'count')$q$, true);
call t('rv trigger 18', :'SA', $q$select expect_true((select count(*) = 18 from pg_trigger where tgname = 'sync_row_version'), 'count')$q$, true);
-- settings keys
call t('auto approve true ok', :'C1', $q$insert into report_settings (school_id, settings) values (1, '{"sync_auto_approve": true}')$q$, true);
call t('auto approve "yes" refused', :'C1', $q$update report_settings set settings = '{"sync_auto_approve": "yes"}' where school_id = 1$q$, false);
call t('offline days 1/60/7.0 ok', :'SA', $q$insert into report_settings (school_id, settings) values (null, '{"offline_signin_days": 1}'); update report_settings set settings = '{"offline_signin_days": 60}' where school_id is null; update report_settings set settings = '{"offline_signin_days": 7.0}' where school_id is null$q$, true);
call t('offline days 0 refused', :'SA', $q$update report_settings set settings = '{"offline_signin_days": 0}' where school_id is null$q$, false);
call t('offline days 61 refused', :'SA', $q$update report_settings set settings = '{"offline_signin_days": 61}' where school_id is null$q$, false);
call t('offline days 7.5 refused', :'SA', $q$update report_settings set settings = '{"offline_signin_days": 7.5}' where school_id is null$q$, false);
call t('offline days "7" refused', :'SA', $q$update report_settings set settings = '{"offline_signin_days": "7"}' where school_id is null$q$, false);
-- ledger
call t('ledger row yes', :'SA', $q$select expect_true((select app_update_required from basa_migrations where id = '20261020020000'), 'missing')$q$, true);
```

(Check `aral_sessions` has a `remarks` column in the baseline; use any updatable non-key column.)

- [ ] **Step 2: Run `bash D:/0_CAPSTONE/verify/sync-s1/run.sh`** — expected: the migration file doesn't exist yet → harness stops at applying it.

- [ ] **Step 3: Write the migration sections** — header (Global Constraints wording, plus an RLS summary comment like `20261020010000`'s), `row_version` via a `do $$ foreach t in array [...18 names] loop execute format(...) $$` block (`add column if not exists`; `drop trigger if exists` + `create trigger`), the two CHECKs (`drop constraint if exists` + `add constraint`; fail the migration with a clear message if existing rows violate them, like `20261019060000` does), and the ledger insert as the last statement. Add the `release.dart` line and the README 2b line.

- [ ] **Step 4: Run the harness** — expected: both migration runs succeed, `0 failing`, all Task 1 names PASS.

- [ ] **Step 5: `dart analyze`** — expected: no errors (existing warnings accepted).

### Task 2: `sync_uploads`, RLS, withdraw and reject

**Files:**
- Modify: `supabase/migrations/20261020020000_sync_uploads.sql` (section above the ledger insert)
- Test: `D:/0_CAPSTONE/verify/sync-s1/steps_2.sql` (add to `run.sh`)

**Interfaces:**
- Produces: table `public.sync_uploads` with the spec 2.2 columns. Types: `id bigint generated always as identity primary key`, `client_upload_id uuid not null unique`, `uploader_id uuid not null default auth.uid() references users(id)`, `school_id bigint references schools(id)` (null only for a superadmin's upload), `device_id uuid not null`, `release text not null`, `status text not null default 'pending'` CHECK in the six values, `payload jsonb not null` CHECK object, `summary jsonb not null default '{}'` CHECK object, `reason text`, `conflicts jsonb`, `id_map jsonb`, `created_at timestamptz not null default now()`, `decided_at timestamptz`, `decided_by uuid references users(id)`. Index on `(school_id, status)`.
- Produces: RLS — `sync_uploads_insert` (authenticated, with check `uploader_id = auth.uid() and current_user_role() is not null and school_id is not distinct from current_user_school_id() and status = 'pending' and reason is null and conflicts is null and id_map is null and decided_at is null and decided_by is null`); `sync_uploads_select` (using `uploader_id = auth.uid() or is_superadmin() or (current_user_role() in ('admin','coordinator') and school_id = current_user_school_id())`); `revoke update, delete, truncate on public.sync_uploads from authenticated`; `revoke all ... from anon`.
- Produces: `public.sync_is_approver(p_school_id bigint) returns boolean` (stable SECURITY DEFINER: `is_superadmin() or (current_user_role() in ('admin','coordinator') and p_school_id = current_user_school_id())`).
- Produces: `public.sync_auto_approve(p_school_id bigint) returns boolean` (stable SECURITY DEFINER: the school row's `settings->'sync_auto_approve'`, else the `school_id is null` row's, else false).
- Produces: schema `basa_private` (`grant usage to authenticated`; `revoke all from anon, public`), and in it:
  - `basa_private.sync_claim(p_id bigint) returns public.sync_uploads` (SECURITY DEFINER): `select ... for update`; raises `'Upload % not found'` if missing; `'Upload % is %, not pending'` unless pending; allowed if `sync_is_approver(school_id)`, or `uploader_id = auth.uid()` and (`current_user_role() in ('admin','coordinator')` or `sync_auto_approve(school_id)`); else raises `'Not allowed to apply upload %'` with errcode `42501`.
  - `basa_private.sync_finish(p_id bigint, p_status text, p_reason text, p_conflicts jsonb, p_id_map jsonb) returns void` (SECURITY DEFINER): only from `pending`; `p_status in ('applied','conflict','error')`; sets `decided_at = now()`, `decided_by = auth.uid()`. It re-checks the same rights as `sync_claim`.
  - execute on both granted to authenticated only.
- Produces: `public.sync_withdraw(p_id bigint) returns void` and `public.sync_reject(p_id bigint, p_reason text) returns void` (SECURITY DEFINER). Withdraw: uploader only, pending only → `withdrawn`. Reject: `sync_is_approver(school_id)`, pending only, `nullif(trim(p_reason), '')` required → `rejected` with reason. Messages: `'Only the uploader can withdraw upload %'`, `'A reason is required to reject an upload'`, `'Upload % is %, not pending'`. Execute: authenticated only.

- [ ] **Step 1: Write `steps_2.sql` (failing)** — use literal uuids for `client_upload_id` and `device_id` and `\gset` for ids:

```sql
call t('T1 inserts own pending', :'T1', $q$insert into sync_uploads (client_upload_id, school_id, device_id, release, payload) values ('11111111-1111-1111-1111-111111111111', 1, '22222222-2222-2222-2222-222222222222', '20261020020000', '{"format":1,"records":[]}')$q$, true);
call t('T1 cannot insert for school 2', :'T1', $q$insert into sync_uploads (client_upload_id, school_id, device_id, release, payload) values (gen_random_uuid(), 2, gen_random_uuid(), 'x', '{}')$q$, false);
call t('T1 cannot insert as applied', :'T1', $q$insert into sync_uploads (client_upload_id, school_id, device_id, release, payload, status) values (gen_random_uuid(), 1, gen_random_uuid(), 'x', '{}', 'applied')$q$, false);
call t('T1 cannot insert as T4', :'T1', $q$insert into sync_uploads (client_upload_id, uploader_id, school_id, device_id, release, payload) values (gen_random_uuid(), :'T4', 1, gen_random_uuid(), 'x', '{}')$q$, false);
call t('duplicate client id refused', :'T1', $q$insert into sync_uploads (client_upload_id, school_id, device_id, release, payload) values ('11111111-1111-1111-1111-111111111111', 1, gen_random_uuid(), 'x', '{}')$q$, false);
call t('T3 inactive cannot insert', :'T3', $q$insert into sync_uploads (client_upload_id, school_id, device_id, release, payload) values (gen_random_uuid(), 1, gen_random_uuid(), 'x', '{}')$q$, false);
call t('T1 direct update refused', :'T1', $q$update sync_uploads set status = 'applied'$q$, false);
call t('C1 direct update refused', :'C1', $q$update sync_uploads set status = 'applied'$q$, false);
call t('T4 sees nothing', :'T4', $q$select expect_true((select count(*) = 0 from sync_uploads), 'sees')$q$, true);
call t('C2 sees nothing', :'C2', $q$select expect_true((select count(*) = 0 from sync_uploads), 'sees')$q$, true);
call t('C1 sees it', :'C1', $q$select expect_true((select count(*) = 1 from sync_uploads), 'blind')$q$, true);
call t('private claim not callable by anon', :'T1', $q$set local role anon; select basa_private.sync_claim(1)$q$, false);
call t('T4 cannot withdraw T1 upload', :'T4', $q$select sync_withdraw(1)$q$, false);
call t('C1 reject without reason refused', :'C1', $q$select sync_reject(1, '  ')$q$, false);
call t('C2 cannot reject school 1', :'C2', $q$select sync_reject(1, 'no')$q$, false);
call t('T1 cannot reject', :'T1', $q$select sync_reject(1, 'no')$q$, false);
call t('C1 rejects', :'C1', $q$select sync_reject(1, 'wrong scores'); select expect_true((select status = 'rejected' and reason = 'wrong scores' and decided_by = auth.uid() from sync_uploads where id = 1), 'not rejected')$q$, true);
call t('withdraw after reject refused', :'T1', $q$select sync_withdraw(1)$q$, false);
-- a second pending upload (id 2) for withdraw
call t('T1 withdraws own pending', :'T1', $q$insert into sync_uploads (client_upload_id, school_id, device_id, release, payload) values (gen_random_uuid(), 1, gen_random_uuid(), '20261020020000', '{"format":1,"records":[]}'); select sync_withdraw((select max(id) from sync_uploads)); select expect_true((select status = 'withdrawn' from sync_uploads where id = (select max(id) from sync_uploads)), 'not withdrawn')$q$, true);
call t('auto approve default false', :'T1', $q$select expect_true(not sync_auto_approve(2), 'true')$q$, true);
```

- [ ] **Step 2: Run the harness** — expected: Task 2 names FAIL (table missing).
- [ ] **Step 3: Write the section** (table, index, RLS, revokes, the two public helpers, `basa_private` + its two functions, withdraw, reject; all `create or replace` / `if not exists` / `drop policy if exists`).
- [ ] **Step 4: Run the harness** — expected: `0 failing`. Also check by hand that the fixture's blanket `grant all on all tables` runs BEFORE the migration (the migration's revoke must win); if not, reorder `run.sh`.

### Task 3: `sync_apply`

**Files:**
- Modify: `supabase/migrations/20261020020000_sync_uploads.sql` (section above the ledger insert)
- Test: `D:/0_CAPSTONE/verify/sync-s1/steps_3.sql`

**Interfaces:**
- Consumes: `basa_private.sync_claim`, `basa_private.sync_finish`, `basa_migrations`, the 18-table list and FK column list (Global Constraints).
- Produces: `public.sync_apply(p_id bigint) returns jsonb` — `SECURITY INVOKER`, `SET search_path = public`, execute to authenticated only. Returns `{"status": "...", "reason": ..., "conflicts": ..., "id_map": ...}` (the row's new values) so the device needs no second read.

Behaviour (in order):
1. `sync_claim(p_id)` (raises on not found / not pending / not allowed; nothing changes).
2. Release guard: if `exists (select 1 from basa_migrations where app_update_required and id > payload->>'release')`, raise `'Upload % was made by an older BASA release (%); update the device and sync again'` (status stays pending, so the tutor can withdraw and resend).
3. Validate shape before any write; a failure → `sync_finish(..., 'error', message, null, null)`: `format` = 1; `records` is an array; each record has `table` in the 18, `op` in `insert|update|delete`, `key` an object with exactly the table's key column, `row` an object for insert/update whose keys are all real columns of that table (check against `pg_attribute`), `base_version` an integer for update/delete. Inserts into id-keyed tables need a negative `key.id`.
4. Sub-block (`begin ... exception when others`), walking records in order, tracking `v_where := format('%s %s', table, key)` for messages:
   - Rewrite every FK column from the list whose value is negative through the flat map; a miss raises `'%: %.% = % is not in this upload'`.
   - insert: drop `id` and `row_version` from the row; for id-keyed tables `insert ... returning id` and add `key.id -> new id` to both maps; for the part tables / `aral_tutor_settings` the key column comes from the (rewritten) key and stays in the row.
   - update: `update <t> set (<cols>) = (select <cols> from jsonb_populate_record(null::<t>, row)) where <key> = ... and row_version = base_version` with `<cols>` = the row's columns minus key, `id`, `row_version`; all identifiers via `format('%I')`. 0 rows → append a conflict `{table, key, base_version, server_version, server_row}` from `select to_jsonb(x) from <t> x where <key> = ...` (null if not visible), continue.
   - delete: same version test; 0 rows → conflict.
   - After the walk: conflicts non-empty → `raise exception using errcode = 'BSY01'`.
   - Handler: `BSY01` → status `conflict` with the list; anything else → status `error`, reason `v_where || ': ' || sqlerrm`. (Variables survive the sub-block rollback.)
5. Success → `sync_finish(p_id, 'applied', null, null, id_map)`.

- [ ] **Step 1: Write `steps_3.sql` (failing)**. Helper at the top (as SA, outside `t()`): a function `mk(uid uuid, school bigint, payload jsonb) returns bigint` that inserts a pending upload directly as superuser and returns its id. Tests (assert both the returned status and the data, each data check as SA):

```sql
-- inserts with children and the polymorphic basis id
-- payload P1 (T1): crla_assessments -1 (section 12) + crla_part2_fluency key {assessment_id:-1};
--   aral_sessions -2 + aral_attendance -3 {session_id:-2, enrollment_id:100};
--   aral_enrollments -4 with basis_source 'crla', basis_assessment_id -1
call t('C1 applies P1', :'C1', $q$select expect_true((select sync_apply(:p1)->>'status' = 'applied'), 'not applied')$q$, true);
call t('P1 children point at new ids', :'SA', $q$select expect_true((select a.session_id = (u.id_map->'aral_sessions'->>'-2')::bigint from aral_attendance a, sync_uploads u where u.id = :p1 and a.id = (u.id_map->'aral_attendance'->>'-3')::bigint), 'bad map')$q$, true);
call t('P1 basis id mapped', :'SA', $q$select expect_true((select e.basis_assessment_id = (u.id_map->'crla_assessments'->>'-1')::bigint from aral_enrollments e, sync_uploads u where u.id = :p1 and e.id = (u.id_map->'aral_enrollments'->>'-4')::bigint), 'bad basis')$q$, true);
call t('applied upload cannot be applied again', :'C1', $q$select sync_apply(:p1)$q$, false);
-- permissions
call t('T1 cannot apply without auto approve', :'T1', $q$select sync_apply(:p2)$q$, false);
call t('C2 cannot apply school 1', :'C2', $q$select sync_apply(:p2)$q$, false);
call t('T1 applies own with auto approve on', :'T1', $q$<as SA beforehand: insert report_settings school 1 {"sync_auto_approve": true}> select expect_true((select sync_apply(:p2)->>'status' = 'applied'), 'x')$q$, true);
call t('T4 cannot apply T1 upload even with auto approve', :'T4', $q$select sync_apply(:p3)$q$, false);
call t('A1 applies own upload (admin)', :'A1', ...);
-- conflicts
-- P4 (T1): update aral_sessions 200 base_version 1 after SA bumped it to 2, plus update aral_enrollments 100 base_version 1, plus delete crla_assessments 300 base_version 9
call t('P4 conflict lists 2', :'C1', $q$select expect_true((select (r->>'status') = 'conflict' and jsonb_array_length(r->'conflicts') = 2 from (select sync_apply(:p4) r) x), 'x')$q$, true);
call t('P4 rolled back', :'SA', $q$select expect_true((select row_version = 1 from aral_enrollments where id = 100), 'enrollment changed')$q$, true);
-- error with rollback
-- P5: insert aral_sessions -10 (valid) then insert aral_attendance with mark 'late' (CHECK fails)
call t('P5 error', :'C1', $q$select expect_true((select sync_apply(:p5)->>'status' = 'error'), 'x')$q$, true);
call t('P5 reason names record', :'SA', $q$select expect_true((select reason like 'aral_attendance%' from sync_uploads where id = :p5), 'x')$q$, true);
call t('P5 session rolled back', :'SA', $q$select expect_true((select count(*) = <count before> from aral_sessions), 'kept')$q$, true);
-- Review Focus 1: hostile payloads -> error, nothing written
call t('table not synced', :'C1', $q$<payload table 'users'> select expect_true((select sync_apply(:p6)->>'status' = 'error'), 'x')$q$, true);
call t('unknown column', :'C1', $q$<row {"id":-1, "x; drop table users":1}> ... 'error'$q$, true);
call t('format 2', :'C1', ... 'error' ..., true);
call t('insert with positive id', :'C1', ... 'error' ..., true);
-- Review Focus 3: hidden row = conflict, server_row null
-- P8 (T2, school 2): update aral_sessions 200 (school 1, invisible to T2) -> applied by C2 -> conflict, server_row null
-- Review Focus 4: parent then child, server trigger bumps parent
-- P9 (T1): update crla_assessments 300 base 1, update crla_part2_fluency {assessment_id:300} base 1 -> applied
-- Review Focus 5: dangling negative FK
-- P10: aral_attendance insert with session_id -99 not in package -> error 'aral_attendance: aral_attendance.session_id = -99 is not in this upload'
-- release guard
-- P11 with release '20261019060000' after inserting a fake ledger row ('20261020015000', 'x', true) as SA -> raises; status still pending; delete the fake row afterwards
call t('old release refused', :'C1', $q$select sync_apply(:p11)$q$, false);
call t('old release still pending', :'SA', $q$select expect_true((select status = 'pending' from sync_uploads where id = :p11), 'x')$q$, true);
```

The `<...>` parts are fixture choices the implementer writes with literal values from the baseline (exact required columns, a real CHECK to violate); the asserted outcomes are fixed. Check that every UPDATE fixture really changed a row (memory: RLS can make an `INSERT ... SELECT` / UPDATE silently do nothing → false pass).

- [ ] **Step 2: Run the harness** — expected: Task 3 names FAIL (`sync_apply` missing).
- [ ] **Step 3: Write `sync_apply`** per the behaviour list.
- [ ] **Step 4: Run the harness** — expected: `0 failing` across steps 1-3, migration applied twice cleanly.
- [ ] **Step 5: Kit README** — `D:/0_CAPSTONE/verify/sync-s1/README.txt`: (1) run `bash run.sh`, expect the last line `0 failing`; (2) apply the migration on the dev cloud in the SQL editor, then run `select id, app_update_required from basa_migrations order by id desc limit 1;` → `20261020020000 | true`; (3) sign in with the console (`dart run lib/console/main.dart`, `sign-in cloud <tutor>`), expect no version warning; (4) the same sign-in from a build WITHOUT the `release.dart` line would be refused (explain, don't require).
- [ ] **Step 6: `dart analyze`**, then fresh reviewer on the migration + harness, then hand the owner the commit message (owner runs git).
