# Sync S2 (SQLite v34) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The device side of sync's bookkeeping: `row_version` on the 18 synced tables, negative ids for every new local row, a one-time renumber of existing local rows, the `sync_changes` journal and the `sync_pending` lock (both by triggers), and `pull-cloud` copying `row_version` without journaling its own writes.

**Architecture:** One new creator, `createSyncLocalSchema`, runs last on create and on every upgrade (IF NOT EXISTS + drop/recreate triggers). A row's state comes from `row_version`: NULL = new on this device, not NULL = a copy of a server row. Every trigger skips while a `sync_meta` row `sync_bypass` exists; that row is only ever written inside a transaction (pull, mirror writes, renumber), so a crash can't leave it on. New ids come from `local_ids` (AUTOINCREMENT, id = -n), so one countdown covers all tables, as S1's flat id map needs.

**Tech Stack:** Dart, sqflite_common / sqflite_common_ffi, the console (`dart run`), scratch Dart probes.

**Spec:** `docs/superpowers/specs/2026-10-20-sync-design.md` (sections 1, 3, 7 for what pull must keep, 12-S2). S1 plan: `docs/superpowers/plans/2026-10-20-sync-s1-server.md`.

## Global Constraints

- `LocalDatabase` version 33 → **34**, with a `// v34:` line in the version comment. `createSyncLocalSchema(db)` is called LAST in `onCreate` and LAST in `onUpgrade` (after `createTutorAssignmentLocalSchema`), unconditionally. The renumber runs only `if (oldVersion < 34)`, after it.
- Synced tables (exactly 18) and their key: `assessment_id` for `crla_part1_standard`, `crla_part1_english`, `crla_part2_fluency`; `tutor_id` for `aral_tutor_settings`; `id` for the other 14. Parent of each child (for the pending lock and the renumber): parts → `crla_assessments.assessment_id`; `phil_iri_readings`, `phil_iri_rubric_scores` → `phil_iri_assessments.assessment_id`; `phil_iri_miscues`, `phil_iri_answers` → `phil_iri_readings.reading_id`; `aral_attendance` → `aral_sessions.session_id`; `aral_checkin_answers` → `aral_checkins.checkin_id`.
- Server-allowed ops (baseline + 20261018050000 policies). The device must never journal an op the server refuses:
  - `crla_assessments`: insert only. Its header changes only `reading_profile` locally (the server recomputes it from the parts), so header updates are NOT journaled; any other column change or a delete of a pulled header is refused.
  - `phil_iri_gst_results`: insert only → update/delete of a pulled row refused.
  - CRLA part tables: insert + update → delete of a pulled row refused.
  - All other 13: update and delete journaled.
  - Refusal text: `'This record is already on the server and cannot be changed on this device'` (delete: `'... cannot be deleted on this device'`).
- Pending-lock text exactly `'pending upload'` (spec 3.2; ViewModels map it in S5).
- `row_key` is TEXT: `CAST(<key> AS TEXT)`; Dart side `'$key'`.
- No SQLite UPSERT (`ON CONFLICT DO`): older Android ships SQLite 3.22. Use `INSERT OR IGNORE` + `UPDATE`.
- Backend only; no UI. Console must keep working under plain `dart run`. `dart analyze`: no errors.

## Decisions taken in this plan (owner please confirm)

1. **`local_ids` table instead of a counter value in `sync_meta`.** One `INSERT` gives the next number atomically; a read-then-write counter can hand out the same id twice when two async writes interleave outside a transaction. Same effect as the spec's single countdown.
2. **Read-only guards on pulled rows** the server would refuse to change (list above). Without them such an edit would sit in the journal and make every later upload fail.
3. **Upgrade sets `row_version = 0` on existing pulled rows.** Their real server version is unknown; 0 never matches the server (which starts at 1), so an edit made before the next pull shows up as a conflict instead of silently overwriting. The next pull replaces them with real versions.
4. **`pull-cloud` also refuses while `sync_changes` has lines** (edits to server records) or new child rows hang under pulled parents, and `discard-local` clears `sync_changes` and `sync_pending`. Today those edits are lost silently; the pull is still a full replace until S4.
5. **Adding a child under a parent that is in a pending upload is refused** (`'pending upload'`), e.g. an attendance mark on a session waiting for approval. Otherwise the next upload would carry a child whose parent id isn't in it.
6. **`offline_credentials` and `login_logs.mode` are created in v34** (spec 3.3), so S3 needs no version bump. Nothing uses them until S3.
7. **Known limit (documented, not fixed):** child rows added on this device to a pulled parent before v34 (an attendance mark on a pulled session, say) can't be told apart from pulled rows. They are treated as pulled, so a pull still drops them, exactly as it does today.

