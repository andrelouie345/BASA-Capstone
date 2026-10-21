# Sync S6: review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An admin/coordinator (or the superadmin) lists the uploads waiting for them, reads one as plain lines, approves or rejects it, and sets the per-school auto-approve and offline sign-in window. The tutor's device withdraws an upload that stopped on a conflict, so nothing stays in `conflict` forever.

**Architecture:** A new `SyncReviewViewModel` wraps the approver half of `sync_uploads` (listing, one upload with its payload, `sync_apply`, `sync_reject`) through new methods on `SyncRemoteRepository`. A pure-Dart describer turns a payload into one line per owner record, using rows the approver's device already holds (read through a small local lookup repository). The two settings go through `ReportSettingsViewModel` like the done threshold. No server migration (the server already allows withdrawing and rejecting a `conflict` upload), no SQLite bump (stays v34).

**Tech Stack:** Dart, sqflite_common (ffi in console), supabase.

**Spec:** `docs/superpowers/specs/2026-10-20-sync-design.md` sections 2.3, 2.4, 5.2, 5.3 (approver commands), 8, 12-S6. Server contract: `supabase/migrations/20261020020000_sync_uploads.sql` (`sync_uploads` RLS, `sync_reject`, `sync_withdraw`, `sync_is_approver`) and `20261021010000_sync_followup_updates.sql` (`sync_apply` and what it returns). Owner decisions 1-10 (2026-10-21): memory `sync-design`, repeated as Global Constraints below.

## Global Constraints

- Approver = admin or coordinator with a school (own school only) or the superadmin (admin, no school: every school, or one by id). Tutors are refused: `Forbidden: only an admin or coordinator reviews uploads.` A school-bound approver naming another school: `Forbidden: you can only review your own school's uploads.`
- Every approver step needs `requireOnlineSession()`; refusals are `ViewModelException`s with plain messages; server errors give the server's own message (`PostgrestException.message`).
- Listings never select `payload`; only `details(id)` reads it (one upload).
- Uploader names come from the approver's local `users` mirror: `full_name`, else `email`, else the uuid. No extra server query (decision 4).
- Names in `sync-show` come from the approver's local copy; a missing row prints its id (`learner 812`, `section 28`) (decision 5).
- Reject reason: trimmed, not blank, at most 500 characters, checked on the device (decision 7).
- Settings: keys `sync_auto_approve` (bool) and `offline_signin_days` (whole number 1-60) in `report_settings.settings`; region row = superadmin, school row = its admin/coordinator; written online, then mirrored (pattern of `setDoneThreshold` / `_writer` / `_cloudWrite` / `_mirror`).
- `core/` and `viewmodels/` never import Flutter; new VM and commands wired in both `lib/console/main.dart` and `lib/main.dart`.
- `dart analyze`: no new errors.

## Owner decisions already taken (2026-10-21, from memory `sync-design`)

1. Scope: school admin/coordinator = own school; superadmin = all, or one via `sync-pending <schoolId>`.
2. `sync-pending`: pending uploads oldest first (uploader, date, counts); separate block "sent back (conflict), waiting for the uploader"; total "N upload(s) still pending".
3. Tutor `refreshStatus` withdraws its own `conflict` upload after taking in the conflict list.
4. Uploader names from the local users mirror (see constraints).
5. `sync-show`: one line per owner record, children folded; changed columns by comparing with the approver's pulled copy, else just "changed"; follow-ups shown as part of their record.
6. `sync-approve` → `sync_apply`; outcome texts below (Task 2).
7. `sync-reject <id> <reason...>` (see constraints).
8. `sync-auto-approve <region|schoolId> [on|off]`; no argument after the scope = show; turning it on does not apply uploads already pending.
9. `offline-days <region|schoolId>` / `offline-days-set <region|schoolId> <1-60>`; output says it reaches tablets after their next pull; `report-settings-reset <schoolId>` help says it drops all three keys.
10. Fold in S5 minors M2 (discard-local clears the `upload_in_flight` marker) and M4 (`upload()` must not report a read error after a successful send). M1/M3/M5 stay deferred.

## New decisions for the owner (came up while writing this plan; my recommendation first)

