# Version Check at Sign-in Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** At online sign-in, compare the migrations this app was built for with the server's `basa_migrations` ledger, and let the user in, warn, or refuse with a message naming the files to apply or the update needed.

**Architecture:** A new migration creates the ledger and backfills only the migrations whose objects exist. The app carries a const map of known migration ids (`lib/core/release.dart`). A pure-Dart rule (`version_check.dart`) compares the two and builds the messages. `AuthViewModel.signIn` runs it after the `isActive` check through an injected ledger repository. The console gets `version-app` and `version-check`.

**Tech Stack:** Dart (no Flutter in `core/` or `viewmodels/`), supabase-dart, Postgres 18 for the migration harness.

**Spec:** `docs/superpowers/specs/2026-10-20-version-check-design.md`

## Global Constraints

- New migration `supabase/migrations/20261020010000_basa_migrations.sql`; header `App update required on all devices: no`; idempotent (run twice without error).
- Ids are compared as strings (14-digit filename timestamps), never as dates. `pubspec.yaml` `version` is untouched.
- No SQLite table, no SQLite version bump (stays 33).
- Fail closed: any ledger fetch error after authentication refuses sign-in.
- Message and `failure_reason` texts are exactly the spec's (section 3).
- Only the anon key; nothing in the app writes `basa_migrations`.
- Done = `dart analyze` (no new errors), PG harness run, console run, kit `D:/0_CAPSTONE/verify/version-check/`, a fresh reviewer, and a commit message handed over (the owner runs git).

## Deviations from the spec (decided here)

1. **Missing-table detection moves from the repository to `AuthViewModel`.** `lib/core/CLAUDE.md` says repositories don't catch `PostgrestException`. So `fetchAll()` returns `List<LedgerRow>` and throws. The ViewModel maps PostgREST `PGRST205` or Postgres `42P01` to "no ledger table". Behaviour and messages are unchanged.
2. **A fifth BLOCK verdict, `noLedger`.** It is kept separate from `blockServerOld` because its message and `failure_reason` differ (spec section 3). Console label: `BLOCK: no ledger table`.
3. **The migration also revokes insert/update/delete from `anon, authenticated`.** RLS without write policies already refuses writes; the revoke is defence in depth.

## Review Focus

1. **Half-migrated LAN server.** A ledger applied on top of a server missing `030000`/`040000` must not claim them. Pinned: Task 1 harness case B.
2. **Missing files listed oldest first, whatever order the server returns.** The admin applies them in that order. Pinned: Task 2 probe case `order`.
3. **Ledger readable but empty** (select policy dropped) gives "unreadable", not "apply all 9 files". **Ledger not readable at all** (grant revoked, an error) fails closed. Pinned: Task 2 probe case `empty`; kit step 6 (revoke/grant).
4. **A refused re-sign-in leaves the previous session untouched.** A blocked sign-in must not clear or replace an existing `_client`/`currentUser`, the same as the inactive-account path today. Pinned: kit step 5 (`whoami` after a refused sign-in).
5. **`versionWarning` does not stick.** It is cleared at the start of every `signIn` and in `signOut`, so a later clean sign-in prints no note. Pinned: kit step 3.

---

### Task 1: Ledger migration

**Files:**
- Create: `supabase/migrations/20261020010000_basa_migrations.sql`
- Test: scratchpad `pg/` (harness per memory *pg-test-harness*: stubs + baseline)

**Interfaces:**
- Produces: table `public.basa_migrations(id text pk, name text not null, app_update_required boolean not null, applied_at timestamptz not null default now())`; policy `basa_migrations_select` (select, `to authenticated`, `using (true)`); the 9 rows listed in spec section 1.

- [ ] **Step 1: Write the harness script** `pg/run.sh`. It starts a fresh cluster (port 54329, `PGCLIENTENCODING=UTF8`), loads the stubs, and runs three cases:
  - **A fresh:** baseline + all 7 newer migrations + the ledger twice. Expect 9 rows.
  - **B half:** baseline + `20261019010000` + `20261019020000` + the ledger. Expect exactly `20261018040000, 20261019010000, 20261019020000, 20261020010000`.
  - **C RLS (on A):** as `authenticated` (with `request.jwt.claim.sub` set), `select count(*)` = 9. `insert`, `update` and `delete` each raise. As `anon`, `select count(*)` = 0 or permission denied.

  Each case runs in its own database (`createdb a`, `b`). The script always ends with `pg_ctl stop` + `rm -rf pgdata`.
