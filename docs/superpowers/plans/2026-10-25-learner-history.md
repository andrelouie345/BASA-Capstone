# Learner History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An admin-build `LearnerHistoryViewModel` that returns one learner's progress by school year (enrollment, CRLA, Phil-IRI, ARAL summary, SRP class) from the device copy, plus console commands `learner-history` / `learner-history-lrn`.

**Architecture:** A small read-only `LearnerHistoryRepository` (interface + SQLite only) gives the learner's rows across all years; the ViewModel assembles the years and asks the existing ViewModels/repositories for each piece (`PhilIriViewModel.learnerResults`, `AralCheckinViewModel.learnerCheckins`, `AralAttendanceSummary.of`, CRLA results). No tables, no migration, no scoring copied.

**Tech Stack:** Dart (no Flutter in core/viewmodels), sqflite_common_ffi, flutter_test for pure-Dart tests, the console command pass.

**Spec:** `docs/superpowers/specs/2026-10-25-learner-history-design.md`

## Plan decisions that refine the spec (owner to confirm at plan review)

- **P1 — reads in their own repository.** The spec put the two new reads on `StudentRepository` and `AralEnrollmentRepository`. Each of those interfaces has a Supabase implementation and test fakes (`test/viewmodels/aral_material_warning_test.dart`, `aral_setting_layers_test.dart`, `report_calendar_screen_calls_test.dart`) that would all need a method they never use. Instead: one new `LearnerHistoryRepository` (interface + SQLite only), following the module workflow (interface → SQLite implementation). Task 3 updates the spec's *Reads* bullet.
- **P2 — no tutor-import list change.** A file named `*_admin_commands.dart` is already admin by rule in `tool/check_tutor_imports.dart` (`isAdminFile`), so the spec's "added to the admin file list" is not needed. Task 3 updates the spec.
- **P3 — open question (not built unless the owner says so):** `students` already holds SF1 fields (birth date, sex, address). The history header shows name and LRN only, as the spec says. Showing birth date/sex/address would cover part of planned feature 2 without a migration. Owner decides; default = name + LRN only.

## Global Constraints

- Admin build only: nothing in this plan may be reachable from `lib/main_tutor.dart` / `lib/console/main_tutor.dart` (`dart run tool/check_tutor_imports.dart` stays OK).
- `lib/viewmodels/` and `lib/core/` never import Flutter; command files import only ViewModels/models (`dart run tool/check_vm_boundary.dart` stays OK).
- No new tables, no migration, no Supabase repository.
- Reads the device copy only (SQLite).
- Messages (exact, wording for screen and console):
  - not signed in: the existing `notSignedInMessage` (`lib/core/services/auth_messages.dart`)
  - tutor: `Forbidden: only an admin or coordinator can view learner history.`
  - other school: `Forbidden: that learner is not in your school.`
  - unknown id: `Learner not found on this device. Download the latest data first (pull-cloud).`
  - unknown LRN: `No learner with LRN <lrn> on this device. Download the latest data first (pull-cloud).`
  - scope note (school-bound viewer only): `Only your school's records are shown.`
- Years are ordered latest first (`schoolYear` strings `YYYY-YYYY` sort descending).
- Per-module `ScopedLogger(logger, 'LearnerHistoryViewModel')`.
- Steps that run tests, the console or the command pass carry the line **DO NOT PLAY RESOURCE INTENSIVE GAMES** (owner rule).
- After every task: `dart analyze` (no errors), `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart`; stop, say what to verify, give the commit message (the owner commits; no git commands).

## Review Focus

1. A learner with `students.school_id` null (legacy rows) viewed by a school-bound coordinator: refused with the other-school message, not a crash. Test in Task 2.
2. A Phil-IRI year whose only row is a GST (no reading session): the year's `philIri` has one entry (the GST's section) and `learnerResults` does not throw. Test in Task 2.
3. A learner with an ARAL entry still waiting for a class (`classId` null): `className`/`tutorName` null, attendance all zeros, check-ins `notTaken`. Test in Task 2.
4. A CRLA attempt with no reading profile (no story match): the language still appears for that round with a null profile, not dropped. Test in Task 2.
5. A learner moved between sections within a year (two Phil-IRI sections): one `PhilIriLearnerResults` per section, not one merged. Test in Task 2.

---

### Task 1: LearnerHistoryRepository (interface + SQLite)

