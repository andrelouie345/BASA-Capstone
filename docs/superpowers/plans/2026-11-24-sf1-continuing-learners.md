# SF1 Continuing Learners Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new school year's SF1 enrolls learners who continue at the same school (one grade up or the same grade) without conflicts, updating a corrected name and filling a blank birth date.

**Architecture:** A repository lookup gives the learner's latest enrollment before the file's school year; `Sf1Importer._existingLearnerRow` turns the eligible cases into a new `continuing` trial row; `import()` applies it (name update, birth-date fill, enroll) and counts it. Console summaries and the SF1 handoff doc show the new count.

**Tech Stack:** Dart, sqflite_common_ffi (tests), supabase_flutter client (remote repo), flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-24-sf1-continuing-learners-design.md`

## Global Constraints

- Continuing only when the learner has **no enrollment in the file's school year**; moving / returning / enrolled / insert outcomes unchanged.
- Eligible: latest earlier enrollment at **this school**, grade **equal** or **one lower** than the file's grade; any status. Everything else stays `conflict` with today's reasons, except two-or-more grades lower or a higher grade, whose reason names both grades: `last enrolled here in Grade <g> (<year>): Grade <file grade> is not the next grade`.
- Labels (exact): `moving up from Grade <g> (<year>)` | `repeating Grade <g>`; suffixes in this order: `, back after leaving (<transferred out|dropped out>, <year>)`, `, last here in <year>` (when `<year>` is not the school year just before the file's), `, name corrected: <Last, First Middle> -> <Last, First Middle>`.
- Name compare: last, first, middle after trimming; exact case. Birth date: fill only when BASA's is blank (as the `enrolled` rule).
- Console summary text: append `, continuing: <n>` **at the end** of the trial's `Would insert: ...` line and the import's `Inserted: ...` line (before the optional extra lines).
- No migration, no SQLite version change, no RLS change.
- After each task: `dart analyze` (no new errors), `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart`. Backend branch `excelsior`; owner commits.

## Review Focus

1. **Re-importing the same new-year file** -> rows are `enrolled` the second time, no second enrollment, no conflict (Task 3 test).
2. **A learner with enrollments in two earlier years** -> the latest one decides, not the first (Task 1 test).
3. **An archived learner whose latest earlier enrollment is at this school but this year's is at another school** -> stays today's conflict (this-year enrollment exists, so continuing never applies) (Task 2 test).
4. **The server refuses the name update** (RLS or the learner was anonymized meanwhile) -> a row warning, the enrollment still happens, the import goes on (Task 3 test with a repository that throws on `update`).
5. **Middle name blank in BASA and present on the SF1** -> counts as a correction (name updated, label shows it) (Task 2 test).

---

### Task 1: Latest earlier enrollment

**Files:**
- Modify: `lib/core/repositories/student_repository.dart` (interface + record type), `lib/core/data/local/student_repository_sqlite.dart`, `lib/core/data/remote/student_repository_supabase.dart`
- Test: `test/core/data/student_latest_enrollment_test.dart`

**Interfaces:**
- Produces: `typedef EnrollmentBefore = ({int enrollmentId, int sectionId, String sectionName, String gradeLevel, int schoolId, String schoolYear, String status, String? leftOn});` and `Future<EnrollmentBefore?> latestEnrollmentBefore(int studentId, String schoolYear);` on `StudentRepository`: the enrollment with the greatest `school_year` strictly below `schoolYear` (text compare), any school, any status; null when none. Supabase: same select shape as `enrollmentInYear` plus `school_year`, `.lt('school_year', schoolYear).order('school_year', ascending: false).limit(1)`; an unreadable section -> null (as `enrollmentInYear`).

- [ ] **Step 1: Write the failing tests** (SQLite file DB as in `sf1_importer_leavers_test.dart`): `none before` -> null; `latest of two earlier years wins` (2024-2025 Grade 2, 2025-2026 Grade 3; asking 2026-2027 -> Grade 3, `schoolYear` `2025-2026`); `the asked year itself is not "before"` (only a 2026-2027 enrollment -> null); `archived counts` (status `dropped_out`, `leftOn` returned).
- [ ] **Step 2:** `flutter test test/core/data/student_latest_enrollment_test.dart` -> FAIL (method missing).
- [ ] **Step 3:** Implement in all three files (any other `StudentRepository` implementers in `test/` get the method too; `grep -rn "implements StudentRepository"`).
- [ ] **Step 4:** Run -> PASS; `flutter test` whole suite -> green (report any failure by name).
- [ ] **Step 5:** Commit message: `feat(sf1): latest enrollment before a school year (repo, SQLite + Supabase)`.

### Task 2: The `continuing` trial row

**Files:**
- Modify: `lib/core/services/sf1_importer.dart` (`Sf1TrialRow`, `Sf1TrialResult`, `_existingLearnerRow` and its call site)
- Test: `test/core/services/sf1_importer_continuing_test.dart`

**Interfaces:**
- Consumes: `latestEnrollmentBefore` (Task 1).
- Produces: `Sf1TrialRow.outcome == 'continuing'`; new fields `bool updatesName` (default false), `String? previousName` (BASA's name when `updatesName`); `fillsBirthDate` also set on continuing rows; `existingStudentId` set. `Sf1TrialResult.wouldContinue` (count). `_existingLearnerRow` gains `required Student incoming` (the parsed row) to compare names and birth dates.

- [ ] **Step 1: Write the failing tests** (fixture school 1 + other school 2, file year `2026-2027`, file grade 4; each test inserts one learner with earlier enrollments, writes a one-row SF1 with the fixture writer of the leavers test, runs `trial`):
  - `one grade up continues`: 2025-2026 Grade 3 at school 1 -> outcome `continuing`, reason `moving up from Grade 3 (2025-2026)`.
  - `same grade continues as repeating`: 2025-2026 Grade 4 -> `repeating Grade 4`.
  - `back after leaving`: 2025-2026 Grade 3, `dropped_out` -> `moving up from Grade 3 (2025-2026), back after leaving (dropped out, 2025-2026)`.
  - `gap year`: only 2024-2025 Grade 3 -> `moving up from Grade 3 (2024-2025), last here in 2024-2025`.
  - `two grades up is a conflict`: 2025-2026 Grade 2 -> `conflict`, reason `last enrolled here in Grade 2 (2025-2026): Grade 4 is not the next grade`.
  - `lower grade is a conflict`: 2025-2026 Grade 5 -> `conflict`, same reason pattern.
  - `other school stays the generic conflict`: 2025-2026 Grade 3 at school 2 -> `conflict`, reason starts `LRN already exists`.
  - `this-year enrollment elsewhere wins` (Review Focus 3): 2025-2026 Grade 3 at school 1 **and** 2026-2027 Grade 4 active at school 2 -> generic conflict.
  - `corrected name`: BASA `Fixture, Zed` vs SF1 `Fixtura, Zed` -> `updatesName` true, `previousName` `Fixture, Zed`, reason ends `, name corrected: Fixture, Zed -> Fixtura, Zed`.
  - `middle name added` (Review Focus 5): BASA middle null, SF1 middle `Q` -> `updatesName` true.
  - `blank birth date filled`: BASA birth date null, SF1 `03-01-2016` -> `fillsBirthDate` true; BASA `2016-02-01` vs SF1 other -> false.
  - `trial writes nothing`: enrollments and students row counts unchanged after `trial`.
- [ ] **Step 2:** `flutter test test/core/services/sf1_importer_continuing_test.dart` -> FAIL.
- [ ] **Step 3:** Implement in `_existingLearnerRow`: today's code when this-year enrollment `e != null`; when `e == null` and `schoolId != null`, call `latestEnrollmentBefore` and apply the Global Constraints rule; otherwise today's generic conflict. "School year just before" = `'${start-1}-$start'` of the file's year.
- [ ] **Step 4:** Run -> PASS; `flutter test test/core/services/sf1_importer_leavers_test.dart` still green; whole suite green.
- [ ] **Step 5:** Commit message: `feat(sf1): trial marks learners continuing at the same school (up a grade or repeating)`.

### Task 3: Import applies continuing rows; console, docs, live check

**Files:**
- Modify: `lib/core/services/sf1_importer.dart` (`Sf1ImportResult.continuing`, `import()`), `lib/core/console/commands/import_commands.dart` (two summary lines), `docs/handoff/screens/admin.md` (*SF1 import*), `CLAUDE.md` (Module checklist: one clause under Import-export)
- Test: extend `test/core/services/sf1_importer_continuing_test.dart`
- Live: `tool/demo_data/_check_two_years.dart` (the throwaway check from the demo plan's Task 1; deleted at the end of this task)

**Interfaces:**
- Consumes: Task 2 row fields.
- Produces: `Sf1ImportResult.continuing` (int); `import()` for a continuing row: when `updatesName`, `studentRepo.update(existing copy with the SF1's last/first/middle)` then `localStudentRepo.upsertWithId`; a throw adds row warning `Row <n> <name>: name not updated (this learner can't be changed)` and continues; when `fillsBirthDate`, the same fill as the `enrolled` path (counts `birthDatesFilled`); then `studentRepo.enroll` + `localStudentRepo.enroll` into the file's section; `continuing++`; no conflict logged.

- [ ] **Step 1: Write the failing tests:** `import enrolls continuing learners and logs no conflict` (one-grade-up learner -> `continuing` 1, `conflicts` 0, an enrollment in the file's section for 2026-2027, last year's enrollment untouched); `import updates a corrected name`; `re-import of the same file gives already enrolled` (Review Focus 1: second import -> `alreadyEnrolled` 1, `continuing` 0, one 2026-2027 enrollment); `refused name update: a warning, still enrolled` (Review Focus 4: a `StudentRepository` wrapper whose `update` throws).
- [ ] **Step 2:** Run -> FAIL. **Step 3:** Implement `import()` and the two console lines (`, continuing: ${t.wouldContinue}` / `, Continuing: ${result.continuing}` at the end of each summary line); in `import-trial`'s per-row list, continuing rows print their reason like other rows.
- [ ] **Step 4:** Run -> PASS; whole suite green; `dart analyze`; both tool checks.
- [ ] **Step 5: Live check:** change `_check_two_years.dart` to use a new school code `ZZDEMOCHK2` and run it (without `--resolve`). Expected: second `import-trial` `would conflict: 0 ... continuing: 3`; `import-students` `Conflicts: 0 ... Continuing: 3`; `learner-history-lrn` shows 2026-2027 Grade 4 and 2025-2026 Grade 3. The script must not print the sign-in password (print only `> sign-in cloud <email>`). Then delete the script.
- [ ] **Step 6:** Full command pass (SF1 batches can't run alone: B0 is one-off setup): `dart run tool/command_pass/run.dart` (**DO NOT PLAY RESOURCE INTENSIVE GAMES** while it runs). Expected: every step passes (the summary lines only gained a suffix; the A8 conflicts are other-school cases, unchanged).
- [ ] **Step 7:** Docs: admin.md *SF1 import* gets a bullet (2026-11-24): outcome `continuing`, `Sf1TrialRow.updatesName` / `previousName`, `Sf1TrialResult.wouldContinue`, `Sf1ImportResult.continuing`, the label texts; CLAUDE.md Import-export clause "SF1 continuing learners (2026-11-24, spec ...): a new year's SF1 enrolls same-school learners one grade up or repeating, no conflict".
- [ ] **Step 8:** Commit message: `feat(sf1): import enrolls continuing learners; console + handoff doc` (body lists the tests and the live check).