A. **`latest` for `sync-show`, `sync-approve`, `sync-reject`** = the newest `pending` upload in the approver's scope (same idea as S5's `sync-withdraw latest`). Upload ids come from the server and change on every run, so the kit can't fill them in; without `latest` the kit needs a `sync-pending` step and you type the id yourself. *Recommend: add it.*
B. **When the conflict withdraw (decision 3) fails** (network drops between reading the status and withdrawing): *recommend* withdraw first, unlock only after it succeeded; on failure the records stay locked and the outcome line says `could not withdraw it on the server; run sync-status again`. The next refresh repeats it. (Alternative: unlock anyway; the upload then stays `conflict` on the server until an approver rejects it.) Only uploads this device still holds locked are withdrawn; old `conflict` uploads from S5 tests on the dev cloud are rejected by hand in the kit.
C. **`sync-auto-approve` and `offline-days[-set]` live in `report_settings_commands.dart`** (they call `ReportSettingsViewModel` and reuse its `region|schoolId` parsing), not `sync_commands.dart` as spec 5.3 lists them. The approver commands (`sync-pending/show/approve/reject`) go in `sync_commands.dart`. *Recommend: as described.*
D. **The settings' "show" form reads this device's copy** (like `report-settings-show`), so it can lag if someone else changed the setting since the last pull; `sync_apply` always uses the server's value. *Recommend: local copy* (same as the done threshold; the setter mirrors right away).
E. **Superadmin listing prints the school** on each upload line (`school 3 ZZTEST HIGH`); school-bound approvers don't get the column. *Recommend: yes.*

## Review Focus

- Approver opens an upload of learners their device never pulled (a superadmin who pulled before the school existed, or a fresh device) → lines still print, with ids instead of names; no crash on a missing student/section/enrollment (Task 1 probe case d).
- Approving an upload another approver just decided → the server says `Upload N is applied, not pending`; the console prints that message, nothing else changes (Task 2: `approve` passes the `PostgrestException` message through; kit file 2 approves twice).
- An upload that ends `error` at approval (e.g. a natural-key clash such as a second mark for the same learner and session) → `Upload N failed on the server: <table key: message>`; the tutor's next `sync-status` unlocks the records with that reason (Task 2 outcome text; S5 already unlocks on `error`).
- Tutor whose conflict upload was sent back syncs again without resolving → the new preview lists the same records as conflicts (they are still journaled) and refuses; the old upload is `withdrawn` on the server (kit file 3).
- `sync-reject` with a 600-character reason, or only spaces → refused on the device, the upload stays pending (Task 2 `reject` checks; kit file 4).

---

### Task 1: Upload describer + local lookup

**Files:**
- Create: `lib/core/services/sync_review_lines.dart`
- Create: `lib/core/repositories/sync_review_local_repository.dart`
- Create: `lib/core/data/local/sync_review_local_sqlite.dart`
- Test: probe `D:/0_CAPSTONE/verify/sync-s6/probe_review.dart` (pure Dart, no DB)

**Interfaces:**
- Produces (`sync_review_local_repository.dart`): `abstract class SyncReviewLocalRepository { Future<List<Map<String, Object?>>> rowsWhere(String table, String column, List<Object> values); }` — refuses (ArgumentError) any table outside `syncedTables` + `students`, `sections`, `users`, `schools`; `SyncReviewLocalSqlite(Database db)` chunks of 500.
- Produces (`sync_review_lines.dart`):
  - `class SyncReviewContext { final Map<String, Map<String, Map<String, Object?>>> rows; /* table -> key (as text) -> local row */ Map<String, Object?>? row(String table, Object key); }`
  - `Map<String, Set<String>> referencedKeys(List<Map<String, Object?>> records)` — which local rows the describer needs: owner records' own keys (updates/deletes), parents of children whose parent isn't in the package, `student_id`, `section_id`, `enrollment_id` (positive only), `tutor_id` → `users`.
  - `List<String> describeUpload(List<Map<String, Object?>> records, SyncReviewContext ctx)` — one line per owner record, package order.
- Consumes: `syncedTables`, `syncedParents` (`sync_local_schema.dart`).