**Files:**
- Create: `lib/core/repositories/learner_history_repository.dart`
- Create: `lib/core/data/local/learner_history_repository_sqlite.dart`
- Test: `test/core/data/learner_history_repository_test.dart`

**Interfaces:**
- Consumes: models `Student`, `AralEnrollment`, `SrpClass` (existing, `fromMap` constructors).
- Produces:
  ```dart
  class LearnerSectionRow {
    final String schoolYear;
    final String status;       // enrollments.status
    final int sectionId;
    final String sectionName;
    final String gradeLevel;   // bare numeric string
    final int schoolId;
    final String schoolName;
  }
  abstract class LearnerHistoryRepository {
    Future<Student?> student(int id);
    Future<Student?> studentByLrn(String lrn);
    /// Every enrollments row of the learner joined to sections and schools; school_year DESC.
    Future<List<LearnerSectionRow>> sectionEnrollments(int studentId);
    /// Every aral_enrollments row of the learner, all years; school_year DESC, entered_on ASC.
    Future<List<AralEnrollment>> aralEntries(int studentId);
    /// The SRP classes the learner is a member of (srp_class_members → srp_classes); school_year DESC.
    Future<List<SrpClass>> srpClasses(int studentId);
  }
  class LearnerHistoryRepositorySqlite implements LearnerHistoryRepository { LearnerHistoryRepositorySqlite(Database db); }
  ```

- [ ] **Step 1: Write the failing tests** (temp `AppContext.open` like `test/viewmodels/aral_class_sessions_test.dart`; insert rows with `ctx.localDb.insert`, school 9801, student 9801 with two years `2025-2026` (section Grade 3) and `2026-2027` (section Grade 4), one ARAL entry in 2026-2027, one SRP class + member in 2025-2026, and a second student 9802 with rows that must not appear):
  - `sectionEnrollments returns both years latest first with section and school names` — `[r.schoolYear for r] == ['2026-2027', '2025-2026']`, first row `gradeLevel == '4'`, `schoolName == 'ZZ History'`.
  - `aralEntries returns only this learner's entries` — length 1, `studentId == 9801`.
  - `srpClasses returns the learner's classes` — length 1, `schoolYear == '2025-2026'`.
  - `student and studentByLrn find the learner; unknown gives null` — `student(9801)!.lrn`, `studentByLrn('999999980100')!.id == 9801`, `student(1) == null`.

- [ ] **Step 2: Run to verify they fail** — **DO NOT PLAY RESOURCE INTENSIVE GAMES** — `flutter test test/core/data/learner_history_repository_test.dart` → FAIL (file/class not defined).

- [ ] **Step 3: Implement** the interface and `LearnerHistoryRepositorySqlite` (plain `db.query`/`rawQuery` joins; `Student.fromMap`, `AralEnrollment.fromMap`, `SrpClass.fromMap`).

- [ ] **Step 4: Run to verify they pass** — same command → PASS; then `dart analyze`, both tool checks OK.

- [ ] **Step 5: Stop for the owner** — what to verify (the test file, the SQL), commit message:
  ```
  feat(learner-history,sqlite): add read-only learner history repository

  - LearnerHistoryRepository + SQLite implementation: a learner's section
    enrollments (with section and school names), ARAL entries and SRP classes
    across all years, student by id or LRN
  - own repository instead of new methods on StudentRepository /
    AralEnrollmentRepository: no Supabase version or test fakes needed (local read only)
  ```

---

### Task 2: LearnerHistoryViewModel + admin wiring

**Files:**
- Create: `lib/viewmodels/learner_history_viewmodel.dart`
- Modify: `lib/core/wiring/wire_admin.dart` (build + register in `vms`, field on `AdminVms`, `adminViewModels`)
- Modify: `lib/viewmodels/admin_viewmodels.dart` (field `learnerHistory`)
- Test: `test/viewmodels/learner_history_test.dart`

