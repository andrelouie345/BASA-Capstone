# Sync S4: pull merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `pull-cloud` stops destroying local work: it refreshes every server copy on the device but keeps new rows, edited/deleted pulled rows and rows in a pending upload, refuses on orphans, and refuses to hand a device with unsent work to a different user.

**Architecture:** The pull logic leaves `pull_commands.dart`. A Supabase download source fetches the full scope (unchanged paging). A SQLite repository does the merge in one transaction under `withSyncBypass`: non-synced tables are replaced as today; synced tables delete only unkept rows (children first), insert server rows that don't clash with kept ones (parents first), then run an orphan check that throws (rollback) if a kept row points at nothing. `SyncViewModel.pull()` owns the rules (online session, owner switch, discard) and `pull-cloud` just calls it.

**Tech Stack:** Dart, sqflite_common (ffi in console), supabase.

**Spec:** `docs/superpowers/specs/2026-10-20-sync-design.md` section 7 (also 3.1-3.2 for row states, 12-S4). S2 plan (bookkeeping it relies on): `docs/superpowers/plans/2026-10-20-sync-s2-sqlite-v34.md`.

## Global Constraints

- No server migration, no SQLite bump (stays v34): everything needed (`row_version`, `sync_changes`, `sync_pending`, `local_ids`) exists since S2.
- Device owner = `sync_meta.last_pull_user_id` (S3 uses the same key for offline sign-in). `last_pull_user_id/_email/_at` are written by every successful pull, as today.
- Row state (S2): `row_version IS NULL` = new on this device; not NULL = copy of a server row. Kept on pull = new rows + rows whose key is in `sync_changes` + rows whose key is in `sync_pending`.
- Download first, then one local transaction under `withSyncBypass`: any error or refusal leaves the local DB exactly as before (as today).
- Regions and login_logs are still never touched; `offline_credentials`, `local_ids` neither.
- `core/` and `viewmodels/` never import Flutter. Wire `SyncViewModel` into both `lib/console/main.dart` and `lib/main.dart` (register it in the `ViewModelRegistry`).
- `pull-cloud` keeps its name and its `yes` / `yes discard-local` arguments.
- `dart analyze`: no new errors.

## Decisions for the owner (proposed; say if any is wrong)

1. **Owner switch is refused at the pull, not at sign-in.** A different user can still sign in online on the device (S3 already overwrites the offline credential then). Their `pull-cloud yes` is refused while the owner has new, edited or pending work, listing it and naming the owner; `pull-cloud yes discard-local` is the way out (a coordinator taking back a device whose tutor left). Without local work the pull just warns "replacing <owner>'s copy" and replaces. Refusing the sign-in instead would leave nobody able to clear a device whose owner is gone. **Carried to S5:** upload refuses when the signed-in user is not the device owner, so a non-owner's local edits can never go up under the owner's records.
2. **Orphan = a kept row whose declared reference is missing after the merge.** Checked with `PRAGMA foreign_key_list` on the 18 synced tables (SQLite doesn't enforce FKs here, but every reference is declared), plus the polymorphic `aral_enrollments.basis_assessment_id` / `suggestion_assessment_id` (CRLA or Phil-IRI by `basis_source` / section grade, as the S2 renumber). References to `users` are **not** checked (audit columns like `administered_by`; a tutor can't read every user; the server validates them at upload).
3. **Server rows under a record deleted on this device are skipped** (a server row whose declared reference to a synced table points at a key journaled as `delete`), so the delete isn't visibly undone; they go away once the delete is uploaded. Counted in the result.
4. **A new `aral_tutor_settings` row (row_version NULL) beats a server row for the same tutor** on the device (the server row is skipped, counted); S5's preview reports it (spec 2.3: an insert hitting an existing server row is an error).
5. **`discard-local` deletes every new row (row_version NULL) in the 18 tables, all `sync_changes` and all `sync_pending` lines, then replaces as today.** When it drops pending lines it says those uploads still exist on the server and come back on a later pull if approved.
6. **The pull's prompt (no `yes`) lists what will be kept**, not "will refuse": same per-kind/section lines as today's refusal (moved from `_unsynced`), plus pending counts per upload.

## Review Focus