Line rules (decision 5):
- Learner label: `Last, First (G<grade> <SECTION>)` from `students` + `sections`; enrollment-keyed records (`aral_irip_weeks`, `aral_checkins`, `aral_readability_logs`) find the enrollment in the package (negative id) or the context, then its student. Missing rows → `learner <id>`, `section <id>`.
- Owner record text: CRLA `CRLA <round> <subject_variant>`; GST `Phil-IRI GST <total>/<max>`; Phil-IRI `Phil-IRI <round>`; enrollment `ARAL <key_stage> <track>`; session `ARAL session <session_no> (<held_on>)`; tutor setting `ARAL tutor setting (<user label>)`; IRIP `IRIP cycle <c> week <w> <strand>`; check-in `ARAL check-in attempt <n>`; readability `readability "<title>"`.
- Op text: insert `new`; delete `deleted`; update `changed (<columns>)` where columns = keys whose value differs from the context row, ignoring `updated_at`, `updated_by`, `row_version`, `origin`, `created_at`; no context row → `changed`. A follow-up update (no `base_version`, same key as an insert earlier) adds its status instead: `, completed` / `, finalized` / `, exited`.
- Children: `with Part 1` / `Part 1 English` / `Part 2` (CRLA parts); `with N readings, N answers, N miscues, N rubric scores`; `with N attendance marks`; `with N answers` (check-in). Children of a record not in the package fold under a line for that parent: `ARAL session 1 (2026-10-14): 2 attendance marks changed, 1 new`.

- [ ] **Step 1: Write `probe_review.dart`** with a hand-made context (students 137 `DELA CRUZ, JUAN`, section 28 G7 `PLARIDEL`, pulled session 1 `remarks 'old'`, user `zztest.tutor` full name `ZZ Tutor`). Cases and exact expected lines:
  - a. new CRLA -3 (student 137, section 28, round bosy, subject_variant mt) + part1_standard + part2_fluency keyed -3 → `DELA CRUZ, JUAN (G7 PLARIDEL): CRLA bosy mt, new, with Part 1, Part 2`
  - b. session 1 update with `remarks 'new'`, `updated_at` changed → `ARAL session 1 (2026-10-14): changed (remarks)`
  - c. new session -5 + marks -6, -7 → `ARAL session 3 (2026-10-20): new, with 2 attendance marks`; a new mark -9 under session 1 and an update of mark 300 under session 1 → one line `ARAL session 1 (2026-10-14): 1 attendance mark new, 1 changed`
  - d. Phil-IRI -8 for student 999 / section 77 (not in context) + follow-up update status completed → `learner 999 (section 77): Phil-IRI bosy, new, completed`
  - e. new enrollment -4 (student 137) + check-in -10 on enrollment -4 with 2 answers → two lines, the check-in's learner taken from the package's enrollment: `DELA CRUZ, JUAN (G7 PLARIDEL): ARAL check-in attempt 1, new, with 2 answers`
  - f. update with no context row → `... changed`; delete of session 2 → `ARAL session 2 (?): deleted` when unknown, with `held_on` when the context has it.
  - g. `referencedKeys` of case e → `{'students': {'137'}, 'sections': {'28'}}` (no negative keys).
- [ ] **Step 2:** Run `dart run --packages=D:/0_CAPSTONE/Code/BASA-Capstone/.dart_tool/package_config.json probe_review.dart` → compile error.
- [ ] **Step 3:** Implement the repository, sqlite class and describer.
- [ ] **Step 4:** Probe → all PASS. `dart analyze`.

### Task 2: Remote approver methods + `SyncReviewViewModel` + tutor-side fixes

**Files:**
- Modify: `lib/core/repositories/sync_remote_repository.dart`, `lib/core/data/remote/sync_remote_supabase.dart`
- Modify: `lib/core/models/sync_upload.dart`
- Create: `lib/viewmodels/sync_review_viewmodel.dart`
- Modify: `lib/viewmodels/sync_viewmodel.dart` (decision 3, decision 10 M4)
- Modify: `lib/core/data/local/sync_local_repository_sqlite.dart` (decision 10 M2: the `discardLocal` branch deletes `sync_meta` key `upload_in_flight`)

