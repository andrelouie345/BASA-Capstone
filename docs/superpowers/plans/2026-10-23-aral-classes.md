# ARAL classes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 15-per-section ARAL rule with ARAL classes (15 active learners per class, one program and grade band, learners from any section, per-class sessions), synced offline-first, with class tutors able to read and assess their class learners.

**Architecture:** One cloud migration (written and tested first, applied last) adds `aral_classes` (19th synced table), `class_id` on `aral_enrollments` and `aral_sessions`, referral columns, new RLS helpers, and drops `aral_enrollments.tutor_id`, the section cap and `aral_tutor_settings`. The device mirrors it in two SQLite steps (v36 roster, v37 sessions). A new `AralClassViewModel` owns classes and placements; `AralViewModel` and `AralSessionViewModel` move from "the learner's tutor" to "the learner's class".

**Tech Stack:** Dart (pure, no Flutter in `lib/core` and `lib/viewmodels`), sqflite_common_ffi (bundled SQLite), Supabase (Postgres 15+ RLS, plpgsql), the console registry, the command-pass runner.

**Spec:** `docs/superpowers/specs/2026-10-23-aral-classes-design.md` (read it with this plan; decisions 1-12 are referred to as D1-D12).

## Global Constraints

- Backend only; no UI files. Owner commits: hand over a commit message per task, never run git.
- Stop after each task for the owner's check; present any decision not in the spec BEFORE acting.
- Migration file `supabase/migrations/20261023040000_aral_classes.sql`: idempotent; header line `App update required on all devices: yes`; ends by inserting its `basa_migrations` row (`app_update_required` true); same commit adds `'20261023040000': 'aral_classes'` to `lib/core/release.dart` and a README 2b line. Never applied before Task 6.
- Every SECURITY DEFINER function: `set search_path to 'public'`; execute revoked from `public, anon, authenticated` unless a policy calls it.
- SQLite: v36 (Task 3), v37 (Task 4). A rebuild copies every column of the old table (row_version included) and runs in `onUpgrade` before every creator (pattern: `rebuildAralEnrollmentsForV35`).
- Device foreign keys that point at a synced table must be declared (`REFERENCES aral_classes(id)`): `followLocalIds` and the pull orphan check find them through `PRAGMA foreign_key_list`.
- Programs (`aral_classes.program`): `foundational`, `ks1`, `ks2_basic`, `ks2_plus`, `ks3_basic`, `ks3_plus`. Grade bands: `1-3`, `4-6`, `7-10`. Class cap: 15 active learners (hard).
- After every task: `dart analyze` (0 errors), `flutter test`, `dart run tool/check_tutor_imports.dart`.
- Every new public ViewModel method calls `_requireSignIn()` first and is added to `test/viewmodels/session_guard_test.dart`.
- Command lists `test/core/wiring/{admin,tutor}_commands.txt`, `tool/command_pass/readonly_commands.txt` and `test/tool/command_pass/coverage_test.dart` totals follow every command added/removed.

## Review Focus

1. A tutor's offline placement or session for a class that filled up or was deleted on the server: the upload is refused with a readable message, not a raw Postgres error (Task 3 / Task 4 refusal mapping tests).
2. Upgrading a real device that holds unsent ARAL work (negative ids, pending upload) to v36/v37: rows, `row_version` and pending locks survive (Task 3 / Task 4 upgrade tests with a negative-id row and a `sync_pending` entry).
3. A learner placed in a class whose band no longer fits after an SF1 section move to another grade: unplaced and flagged, not refused or silently kept (Task 3 `moveToSection` test).
4. A referred learner whose later results are Developing (KS1, switch off): stays in ARAL; only grade-level ready exits (Task 3 `applyResults` test).
5. Two classes with the same name differing only in case or spaces ("7-Rose", "7-rose "): refused as duplicates on device and server (Task 2 / Task 1 tests).

---