**Interfaces:**
- Consumes: Task 1's `LearnerHistoryRepository`; existing `PhilIriViewModel.learnerResults({studentId, sectionId, schoolYear})`, `AralCheckinViewModel.learnerCheckins(int enrollmentId)` (`AralLearnerCheckins.results`, each `AralCheckinResult` has `tool.checkpoint`, `checkin.attemptNo`, `passed`), `AralAttendanceSummary.of(...)` over `AralSessionRepository.getAttendanceForEnrollment(id)`, `CrlaResultRepository.getByStudent(studentId)` (`CrlaResult.schoolYear/round/language/attemptNo/readingProfile`), `PhilIriAssessmentRepository.getByStudent(id)` and `PhilIriGstRepository.getByStudent(id)` (both carry `schoolYear`, `sectionId`), `AralClassRepository.findById`, `UserRepository.getById` (local; `fullName`).
- Produces (all in `learner_history_viewmodel.dart`):
  ```dart
  const learnerHistoryScopeNote = "Only your school's records are shown.";
  enum LearnerHistoryCheckin { passed, failed, notTaken }
  class LearnerHistoryEnrollment { final String sectionName; final String gradeLevel; final String schoolName; final String status; }
  class LearnerHistorySrp { final String className; final String? tutorName; final String? room; }
  class LearnerHistoryAral {
    final AralEnrollment enrollment; final String? className; final String? tutorName;
    final AralAttendanceSummary attendance; final LearnerHistoryCheckin checkin16; final LearnerHistoryCheckin checkin32;
  }
  class LearnerHistoryYear {
    final String schoolYear;
    final List<LearnerHistoryEnrollment> enrollments;
    final Map<CrlaRound, Map<String, String?>> crla;   // round → language → profile (null = no profile)
    final List<PhilIriLearnerResults> philIri;          // one per section with Phil-IRI rows that year
    final List<LearnerHistoryAral> aral;
    final LearnerHistorySrp? srp;
    bool get isEmpty;                                   // crla, philIri, aral empty and srp null
  }
  class LearnerHistory { final Student student; final List<LearnerHistoryYear> years; final String? scopeNote; }
  class LearnerHistoryViewModel {
    LearnerHistoryViewModel({required AuthViewModel auth, required LearnerHistoryRepository history,
      required CrlaResultRepository crlaResults, required PhilIriAssessmentRepository philIriSessions,
      required PhilIriGstRepository gst, required PhilIriViewModel philIri, required AralCheckinViewModel checkins,
      required AralSessionRepository sessions, required AralClassRepository classes, required UserRepository users,
      Logger? logger});
    Future<LearnerHistory> history(int studentId);
    Future<LearnerHistory> historyByLrn(String lrn);
  }
  ```
  `AdminViewModels.learnerHistory` and `AdminVms.learnerHistoryVm` (type `LearnerHistoryViewModel`).

Rules the code must follow (from the spec):
- Access order: not signed in → `notSignedInMessage`; tutor → tutor message; learner missing → unknown-id/LRN message; `me.schoolId != null && student.schoolId != me.schoolId` → other-school message (a null `student.schoolId` counts as another school).
- `scopeNote` = `learnerHistoryScopeNote` when `me.schoolId != null`, else null.
- Years = union of years from section enrollments, CRLA results, Phil-IRI sessions, GST results, ARAL entries, SRP classes; descending.
- CRLA: per (year, round, language) the attempt with the highest `attemptNo` (tie: latest `assessedAt`); value = its `readingProfile` (may be null).
- Phil-IRI: per year, the distinct `sectionId`s of that year's Phil-IRI sessions and GST results, each read with `learnerResults(studentId:, sectionId:, schoolYear:)`, ordered by section id.
- Check-ins: per checkpoint (16, 32) the result with the highest `checkin.attemptNo` over all tools of that checkpoint; `passed` → `passed`, else `failed`; none → `notTaken`.
- Names: class from `AralClassRepository.findById(enrollment.classId)`, tutor = that class's `tutorId` → `UserRepository.getById(..).fullName`; SRP tutor likewise from `SrpClass.tutorId`.