**Interfaces:**
- Remote additions: `Future<List<SyncUploadRow>> schoolUploads({int? schoolId, required List<String> statuses});` (oldest first; `schoolId` null = all the caller may read); `Future<SyncUploadRow?> uploadById(int id, {bool withPayload = false});` `Future<void> reject(int uploadId, String reason);` `apply` now returns conflicts too. `_uploadColumns` gains `uploader_id, school_id`.
- Model additions: `SyncUploadRow` gains `String? uploaderId`, `int? schoolId`, `Map<String, Object?>? payload`, `List<LocalWorkLine> get summaryLines` (from `summary.lines`); `SyncApplyResult` gains `List<SyncProblem> conflicts`; `SyncUploadResult` gains `String? statusError`.
- Produces (`sync_review_viewmodel.dart`): `SyncReviewViewModel({required AuthViewModel auth, required SyncReviewLocalRepository local, required SyncRemoteRepository Function(SupabaseClient) remote, Logger? logger})` with
  - `Future<SyncPendingList> pending({int? schoolId})` → `class SyncPendingList { final List<SyncReviewItem> pending, sentBack; }`; `class SyncReviewItem { final SyncUploadRow upload; final String uploader; final String? school; }`
  - `Future<SyncUploadDetails> details(int id)` → `class SyncUploadDetails { final SyncReviewItem item; final List<String> lines; }`
  - `Future<SyncApproveResult> approve(int id)` → `class SyncApproveResult { final int uploadId; final String status; final String? reason; final List<SyncProblem> conflicts; final String uploader; toString(); }`
  - `Future<void> reject(int id, String reason)`
  - `Future<int?> latestPendingId({int? schoolId})` (decision A)
- Approve texts (decision 6): applied `Upload <id> applied. Run pull-cloud to see it on this device.`; conflict `Upload <id> stopped on <n> conflict(s), sent back to <uploader>:` + one indented line per conflict; error `Upload <id> failed on the server: <reason>`; a server message containing `older BASA release` → `Upload <id> was made by an older BASA release: reject it so <uploader> updates BASA and syncs again.`
- `SyncViewModel.refreshStatus()` on `conflict`: `remote.withdraw(id)` then `releaseUpload(id)`; on a withdraw failure the lock stays and the outcome is `SyncOutcome(status: 'conflict', ...)` with `reason: 'could not withdraw it on the server; run sync-status again'` (decision B). `SyncOutcome.toString()` for conflict says `withdrawn on the server` when it worked.
- `SyncViewModel.upload()`: the final `refreshStatus()` is wrapped; a failure sets `statusError` and the text becomes `Upload <id> sent: <n> row(s). Its decision could not be read (<error>); run sync-status.` (M4).

- [ ] **Step 1:** Implement the remote additions, models and VM. `pending` scope rules per Global Constraints (superadmin + `schoolId` null = all, adds the school label per decision E from local `schools`). `details` reads the payload, prefetches `referencedKeys` through the local repo, calls `describeUpload`. `reject` checks the reason before calling the server.
- [ ] **Step 2:** `dart analyze`. Console checks come with Task 3.

### Task 3: Settings, commands, wiring, kit

**Files:**
- Modify: `lib/core/models/report_setting.dart` (`syncAutoApproveKey = 'sync_auto_approve'`, `bool syncAutoApprove` default false)
- Modify: `lib/viewmodels/report_settings_viewmodel.dart` (shared private `_setKey(int? schoolId, String key, Object value)` used by `setDoneThreshold` and the new setters; behaviour of `setDoneThreshold` unchanged)
- Modify: `lib/core/console/commands/report_settings_commands.dart` (decision C), `lib/core/console/commands/sync_commands.dart`
- Modify: `lib/console/main.dart`, `lib/main.dart`

