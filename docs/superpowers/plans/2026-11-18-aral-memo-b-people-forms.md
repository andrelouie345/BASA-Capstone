# ARAL memo, Plan B: advisers, tutor type, daily tutor limits, class names, ARAL Forms 1, 2, 4 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record section advisers, tutor type and each class's session type; enforce "an adviser does not tutor their own learners" and the daily tutor limits as school settings; suggest memo-style class names; export ARAL Forms 1, 2 and 4 (Reading).

**Architecture:** Builds on Plan A (`AralRuleSettings`, the `aral_setting` server helper, SQLite v46). New columns on `sections`, `users`, `aral_classes` (migration `20261118030000`, SQLite v47); three more setting keys; checks in the ViewModels and on the server; a new read-only `AralFormsViewModel` (admin build) that reuses the implementation report's per-learner results and writes `.xlsx` with `writeXlsx`.

**Tech Stack:** Dart, sqflite_common_ffi, Supabase Postgres, `lib/core/services/xlsx_writer.dart`, `excel_plus` (reading back in tests), flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-18-aral-division-memo-design.md` (sections 3 daily limits, 6, 7, 8, 9). Plan A: `docs/superpowers/plans/2026-11-18-aral-memo-a-settings.md` must be done first.

## Global Constraints

- New keys (spec §1): `internal_tutor_max_sessions_per_day` int 1-10, absent = none; `external_tutor_max_minutes_per_day` int 1-600, absent = none; `adviser_tutors_own_class` bool, default true (allowed). Defaults = today's behaviour.
- A tutor without a `tutor_type`: no daily check; blank type in Form 2.
- Daily limits count sessions held by that tutor (`aral_sessions.tutor_id`) on that date in that school; server side a deferrable end-state constraint trigger serialized per tutor and date (pattern of `aral_enrollments_class_cap`, `20261024050000`), so `sync_apply` can apply offline swaps.
- `sections.adviser_name` text optional; `sections.adviser_user_id` uuid optional, a user of the section's school (server trigger check). `users.tutor_type` `internal`/`external`/null. `aral_classes.session_type` `pull_out`/`before_after`/null.
- Adviser rule (`adviser_tutors_own_class` false): refuse placing a learner into a class whose tutor is the `adviser_user_id` of the learner's home section; refuse setting a class's tutor to the adviser of any active learner's home section. Checked in the ViewModel and on the server.
- Class names suggested as `ARAL-R-G<grade>-<nn>` (two digits, next free for that school and year, compared ignoring case); names stay free text.
- Forms are admin build only, `.xlsx`, BASA's own layout copying the form's header fields and columns (no DepEd template file exists). Fields BASA doesn't hold are blank and listed in each sheet's footer note. Mathematics columns blank.
- Form 4 definitions (owner-approved 2026-11-18): Identified at BoSY = ARAL learners of the year with `basisRound` BoSY; Served = placed in a class and marked present at least once by the date; Reached grade level = exited grade-level ready by the date; Improved, still below = still in ARAL, MoSY result better than BoSY (CRLA profile order; Phil-IRI adjusted level higher); No improvement = still in ARAL, MoSY not better or none; ARAL learners at MoSY = still in ARAL on the date; results follow the school's ARAL value source; Part II = classes, internal/external tutors, sessions and hours (sum of minutes / 60) by the date.
- Migration `20261118030000`: header `App update required on all devices: yes` (new refusals), the apply-only-when-finalized line, ledger row, `release.dart`, README 2b; RLS of `sections`, `users`, `aral_classes`, `aral_sessions` reviewed in the file (no policy should need widening: section and class writes are already admin/coordinator of the school; `users_update_scoped` already lets them update their school's users).
- Admin-only writes and the forms in `*_admin_commands.dart`; both tool checks pass. Owner rule: never run git; hand over commit messages. Close any open BASA console before console/kit runs.

## Review Focus

1. An adviser who is a BASA tutor of their own section through `tutor_section_assignments` (reads the section) and also tutors an ARAL class: with the rule on, placing their advisory learner in their class is refused, but their section access is unchanged. (Task 3 test.)
2. A tutor whose type changes from internal to external mid-month: past sessions are not re-checked; new sessions follow the new limit. (Task 3 test.)
3. An adviser user deactivated or moved to another school: the section keeps `adviser_name`; `adviser_user_id` pointing at a user of another school is refused on write; a deactivated adviser user still counts as the adviser for the rule (the person still advises the section) until the coordinator changes it. (Task 1 PG test, Task 3 test.)
4. Form 1/2 for a class with no tutor, no schedule, no room, or a learner without a MoSY result: blanks, never "null", never a crash. (Task 5 test.)
5. Form 4 as of a date before any MoSY session: "No improvement" must not count learners simply not yet assessed at MoSY as failures without saying so; footer note states that learners without a MoSY result are counted under No improvement. (Task 5 test.)

---

### Task 1: Server migration (columns, adviser rule, daily tutor limits)

**Files:**
- Create: `supabase/migrations/20261118030000_aral_memo_people.sql`
- Modify: `lib/core/release.dart`, `README.md` (2b)
- Test: PG 18 throwaway harness (stubs + baseline + every migration, the new one twice).

**Interfaces:**
- Produces (SQL): columns above with CHECKs; `aral_settings` CHECKs for the three keys; trigger `sections_adviser_same_school` (adviser_user_id's `users.school_id` = section's school); adviser rule inside `aral_check_class_placement` (reads `coalesce((aral_setting(school,'adviser_tutors_own_class'))::boolean, true)`) and a BEFORE UPDATE OF tutor_id trigger on `aral_classes`; constraint trigger `aral_sessions_tutor_day_limits` (built instead inside the existing constraint trigger `aral_sessions_one_per_day`, owner 2026-11-18, so `sync_apply` needs no change; advisory lock on tutor+date) refusing more than N sessions (internal) or more than N minutes (external) per tutor per date; messages name the number and the tutor's type.
- [x] **Step 1: Write the PG steps** — defaults: none of the new refusals fire; adviser rule off/on (place refused, tutor change refused, other section fine); adviser of another school refused; internal limit 2: 3rd session that day refused, next day fine; external 120 minutes: 60+60 fine, +1 minute refused; `sync_apply` moving a session from one date to another at the limit succeeds; type null → no limit; CHECKs refuse bad values.
- [x] **Step 2: Run** — new cases FAIL.
- [x] **Step 3: Write the migration** (idempotent).
- [x] **Step 4: Run** twice — PASS; stop and remove the cluster.
- [x] **Step 5: release.dart + README 2b** line ("ARAL memo, people: section advisers, tutor type and class session type; an adviser does not tutor their own learners and daily tutor limits, as school settings, off by default; app update required: **yes**, …"); `flutter test test/supabase/migration_grants_test.dart` — PASS.
- [x] **Step 6: Commit message:** `feat(aral,db): advisers, tutor type, class session type and their rules (20261118030000)`.

### Task 2: SQLite v47, models and repositories

**Files:**
- Modify: `lib/core/data/local/local_database.dart` (v47 `upgradeAralMemoForV47`: ALTER TABLE ADD COLUMN on `sections`, `users`, `aral_classes`, guarded by `PRAGMA table_info`; on create and every upgrade), the sections/users/classes create statements, `lib/core/models/section.dart` (`adviserName`, `adviserUserId`), `lib/core/models/user.dart` (`TutorType? tutorType`), `lib/core/models/aral_class.dart` (`AralSessionType? sessionType`), their `fromMap`/`toMap`/`copyWith`, the Supabase and SQLite repositories and the pull mirror that copy these tables
- Test: `test/core/data/aral_memo_v47_test.dart`

**Interfaces:**
- Produces: `enum TutorType { internal, external }` (`value` strings), `enum AralSessionType { pullOut('pull_out','Pull-out'), beforeAfter('before_after','Before/after class') }`; model fields nullable; `copyWith` with `() => value` closures like the existing ones.
- [x] **Step 1: Failing test:** a v46 database upgraded keeps rows and gains the three columns; a section/user/class round-trips the new fields through the SQLite repositories; a pulled row with the fields is mirrored.
- [x] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `flutter test test/core/data` — PASS.
- [x] **Step 5: Commit message:** `feat(sqlite): v47 section adviser, tutor type and class session type`.

### Task 3: Setting and checking them in the ViewModels (advisers, tutor type, daily limits, session type, class names)

**Files:**
- Modify: `lib/core/services/aral_rule_settings.dart` (three keys), `lib/viewmodels/section_viewmodel.dart` (`setAdviser`), the user management ViewModel that owns `user-set-active` (`setTutorType`), `lib/viewmodels/aral_class_viewmodel.dart` (`place`, `updateClass` tutor change, `suggestClassName`, session type on create/edit), `lib/viewmodels/aral_session_viewmodel.dart` (daily limits in log/edit)
- Modify commands: `section_admin_commands.dart` (`section-adviser <sectionId> <name|-> [userId]`), `user_commands.dart` or its admin file (`user-tutor-type <userId> <internal|external|->`), `aral_class_admin_commands.dart` (`aral-class-add` name optional → suggested; `session=pull_out|before_after|-` on add/edit)
- Test: `test/viewmodels/aral_memo_people_test.dart`

**Interfaces:**
- Consumes: Task 2 models; Plan A `AralRuleSettings`, `_rules(schoolId)` pattern.
- Produces: `Future<Section> setAdviser(int sectionId, {String? name, String? userId})`; `Future<User> setTutorType(String userId, TutorType? type)` (online, admin/coordinator of the user's school); `Future<String> suggestClassName({required int schoolId, required String schoolYear, required int grade})`; `AralRuleSettings` fields `int? internalTutorMaxSessionsPerDay`, `int? externalTutorMaxMinutesPerDay`, `bool adviserTutorsOwnClass`.
- [x] **Step 1: Failing tests:** adviser rule off → placement works; on → `place` of the adviser's own learner refused naming learner and section; setting the class tutor to that adviser refused; internal limit 2 → 3rd `logSession` that day refused, `editSession` moving one to a full day refused; external 120 → minutes over refused; no type → no limit; type changed later doesn't re-check old sessions; `suggestClassName` with existing `aral-r-g4-01` → `ARAL-R-G4-02`, empty → `ARAL-R-G4-01`; session type saved and shown; adviser with a user of another school refused.
- [x] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `flutter test test/viewmodels` and `dart analyze` — PASS.
- [x] **Step 5: Commit message:** `feat(aral): section advisers, tutor type, daily tutor limits, class session type and suggested class names`.

### Task 4: Per-learner BoSY/MoSY results shared with the implementation report

**Files:**
- Modify: `lib/viewmodels/aral_report_viewmodel.dart` (factor the per-learner part of `implementationReport` ~208-320 into a public method; the report keeps its numbers)
- Test: `test/viewmodels/aral_report_totals_test.dart` (must stay green, unchanged expectations) + a new case

**Interfaces:**
- Produces: `class AralLearnerRounds { int enrollmentId; int grade; String instrument /* 'CRLA' | 'Phil-IRI' */; String? bosyResult; String? mosyResult; int? bosyRank; int? mosyRank; bool notAssessed; }` (`*Result` = CRLA profile, or Phil-IRI 'Frustration' (3+ levels down, non-readers, not assessed) / 'Instructional' (1-2 down) / grade-level ready label; `*Rank` = an orderable number: CRLA profile order 0 Low Emerging … 4 At Grade Level; Phil-IRI adjusted level) and `Future<List<AralLearnerRounds>> learnerRounds({required int schoolId, required String schoolYear, String? asOf})`.
- [ ] **Step 1: Failing test:** two learners (one CRLA G2, one Phil-IRI G7) with BoSY and MoSY results → the expected strings and ranks; the existing totals test unchanged.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** by extraction (no new rules). **Step 4: Run** `flutter test test/viewmodels/aral_report_totals_test.dart` and the new case — PASS.
- [ ] **Step 5: Commit message:** `refactor(aral): per-learner BoSY/MoSY results shared by the reports`.

### Task 5: AralFormsViewModel (Forms 1, 2, 4 data)

**Files:**
- Create: `lib/viewmodels/aral_forms_viewmodel.dart`; wire in `lib/core/wiring/wire_admin.dart` and `lib/viewmodels/admin_viewmodels.dart`
- Test: `test/viewmodels/aral_forms_test.dart`

**Interfaces:**
- Consumes: `learnerRounds` (Task 4), class/roster/session/user/section repositories, `AralRuleSettings`.
- Produces: `class AralForm1 { header fields; List<AralForm1Row> rows; List<String> blanks; }`, `class AralForm2 { List<AralForm2Row> rows; int readingClasses, readingLearners, internalTutors, externalTutors; List<String> blanks; }`, `class AralForm4 { List<AralForm4Grade> grades /* 1..10 */; int classes, internalTutors, externalTutors, sessions; double hours; List<String> notes; }`; methods `Future<List<AralForm1>> form1({required int schoolId, required String schoolYear, int? classId})`, `Future<AralForm2> form2({...})`, `Future<AralForm4> form4({required int schoolId, required String schoolYear, required String asOf})`. Admin/coordinator of the school or superadmin; tutors refused.
- [ ] **Step 1: Failing tests** (fixture: school with two classes, one with tutor/schedule/room/session type, one empty; learners G2 CRLA and G7 Phil-IRI with BoSY/MoSY; sessions with minutes; one exited grade-level ready):
  - Form 1: rows sorted by last name; name 'Last, First M.'; adviser from the home section; MoSY tool/result; M/F/total; blank fields listed (`'district'`, `'workbook issued'`); class without tutor → tutor '' and type ''.
  - Form 2: one row per class; 'MoSY result of class' = shared result or 'mixed'; tutor's advisory class from `adviser_user_id`; footer counts.
  - Form 4: each Part I column per the definitions, including a learner with no MoSY result counted under No improvement and named in `notes`; Part II sessions and hours (e.g. 3 sessions of 60, 45, 45 → hours 2.5).
  - a tutor caller refused.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** the test, `dart analyze`, both tool checks — PASS.
- [ ] **Step 5: Commit message:** `feat(aral): ARAL Forms 1, 2 and 4 (Reading) from the device copy`.

### Task 6: Forms as .xlsx and their commands

**Files:**
- Create: `lib/core/services/aral_forms_xlsx.dart` (pure: `List<int> aralForm1Xlsx(List<AralForm1>)`, `aralForm2Xlsx(AralForm2)`, `aralForm4Xlsx(AralForm4)` using `writeXlsx`/`XlsxSheetSpec`; LRN as a text column)
- Create: `lib/core/console/commands/aral_forms_admin_commands.dart` (`aral-form1 <schoolId> <schoolYear> <out.xlsx> [classId]`, `aral-form2 <schoolId> <schoolYear> <out.xlsx>`, `aral-form4 <schoolId> <schoolYear> <out.xlsx> [asof=YYYY-MM-DD]`), registered in the admin command registration; listed as a wholly admin file in `tool/check_tutor_imports.dart`
- Test: `test/core/services/aral_forms_xlsx_test.dart`

- [ ] **Step 1: Failing test:** write each form for the Task 5 fixture, read back with `excel_plus`: Form 1 one sheet per class named by class code, header cells and the LRN as text (leading zeros kept); Form 2 counts row; Form 4 Grade 1-10 rows, TOTAL row = column sums, hours '2.5'; footer note text present.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** the test, `dart analyze`, `dart run tool/check_tutor_imports.dart` — PASS.
- [ ] **Step 5: Commit message:** `feat(aral): export ARAL Forms 1, 2 and 4 as .xlsx (admin)`.

### Task 7: Docs, command lists, command pass, verify kit

**Files:**
- Modify: `README.md` (7: new commands), `tool/installer/guide/admin/Functions/ARAL-Reading.txt` (advisers, tutor type, the two school rules, class names, the forms, and "Forms 3, 5 and 6: tutor details, printing and overload pay are kept in the separate tutor-management system, so BASA leaves them out; BASA's session records give each tutor's ARAL hours"), `docs/handoff/screens/` (section adviser field, user tutor type, class session type and suggested name, forms export), `CLAUDE.md` (module checklist; command counts), `lib/core/CLAUDE.md` (adviser rule checked in the ViewModel and on the server), `docs/guides/BASA_ARAL.html` + re-export `BASA_ARAL.pdf` (class size and session rules are school settings; the forms), `test/core/wiring/admin_commands.txt` (+ `section-adviser`, `user-tutor-type`, `aral-form1`, `aral-form2`, `aral-form4`), `tool/command_pass/scenarios/` (batch: set adviser, rule on → placement refused, tutor type + internal limit → 3rd session refused, export each form to the run folder)
- [ ] **Step 1:** update the command list; `flutter test test/core/wiring` — PASS.
- [ ] **Step 2:** owner applies `20261118030000` on the dev cloud (closes any open console); run the pass batch — PASS (**DO NOT PLAY RESOURCE INTENSIVE GAMES** while it runs).
- [ ] **Step 3:** `dart analyze`, `flutter test`, both tool checks — PASS.
- [ ] **Step 4:** write the docs; verify kit `D:/0_CAPSTONE/verify/aral-memo-b/` (adviser, tutor type, refusals, three form files with expected cells).
- [ ] **Step 5: Commit message:** `docs(aral): advisers, tutor type and ARAL Forms in the README, guides and project notes; why Forms 3, 5, 6 are outside BASA`.