- [ ] **Step 1: Write the failing tests** — `test/viewmodels/learner_history_test.dart`. Setup like `aral_class_sessions_test.dart` (wireShared → wireTutor → `await wireAdmin(ctx, s, t)`), school 9901 (region 13) and school 9902, users coordinator (school 9901), tutor, superadmin (`schoolId: null`) seeded with `seedOfflineOwner`. Data: student 9901 — 2025-2026 Grade 3 section with CRLA attempts (Filipino BOSY with a profile: insert a `crla_stories` row for region 13 so the local `crla_results` view gives one; English BOSY without a matching story → null profile); 2026-2027 Grade 4 section with GST (via `philIriVm.recordGst`), an ARAL entry placed in a class with a tutor, two marked sessions (one present, one absent) and an SRP class membership; a second Grade 4 section in 2026-2027 with a GST (moved learner, Review Focus 5); student 9902 at school 9902; student 9903 at 9901 with only an ARAL entry waiting for a class in 2026-2027 and no `enrollments` row; student 9904 with `school_id` null. Tests and assertions:
  - `years come latest first with every part filled` — `years.map((y) => y.schoolYear) == ['2026-2027', '2025-2026']`; 2025-2026 `crla[CrlaRound.bosy]` has keys Filipino and English, English value `null` (Review Focus 4); 2026-2027 `enrollments.single.gradeLevel == '4'`, `aral.single.className` and `tutorName` set, `attendance.present == 1`, `attendance.absent == 1`, `checkin16 == LearnerHistoryCheckin.notTaken`, `srp!.className` set.
  - `a GST-only year gives one Phil-IRI result per section` — 2026-2027 `philIri.length == 2`, each `gst != null` (Review Focus 2 and 5).
  - `historyByLrn finds the same learner` — `historyByLrn(lrn).student.id == 9901`.
  - `a coordinator gets the scope note, a superadmin none` — `scopeNote == learnerHistoryScopeNote` / `isNull`.
  - `a tutor is refused` — throws `ViewModelException` with the tutor message.
  - `another school's learner is refused` — 9902 and 9904 (null school, Review Focus 1) → other-school message.
  - `unknown id and LRN give the pull-cloud messages` — exact texts from Global Constraints.
  - `a year with only a waiting ARAL entry is listed` — 9903: one year, `enrollments` empty, `aral.single.className == null`, `tutorName == null`, `attendance.marked == 0`, both check-ins `notTaken` (Review Focus 3).
  - `an enrollment-only year is empty` — a 2024-2025 enrollment for 9901 with nothing else → that year `isEmpty`.

- [ ] **Step 2: Run to verify they fail** — **DO NOT PLAY RESOURCE INTENSIVE GAMES** — `flutter test test/viewmodels/learner_history_test.dart` → FAIL (not defined).

- [ ] **Step 3: Implement** the ViewModel (rules above) and wire it in `wire_admin.dart` with `LearnerHistoryRepositorySqlite(db)`, `CrlaResultRepositorySqlite(db)`, `PhilIriAssessmentRepositorySqlite(db)`, `PhilIriGstRepositorySqlite(db)`, `t.philIriVm`, `t.aralCheckinVm`, `AralSessionRepositorySqlite(db)`, `AralClassRepositorySqlite(db)`, `UserRepositorySqlite(db)`; `vms.register('LearnerHistoryViewModel', ...)`; add to `AdminVms`, `adminViewModels`, `AdminViewModels`.

- [ ] **Step 4: Run to verify they pass** — **DO NOT PLAY RESOURCE INTENSIVE GAMES** — same command → PASS; then the full `flutter test` (all green), `dart analyze`, both tool checks OK.

- [ ] **Step 5: Stop for the owner** — what to verify, commit message:
  ```
  feat(learner-history): add LearnerHistoryViewModel (admin build)

  - one learner's progress by school year from the device copy: section
    enrollment, CRLA profile per round and language, Phil-IRI results per
    section (learnerResults), ARAL entry summary (class, tutor, attendance,
    16th/32nd check-in), SRP class
  - tutors refused; school-bound viewers limited to their school's learners and
    shown "Only your school's records are shown."
  - exposed as AdminViewModels.learnerHistory
  ```

---

### Task 3: Console commands, command pass, docs

**Files:**
- Create: `lib/core/console/commands/learner_history_admin_commands.dart`
- Modify: `lib/core/wiring/wire_admin.dart` (`registerLearnerHistoryCommands(r, a.learnerHistoryVm)` in `registerAdminCommands`)
- Modify: `test/core/wiring/admin_commands.txt` (add `learner-history`, `learner-history-lrn` in sorted order; 241 lines)
- Modify: `tool/command_pass/scenarios/35_a5.pass` (new section, see Step 3)
- Modify: `docs/handoff/screens/admin.md` (block "Learner history (pending backend)" → "Learner history", `Build: admin`, calls `LearnerHistoryViewModel.history(studentId)` / `historyByLrn(lrn)` → `LearnerHistory`, console both commands)
- Modify: `docs/handoff/checklist.md` row 17 (title "Learner history", build `admin`, anchor `#learner-history`)
- Modify: `CLAUDE.md` (module checklist: learner history done with spec path; admin console count 241)
- Modify: `docs/superpowers/specs/2026-10-25-learner-history-design.md` (P1 and P2 wording; *Status* line: built)