## Review Focus

1. A local insert that slips past `nextLocalId` (a repository missed, or a future one) → refused with a clear message, never stored with a positive id that can collide with a pulled id. Pinned by the guard test in Task 1 and the console run in Task 2.
2. A pull, discard or mirror write (CRLA regenerate) touching pulled rows → no journal lines and no lock refusal. Test in Task 3 (pull) and Task 2 (regenerate mirror).
3. An upgrade from v33 with local rows whose children point at them (CRLA parts, Phil-IRI readings/miscues/answers, ARAL attendance and check-in answers, an ARAL enrollment whose basis is a local assessment) → every link still points at the same record after the renumber. Test in Task 4 against the owner's verify DB.
4. Listings ordered by `id` (attendance) → new rows keep entry order (`-1, -2, -3` would otherwise list newest first). Test in Task 2.
5. Editing a pulled row twice, or editing then deleting → one journal line with the FIRST base version, op `delete` after a delete. Test in Task 1.

---

### Task 1: v34 schema, journal, lock, guards

**Files:**
- Create: `lib/core/data/local/sync_local_schema.dart`
- Modify: `lib/core/data/local/local_database.dart` (version 34, comment line, the two calls)
- Test: `D:/0_CAPSTONE/verify/sync-s2/probe_schema.dart` (scratch probe, absolute DB path in its own folder)

**Interfaces:**
- Produces: `Future<void> createSyncLocalSchema(Database db)`; `const syncedTables = <String, String>{table: keyColumn}` (the 18, in `_pullOrder` order, exported for S4/S5); `const syncedParents = <String, (String parentTable, String fkColumn)>{...}` (the 7 child tables above).
- Produces (tables): `local_ids (n INTEGER PRIMARY KEY AUTOINCREMENT, made_at TEXT)`; `sync_changes (table_name TEXT NOT NULL, row_key TEXT NOT NULL, op TEXT NOT NULL CHECK (op IN ('update','delete')), base_version INTEGER NOT NULL, changed_at TEXT NOT NULL DEFAULT (datetime('now')), PRIMARY KEY (table_name, row_key))`; `sync_pending (table_name TEXT NOT NULL, row_key TEXT NOT NULL, upload_id INTEGER NOT NULL, PRIMARY KEY (table_name, row_key))`; `offline_credentials (user_id TEXT PRIMARY KEY, email TEXT NOT NULL, salt TEXT NOT NULL, iterations INTEGER NOT NULL, hash TEXT NOT NULL, last_online_at TEXT NOT NULL, failed_attempts INTEGER NOT NULL DEFAULT 0)`; column `row_version INTEGER` (nullable) on the 18 tables and `login_logs.mode TEXT NOT NULL DEFAULT 'online' CHECK (mode IN ('online','offline'))`, both added by PRAGMA check like `_addCrlaV14Columns`.
- Produces (triggers, names fixed so S4/S5 and the reviewer can find them; `bypass` = `NOT EXISTS (SELECT 1 FROM sync_meta WHERE key = 'sync_bypass')`):
  - `sync_new_id_<t>` (14 id tables): AFTER INSERT WHEN `NEW.id > 0 AND NEW.row_version IS NULL` → `RAISE(ABORT, 'A new <t> row needs a local id (nextLocalId)')`. No bypass: a pulled row always carries `row_version`.
  - `sync_journal_upd_<t>` (16 tables: all but `crla_assessments` and `phil_iri_gst_results`): AFTER UPDATE WHEN bypass off AND `OLD.row_version IS NOT NULL` → `INSERT OR IGNORE INTO sync_changes (table_name, row_key, op, base_version) VALUES ('<t>', CAST(OLD.<key> AS TEXT), 'update', OLD.row_version)`.
  - `sync_journal_del_<t>` (13 tables: those 16 minus the 3 part tables): AFTER DELETE, same WHEN → `INSERT OR IGNORE ... 'delete' ...; UPDATE sync_changes SET op = 'delete' WHERE table_name = '<t>' AND row_key = CAST(OLD.<key> AS TEXT);` (keeps the first base version).
  - `sync_readonly_upd_<t>` / `sync_readonly_del_<t>` for the refused ops in Global Constraints: BEFORE, WHEN bypass off AND `OLD.row_version IS NOT NULL` (for `crla_assessments` update: AND any column other than `reading_profile` changed, compared with `IS NOT`) → the refusal text.
  - `sync_lock_upd_<t>` / `sync_lock_del_<t>` (18): BEFORE, WHEN bypass off AND `EXISTS (SELECT 1 FROM sync_pending WHERE table_name = '<t>' AND row_key = CAST(OLD.<key> AS TEXT))` → `RAISE(ABORT, 'pending upload')`.
  - `sync_lock_child_<t>` (7 child tables): BEFORE INSERT, WHEN bypass off AND the parent key `NEW.<fk>` is in `sync_pending` under the parent table → `RAISE(ABORT, 'pending upload')`.
  - Build the SQL in Dart loops over `syncedTables` / `syncedParents`; table and column names come only from those constants.

