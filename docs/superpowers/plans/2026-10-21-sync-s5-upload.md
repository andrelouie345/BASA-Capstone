# Sync S5: upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A device owner can preview, resolve, upload and withdraw their unsent work, and after a decision on the server the device takes the outcome in (real ids and server copies for an applied upload; lock lifted for rejected/error/conflict/withdrawn).

**Architecture:** A local package builder reads new rows (row_version NULL) and `sync_changes` lines that are not pending and turns them into the S1 package format. A remote repository wraps the `sync_uploads` table and the S1 RPCs plus keyed reads of the synced tables. `SyncViewModel` gains `preview / resolve / upload / refreshStatus / withdraw / sync` and owns the rules (online, owner, conflicts, lock lifecycle). An applied upload is taken in by one local transaction that swaps negative ids for the server's and rewrites those records from the server's copy.

**Tech Stack:** Dart, sqflite_common (ffi in console), supabase.

**Spec:** `docs/superpowers/specs/2026-10-20-sync-design.md` sections 4, 5.1, 5.3 (tutor commands), 9, 12-S5. Server contract: `supabase/migrations/20261020020000_sync_uploads.sql` (`sync_check_payload`, `sync_apply`, `sync_withdraw`, `sync_auto_approve`). S4 plan carries: `docs/superpowers/plans/2026-10-20-sync-s4-pull-merge.md` (Known follow-ups).

## Global Constraints

- No server migration, no SQLite bump (stays v34). The `sync_pending` trigger text change (decision 6) needs none: `createSyncLocalSchema` recreates triggers on every open.
- Package = `{format: 1, release, device_id, records: [{table, op, key, base_version?, row?}]}` exactly as `sync_check_payload` accepts: key `{id}` (negative for insert, positive otherwise), `{assessment_id}` for the CRLA parts, `{tutor_id}` (text) for `aral_tutor_settings`; `base_version` on update/delete only; no unknown columns.
- Local-only columns stripped from every row: `origin`, `row_version`, and the key column (the server takes the key from `key`). Verified 2026-10-21: those are the only local columns the server lacks.
- Server type conversions (static map in the package builder, from the baseline): booleans `phil_iri_readings.obs_word_by_word, obs_lacks_expression, obs_voice_inaudible, obs_disregards_punctuation, obs_points_to_words, obs_little_analysis`; `phil_iri_miscues.self_corrected`; `phil_iri_answers.is_correct, looked_back`; `aral_tutor_settings.multiple_sessions_per_day`; `aral_checkin_answers.is_correct` (0/1 → false/true). jsonb `crla_assessments.thresholds_snapshot`, `phil_iri_assessments.thresholds_snapshot` (JSON text → decoded). A future bool/jsonb column on these tables must be added here (comment says so).
- `release` = the last key of `basaMigrations` (`lib/core/release.dart`). `device_id` = uuid v4 made once with `Random.secure()` and kept in `sync_meta` key `device_id` (no new dependency).
- Every server step needs `requireOnlineSession()`; every refusal is a `ViewModelException` with a plain message; any failure leaves the local DB as before.
- `core/` and `viewmodels/` never import Flutter; new commands wired in both `lib/console/main.dart` and `lib/main.dart`.
- `dart analyze`: no new errors.

## Decisions for the owner (proposed; say if any is wrong)