### Task 1: Server migration (C1) — written and tested, not applied

**Files:**
- Create: `supabase/migrations/20261023040000_aral_classes.sql`
- Create (outside repo): `D:/0_CAPSTONE/verify/pass/tools/classes_test.sql`, `classes_run.sh` (copy of `ks1_run.sh` pointing at the new files)

**Interfaces (Postgres objects later tasks rely on):**
- Table `public.aral_classes` (spec §1 columns), unique index `aral_classes_name_key on (school_id, school_year, lower(btrim(class_name)))`, checks `aral_classes_program_check`, `aral_classes_grade_band_check`, `row_version bigint not null default 1` + `sync_row_version` trigger.
- `aral_enrollments`: `class_id bigint references aral_classes(id) on delete restrict`, `referred_by text`, `referral_reason text`; `basis_source` check adds `referral`; check `aral_enrollments_referral` = `(basis_source = 'referral') = (referred_by is not null and btrim(referred_by) <> '' and referral_reason is not null and btrim(referral_reason) <> '')`; `basis_level` check (`aral_enrollments_basis`) also accepts `referral`; column `tutor_id` dropped.
- `aral_sessions`: `class_id bigint references aral_classes(id) on delete restrict`; per-class numbering and one-per-class-per-date when `class_id` is not null (old rows keep per-tutor numbers).
- Functions: `aral_tutor_has_class(bigint)`, `aral_tutor_has_student(bigint)`, `aral_check_class_placement(p_id bigint, p_class_id bigint, p_student_id bigint, p_section_id bigint, p_school_id bigint, p_school_year text, p_key_stage text, p_track text)` (raises the messages below; advisory lock `hashtext('aral_class:' || p_class_id)`).
- Exact cloud refusal texts (the device maps them): `an ARAL class has at most 15 active learners`, `the learner's program does not match the ARAL class`, `the learner's grade is outside the ARAL class's grade band`, `the ARAL class belongs to another school or school year`, `the ARAL class tutor must be an active tutor of the class's school`, `an ARAL class already has a session on that date`, `an ARAL class with learners keeps its program and grade band`.
- Sync lists: `aral_classes` added to `sync_row_version` loop, `basa_private.sync_check_payload` synced list, `basa_private.sync_key_column` (id); `sync_ref_columns`: `aral_enrollments` → `basis_assessment_id, suggestion_assessment_id, class_id`; `aral_sessions` → `class_id`. `aral_tutor_settings` removed from all of them, then dropped with its policies and `aral_check_session_day`'s tutor-settings branch.

- [ ] **Step 1: Write `classes_test.sql`** — fixture: 2 schools, sections G2/G5/G7 in school A and G7 in school B, coordinator A and B, tutors T1, T2 (school A), 18 G7 students + 1 G5 + 1 G2 student, enrollments. Cases (each a `try(label, sql, want_ok)` row as in `f9_test.sql`), run as postgres and with `request.jwt.claim.sub` set per role:
  1. coordinator A creates class "7-Rose" (`ks3_basic`, `7-10`, T1) — ok; "7-rose " in same school/year — refused (unique).
  2. coordinator A places 15 G7 `ks3_basic` learners — ok; 16th — refused `at most 15`; exiting one, then placing the 16th — ok.
  3. placing a `ks2_basic` learner — refused `program does not match`; a G5 `ks3_basic` learner — refused `grade band`; a school-B learner — refused `another school`.
  4. `aral-update`-style program change of a placed learner (update `key_stage`/`track` only) — ok (no re-check).
  5. coordinator B reads/writes school A classes — 0 rows / refused.
  6. T1 reads class "7-Rose", its learners' `aral_enrollments`, `students`, the G7 section row, and inserts a CRLA/Phil-IRI assessment for a placed learner from a section T1 is not assigned to — ok; T2 does the same — 0 rows / refused.
  7. T1 inserts a session for "7-Rose" — ok; second on the same date — refused `already has a session`; T2 inserts for "7-Rose" — refused.
  8. move a learner (with a mark in a T1 session) to T2's class "7-Lily": T2 reads that learner's mark and the old session header — ok; T2 reads another learner's mark in that session — 0 rows; T1 now reads the moved learner's `students` row — 0 rows unless section-assigned.
  9. referral row without `referred_by` — refused; with both texts — ok.
  10. deleting a class with learners or sessions — refused; an empty class — ok; editing `program` of a class with learners — refused.
  11. `aral_tutor_settings` gone; `aral_check_section_cap` gone; `authenticated` cannot execute `aral_check_class_placement`; no policy on the touched tables is `using (true)`.
  12. ledger row `20261023040000` with `app_update_required = true`.
