# Version check at sign-in — design

Date: 2026-10-20. Status: approved in brainstorming, awaiting written-spec review.
Related: README *Keeping BASA up to date*, README 2b, CLAUDE.md data-model rule
(the database and every device run the same BASA release).

## Goal

At online sign-in (cloud and LAN, app and console), compare the database
migrations the app was built for with the ones applied to the server, and
either let the user in, warn, or refuse with a message naming the exact files
or the update needed. This replaces the cryptic failure an outdated app or
database produces today (for example a `pull-cloud` that rolls back).

Out of scope: auto-update or downloads (detection and message only), offline
sign-in (none exists yet; the sync design decides it), checks on every command,
release numbers (`pubspec.yaml` `version` is untouched; only migration ids are
compared, never dates).

## Rule A

| Situation | Result |
|---|---|
| Server and app know the same migrations | OK |
| Server has migrations the app doesn't know, all `app_update_required = no` | WARN, sign-in continues |
| Server has a migration the app doesn't know with `app_update_required = yes` | BLOCK: app older |
| App knows a migration the server doesn't have | BLOCK: server older |
| Both of the last two | BLOCK: server older (the server must be fixed first) |

## 1. Table and migration

New migration `supabase/migrations/20261020010000_basa_migrations.sql`.
Header: `App update required on all devices: no` (pure addition). Idempotent.

```sql
create table if not exists public.basa_migrations (
  id                  text primary key,   -- filename timestamp, '20261019060000'
  name                text not null,      -- 'aral_idle_session_days'
  app_update_required boolean not null,
  applied_at          timestamptz not null default now()
);
alter table public.basa_migrations enable row level security;
drop policy if exists basa_migrations_select on public.basa_migrations;
create policy basa_migrations_select on public.basa_migrations
  for select to authenticated using (true);
-- no insert/update/delete policy: only migrations (SQL editor) write it.
```

`using (true)` is a deliberate exception to the "no wide-open policies" rule:
the table holds release metadata only, no school data, and is read-only to
every signed-in role (tutors included, since every role signs in). The
migration comment says so, so an RLS audit doesn't flag it.

**Conditional backfill.** A row is inserted only when that migration's
object actually exists, so a half-migrated server (e.g. a LAN instance missing
030000 and 040000) is reported correctly instead of passing. All rows use
`on conflict (id) do nothing` and `app_update_required = false`
(none of the earlier migrations changed rules an older app relied on; the
value is moot anyway because every app with this check knows all of them).

| id | name | inserted when |
|---|---|---|
| 20261018040000 | baseline | always |
| 20261018050000 | aral_readability_logs | `to_regclass('public.aral_readability_logs') is not null` |
| 20261019010000 | srp_classes | `to_regclass('public.srp_class_members') is not null` |
| 20261019020000 | srp_tutor_reads_learners | policy `students_select_srp_tutor` on `public.students` exists in `pg_policies` |
| 20261019030000 | assessment_calendar | `to_regclass('public.assessment_calendar') is not null` |
| 20261019040000 | report_settings | `to_regclass('public.report_settings') is not null` |
| 20261019050000 | calendar_round_pairing | constraint `assessment_calendar_round_pairing` exists in `pg_constraint` |
| 20261019060000 | aral_idle_session_days | constraint `aral_settings_idle_session_days` exists in `pg_constraint` |
| 20261020010000 | basa_migrations | always (last statement) |

**Rule for every future migration** (CLAUDE.md + README 2b): its last
statement is

```sql
insert into public.basa_migrations (id, name, app_update_required)
values ('<id>', '<name>', <true|false>) on conflict (id) do nothing;
```

with the boolean matching the header line, and the same commit adds the id to
`lib/core/release.dart`.

Not mirrored in SQLite: the local database is a copy, not a server.

## 2. Components

All pure Dart (no Flutter imports).

- **`lib/core/release.dart`** — `const basaMigrations = <String, String>{id: name}`,
  oldest first, the 9 rows above. One line added per new migration.
- **`lib/core/models/ledger_row.dart`** (or inside the service file if tiny) —
  `LedgerRow(id, name, appUpdateRequired)`.
- **`lib/core/services/version_check.dart`** — pure rule, no I/O:
  `VersionCheck checkVersion(Map<String, String> appKnown, List<LedgerRow> server)`
  returning `missingOnServer` (ids + names from the app list), `unknownToApp`
  (rows with their flag), and `verdict` ∈ `ok`, `warn`, `blockServerOld`,
  `blockAppOld`, `unreadable` (empty server list). Precedence as in Rule A.
- **`lib/core/repositories/migration_ledger_repository.dart`** — abstract
  `Future<List<LedgerRow>?> fetchAll()`; `null` = table doesn't exist.
- **`lib/core/data/remote/migration_ledger_repository_supabase.dart`** — selects
  `id, name, app_update_required`; maps a missing table (Postgres `42P01`,
  PostgREST `PGRST205`) to `null`; any other error is rethrown. No SQLite
  implementation.
- **`AuthViewModel`** — new constructor parameter
  `ledgerRepoFactory: MigrationLedgerRepository Function(SupabaseClient)`
  (same pattern as `userRepoFactory`); new public
  `Future<VersionCheck> checkVersion([SupabaseClient? client])` (defaults to
  the session client); new field `String? versionWarning` (cleared on
  sign-in and sign-out).