1. **Lock before sending, not after.** Spec 5.1.3 writes `sync_pending` only after the insert is confirmed. If the response is lost and the tutor edits a record before the retry, the server holds the old values and the later edit is wiped when the applied upload is taken in. Instead: one local transaction writes an in-flight marker (`sync_meta` key `upload_in_flight` = JSON `{client_upload_id, package, summary}`) and locks every record with `upload_id = 0`; after the insert, the lines get the real id and the marker is removed. On any failure the VM asks the server for the `client_upload_id`: found → adopt it; not found → unlock; server unreachable → stays locked with "Upload state unknown; run sync-status when online". `upload()` and `refreshStatus()` settle a leftover marker first (spec 9, retry-safe).
2. **Deletes go last, children first.** Inserts and updates follow `pullOrder` (parents first, spec 4); deletes follow `pullClearOrder`, so the server never deletes a session before its marks (a cascade would turn the marks' own deletes into false conflicts).
3. **Insert rows omit null values** (server defaults apply, e.g. `created_at`, `created_by` = the uploader); update rows send every column, nulls included.
4. **Preview finds two kinds of problems before sending:** (a) a journaled record whose server `row_version` differs from `base_version`, or that the server no longer gives this user (deleted or out of scope; includes base 0 = copied before v34); (b) a new `aral_tutor_settings` row while the server has one for that tutor (S4 `skippedNewClash`). Other natural-key clashes (a mark for the same session and learner, a CRLA attempt number) are not predictable from the device; they come back from `sync_apply` as `error` with the server message. `upload()` refuses while preview lists any problem.
5. **`resolve(table, key, mine|server)`:** *mine* on (a) sets the journal's `base_version` to the server's current version (a knowing overwrite); refused when the server deleted the record and the local change is an update ("the server deleted it; keep the server's"). *mine* on (b) turns the new setting into an update of the server row (row_version = server's, journal line `update` with that base). *server* drops the journal lines of the record and its children (`syncedParents`) and writes the server's copy of the record and its children under the bypass, or deletes the local record and children when the server has none. Refused for pending records.
6. **The lock's message becomes the spec's text** in the triggers: `This record is waiting for approval. Withdraw the upload to change it.` (was `pending upload`; S2/S4 probes that match the old text are updated). Every ViewModel already passes the DB error text through, so no per-VM mapping is needed.
7. **Upload refuses when the signed-in user is not the device owner** (`sync_meta.last_pull_user_id`, S4 decision 1) or the device was never pulled: "This device's work belongs to <owner>; only they can upload it." / "Pull first."
8. **`refreshStatus()` runs at the start of `preview()`, `upload()` and `pull()`** (S4 carry I3), not inside sign-in (`AuthViewModel` can't depend on `SyncViewModel`); the future UI calls it after an online sign-in.
9. **Taking in an applied upload:** if the server no longer gives a record back (scope changed since), the local copy stays with the swapped id, `origin = 'cloud'`, `row_version = 0` (S2 meaning: version unknown).
10. **Size limit measured on the dev cloud** (Task 4 step 1, test uploads withdrawn afterwards); `maxPackageBytes` = 80% of the largest accepted payload, written into `sync_upload_rules.dart` with the measurement date.

## Review Focus

- Upload response lost (insert committed, client sees an error) → retry finds the row by `client_upload_id`; no second upload, records locked under the real id (Task 3 probe case "in-flight adopt").
- Applied upload where a new session -5 has marks -6/-7 and a check-in -8 points at a new enrollment -4 → after taking it in, no negative id remains anywhere in the 18 tables or in `aral_enrollments.basis_/suggestion_assessment_id`, and every reference points at the server id (Task 3 probe).
- Taking in an applied upload twice (crash after the server read, or a second `refreshStatus`) → second run changes nothing (Task 3 probe "idempotent").
- Record edited after it was pulled at base 0 (pre-v34 copy) → preview shows it as a conflict, not a silent overwrite (Task 2 console run).
- Pull right after an auto-applied upload → no duplicate negative-id copies next to the server's (Task 4 kit file 1 last step).

---

### Task 1: Package builder (local)

**Files:**
- Create: `lib/core/models/sync_upload.dart`
- Create: `lib/core/services/sync_upload_rules.dart` (bool/jsonb column map, `toServerRow`, `maxPackageBytes`, `newUuidV4()`)
- Create: `lib/core/repositories/sync_upload_local_repository.dart`
- Create: `lib/core/data/local/sync_upload_local_sqlite.dart`
- Modify: `lib/core/data/local/sync_local_schema.dart` (lock trigger text, decision 6)
- Test: probe `D:/0_CAPSTONE/verify/sync-s5/probe_package.dart`

**Interfaces:**
- Produces (`sync_upload.dart`):
  - `class SyncRecord { final String table, op; final String keyColumn; final Object key; final int? baseVersion; final Map<String, Object?>? row; Map<String, Object?> toJson(); }` (`toJson` = the spec 4 record).
  - `class SyncPackage { final String release, deviceId; final List<SyncRecord> records; final List<LocalWorkLine> summary; Map<String, Object?> toJson(); Map<String, Object?> summaryJson(); bool get isEmpty; }` — `summaryJson()` = `{"total": n, "lines": [{"kind", "section_id", "grade_level", "section_name", "school_year", "count"}]}` (S6 listings read only this).
  - `class SyncProblem { final String table; final String key; final String kind /* 'conflict' | 'server_deleted' | 'clash' */; final int? baseVersion, serverVersion; String toString(); }` e.g. `aral_sessions 14: changed on the server (yours from version 2, server now 4)`.
- Produces (`sync_upload_local_repository.dart`): `abstract class SyncUploadLocalRepository { Future<String> deviceId(); Future<SyncPackage> buildPackage({required String release}); Future<Map<String, Map<String, int>>> journal(); /* table -> key -> base_version, not pending */ Future<List<String>> newTutorSettingKeys(); }` (Task 3 adds the lock/apply methods to the same interface.)
- Consumes: `syncedTables`, `syncedParents` (`sync_local_schema.dart`), `pullOrder`, `pullClearOrder` (`pull_tables.dart`), `SyncLocalRepository.localWork()` grouping (reuse its query for the summary minus the `waiting in upload` lines; move it to a shared function rather than copy it).

Package content (decisions 2-3): every row with `row_version IS NULL` not in `sync_pending` → insert; every `sync_changes` line not in `sync_pending` → update (current local row) or delete; inserts/updates ordered by `pullOrder`, then within a table by key descending for negative ids (-1 before -2, i.e. creation order); deletes by `pullClearOrder`.

- [ ] **Step 1: Write `probe_package.dart`** (fresh DB in `verify/sync-s5/probe_db/` as the S4 probe; seeding by raw SQL under `sync_bypass`). Cases:
  - a. new session -5 + marks -6, -7 under it, new attendance -9 under pulled session 200 → records in order `aral_sessions -5`, `aral_attendance -6`, `-7`, `-9`, all `insert`, no `origin`/`row_version`/`id` in `row`, `session_id` -5 kept as is.
  - b. pulled session 201 edited (journal base 3) → `update`, `base_version 3`, `row` has every column incl. nulls; pulled mark 300 deleted (journal delete base 1) and pulled session 202 deleted → deletes come after every insert/update, `aral_attendance 300` before `aral_sessions 202`.
  - c. a pending record (`sync_pending` line) and its journal line → not in the package.
  - d. new Phil-IRI reading with `obs_word_by_word = 1`, answer `is_correct = 0` → `true` / `false`; new CRLA assessment with `thresholds_snapshot '{"a":1}'` → a map; null `notes` absent on insert.
  - e. new CRLA part under pulled assessment 50 → `{"table": "crla_part1_standard", "op": "insert", "key": {"assessment_id": 50}}`; new tutor setting → key `{"tutor_id": "<uuid>"}`.
  - f. `summaryJson()` totals equal `localWork()` minus the pending line; `deviceId()` twice → same uuid v4 (`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`).
  - g. empty device → `isEmpty`.
  - h. UPDATE of a pending record → error text contains `This record is waiting for approval`.
- [ ] **Step 2:** Run `dart run --packages=D:/0_CAPSTONE/Code/BASA-Capstone/.dart_tool/package_config.json probe_package.dart` → compile error (no repository).
- [ ] **Step 3:** Implement the models, rules, interface and `SyncUploadLocalSqlite(Database db)`; change the trigger text.
- [ ] **Step 4:** Probe → all PASS; update the S2 `probe_schema.dart` / S4 `probe_merge.dart` lock-text checks and re-run both (34 / 47 passed). `dart analyze`.

### Task 2: Remote repository + preview + resolve

**Files:**
- Create: `lib/core/repositories/sync_remote_repository.dart`
- Create: `lib/core/data/remote/sync_remote_supabase.dart`
- Modify: `lib/viewmodels/sync_viewmodel.dart`, `lib/core/models/sync_upload.dart`
- Modify: `lib/core/repositories/sync_upload_local_repository.dart` + sqlite (resolve writes)

**Interfaces:**
- Produces (`sync_remote_repository.dart`): `abstract class SyncRemoteRepository { Future<List<Map<String, dynamic>>> rowsWhere(String table, String column, List<Object> values); /* chunks of 200 */ Future<SyncUploadRow> insertUpload({required String clientUploadId, required int? schoolId, required String deviceId, required String release, required Map<String, Object?> payload, required Map<String, Object?> summary}); Future<SyncUploadRow?> uploadByClientId(String clientUploadId); Future<List<SyncUploadRow>> myUploads({List<int>? ids, int limit = 20}); /* never selects payload */ Future<bool> autoApprove(int? schoolId); Future<SyncApplyResult> apply(int uploadId); Future<void> withdraw(int uploadId); }`; `class SyncRemoteSupabase implements SyncRemoteRepository { SyncRemoteSupabase(SupabaseClient client); }`.
- Produces (`sync_upload.dart`): `class SyncUploadRow { final int id; final String status; final String? reason; final List<SyncProblem> conflicts; final Map<String, Map<String, int>> idMap; final DateTime createdAt; final DateTime? decidedAt; final Map<String, Object?> summary; }`; `class SyncApplyResult { final String status; final String? reason; }`; `class SyncPreview { final SyncPackage package; final List<SyncProblem> problems; final List<SyncOutcome> settled; /* from refreshStatus */ }`.
- Produces (VM): `SyncViewModel({..., required SyncUploadLocalRepository uploadLocal, required SyncRemoteRepository Function(SupabaseClient) remote})`; `Future<SyncPreview> preview()`; `Future<void> resolve(String table, String key, SyncChoice choice)` with `enum SyncChoice { mine, server }`.
- Local additions: `Future<void> setBaseVersion(String table, String key, int version)`; `Future<void> adoptServerSetting(String tutorId, int serverVersion)` (decision 5 *mine* on a clash); `Future<void> restoreServerCopy(String table, String key, Map<String, dynamic>? serverRow, Map<String, List<Map<String, dynamic>>> serverChildren)` (one transaction under bypass; uses S4's `_toLocal`, moved to a shared function).

- [ ] **Step 1:** Implement; `preview()` = guard → `refreshStatus()` (stub returning `[]` until Task 3) → `buildPackage` → `rowsWhere(table, keyColumn, keys)` per journaled table and for new tutor settings → problems (decision 4). `resolve` per decision 5; refuses keys not in the journal / not a clash with `Nothing to resolve for <table> <key>.`
- [ ] **Step 2:** `dart analyze`. Console checks come with the commands in Task 4.

### Task 3: Upload, lock lifecycle, refreshStatus, withdraw

**Files:**
- Modify: `lib/viewmodels/sync_viewmodel.dart`, `lib/core/models/sync_upload.dart`
- Modify: `lib/core/repositories/sync_upload_local_repository.dart` + sqlite
- Modify: `lib/core/data/local/sync_local_schema.dart` (move the trigger-off + reference-following parts of `renumberLocalRowsForV34` into shared helpers `withOtherSyncTableTriggersOff(Transaction, Future<void> Function())` and `followMovedIds(Transaction, Map<int, int> moved)`; the renumber calls them, behaviour unchanged)
- Test: probe `D:/0_CAPSTONE/verify/sync-s5/probe_apply.dart`

**Interfaces:**
- Local additions: `Future<void> beginUpload(String clientUploadId, SyncPackage p)` (marker + lock with upload_id 0, one transaction); `Future<InFlightUpload?> inFlight()` (`{clientUploadId, payload, summary, records}`); `Future<void> confirmUpload(int uploadId)`; `Future<void> abandonUpload()`; `Future<List<int>> pendingUploadIds()`; `Future<List<(String, String)>> pendingRecords(int uploadId)`; `Future<void> releaseUpload(int uploadId)` (delete its pending lines); `Future<int> takeInApplied(int uploadId, Map<int, int> idMap, Map<String, List<Map<String, dynamic>>> serverRows)` → number of records taken in.
- `followMovedIds` follows every declared FK pointing at a synced table (`PRAGMA foreign_key_list` over all local tables) plus `aral_enrollments.basis_assessment_id` / `suggestion_assessment_id` by value (one countdown = unique negative ids, as S1 relies on).
- `takeInApplied` (one transaction, bypass + other triggers off): swap ids (flat map from every table of `id_map`), write each server row by key as INSERT OR REPLACE with `origin = 'cloud'` on origin tables and the server's `row_version` (decision 9 when missing), delete the `sync_changes` and `sync_pending` lines of that upload's records. Running it again finds no negative keys and rewrites the same rows.
- VM: `Future<List<SyncOutcome>> refreshStatus()`; `Future<SyncUploadRow> upload()`; `Future<void> withdraw(int uploadId)`; `Future<List<SyncUploadRow>> uploads()` (for `sync-status`); `Future<SyncRunResult> sync({required Future<bool> Function(SyncPreview) confirm})` = refreshStatus → preview → confirm → upload → pull. `class SyncOutcome { final int uploadId; final String status; final String? reason; final List<SyncProblem> conflicts; final int records; }`.
- `upload()`: guard → owner check (decision 7) → settle in-flight → `preview()`; refuse if empty (`Nothing to upload.`), if problems (`Resolve these first (sync-resolve):\n<lines>`), or if `jsonEncode(payload).length > maxPackageBytes` (`Too much unsynced work for one upload (<n> KB); sync more often.` + per-kind lines); `beginUpload` → `insertUpload` (school = `currentUser.schoolId`) → `confirmUpload`; failure path per decision 1. Then if the user is admin/coordinator or `autoApprove(schoolId)`, `apply(id)` (an exception such as the release guard is reported, upload stays pending) and `refreshStatus()`.
- `refreshStatus()`: settle in-flight; for each id in `pendingUploadIds()` read `myUploads(ids:)`: `applied` → `rowsWhere` for every record by its new key (children via their own keys) → `takeInApplied`; `rejected` / `error` / `withdrawn` / `conflict` → `releaseUpload`; `pending` → nothing. An id the server doesn't return (not visible) is left locked and reported.
- `pull()` calls `refreshStatus()` first (decision 8; S4 carry I3).

- [ ] **Step 1: Write `probe_apply.dart`** (local only, no server): seed pulled enrollment 10 + session 200; new enrollment -4 (basis_assessment_id -3, a new CRLA assessment with parts), session -5 with marks -6, -7 (enrollment -4), check-in -8 (enrollment -4) with answers -11, -12; journal update on session 200. Cases:
  - a. `beginUpload` → every record locked with upload 0, marker present; an UPDATE of session -5 fails with the lock text.
  - b. `confirmUpload(41)` → lines carry 41, marker gone.
  - c. `takeInApplied(41, {-3: 900, -4: 901, -5: 902, -6: 903, -7: 904, -8: 905, -11: 906, -12: 907}, serverRows)` (hand-made server rows with `row_version` 1, and session 200 at v4) → `SELECT COUNT(*) WHERE id < 0` = 0 in all 18 tables; CRLA parts keyed 900; marks point at 902/901; check-in answers at 905; `basis_assessment_id = 900`; origin `cloud`; session 200 row_version 4; no `sync_changes` / `sync_pending` lines left; no new journal lines.
  - d. running c again → identical table contents.
  - e. a record missing from `serverRows` → swapped id, row_version 0.
  - f. `abandonUpload()` after a fresh `beginUpload` → no lock lines, marker gone, records editable.
  - g. `releaseUpload(41)` on a fresh lock → lines gone, journal line on 200 still there.
  - h. the v34 renumber probe (`verify/sync-s2/probe_*`) still passes after the helper extraction.
- [ ] **Step 2:** Run → compile error.
- [ ] **Step 3:** Implement local methods, helpers and the VM methods.
- [ ] **Step 4:** Probe → all PASS; S2 and S4 probes still pass. `dart analyze`.

### Task 4: Console commands, size measurement, kit

**Files:**
- Create: `lib/core/console/commands/sync_commands.dart` (`registerSyncCommands(ConsoleRegistry registry, SyncViewModel syncVm)`)
- Modify: `lib/console/main.dart`, `lib/main.dart` (construct `SyncUploadLocalSqlite`, `SyncRemoteSupabase.new`; register commands)
- Modify: `lib/core/services/sync_upload_rules.dart` (`maxPackageBytes`)

Commands (one action each; spec 5.3 tutor set):
- `sync-preview` → settled outcomes, then `Would upload <n> record(s):` + summary lines, then `Problems (resolve with sync-resolve):` + problem lines, or `Ready: run "sync-upload yes".`
- `sync-resolve <table> <key> mine|server` → `Kept yours for <table> <key> (will overwrite server version <v>).` / `Took the server's copy of <table> <key>.`
- `sync-upload` (no `yes`: same text as `sync-preview` + `Run "sync-upload yes" to send.`) / `sync-upload yes` → `Upload <id> sent: <n> record(s), waiting for approval.` or `Upload <id> applied: <n> record(s) now on the server.` (+ conflict/error text).
- `sync-status` → one line per own upload (`<id>  <status>  <created>  <total> record(s)  <reason>`), conflicts listed under a `conflict` row, then this device's locked records per upload.
- `sync-withdraw <id>` → `Upload <id> withdrawn; its records can be changed again.`

- [ ] **Step 1: Measure the size limit:** scratch probe signed in as zztest.tutor inserting `sync_uploads` rows with padded `summary` of 1, 2, 4, 8, 16 MB until refused; record the largest accepted, withdraw every test upload; set `maxPackageBytes` (decision 10) and note the result in the kit ledger.
- [ ] **Step 2:** Implement commands + wiring; `dart analyze`.
- [ ] **Step 3: Console run against the dev cloud**, kit `D:/0_CAPSTONE/verify/sync-s5/` (fresh verify DB, launch.dart, ids filled as the S4 kit; zztest.tutor's ARAL session 1 and its learners):
  1. `1_upload_approved_by_auto.txt`: coordinator `sync-auto-approve` is S6, so this file uses the **coordinator's own upload** (applies at once): coordinator pulls (discard-local), logs a session + 2 marks, `sync-preview`, `sync-upload yes` → applied, `sync-status`, `aral-sessions …` shows positive ids, `pull-cloud yes` → nothing kept, no duplicates. (If the ARAL commands refuse a coordinator, I switch this file to a CRLA assessment in section 6 and say so in the README.)
  2. `2_tutor_pending_withdraw.txt`: tutor pulls, edits session 1 remarks + new session, `sync-upload yes` → pending; editing session 1 → the lock text; `sync-withdraw <id>` → editable again; `sync-upload yes` again → pending (left for S6's approve test; README notes the id).
  3. `3_conflict.txt`: after the tutor's pull, the coordinator (own device copy) edits session 1 remarks and `sync-upload yes` (applies at once, server version moves on); the tutor edits the same session, `sync-preview` → conflict line; `sync-resolve aral_sessions 1 server` → server copy back; repeat with `mine` → upload goes through as an overwrite.
  4. `4_not_owner.txt`: coordinator signs in on the tutor's device copy → `sync-upload yes` refused naming zztest.tutor.
  Expected outputs from my run; README with reset line; probe lines (`probe_package.dart`, `probe_apply.dart` → `N passed, 0 failed`).
- [ ] **Step 4:** Fresh reviewer on the whole piece; fix Critical/Important; hand the owner the kit and the commit message; wait.

## Known follow-ups (not in S5)

- S6: approver commands (`sync-pending`, `sync-show`, `sync-approve`, `sync-reject`, `sync-auto-approve`, `offline-days[-set]`), `SyncReviewViewModel`; kit file 2's pending upload is its test case.
- Natural-key clashes other than tutor settings show up only as `error` at apply (decision 4).
- Refresh at online sign-in is the UI's job (decision 8); S7 documents it.
- Full download on every pull stays (spec 10).