- [ ] **Step 2: Run it against the current migrations** — `bash classes_run.sh d:/0_CAPSTONE/Code/BASA-Capstone <scratch dir>`. Expected: fails (table missing).
- [ ] **Step 3: Write the migration** — header per Global Constraints (what, why, rules, RLS raised); objects from Interfaces; policies from spec §3 (drop+create each touched policy); existing rows: `class_id` null (D11).
- [ ] **Step 4: Run again, twice** — Expected: every `result|...|PASS`, `second run OK`, no `FAIL <file>`.
- [ ] **Step 5: Hand over** — summary + commit message (`feat(db): ARAL classes migration (not applied)`), noting it must not be applied until Task 6.

### Task 2: Class model, rules, repository, class ViewModel (C3/C4, additive)

**Files:**
- Create: `lib/core/models/aral_class.dart`, `lib/core/repositories/aral_class_repository.dart`, `lib/core/data/local/aral_class_repository_sqlite.dart`, `lib/core/data/remote/aral_class_repository_supabase.dart`, `lib/viewmodels/aral_class_viewmodel.dart`, `lib/core/console/commands/aral_class_commands.dart` (both builds), `lib/core/console/commands/aral_class_admin_commands.dart` (admin)
- Modify: `lib/core/services/aral_rules.dart` (placement rules), `lib/core/data/local/aral_local_schema.dart` (create `aral_classes` + its triggers), `lib/core/wiring/wire_tutor.dart` / `wire_admin.dart`, `lib/core/data/local/local_database.dart` (no version change: table is `IF NOT EXISTS` in `createAralLocalSchema`, which runs on every upgrade)
- Test: `test/core/services/aral_placement_rules_test.dart`, `test/core/data/aral_class_repository_sqlite_test.dart`, `test/viewmodels/session_guard_test.dart`