- [ ] **Step 2:** Run it before the migration exists. Expected: case A fails on the missing file.
- [ ] **Step 3: Write the migration.** Use the spec section 1 DDL plus the policy (`drop policy if exists` first), then `revoke insert, update, delete on public.basa_migrations from anon, authenticated;`. Add a comment that explains the deliberate `using (true)` exception. Then insert the backfill rows, one statement per row, in this shape:

  ```sql
  insert into public.basa_migrations (id, name, app_update_required)
  select '20261019040000', 'report_settings', false
  where to_regclass('public.report_settings') is not null
  on conflict (id) do nothing;
  ```

  The guards are the spec's table:
  - `pg_policies` (`schemaname='public' and tablename='students' and policyname='students_select_srp_tutor'`)
  - `pg_constraint` (`conname = '...'`) for 050000/060000

  The baseline row is unconditional, and the last statement is the ledger's own row.
- [ ] **Step 4:** Run the harness. Expected: A = 9 rows (and 9 after the second run), B = the 4 ids, C as stated.

---

### Task 2: Pure rule and app list

**Files:**
- Create: `lib/core/release.dart`, `lib/core/models/ledger_row.dart`, `lib/core/services/version_check.dart`
- Test: scratchpad `probe_version.dart` (run with `--packages=.../.dart_tool/package_config.json`)

**Interfaces:**
- `const Map<String, String> basaMigrations`: id → name, the 9 entries, oldest first.
- `class LedgerRow { final String id; final String name; final bool appUpdateRequired; LedgerRow(...); factory LedgerRow.fromMap(Map<String, Object?> m) }` (keys `id`, `name`, `app_update_required`).
- `enum VersionVerdict { ok, warn, blockServerOld, blockAppOld, noLedger, unreadable }`
- `class VersionCheck { final VersionVerdict verdict; final Map<String, String> missingOnServer; final List<LedgerRow> unknownToApp; bool get blocks; }`. `blocks` is true for every verdict except `ok` and `warn`. Both collections are sorted by id ascending.
- `VersionCheck checkVersion(Map<String, String> appKnown, List<LedgerRow>? server)`. `null` gives `noLedger`. An empty list gives `unreadable`. Otherwise Rule A, where server-old beats app-old.
- `String versionMessage(VersionCheck c)`: the spec's exact text per verdict. Each file line is `  <id>_<name>.sql` for server-old/noLedger and `  <id>_<name>` (+ ` (app update required)`) for app-old/warn. For `ok`, it returns `''`.
- `String versionFailureReason(VersionCheck c)`: the spec's `login_logs` strings (ids comma-separated).
- `String versionLabel(VersionVerdict v)`: `OK`, `WARN`, `BLOCK: server older`, `BLOCK: app older`, `BLOCK: no ledger table`, `BLOCK: ledger unreadable`.
- `const fetchFailedReason = 'version check: fetch failed'` and `String fetchFailedMessage(Object error)` (spec text).

- [ ] **Step 1: Write the probe.** Use `app = {'1':'a','2':'b','3':'c'}` and `r(id, yes)` to build rows. Assert:
  - `same`: all three rows give `ok`, and `versionMessage` is `''`.
  - `server-old`: rows 1,3 give `blockServerOld`, `missingOnServer.keys` is `['2']`, and the message contains `  2_b.sql` and `README section 2b`.
  - `order`: app with 5 ids and server rows `[1]` only, passed as `[r('1')]`, give `missingOnServer.keys` in ascending order `['2','3','4','5']`. Also run `checkVersion` with the server list shuffled `[3,1]` against app `{1,2,3}`: missing is `['2']`.
  - `warn`: rows 1,2,3 + `r('4', false)` give `warn`, the message contains `additions this app doesn't use yet`, and `blocks == false`.
  - `app-old`: rows 1,2,3 + `r('4', false)` + `r('5', true)` give `blockAppOld`. The message lists both 4 and 5, only 5 is tagged `(app update required)`, and the reason is `version check: app missing 4, 5`.
  - `both`: rows 1,3 + `r('5', true)` give `blockServerOld`.
  - `empty`: `[]` gives `unreadable`, and the message contains `empty or not readable`.
  - `null`: gives `noLedger`. The message contains `20261020010000_basa_migrations.sql` and `and any earlier file from section 2b not yet applied`. The reason is `version check: no ledger table`.
  - `real`: `checkVersion(basaMigrations, <the 9 as rows>)` gives `ok`, and `basaMigrations.keys.last == '20261020010000'`.

  Print `PASS`/`FAIL <case>` for each case, then exit 1 on any failure.
- [ ] **Step 2:** Run the probe. Expected: it doesn't compile (the files are missing).
- [ ] **Step 3:** Write the three files.
- [ ] **Step 4:** Run the probe. Expected: every case `PASS`. Then run `dart analyze`: no new errors.

---

### Task 3: Ledger repository, sign-in gate, console, wiring

**Files:**
- Create: `lib/core/repositories/migration_ledger_repository.dart`, `lib/core/data/remote/migration_ledger_repository_supabase.dart`, `lib/core/console/commands/version_commands.dart`
- Modify: `lib/viewmodels/auth_viewmodel.dart`, `lib/core/console/commands/auth_commands.dart`, `lib/console/main.dart:171-177`, `lib/main.dart:165-171`