- [ ] **Step 1: Write the probe (failing).** Opens a fresh DB in `D:/0_CAPSTONE/verify/sync-s2/probe_db/` through `LocalDatabase.instance` (set `databaseFactory = databaseFactoryFfi` first), seeds minimal rows with raw SQL under `sync_bypass` where it needs pulled rows, and prints `PASS`/`FAIL name` lines and a final count. Checks:
  - `user_version = 34`; 18 tables have `row_version`; `sync_changes`, `sync_pending`, `local_ids`, `offline_credentials`, `login_logs.mode` exist.
  - `insert aral_sessions` with no id and `row_version` NULL → error containing `needs a local id`.
  - pulled `aral_sessions` id 200 `row_version 3`: update `remarks` twice → exactly one line `('aral_sessions','200','update',3)`; then delete → same line, op `delete`, base 3.
  - pulled `aral_attendance` update → journaled; new session id -5 update → no line.
  - pulled `crla_assessments` update of `reading_profile` → allowed, no line; update of `language` → refused text; delete → refused.
  - pulled `phil_iri_gst_results` update → refused; pulled `crla_part2_fluency` update → journaled under key = assessment_id; delete → refused.
  - row `('aral_sessions','-5',1)` in `sync_pending`: update / delete of session -5 → `pending upload`; insert attendance with `session_id -5` → `pending upload`.
  - inside a transaction with `sync_bypass`: update + delete a pulled row → no journal line, no lock refusal; after commit `sync_bypass` row is gone.
- [ ] **Step 2: Run it:** `dart run --packages=d:/0_CAPSTONE/Code/BASA-Capstone/.dart_tool/package_config.json D:/0_CAPSTONE/verify/sync-s2/probe_schema.dart` → FAIL (version 33, nothing exists).
- [ ] **Step 3: Implement `sync_local_schema.dart` and wire it into `LocalDatabase`.** File header comment states the row-state rule (`row_version` NULL = new), the bypass rule (only inside a transaction) and that any future table rebuild (like v21/v26) must copy `row_version` and run before `createSyncLocalSchema` so its triggers come back.
- [ ] **Step 4: Run the probe → all PASS.** Run it a second time on the same DB (reopen = no upgrade) → still PASS. `dart analyze` → no errors.

### Task 2: negative ids in the repositories, mirror writes, ordering

**Files:**
- Create: `lib/core/data/local/sync_local_writes.dart`
- Modify (each local insert into the 14 id tables gets `'id': await nextLocalId(executor)`; drop the `..remove('id')`): `crla_assessment_repository_sqlite.dart:14`, `phil_iri_gst_repository_sqlite.dart:17`, `phil_iri_assessment_repository_sqlite.dart:30,154,205,247,280`, `aral_enrollment_repository_sqlite.dart:33`, `aral_session_repository_sqlite.dart:32,89`, `aral_irip_repository_sqlite.dart:53`, `aral_checkin_repository_sqlite.dart:67,115`, `aral_readability_repository_sqlite.dart:31`. Mirror writers of the 18 tables (`upsertWithId`, `upsert*WithId`, `upsertMirrored` in the crla/phil_iri/aral local repos) switch from `upsertById` to `mirrorSyncedRow`.
- Modify: `aral_session_repository_sqlite.dart:110` ordering.
- Test: `D:/0_CAPSTONE/verify/sync-s2/probe_ids.dart` + a console run.