**Interfaces:**
- Produces (`aral_class.dart`): `enum AralClassProgram { foundational, ks1, ks2Basic('ks2_basic'), ks2Plus('ks2_plus'), ks3Basic('ks3_basic'), ks3Plus('ks3_plus') }` with `String value`, `String label` (`Foundational`, `KS1`, `KS2 Basic`, …), `static AralClassProgram of(AralKeyStage ks, AralTrack? track)`, `static AralClassProgram fromString(String)`; `enum AralGradeBand { g1to3('1-3', 1, 3), g4to6('4-6', 4, 6), g7to10('7-10', 7, 10) }` with `bool contains(int grade)`, `static AralGradeBand? ofGrade(int grade)`, `fromString`; `class AralClass { int? id; int schoolId; String schoolYear; String className; AralClassProgram program; AralGradeBand gradeBand; String? tutorId; String? room, schedule, notes, createdBy, createdAt, updatedAt; toMap(); fromMap(); copyWith(...) }` (nullable fields via `T? Function()?` like `AralEnrollment.copyWith`).
- Produces (`aral_rules.dart`): `const aralClassCap = 15;` `enum AralPlacementProblem { otherSchoolOrYear, programMismatch, gradeOutsideBand, full }`; `AralPlacementProblem? aralPlacementProblem({required AralClass target, required int schoolId, required String schoolYear, required AralClassProgram program, required int grade, required int activeOthersInClass})`; `String aralPlacementMessage(AralPlacementProblem p, {required String learner, required AralClass target, required int grade, required AralClassProgram program})` with texts: full → `Class "{name}" already has 15 active ARAL learners.`; program → `{learner} is in {program.label}; class "{name}" is {target.program.label}.`; band → `{learner} is in Grade {grade}; class "{name}" takes Grades {band.value}.`; other → `Class "{name}" belongs to another school or school year.`
- Produces (`AralClassRepository`): `insert(AralClass)`, `update(AralClass)`, `delete(int id)`, `findById(int)`, `getBySchool(int schoolId, {String? schoolYear})`, `getByTutor(String tutorId, {String? schoolYear})`, `upsertWithId(AralClass)` (mirror; Supabase impl throws `UnimplementedError`). SQLite insert uses `nextLocalId` (negative id) like the roster.
- Produces (`AralClassViewModel`): `createClass({required int schoolId, required String schoolYear, required String className, required AralClassProgram program, required AralGradeBand gradeBand, String? tutorId, String? room, String? schedule, String? notes})`, `editClass(AralClass c)`, `deleteClass(int classId)`, `classes({required int schoolId, String? schoolYear})` (tutor: own only), `getClass(int id)`. Refusals: `A class named "{name}" already exists for {year}.`, `Forbidden: admin or coordinator only.`, `The class tutor must be an active tutor of the school.`, `Class "{name}" has learners; its program and grade band can't change.`, `Class "{name}" still has learners or sessions; it can't be deleted.` (the learner/session checks arrive in Tasks 3/4; until then delete checks only the class exists).
- Produces (console): `aral-classes <schoolId> <schoolYear>`, `aral-class-show <classId>` (both builds); `aral-class-add <schoolId> <schoolYear> <program> <band> <name...> [tutor=<id>] [room=..] [schedule=..]`, `aral-class-edit <classId> <name|tutor|room|schedule|notes|program|band> <value>` (`-` clears), `aral-class-delete <classId>` (admin). Line format: `#{id} | {name} | {program.label} | Grades {band} | tutor {tutorId ?? '-'} | {active}/15 active`.

- [ ] **Step 1: Write `aral_placement_rules_test.dart`** — `AralClassProgram.of(ks2, basic) == ks2Basic`; `of(ks1, null) == ks1`; `AralGradeBand.ofGrade(6) == g4to6`, `ofGrade(11) == null`; `aralPlacementProblem` returns `full` at 15 others, null at 14; `programMismatch` for ks2Plus into ks2Basic; `gradeOutsideBand` for grade 7 into `g4to6`; `otherSchoolOrYear` for school 2 into a school-1 class; messages equal the exact texts above for "DELA CRUZ, JUAN" / class "7-Rose".
- [ ] **Step 2: Run** — `flutter test test/core/services/aral_placement_rules_test.dart`. Expected: FAIL (undefined).
- [ ] **Step 3: Implement the model and rules.**
- [ ] **Step 4: Write `aral_class_repository_sqlite_test.dart`** — insert gets a negative id; unique name ignoring case/trim is refused (`DatabaseException`); `getByTutor` returns only that tutor's classes; the local trigger refuses an unknown program/band.
- [ ] **Step 5: Implement the table (`createAralLocalSchema`, columns as spec §1 plus `origin TEXT NOT NULL DEFAULT 'local'`, `row_version INTEGER`, unique index on `(school_id, school_year, lower(trim(class_name)))`) and both repositories; run both tests — PASS.**
- [ ] **Step 6: Implement `AralClassViewModel` (admin/coordinator writes; tutor reads own), wiring (built in `wire_tutor.dart`, registered as `AralClassViewModel`), commands, command lists, session-guard entries; `dart analyze`, `flutter test`, import walk.** Expected: 0 errors, all pass, `OK: no admin file reachable`.
- [ ] **Step 7: Hand over** — commit message `feat(aral): ARAL class model, rules and class commands`.