**Interfaces:**
- Consumes: Task 2 (`checkVersion`, `versionMessage`, `versionFailureReason`, `versionLabel`, `fetchFailedReason`, `fetchFailedMessage`, `basaMigrations`, `LedgerRow`).
- `abstract class MigrationLedgerRepository { Future<List<LedgerRow>> fetchAll(); }`. The Supabase implementation runs `client.from('basa_migrations').select('id, name, app_update_required')` and throws on error.
- `AuthViewModel` changes:
  - New constructor parameter `required MigrationLedgerRepository Function(SupabaseClient client) ledgerRepoFactory`.
  - New field `String? versionWarning`.
  - New public method `Future<VersionCheck> checkVersion([SupabaseClient? client])`. It defaults to the session client and throws `StateError('Not signed in.')` if there is none. A `PostgrestException` whose code is `PGRST205` or `42P01` gives `checkVersion(basaMigrations, null)`. Every other error is rethrown.
- `void registerVersionCommands(ConsoleRegistry registry, AuthViewModel authVm)`.

- [ ] **Step 1: Change `signIn`.** Set `versionWarning = null` at its start, and also clear it in `signOut`. After the `isActive` check and before `previous`/`_client` are touched:
  - `try { check = await checkVersion(client); } catch (e)` → `_recordAttempt(..., failureReason: fetchFailedReason)`, `_abandon(client)`, return `fetchFailedMessage(e)`.
  - If `check.blocks`: record `versionFailureReason(check)`, abandon, return `versionMessage(check)`.
  - If the verdict is `warn`: set `versionWarning = versionMessage(check)` and continue as normal.
- [ ] **Step 2: Console.**
  - `sign-in`: on success, append `'\n$versionWarning'` when it is set.
  - `version-app` (offline): one line per entry, `<id>_<name>`, then `<n> migrations, latest <id>_<name>`.
  - `version-check`: if not signed in, return the `requireActiveSession()` text. Otherwise print `versionLabel(...)`, then `versionMessage(...)` when it isn't `''`. On an exception, print `fetchFailedMessage(e)`.
  - Register it in both `main.dart` files right after `registerAuthCommands`, and pass `ledgerRepoFactory: (client) => MigrationLedgerRepositorySupabase(client)` in both `AuthViewModel(...)` calls.
- [ ] **Step 3:** Run `dart analyze`: no new errors. Run the console (scratch launcher, *console-test-harness*): `version-app` prints 9 lines + `9 migrations, latest 20261020010000_basa_migrations`. Before the owner applies the migration, `sign-in cloud zztest.coord@basa.test abc123` must print the **no ledger table** refusal. That also proves the PGRST205 mapping against the real cloud.
- [ ] **Step 4:** Run the Task 2 probe again: still all `PASS`.

---

### Task 4: Docs and verify kit

**Files:**
- Modify: `README.md` (section 2b list + new rule; *Keeping BASA up to date*: replace the "Not built yet" paragraph at ~line 313 with the three outcomes and what to do for each), `CLAUDE.md` (data-model bullet: every migration ends with its ledger insert and adds its id to `lib/core/release.dart`)
- Create: `D:/0_CAPSTONE/verify/version-check/` (README.md, `0_apply.sql`, step files with SQL + console commands + expected output)

- [ ] **Step 1:** Edit the docs. Use the insert template from spec section 1 verbatim in README 2b.
- [ ] **Step 2:** Write the kit. The owner applies `0_apply.sql` (= the migration) on the dev cloud project. Then, signed in as the coordinator:
  1. `sign-in`: no note. `version-check` gives `OK`.
  2. Insert `('29990101000000','fake',false)` → `sign-in` prints the warn note. `version-check` gives `WARN`.
  3. Delete the fake row → `sign-in` again: no note (Review Focus 5).
  4. Insert the fake row with `true` → `sign-in` is refused with the app-old message. `login-logs` (or SQL) shows `version check: app missing 29990101000000`.
  5. Delete the fake row and sign in. Then, with the session open, delete row `20261019060000` → `version-check` gives `BLOCK: server older` naming `20261019060000_aral_idle_session_days.sql`. A new `sign-in` is refused, and `whoami` still shows the earlier session (Review Focus 4). Restore the row.
  6. `revoke select on public.basa_migrations from authenticated;` → `sign-in` is refused with `couldn't check the database version`. Then `grant select on public.basa_migrations to authenticated;` → `sign-in`: OK.
  7. `version-app` output, as in Task 3 step 3.

  Every file states its exact expected output. The last file restores state, and a final query lists the 9 rows.
- [ ] **Step 3:** Run the kit's console parts myself where I can (the steps before the migration is applied). Run a fresh reviewer over the whole change, fix Critical/Important findings, and hand over the commit message.