**Interfaces:**
- Consumes: `local_ids`, `sync_meta`, `syncedTables` (Task 1).
- Produces:
  - `Future<int> nextLocalId(DatabaseExecutor db)` → `-(insert into local_ids)`; first value on a fresh DB is -1, strictly decreasing, never reused.
  - `Future<T> withSyncBypass<T>(Transaction txn, Future<T> Function() body)` → inserts `('sync_bypass','1')` into `sync_meta`, runs `body`, deletes it (in a `finally`). Takes a `Transaction` so it can only run inside one.
  - `Future<void> mirrorSyncedRow(Database db, String table, Map<String, Object?> row, {String key = 'id'})` → one transaction under the bypass; update if the key exists (keeps the local `row_version` unless `row` has one), else insert with `row_version` = `row['row_version'] ?? 0`. Same `MirrorConflictException` behaviour as `upsertById` (reuse it).
  - Ordering rule for lists that ordered by `id`: `ORDER BY (id < 0), abs(id)` (pulled rows first, then new rows in entry order).

- [ ] **Step 1: Write `probe_ids.dart` (failing):** fresh DB → `nextLocalId` gives -1, -2, -3; a session inserted through `AralSessionRepositorySqlite.insertSession` has id < 0 and `session_no` 1; three attendance marks added through `saveAttendance` come back from `getAttendance` in entry order; `mirrorSyncedRow` on a pulled `crla_assessments` row (as CRLA regenerate does) changes it with no `sync_changes` line and no refusal, and on a missing id inserts it with `row_version 0`.
- [ ] **Step 2: Run → FAIL** (`nextLocalId` undefined).
- [ ] **Step 3: Implement** the file and the repository edits. Then grep every `insert('<14 tables>'` under `lib/` again; any site not converted is a bug (the Task 1 guard would refuse it at run time).
- [ ] **Step 4: Run the probe → PASS.** `dart analyze` → no errors.
- [ ] **Step 5: Console run** on a scratch copy of `D:/0_CAPSTONE/verify/data` (sign in `zztest.coord@basa.test`, then as the tutor where needed): create an ARAL session, mark attendance, add a CRLA assessment with parts, start a Phil-IRI session with a reading and an answer, then show each. Expected: negative ids printed, no trigger refusals, show/list commands accept a negative id argument (if the console parser takes `-5` for something else, fix the parser, not the id).

### Task 3: pull-cloud under the bypass, new refusal lines, discard clears the journal

**Files:**
- Modify: `lib/core/console/commands/pull_commands.dart`
- Test: console run (scratch copy of the verify DB, dev cloud)

**Interfaces:**
- Consumes: `withSyncBypass`, `syncedTables`, `syncedParents`.
- Produces: no new API. (S4 moves this logic into `SyncViewModel.pull()`.)

Changes:
- The clear-and-write transaction body runs inside `withSyncBypass(txn, ...)`. `row_version` needs no code: `_toLocal` copies every column the local table has.
- `discard-local` also deletes all rows of `sync_changes` and `sync_pending` in the same transaction.
- `_unsynced` gains two kinds, each one line: `'change(s) to records already on the server'` (count of `sync_changes`) and `'new item(s) added to records already on the server'` (rows with `row_version IS NULL` in a child table whose parent row has `row_version IS NOT NULL`). Both make the pull refuse like the existing kinds; the prompt text stays the same otherwise.

- [ ] **Step 1: Implement.** (Without the bypass, the pull's own deletes of pulled rows would write `delete` lines and the next pull would refuse; Step 2's first check pins that.)
- [ ] **Step 2: Console run:** `pull-cloud yes discard-local` → `Done.`; read-only check `select count(*) from sync_changes` = 0 and pulled rows have `row_version >= 1`; edit one pulled ARAL session → one `sync_changes` line; `pull-cloud yes` → refused with `1 change(s) to records already on the server`; `pull-cloud yes discard-local` → done, `sync_changes` empty. `dart analyze` → no errors.