- Wired in both `lib/console/main.dart` and `lib/main.dart`.

## 3. Sign-in flow

In `AuthViewModel.signIn`, after the `isActive` check and before the session
is kept (the table's RLS needs an authenticated user; a wrong password or
inactive account keeps its usual message):

1. `fetchAll()` with the new client.
2. Fetch throws → refuse (fail closed): `_recordAttempt(failure: 'version check: fetch failed')`,
   `_abandon(client)`, return the message below.
3. `null` (no table) → treat as server older with `20261020010000_basa_migrations`.
4. Run `checkVersion`. On any BLOCK or `unreadable`: record, abandon, return the
   message. On WARN: keep the session, set `versionWarning`, record a normal
   success. On OK: unchanged.

### Messages (returned by the ViewModel; console and UI show them as-is)

Server older:
```
Sign-in refused: the database is older than this BASA app.
Ask the person who manages the database to apply these files from
supabase/migrations/, in this order (README section 2b):
  20261019040000_report_settings.sql
  20261020010000_basa_migrations.sql
```
No ledger table: the same message listing `20261020010000_basa_migrations.sql`
followed by `and any earlier file from section 2b not yet applied`.

App older (a "yes" migration):
```
Sign-in refused: this BASA app is too old for the database.
Update BASA on this device. The database has changes this app can't work with:
  20261101010000_new_rounds (app update required)
  20261101020000_extra_column
```
(all unknown migrations listed; the "yes" ones tagged).

Warn (`versionWarning`, sign-in succeeds):
```
Note: the database has additions this app doesn't use yet
(20261101010000_x). Update BASA on this device when you can.
```

Unreadable (table exists, 0 rows):
```
Sign-in refused: the basa_migrations table is empty or not readable.
Check its select policy (migration 20261020010000_basa_migrations).
```

Fetch failed:
```
Sign-in refused: couldn't check the database version (<error>). Try again.
```

### login_logs

Blocks record `success = false` locally and to the cloud (same path as an
inactive account), with `failure_reason`:
- `version check: server missing <id>, <id>`
- `version check: app missing <id>, <id>`
- `version check: no ledger table`
- `version check: ledger unreadable`
- `version check: fetch failed`

WARN records an ordinary success (no failure reason).

## 4. Console

- `sign-in` (changed, `auth_commands.dart`): prints the warning line after the
  usual success line when `versionWarning` is set; a refusal prints the
  message. No new arguments.
- `version-app` (new, `version_commands.dart`, offline): lists `basaMigrations`,
  oldest first, ending `N migrations, latest <id>_<name>`.
- `version-check` (new, needs a session): calls `AuthViewModel.checkVersion()`,
  prints the verdict (`OK`, `WARN`, `BLOCK: server older`, `BLOCK: app older`,
  `BLOCK: ledger unreadable`) and both lists. Reports only; does not sign out.

Not checked: `pull-cloud` and other commands (the session already passed at
sign-in; `version-check` covers a server migrated mid-session);
`admin-bootstrap` (Edge Function, no sign-in).

## 5. Errors and offline

- Offline: unchanged; sign-in already requires a connection and sessions don't
  persist across restarts.
- Fetch errors fail closed (above). Rationale: the profile fetch just
  succeeded over the same connection, so this is rare, and letting a
  mismatched app through is what the feature prevents.
- Empty ledger = unreadable, not "everything missing".
- Cloud and LAN behave the same; each server has its own ledger.

## 6. Testing

1. **Rule** — scratchpad console probe calling `checkVersion` with hand-built
   lists: identical → ok; server missing one → blockServerOld; unknown "no" →
   warn; unknown "yes" → blockAppOld; both → blockServerOld; empty → unreadable.
2. **Migration** (PG test harness, throwaway Postgres 18):
   fresh (baseline + 7 + ledger) → 9 rows; half-migrated (baseline + ledger,
   others skipped) → only rows whose objects exist; run twice → still the same
   rows, no error; RLS: `authenticated` can select, cannot insert/update/delete;
   `anon` selects nothing.
3. **Sign-in end to end** (dev cloud project, test accounts; owner applies
   `20261020010000` first): normal sign-in prints nothing extra; insert
   `('29990101000000','fake',false)` → warn; flip to `true` → refusal +
   `login_logs` row `version check: app missing 29990101000000`; delete the fake
   row and the `20261019060000` row → server-older message naming
   `20261019060000_aral_idle_session_days.sql`; restore the row; `version-check`
   and `version-app` match.
4. `dart analyze`: no errors. Fresh reviewer pass before handover.
5. Verify kit under `D:/0_CAPSTONE/verify/version-check/` with the exact SQL
   (fake row, flip, delete, restore) and expected output per step.

## Docs in the same piece

- README 2b: add `20261020010000` and the "end each migration with its ledger
  insert" rule.
- README *Keeping BASA up to date*: remove the "Not built yet" paragraph;
  describe the three outcomes and what to do for each.
- CLAUDE.md data-model rule: every migration ends with its ledger insert and
  adds its id to `lib/core/release.dart`.