**Interfaces:**
- Consumes: Task 2's `LearnerHistoryViewModel.history/historyByLrn` and the types it produces.
- Produces: `void registerLearnerHistoryCommands(ConsoleRegistry registry, LearnerHistoryViewModel vm)`; commands
  - `learner-history <studentId>` — usage `Usage: learner-history <studentId>`
  - `learner-history-lrn <lrn>` — usage `Usage: learner-history-lrn <lrn>`

Output format (exact header lines; the rest one line per item, two-space indent):
```
<Last>, <First> (LRN <lrn>)
Only your school's records are shown.        ← only when scopeNote != null
== <schoolYear> ==
  Section: Grade <g> <section> (<school>), <status>
  CRLA <ROUND> <language>: <profile or "no profile">
  Phil-IRI (section <id>): GST <score>/<max>; <ROUND> <result label> ...; end <label or "none">
  ARAL <program>: class <name or "waiting for a class">, tutor <name or "none">, entered <date>[, exited <date> (<reason>)]; <attendance label>; check-in 16 <passed|failed|not taken>, 32 <...>
  SRP: <class> (tutor <name or "none">[, room <room>])
  No assessments recorded                    ← when isEmpty
```
Phil-IRI and ARAL labels come from the existing model/enum labels (reuse what `phil-iri-results` and `aral-show` print; no new wording rules in the command file).

- [ ] **Step 1: Write the failing check** — add both names to `test/core/wiring/admin_commands.txt`; run **DO NOT PLAY RESOURCE INTENSIVE GAMES** `flutter test test/core/wiring/command_sets_test.dart` → FAIL (admin set lacks the two commands).

- [ ] **Step 2: Implement** the command file and its registration → the same test PASSES; `dart analyze`, both tool checks OK (the file is admin by name; confirm `check_tutor_imports` still says OK).

- [ ] **Step 3: Command pass section in `35_a5.pass`** (coordinator device, after the pull, before the batch's undo steps), using learners whose history the header comment already describes:
  - `run learner-history {s_g2_3}` → `expect Only your school's records are shown.`, `expect == {year} ==`, `expect CRLA BOSY Filipino: High Emerging Reader`, `expect CRLA MOSY Filipino: Developing Reader` (copy the exact profile labels the console prints in that batch's existing CRLA lines).
  - `run learner-history {s_c4}` → `expect Phil-IRI` line with `GST 10/40`, `expect ARAL` line with the class name A4 placed her in.
  - `run learner-history-lrn 000000000000` → `expect No learner with LRN 000000000000 on this device. Download the latest data first (pull-cloud).`
  - `run learner-history abc` → `expect Usage: learner-history <studentId>`.

  Run **DO NOT PLAY RESOURCE INTENSIVE GAMES** one full run (`dart run tool/command_pass/run.dart`, no arguments; A5 depends on every earlier batch's data, and a subset run failed on skipped-batch data before, r15) → report clean, 0 failing steps, coverage 361/361. If an A5 line fails, fix it and rerun `--run r<N> a5` then `--run r<N> z`.

- [ ] **Step 4: Docs** — the handoff, checklist, CLAUDE.md and spec edits listed under **Files**.

- [ ] **Step 5: Verify kit** — `D:/0_CAPSTONE/verify/learner-history/` per the verify-kit recipe: a fresh copy of the verify data folder, a command file running `learner-history` / `learner-history-lrn` on the owner's verify DB learners (ids filled in), and the expected output beside it.

- [ ] **Step 6: Stop for the owner** — what to verify (kit, pass report path), commit message:
  ```
  feat(learner-history,console): learner-history commands, pass, docs

  - learner-history <studentId> and learner-history-lrn <lrn> (admin console,
    241 commands); thin over LearnerHistoryViewModel
  - command pass A5 checks a CRLA learner and a Phil-IRI/ARAL learner; full run clean
  - handoff screen doc and checklist row 17 now point at the built calls;
    CLAUDE.md module list and count; spec notes the own-repository read

  Known follow-ups not included here:
  - cross-school history and academic history (spec: Planned features)
  ```