### Task 4: one-time renumber on upgrade (v33 → v34)

**Files:**
- Modify: `lib/core/data/local/sync_local_schema.dart` (add the function), `local_database.dart` (call it `if (oldVersion < 34)` after `createSyncLocalSchema`)
- Test: `D:/0_CAPSTONE/verify/sync-s2/probe_upgrade.dart` against a copy of `D:/0_CAPSTONE/verify/data/basa_local.db` (v33; holds local CRLA assessments 4-7 in section 6 and a local ARAL learner, student 137, section 28)

**Interfaces:**
- Produces: `Future<void> renumberLocalRowsForV34(Database db)` — one transaction under `withSyncBypass`.

Behaviour, in this order:
1. Pulled rows get `row_version = 0`: owner tables where `origin = 'cloud'`; child tables where the parent row is pulled, and for `aral_attendance` also the enrollment is `origin = 'cloud'` (an attendance row pointing at a local enrollment can't be on the server). `aral_tutor_settings` with `origin = 'local'` stay NULL (insert; S5 preview handles a server row that already exists).
2. Every other row with `id > 0` in the 14 id tables is new: give it `nextLocalId`, parents before children (`syncedTables` order), keeping one `Map<String, Map<int,int>>` old → new per table, and rewrite the children's FK columns (`syncedParents`, plus `aral_attendance.enrollment_id`, `aral_irip_weeks.enrollment_id`, `aral_checkins.enrollment_id`, `aral_readability_logs.enrollment_id` → `aral_enrollments`). Update a child's FK whether or not the child itself is renumbered.
3. Part tables follow their assessment's new id (`assessment_id` is their key).
4. `aral_enrollments.basis_assessment_id` → through `crla_assessments` when `basis_source = 'crla'`, `phil_iri_assessments` when `'phil_iri'`. `suggestion_assessment_id` → by the enrollment's section grade: `'1'..'3'` = CRLA, else Phil-IRI (the ARAL ViewModel takes the latest CRLA result for Grades 1-3 and Phil-IRI otherwise). Only ids found in that table's map change.
5. Safe to run twice: a second run finds no `id > 0` row with `row_version` NULL.

- [ ] **Step 1: Write `probe_upgrade.dart` (failing):** before opening, read with plain sqlite (read-only) the local rows and their links into a snapshot keyed by natural keys (CRLA: student + variant + attempt; parts by their assessment's natural key; ARAL enrollment: student + year, its attendance/IRIP/check-ins by (session date, learner) etc.). Then open through `LocalDatabase.instance` (upgrade), and check: `user_version = 34`; every former local row now has `id < 0`; every snapshot link resolves to the same natural key; pulled rows have `row_version = 0`; `sync_changes` is empty; row counts per table unchanged; `PRAGMA foreign_key_check` style orphan query (child FK not found in parent) returns nothing new.
- [ ] **Step 2: Run on a copy → FAIL** (ids still positive).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run on a fresh copy → PASS.** Then run the console on that upgraded copy: `crla-results` / ARAL roster for section 6 / 28 show the same learners and scores as on the old copy (compare the two outputs; only ids differ).

### Task 5: review, kit, docs line

- [ ] **Step 1:** `dart analyze`; all three probes PASS on fresh DBs.
- [ ] **Step 2:** Fresh reviewer (opus) on the S2 diff against this plan and spec section 3.
- [ ] **Step 3:** Verify kit `D:/0_CAPSTONE/verify/sync-s2/` per the standing recipe: `data/` + `data_fresh/` (copy of the v33 verify DB), `launch.dart`, the three probes, numbered console files (`1_upgrade_check`, `2_new_ids`, `3_journal_and_pull`), expected outputs from my own run, README with reset line.
- [ ] **Step 4:** `lib/core/CLAUDE.md`: a short *Sync bookkeeping (v34)* note: row states, `nextLocalId` for every new row in the 14 id tables, `mirrorSyncedRow` for mirror writes, the bypass rule, table rebuilds must keep `row_version`. Hand the owner the commit message.