### Task 3: Roster on classes (C2 roster part + C5) — SQLite v36

**Files:**
- Modify: `lib/core/models/aral_enrollment.dart` (drop `tutorId`; add `int? classId`, `String? referredBy`, `String? referralReason`; `AralBasisSource.referral`), `lib/core/data/local/aral_local_schema.dart` (`_enrollmentsTableSql`: `class_id INTEGER REFERENCES aral_classes(id)`, referral columns + check, no `tutor_id`; placement trigger; `rebuildAralEnrollmentsForV36`), `lib/core/data/local/local_database.dart` (v36), `lib/core/data/local/aral_enrollment_repository_sqlite.dart` + `remote/aral_enrollment_repository_supabase.dart` (`getByClass`; `getByTutor` = learners whose class's `tutor_id` matches), `lib/core/repositories/aral_enrollment_repository.dart`, `lib/core/data/pull_tables.dart` (`aral_classes` in `pullOrder` before `aral_enrollments`, in `pullClearOrder` after it, in `syncedTables`), `lib/core/data/local/sync_local_schema.dart` (`_originTables` + class ref lock: new rows may not point at a pending new class), `lib/core/data/local/sync_local_repository_sqlite.dart` (local-work line `ARAL class(es)`), `lib/core/services/sync_review_lines.dart` (`aral_classes` label `ARAL class "{name}" ({band}, {program}, tutor {name|-})`; enrollment label adds ` placed in class "{name}"` when `class_id` is set), `lib/viewmodels/aral_class_viewmodel.dart` (`place`, `unplace`, `classRoster`, delete/program checks), `lib/viewmodels/aral_viewmodel.dart`, `lib/viewmodels/aral_roster_import_viewmodel.dart`, `lib/viewmodels/reminder_viewmodel.dart`, `lib/viewmodels/dashboard_viewmodel.dart`, console `aral_commands.dart`, `aral_admin_commands.dart`, `aral_export_commands.dart`, `aral_class_admin_commands.dart`, `aral_command_helpers.dart` (`aralLine`: `class "{name}"|unplaced` replaces `tutor …`)
- Test: `test/core/data/aral_enrollments_v36_test.dart`, `test/viewmodels/aral_roster_classes_test.dart` (signed-in VM tests through a seeded local DB; see Step 5), `test/viewmodels/session_guard_test.dart`

**Interfaces:**
- Consumes: Task 2 model, rules, `AralClassRepository`, `AralClassViewModel`.
- Produces:
  - `AralClassViewModel.place(int enrollmentId, int classId) -> Future<AralEnrollment>`, `unplace(int enrollmentId) -> Future<AralEnrollment>`, `classRoster(int classId) -> Future<List<AralEnrollment>>`.
  - `AralViewModel.enroll({..., int? classId})` (replaces `tutorId`), `enrollProposed({required int sectionId, required String schoolYear, int? classId})` (fills to 15 weakest first; the rest unplaced, named in `lastWarning`), `refer({required int sectionId, required String schoolYear, required int studentId, required AralKeyStage keyStage, AralTrack? track, required String referredBy, required String reason, int? classId, String? notes, DateTime? enteredOn}) -> Future<AralEnrollment>`, `moveToSection(int enrollmentId) -> Future<AralEnrollment>`; `assignTutor` removed; `reactivate` unplaces when the class is full (`lastWarning`: `Class "{name}" is full, so this learner is back without a class. Place them in a class (aral-class-place).`).
  - `AralUpdateKind` gains `programMismatch`, `unplaced`, `otherSection`, `leftSchool` (no write; `before == after`). Texts: `program now {label}: move to a {label} class (class "{name}" is {class label})`; `waiting for a class`; `now in section {id} ({grade} {name}): aral-move {enrollmentId}`; `left the school: aral-exit {enrollmentId} transferred_out`.
  - Referral rule: a `referral` learner is exited only grade-level ready (`_latestCrla`/`_apply` skip `classroom_support` for them).
  - `moveToSection`: the learner's active `enrollments` row is in another section of the same school and year → update `section_id`; keep the class if the new grade is in its band, else clear `class_id` and set `lastWarning` `Grade {g} is outside class "{name}" (Grades {band}); the learner now waits for a class.`; no active row in this school → refuse `{learner} has left the school: exit them as transferred out (aral-exit {id} transferred_out).`; same section → refuse `{learner} is already in section {id}.`
  - Console: `aral-class-place <enrollmentId> <classId>`, `aral-class-unplace <enrollmentId>`, `aral-refer <sectionId> <schoolYear> <studentId> <program> by="<who>" reason="<why>" [class=<id>]`, `aral-move <enrollmentId>` (admin); `aral-enroll`/`aral-enroll-proposed` take `class=<id>` instead of `tutor=`; `aral-tutor` removed; `aral-tutors` shows `{n} class(es), {m} active ARAL learner(s)`.
  - Roster import: column `Class` (class name in that school/year) replaces `Tutor email`; unknown class → row error; full or mismatched → row imported unplaced, flagged `class "{name}" is full|… : imported without a class`.
  - Device refusal mapping (`AralViewModel._dbRefusals`, `AralClassViewModel`): the Task 1 cloud texts and the SQLite trigger texts (`An ARAL class has at most 15 active learners`, `The learner's program does not match the ARAL class`, `The learner's grade is outside the ARAL class's grade band`, `The ARAL class belongs to another school or school year`).

- [ ] **Step 1: Write `aral_enrollments_v36_test.dart`** (model: `aral_enrollments_v35_test.dart`) — a v35-shaped table holding a pulled row (`row_version` 3, `tutor_id` set) and a new row (negative id) listed in `sync_pending`; after `rebuildAralEnrollmentsForV36` + the creators: `tutor_id` gone, `class_id` null on both, `row_version` kept, the pending lock still refuses an update of the pending row, every trigger/view/index back; placement trigger refuses a 16th active learner, a program mismatch and a band mismatch; referral check refuses a referral without `referred_by`.
- [ ] **Step 2: Run** — FAIL (no function).
- [ ] **Step 3: Implement v36** (schema, rebuild, `version: 36` with a comment, `onUpgrade` call before every creator, pull/sync lists).
- [ ] **Step 4: Run the v36 test** — PASS (raise its timeout to 3 min like v35).
- [ ] **Step 5: Write `aral_roster_classes_test.dart`** — sign in offline as the device owner (`AuthViewModel.signInOffline` with a credential stored by the test, as `sync_local` tests do; if no such helper exists, stop and ask the owner before adding one) and assert: `place` refuses the 16th with `Class "7-Rose" already has 15 active ARAL learners.`; `enrollProposed(classId:)` with 17 proposed puts 15 in the class and names 2 in `lastWarning`; `refer` without reason throws `A referral needs who referred the learner and why.`; a referred KS1 learner with a Developing latest CRLA stays active after `applyResults` (switch off); `moveToSection` across a band clears the class and warns; `applyResults` lists `waiting for a class` for an unplaced learner.
- [ ] **Step 6: Run** — FAIL; **implement** the ViewModel, import/export and console changes; **run** — PASS.
- [ ] **Step 7: Full checks** — `dart analyze`, `flutter test`, import walk; upgrade a copy of `D:/0_CAPSTONE/verify/data/basa_local.db` with the scratchpad probe (`v35_upgrade_probe.dart`, adapted): rows kept, `takes class_id`.
- [ ] **Step 8: Hand over** — commit message `feat(aral): roster on ARAL classes (SQLite v36)`.

### Task 4: Sessions on classes (C2 sessions part + C6) — SQLite v37

**Files:**
- Modify: `lib/core/models/aral_session.dart` (`int? classId`), `aral_local_schema.dart` (sessions table `class_id INTEGER REFERENCES aral_classes(id)`; numbering and one-per-date per class when `class_id` is set; drop `aral_tutor_settings`; `rebuildAralSessionsForV37`), `local_database.dart` (v37), `aral_session_repository_sqlite.dart` + supabase (`getByClass`), `repositories/aral_session_repository.dart`, `pull_tables.dart` / `sync_local_schema.dart` / `sync_local_repository_sqlite.dart` / `sync_upload_local_sqlite.dart` / `sync_upload_rules.dart` / `sync_review_lines.dart` / `models/sync_upload.dart` (remove `aral_tutor_settings` everywhere), `lib/viewmodels/aral_session_viewmodel.dart`, `lib/viewmodels/aral_class_viewmodel.dart` (delete refuses classes with sessions), `lib/viewmodels/reminder_viewmodel.dart`, `lib/viewmodels/dashboard_viewmodel.dart`, `lib/viewmodels/sync_viewmodel.dart`, console `aral_session_commands.dart`, `aral_session_admin_commands.dart`, `wire_tutor.dart`
- Delete: `lib/core/models/aral_tutor_setting.dart`, `lib/core/repositories/aral_tutor_setting_repository.dart`, `lib/core/data/local/aral_tutor_setting_repository_sqlite.dart`, `lib/core/data/remote/aral_tutor_setting_repository_supabase.dart`
- Test: `test/core/data/aral_sessions_v37_test.dart`, `test/viewmodels/aral_class_sessions_test.dart`, `test/viewmodels/session_guard_test.dart`

**Interfaces:**
- Consumes: Tasks 2-3.
- Produces:
  - `AralSessionViewModel.logSession({required int classId, DateTime? heldOn, required int minutes, required AralSetup setup, String? lesson, String? remarks, String? tutorId})` (`schoolYear` comes from the class; `tutorId` = who held it: a tutor logs only their own classes with themselves; an admin/coordinator may name any active tutor of the school as substitute, default the class tutor); `classSessions(int classId) -> Future<List<AralSession>>`; `classSummary(int classId) -> Future<AralClassSummary>` (`AralClassSummary { AralClass aralClass; int sessions; int totalMinutes; int? lastSessionNo; int? nextCheckInAfter; int activeLearners; AralAttendanceSummary attendance; }`); `tutorSummary` keeps its signature, sums the tutor's classes, and drops `multipleSessionsPerDay`; `setMultipleSessionsPerDay` / `allowsMultipleSessionsPerDay` removed.
  - Refusals: `Forbidden: you can only log sessions for your own classes.`, `Class "{name}" already has session {no} (#{id}) on {date}.` (replaces the per-tutor one-per-day text), `Class "{name}" has no tutor yet; set one or name the tutor who held the session.`
  - Default attendance list = the class's learners active on the date; marking a learner of another class stays allowed for admins/coordinators only.
  - `learnerAttendance(enrollmentId)` includes marks from earlier classes (rows the device holds).
  - Reminders: tutor reminders per class (`Class "{name}": no session since {date}`, `Class "{name}": check-in due (session {n} done)`); coordinator reminders add `{n} ARAL learner(s) waiting for a class`, `{n} learner(s) in a class of another program`, `Class "{name}" has no tutor`.
  - Console: `aral-log <classId> <minutes> <setup> [YYYY-MM-DD] [lesson=..] [tutor=<id>]`, `aral-class-sessions <classId>`, `aral-class-summary <classId>` (both builds); `aral-sheet` unchanged in shape; `aral-tutor-multi` removed.

- [ ] **Step 1: Write `aral_sessions_v37_test.dart`** — v36-shaped sessions (pulled with `row_version`, new negative-id listed in `sync_pending`) + an `aral_tutor_settings` row: the pending lock still refuses an update of the pending session after the rebuild; after rebuild + creators the settings table is gone, sessions keep rows/`row_version`/`session_no`, `class_id` null; new sessions in class A number 1, 2 independently of class B; a second session in class A on the same date is refused with `An ARAL class already has a session on that date`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement v37 + list removals.** **Step 4: Run** — PASS.
- [ ] **Step 5: Write `aral_class_sessions_test.dart`** (signed in as in Task 3) — tutor T1 logs for their class (ok) and T2's class (refused text above); the default sheet lists only the class's active learners; session 16 in class A sets the check-in `lastWarning` while class B is at session 3; `classSummary` attendance rate excludes excused (existing `AralAttendanceSummary.rate`); after moving a learner to T2's class, `learnerAttendance` still lists the class-A mark.
- [ ] **Step 6: Run** — FAIL; **implement** VM, reminders, dashboard, console, wiring; **run** — PASS.
- [ ] **Step 7: Full checks** — analyze, `flutter test`, import walk; upgrade the verify DB copy again (v35 → v37).
- [ ] **Step 8: Hand over** — commit message `feat(aral): sessions per ARAL class (SQLite v37)`.

### Task 5: Docs and lists (C7)

**Files:**
- Modify: `lib/core/release.dart`, `README.md` (2b), `CLAUDE.md` (Module workflow ARAL line, Data model ARAL tables, command counts), `lib/core/CLAUDE.md` (SQLite v36/v37 notes, ARAL classes section: cap/program/band checked in three places — rules, local triggers, cloud `aral_check_class_placement`), spec status line + "Changes during implementation", memory `aral-analysis.md`.

- [ ] **Step 1: Update the files; check `release.dart` has `20261023040000`.**
- [ ] **Step 2: `flutter test test/core` (version-check tests read `release.dart`)** — PASS.
- [ ] **Step 3: Hand over** — commit message `docs(aral): ARAL classes`.

### Task 6: Go live (C8)

**Files:**
- Modify: `tool/command_pass/scenarios/10_b0.pass` (create class "ZZ 7-Rose" `ks3_basic`/`7-10` with tutor1; `aral-enroll … class=`), `25_t5.pass`, `26_t6.pass` (sessions by class), `34_a4.pass` (part 2: classes, placements, cap, program/band refusals, referral, `aral-update` notices, `aral-move` across sections and bands, reactivate into a full class, cross-section assessing by the class tutor, history after a move, signed-out probes for every new command).

- [ ] **Step 1: Owner applies `20261023040000_aral_classes.sql` on the dev cloud** (after every upload is decided; upload 78 is the known orphan).
- [ ] **Step 2: New run** — `dart run tool/command_pass/run.dart` (creates r6 with the updated B0), then `--run r6 t1 t2 t3 t4 t5 t6 a1 a2 a3 a4`; pin outputs with hand-worked figures (class counts, per-class session numbers, attendance rates).
- [ ] **Step 2b: Upload refusals at apply (Review Focus 1)** — in `34_a4.pass`, two coordinator devices (`a4-pc`, `a4-pc2`, both `as coord`, both pulled): `a4-pc` places learner X in a class holding 14 (local), `a4-pc2` places learner Y in the same class and runs `sync-upload yes` (applied); `a4-pc` runs `sync-upload yes` → refused with output containing `an ARAL class has at most 15 active learners` (no raw `PostgrestException`); same pattern for two offline classes named "ZZ Dup {stamp}" → the second upload is refused with a message naming the duplicate class. Each device then withdraws or fixes and uploads so no upload stays pending.
- [ ] **Step 3: Findings to the owner; agreed fixes; rerun twice.**
- [ ] **Step 4: Hand over** — commit message `test(pass): ARAL classes live (A4 part 2, B0/T5/T6 on classes)`.