- Pulled row edited locally while the server also changed it → the local edit and its base `row_version` stay (not overwritten, not bumped to the server's), so S5 preview can see the conflict (Task 2 probe case c).
- A new child under a pulled parent (attendance mark on a pulled session) whose parent the server still has → child kept and parent refreshed; the parent's delete-then-insert must not drop the child (Task 2 case f).
- Kept row in a section the user lost on the server → refused, rolled back, listed with table, key and the missing reference; nothing changed locally (Task 2 case h, row counts before = after).
- The pull's own deletes/inserts → no `sync_changes` lines, no "pending upload" refusal, `sync_bypass` row gone afterwards (Task 2 case k).
- Second pull with nothing changed on either side → same row counts, same kept rows, no new journal lines (idempotent; Task 2 case n).

---

### Task 1: Download source + shared table order

**Files:**
- Create: `lib/core/data/pull_tables.dart` (moved `_pullOrder` and `_clearedTables` from `pull_commands.dart`, renamed `pullOrder` / `pullClearOrder`; the same comments)
- Create: `lib/core/repositories/sync_download_source.dart`
- Create: `lib/core/data/remote/sync_download_supabase.dart` (moved `_fetchTable`, unchanged paging of 1000)

**Interfaces:**
- Produces: `const Map<String, String> pullOrder` (table → paging column, parents first); `const List<String> pullClearOrder` (children first); `abstract class SyncDownloadSource { Future<Map<String, List<Map<String, dynamic>>>> downloadAll(); }` (every table of `pullOrder`, in that order); `class SyncDownloadSupabase implements SyncDownloadSource { SyncDownloadSupabase(SupabaseClient client); }`.

- [ ] **Step 1:** Move the code; `pull_commands.dart` temporarily uses the new names so it still compiles and behaves the same. `dart analyze` → no errors.

### Task 2: Merge in SQLite

**Files:**
- Create: `lib/core/models/sync_pull.dart`
- Create: `lib/core/repositories/sync_local_repository.dart`
- Create: `lib/core/data/local/sync_local_repository_sqlite.dart` (takes `_unsynced`, `_newUnderServerRows`, `_setMeta`, `_writeTable`, `_toLocal`, `_originTables` from `pull_commands.dart`)
- Test: probe `D:/0_CAPSTONE/verify/sync-s4/probe_merge.dart`

**Interfaces:**
- Consumes: `pullOrder`, `pullClearOrder` (Task 1); `syncedTables`, `syncedParents` (`sync_local_schema.dart`); `withSyncBypass` (`sync_local_writes.dart`).
- Produces (`sync_pull.dart`):
  - `class LocalWorkLine { final String kind; final int? sectionId; final int count; final String? gradeLevel, sectionName, schoolYear; }` (the existing `_unsynced` row, same kinds and texts) plus kind `'record(s) waiting in upload <id>'` per pending upload (from `sync_pending` grouped by `upload_id`).
  - `class PullOwner { final String userId; final String? email; final String? pulledAt; }`
  - `class PullOrphan { final String table; final String key; final String column; final String refTable; final Object refValue; }` with `toString()` like `aral_attendance -30: aral_sessions 14 (session_id) is no longer on the server for you`.
  - `class PullOrphansException implements Exception { final List<PullOrphan> orphans; }`
  - `class PullMerge { final Map<String, int> serverRows; final int keptNew, keptChanged, keptPending, skippedUnderDeleted, skippedNewClash, discarded; }` (`serverRows` = rows written per table).
- Produces (`sync_local_repository.dart`): `abstract class SyncLocalRepository { Future<PullOwner?> owner(); Future<List<LocalWorkLine>> localWork(); Future<PullMerge> mergePull(Map<String, List<Map<String, dynamic>>> fetched, {required String userId, required String? email, required bool discardLocal}); }` — `mergePull` throws `PullOrphansException` after rolling back.

Merge algorithm (one `localDb.transaction` + `withSyncBypass`; the order matters, the rest is the implementer's):
1. If `discardLocal`: count, then delete rows with `row_version IS NULL` in the 18 tables (children first), all `sync_changes`, all `sync_pending`.
2. Kept keys per synced table = keys with `row_version IS NULL` ∪ `sync_changes.row_key` ∪ `sync_pending.row_key` for that table (keys compared as `CAST(key AS TEXT)`, as the triggers do).
3. In `pullClearOrder`: non-synced tables → `DELETE FROM t`; synced tables → delete rows whose key is not kept.
4. In `pullOrder`: non-synced → insert every fetched row (as today); synced → insert a fetched row unless its key is kept (count `skippedNewClash` when the kept row is a NULL-version `aral_tutor_settings`), or a declared reference to a synced table points at a key journaled `delete` (count `skippedUnderDeleted`). `origin = 'cloud'` on origin tables, `row_version` copied as in S2.
5. Orphan check over kept rows (decision 2); any → throw `PullOrphansException` (the transaction rolls back).
6. `_setMeta` last_pull_user_id/_email/_at.

- [ ] **Step 1: Write `probe_merge.dart` (failing: the repository doesn't exist).** Fresh DB in `verify/sync-s4/probe_db/` via `LocalDatabase.instance` (`databaseFactoryFfi`); seed "pulled" rows with raw SQL under `sync_bypass` (row_version set), local work through raw SQL with negative ids; build `fetched` maps by hand (every `pullOrder` table present, most empty). Prints `PASS`/`FAIL name` and a final count. Cases:
  - a. pulled session 200 (v1) unedited, server sends it with `remarks 'srv'`, v2 → local has `remarks 'srv'`, `row_version 2`.
  - b. pulled session 201 unedited, absent from server → gone locally.
  - c. pulled session 202 (v1) edited locally (journal line base 1), server sends v3 → local keeps the local remarks, `row_version 1`, journal line unchanged.
  - d. pulled session 203 deleted locally (journal `delete`), server sends it with attendance 300 → neither 203 nor 300 inserted (203 is kept-by-journal, so absent; 300 counts `skippedUnderDeleted = 1`); journal line still there.
  - e. new session -5 + attendance -6 (under -5, learner = a pulled enrollment the server still sends) → both kept, `keptNew` counts them.
  - f. new attendance -7 under pulled session 200 (server still sends 200) → -7 kept, 200 refreshed.
  - g. session 204 pulled + in `sync_pending` (upload 9) → kept; afterwards an UPDATE of 204 outside the bypass still fails with `pending upload`; `localWork()` has a line for upload 9.
  - h. new CRLA assessment -8 in section 6, `fetched['sections']` without section 6 → `PullOrphansException` listing `crla_assessments -8 … sections 6 (section_id)`; every table's row count and `sync_changes` identical to before the call.
  - i. new attendance -9 under pulled session 205, server no longer sends 205 → orphan on `aral_sessions 205 (session_id)`.
  - j. `discardLocal: true` on the state of h → succeeds; no `row_version IS NULL` rows, `sync_changes` and `sync_pending` empty, `discarded` = number of new rows removed; 202 now has the server's v3.
  - k. after a successful merge: no new `sync_changes` lines from the pull itself, no `sync_bypass` row in `sync_meta`.
  - l. non-synced: `schools` row 6 renamed on the server → renamed locally; a region row untouched; `login_logs` untouched.
  - m. new `aral_tutor_settings` for tutor T (row_version NULL) + server row for T → local kept, `skippedNewClash = 1`.
  - n. running the same successful merge twice → identical row counts per table and identical `sync_changes`.
  - o. `owner()` after merge = the given user id/email.
  (h and i run on their own seeded DB states, then reset; the implementer may split the probe's seeding helpers as they like.)
- [ ] **Step 2: Run** `dart run --packages=D:/0_CAPSTONE/Code/BASA-Capstone/.dart_tool/package_config.json probe_merge.dart` → compile error (no repository).
- [ ] **Step 3: Implement** the models, the interface and `SyncLocalRepositorySqlite(Database db)` per the algorithm above.
- [ ] **Step 4: Run the probe** → all PASS; also re-run S2's `probe_schema.dart` (fresh `probe_db/`) → 34 passed. `dart analyze`.

### Task 3: SyncViewModel.pull + pull-cloud rewired + wiring

**Files:**
- Create: `lib/viewmodels/sync_viewmodel.dart`
- Modify: `lib/core/console/commands/pull_commands.dart` (becomes a thin command over the ViewModel; signature `registerPullCommands(ConsoleRegistry registry, SyncViewModel syncVm)`)
- Modify: `lib/console/main.dart`, `lib/main.dart` (construct + register `SyncViewModel`, new `registerPullCommands` call)
- Test: verify kit console files (below)

**Interfaces:**
- Consumes: `SyncLocalRepository`, `SyncDownloadSource` (Tasks 1-2), `AuthViewModel.requireOnlineSession()`, `.currentUser`, `.client`.
- Produces: `class SyncViewModel { SyncViewModel({required AuthViewModel auth, required SyncLocalRepository local, required SyncDownloadSource Function(SupabaseClient client) download, Logger? logger}); Future<PullPreview> pullPreview(); Future<PullResult> pull({bool discardLocal = false}); }` (own `ScopedLogger(logger, 'SyncViewModel')`; S5 adds the upload methods to this class).
  - `class PullPreview { final PullOwner? owner; final String? currentUserId, currentEmail; final bool ownerSwitch; final List<LocalWorkLine> localWork; int get localTotal; }` (in `sync_pull.dart`).
  - `class PullResult { final PullMerge merge; final bool ownerChanged; final String? previousOwnerEmail; final List<String> unknownCalendarRounds; }` (in `sync_pull.dart`; `_unknownCalendarRounds` moves into the ViewModel).
- Refusals are `ViewModelException` with these messages (exact):
  - not online: the `requireOnlineSession()` text.
  - owner switch with local work and no discard: `Refused: this device holds work of <owner email> that is not on the server yet:\n<lines>\nThey must sync first, or run "pull-cloud yes discard-local" to delete it.`
  - download failure: `Pull stopped while downloading, nothing was changed: <e>`
  - orphans: `Refused, nothing was changed: <n> record(s) on this device point at data the server no longer gives you:\n  <orphan lines>\nRun "pull-cloud yes discard-local" to delete this device's unsent work.`
  - other write error: `Pull stopped, nothing was changed (rolled back): <e>`
- Console output of `pull-cloud` without `yes`: `This refreshes the local copy (schools, users, sections, learners, enrollments, CRLA, Phil-IRI, ARAL, SRP) with everything <email> can read on the server. Regions and login logs are kept.` + `Local data was last pulled by <owner or "nobody (never pulled)">.` + either the kept-work lines (`Kept on this device: …`) or, on an owner switch, the refusal/warning text + `Run "pull-cloud yes" to continue.`
- Console output after success: `<table>: <n> rows` per table (as today), then `Kept on this device: <keptNew> new, <keptChanged> changed, <keptPending> waiting for approval.` (only if any), the two skip counts (only if any), `Discarded this device's unsent work: <n> new record(s), <m> change(s) to server records.` (only if any; plus the pending-uploads note of decision 5), `Done. Local data now belongs to <email>.`, and the calendar WARNING as today.

- [ ] **Step 1: Implement** the ViewModel, rewire the command, wire both entry points. `dart analyze` → no errors; `grep -n "client!" lib/viewmodels/sync_viewmodel.dart` shows only lines after `requireOnlineSession()`.
- [ ] **Step 2: Console run against the dev cloud** (kit `D:/0_CAPSTONE/verify/sync-s4/`, fresh copy of the verify DB, launch.dart as S2/S3):
  1. `1_merge_keeps_work.txt`: `sign-in cloud zztest.tutor@…` → `pull-cloud yes discard-local` (clean start, tutor owns the device) → `aral-session-edit 1 remarks "ZZTEST S4 edited"` → `aral-log …` new session + two `aral-mark` on it (session 1 and the learners as in the S2 kit; if the tutor can't see them, I pick the tutor's own and note it in the README) → `pull-cloud` (prompt lists 1 change + the new session/marks) → `pull-cloud yes` → Done with `Kept on this device: 3 new, 1 changed` → `aral-sessions …` shows the edited remarks and the new session.
  2. `2_owner_switch.txt` (same data): `sign-in cloud zztest.coord@…` → `pull-cloud yes` → the owner-switch refusal naming zztest.tutor → `pull-cloud yes discard-local` → `Discarded 3 local record(s).`, done, owner = coordinator; session 1 shows the server's remarks again.
  3. `3_second_pull.txt`: coordinator `pull-cloud yes` twice → same row counts both times, nothing kept.
  Expected outputs saved from my run; README with the reset line, plus the probe line (`probe_merge.dart` → `N passed, 0 failed`).
- [ ] **Step 3:** Hand the owner the kit and the commit message; wait for their result.

## Known follow-ups (not in S4)

- Built (rulings, see kit ledger): any unique clash of a server row with a kept row is skipped and counted in `skippedNewClash` (not only tutor settings), and so is every server row under a skipped record; a pulled CRLA header with a new local part is kept as it is (its local reading profile isn't journaled); `keptNew`/`discarded` count records the way the prompt lists them.
- S5: `SyncViewModel.pull()` must run `refreshStatus()` first (or refuse while `sync_pending` lines belong to uploads already decided), else a pull after an auto-applied upload keeps the negative-id copies next to the server's (review finding I3).

- S5: upload refuses for a non-owner (decision 1); preview reports kept edited rows whose server row moved on or vanished, and a NULL-version tutor setting that clashes with a server row.
- Pre-v34 local children of pulled parents are still treated as pulled (S2 known limit), so a merge pull replaces them like today.
- Still a full download on every pull (spec 10).