**Interfaces:**
- `ReportSettingsViewModel`: `Future<({bool? region, bool? school, bool effective})> autoApproveLayers(int? schoolId)`; `Future<ReportSetting> setAutoApprove(int? schoolId, bool on)`; `Future<({int? region, int? school, int effective})> offlineDaysLayers(int? schoolId)`; `Future<ReportSetting> setOfflineDays(int? schoolId, int days)` (refuses outside 1-60: `The offline sign-in window is 1 to 60 days, not <n>.`).
- `registerSyncReviewCommands(ConsoleRegistry registry, SyncReviewViewModel vm)` in `sync_commands.dart`.

Commands:
- `sync-pending [schoolId]` → `Waiting for approval (oldest first):` + `  <id>  <uploader>  <created>  <rows> row(s)[  school <id> <name>]` with the summary lines indented under each; `Sent back (conflict), waiting for the uploader:` block (only when non-empty); last line `<n> upload(s) still pending.`
- `sync-show <id>|latest` → header `Upload <id> by <uploader>, <created>, <status>[: <reason>]`, then the record lines.
- `sync-approve <id>|latest` → approve texts above.
- `sync-reject <id>|latest <reason...>` → `Upload <id> rejected and sent back to <uploader>: <reason>`.
- `sync-auto-approve <region|schoolId> [on|off]` → `Auto-approve: region <on|off|not set> · school <...> · applies <on|off>`; set → `Auto-approve for <who> is now <on|off>.` + `Uploads already waiting still need sync-approve.` when turned on.
- `offline-days <region|schoolId>` → `Offline sign-in window: region <n days|not set> · school <...> · applies <n> days`; `offline-days-set <region|schoolId> <1-60>` → `Offline sign-in window for <who>: <n> days. Tablets get it after their next pull-cloud.`
- `report-settings-reset` help → `... drops the school's done threshold, auto-approve and offline window so the region's apply (online)`.

- [ ] **Step 1:** Implement settings, commands and wiring; `dart analyze`.
- [ ] **Step 2: Console run against the dev cloud**, kit `D:/0_CAPSTONE/verify/sync-s6/` (copy of the S5 kit layout: `data/` = tutor device, `coord/` = coordinator device, `data_fresh/`; I clear the tutor's leftover pending/conflict S5 uploads first and note it in the ledger):
  1. `1_tutor_upload.txt` (tutor): pull, new session + 2 marks, edit session 1 remarks, `sync-upload yes` → pending.
  2. `2_coord_approve.txt` (coord): `sync-pending`, `sync-show latest`, `sync-approve latest` → applied; `sync-approve <same id>` again → `... is applied, not pending`; tutor `sync-status` → applied, ids positive.
  3. `3_conflict_sent_back.txt`: tutor edits session 1 and uploads; coord edits session 1 (own upload, applies at once), `sync-approve latest` → conflict sent back; `sync-pending` shows the sent-back block; tutor `sync-status` → conflict lines, upload `withdrawn`; tutor `sync-preview` → same conflict listed; `sync-resolve aral_sessions 1 server`.
  4. `4_reject.txt`: tutor uploads; coord `sync-reject latest` with blanks → refused, with a 501-character reason → refused, with `wrong date, fix and sync again` → rejected; tutor `sync-status` → rejected with the reason, record editable.
  5. `5_settings.txt`: tutor `sync-approve latest` → Forbidden; coord `sync-auto-approve <school> on`; tutor uploads → applied at once; coord `sync-auto-approve <school> off`; `offline-days <school>`, `offline-days-set <school> 7`, `offline-days-set <school> 61` → refused, `report-settings-reset <school>` → all three back to the region's.
  Expected outputs from my run; README with reset line; probe line (`probe_review.dart` → `N passed, 0 failed`); S5 probes still pass (`probe_package` 30/0, `probe_apply` 37/0).
- [ ] **Step 3:** Fresh reviewer on the whole piece; any finding that changes behaviour comes to the owner before it is fixed; hand over the kit and the commit message; wait.

## Known follow-ups (not in S6)

- S7 docs: README pre-update checklist (`sync-pending` count = step 2), CLAUDE.md sessions line, sync no longer parked.
- Release-guard text is checked only by message match; the PG harness (S1) covers the guard itself; no console case (needs an older device release).
- S5 minors M1, M3, M5 stay deferred.
- Superadmin's `sync-show` on a school they never pulled prints ids (decision 5 fallback).
