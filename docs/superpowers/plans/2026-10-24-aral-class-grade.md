# ARAL class grade and mixed programs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every ARAL class a home grade and either one program or mixed programs; learners of another grade join only when the coordinator confirms it; the fixed grade band goes.

**Architecture:** One new cloud migration changes `aral_classes` (`grade_level` required, `program` optional = mixed, `grade_band` dropped) and the placement check (no grade check on the cloud; program only for one-program classes). The device follows in SQLite v38 (rebuild of the synced `aral_classes` table). The ViewModels enforce the coordinator's confirmation for another grade and flag grade differences; everything else built in the ARAL classes plan stays.

**Tech Stack:** Dart (pure), sqflite_common_ffi, Supabase (Postgres 15+, plpgsql, RLS), PG18 test harness, console registry.

**Spec:** `docs/superpowers/specs/2026-10-23-aral-classes-design.md` (decision 2 is replaced by the owner decisions below; Task 3 writes them into the spec).

Owner decisions (2026-10-24, from the reading coordinator):
- G1. A class has a **home grade** (1-10, always) and **one program or mixed programs** (coordinator's choice per class). Classes are normally by grade, then by program; the grade band (1-3 / 4-6 / 7-10) is removed.
- G2. A one-program class takes only that program (as built); a mixed class takes any program.
- G3. A learner of **another grade** joins only when the coordinator confirms it (`aral-class-place … other-grade`); BASA never does it on its own: enrol with a class, enrol-proposed, referral and roster import leave such a learner waiting for a class, with a warning. The cloud does not check grades.
- G4. A placed learner whose grade changes (SF1 section move) **stays** in the class. `aral-update` and the coordinator reminders show every placed learner whose grade differs from the class's grade.
- G5. Unchanged: 15 active learners per class, same school and year, one tutor (possibly blank), sessions per class; a one-program class's learner whose program changes stays and is flagged.

## Global Constraints

- Backend only. Owner commits (commit message per task); stop after each task for the owner's check; decisions not covered here go to the owner before acting.
- Migration `supabase/migrations/20261024010000_aral_class_grade.sql`: idempotent; header `App update required on all devices: yes`; ends with its `basa_migrations` row (`app_update_required` true). Applied by the owner only after Task 2 (dev sign-in refuses the app until Task 3 adds it to `lib/core/release.dart`).
- Columns: `aral_classes.grade_level integer not null` (1-10), `program` nullable (null = mixed programs; otherwise the six values), `grade_band` dropped (cloud and device). Existing rows: `grade_level` = the lower end of their band (`1-3` → 1, `4-6` → 4, `7-10` → 7; the dev cloud has none).
- Cloud refusal texts: `an ARAL class has at most 15 active learners`, `the learner's program does not match the ARAL class`, `the ARAL class belongs to another school or school year`, `an ARAL class with learners keeps its grade and program`; the grade-band text and the section-change band check are removed.
- SQLite v38: `rebuildAralClassesForV38` copies every column of the old table except `grade_band` (row_version included), fills `grade_level` as above, drops the triggers/views mentioning `aral_classes` and runs in onUpgrade before every creator.
- After every task: `dart analyze` (0 errors), `flutter test`, `dart run tool/check_tutor_imports.dart`; every new or changed public ViewModel method in `test/viewmodels/session_guard_test.dart`.

## Review Focus

1. `aral-class-place` of a Grade 9 learner into a Grade 7 class without `other-grade`: refused with the reason and the way to confirm; with it: placed (Task 2 roster test).
2. `enrollProposed(class=)` from a section of another grade than the class: everybody enrolled, nobody placed, all named in the warning (Task 2 roster test).
3. A mixed-programs class with KS1, KS2 Basic and KS3 Plus learners of its grade: all placed; the 16th refused (Task 1 PG test + Task 2 test).
4. Changing a class's grade or program (incl. to/from mixed) while it has learners: refused on device and cloud (Task 1 + Task 2 tests).
5. A device upgraded to v38 holding a pending (negative-id) class: id, row_version and the pending lock survive; `grade_level` filled from its band (Task 2 v38 test).

---

### Task 1: Cloud migration (written and tested, not applied)

**Files:**
- Create: `supabase/migrations/20261024010000_aral_class_grade.sql`
- Create (outside repo): `D:/0_CAPSTONE/verify/pass/tools/grade_test.sql`, `grade_run.sh` (copy of `classes_run.sh`: chain, then this migration twice)

**Interfaces (Postgres):**
- `aral_classes.grade_level` (check `aral_classes_grade_level_check` 1-10), `program` nullable with `aral_classes_program_check` allowing null; `grade_band` + its check dropped.
- `aral_check_class_placement` (same signature): school/year; program only when the class has one; cap. `aral_class_band_ok` dropped; `aral_enrollments_before_update` no longer checks the band on a section change.
- `aral_classes_before_write`: a `grade_level` or `program` change (null ↔ value included) refused while any roster entry points at the class.

- [ ] **Step 1: Write `grade_test.sql`** (fixture like `classes_test.sql`; `try`/`cnt` rows): a Grade 7 KS3 Basic class takes G7 and G9 KS3 Basic learners (no grade check on the cloud) and refuses a KS2 learner (`program does not match`); a Grade 7 mixed class (program null) takes KS1, KS2 Basic and KS3 Plus learners, the 16th active refused; a placed learner's section move to another grade is allowed; a class with learners refuses `grade_level` and `program` changes (also to null), an empty one allows them; grade 11 and 0 refused; `grade_band` column gone; `aral_class_band_ok` gone; existing-row backfill (a row inserted with a band before the migration in the fixture setup step gets grade 7); ledger row true.
- [ ] **Step 2: Run** `bash grade_run.sh d:/0_CAPSTONE/Code/BASA-Capstone <scratch>` — Expected: fails (column missing).
- [ ] **Step 3: Write the migration** (header: what, why (G1-G5), rules, RLS unchanged).
- [ ] **Step 4: Run twice** — Expected: every case PASS, `second run OK`, no `FAIL <file>`.
- [ ] **Step 5: Hand over** — commit `feat(db): ARAL class home grade and mixed programs (not applied)`.

### Task 2: Device, model, rules, ViewModels, console (SQLite v38)

**Files:**
- Modify: `lib/core/models/aral_class.dart` (remove `AralGradeBand`; `AralClass.gradeLevel` (int), `AralClassProgram? program` (null = mixed); `String get groupLabel` = `Grade 7, KS2 Basic` / `Grade 7, mixed programs`), `lib/core/services/aral_rules.dart`, `lib/core/data/local/aral_local_schema.dart` (table, `rebuildAralClassesForV38`, triggers), `local_database.dart` (v38), class repositories, `lib/viewmodels/aral_class_viewmodel.dart`, `aral_viewmodel.dart` (enrol/proposal/refer/reactivate/move/notices), `aral_roster_import_viewmodel.dart`, `reminder_viewmodel.dart`, `sync_review_lines.dart` (class label), console `aral_class_admin_commands.dart`, `aral_admin_commands.dart` (aral-update summary), `reminder_commands.dart`, `aral_command_helpers.dart`
- Test: `test/core/services/aral_placement_rules_test.dart`, `test/core/data/aral_class_repository_sqlite_test.dart`, `test/core/data/aral_classes_v38_test.dart` (new), `aral_enrollments_v36_test.dart`, `aral_sessions_v37_test.dart`, `test/viewmodels/aral_roster_classes_test.dart`, `aral_class_sessions_test.dart`, `session_guard_test.dart`

**Interfaces:**
- `enum AralPlacementProblem { otherSchoolOrYear, programMismatch, otherGrade, full }`; `aralPlacementProblem({…same…, bool otherGradeOk = false})` (otherGrade only when the grades differ and `otherGradeOk` is false; checked after program, before full); message `otherGrade`: `{learner} is in Grade {grade}; class "{name}" is for Grade {gradeLevel}.`; a mixed class never gives `programMismatch`.
- `AralClassViewModel.createClass({required int schoolId, required String schoolYear, required String className, required int gradeLevel, AralClassProgram? program, …})` (null program = mixed; grade outside 1-10: `ARAL-Reading classes are for Grades 1-10.`); `editClass` refuses a grade/program change while learners exist: `Class "{name}" has learners; its grade and program can't change.`; `place(int enrollmentId, int classId, {bool otherGrade = false})` — the refusal without it ends with ` Place them in it anyway with other-grade if you decide so.`
- `AralViewModel`: enrol with a class, `enrollProposed(class=)`, `refer(class=)`: a learner of another grade is not placed (warning as for a full class); `reactivate` re-checks program and cap only; `moveToSection` keeps the class always and, when the grade now differs, sets `lastWarning` `Grade {g} is now in class "{name}" (Grade {G}); move them if needed (aral-class-place).`
- `AralUpdateKind.otherGrade` notice: `Grade {g} in class "{name}" (Grade {G})` for every placed active learner whose grade differs; coordinator reminders add `AralClassNoticeKind.otherGrade`: `{n} ARAL learner(s) in a class of another grade.`; the program-mismatch notice skips mixed classes.
- Roster import: a `Class` of another grade → imported without a class, flagged `class "{name}" is for Grade {G}: imported without a class`.
- Console: `aral-class-add <schoolId> <schoolYear> <grade 1-10> <program|mixed> <name...> [opts]`; `aral-class-edit <classId> <name|tutor|room|schedule|notes|grade|program> <value>` (`program mixed` allowed); `aral-class-place <enrollmentId> <classId> [other-grade]`; class line `#{id} | {name} | {groupLabel} | tutor … | n/15 active`.

- [ ] **Step 1: Update the tests first** — rules: other grade refused without the flag, allowed with it; mixed class takes any program; exact `otherGrade` message; repo: insert a mixed class (program null), check refuses grade 11; new `aral_classes_v38_test.dart`: a v37-shaped `aral_classes` (with `grade_band`) holding a pulled row (row_version 3, band `7-10`) and a pending new row (`4-6`, in `sync_pending`) → after rebuild + creators: `grade_band` gone, grade_level 7 and 4, ids/row_version kept, the pending lock refuses an update, every trigger back; device trigger: mixed class takes any program, a one-program class refuses another, no grade check; v36/v37/VM tests move from bands to grades; roster test: plain place of another grade refused with the message, `other-grade` places; `enrollProposed(class=)` from a G9 section into a Grade 7 class places nobody; `moveToSection` to another grade keeps the class and warns; `applyResults` lists the `otherGrade` notice; import flags a class of another grade.
- [ ] **Step 2: Run** — Expected: FAIL (undefined / old columns).
- [ ] **Step 3: Implement** (model, rules, schema v38 + rebuild, repos, VMs, console, review label, reminders, import).
- [ ] **Step 4: Run** `flutter test`, `dart analyze`, import walk — Expected: all pass, 0 errors, `OK: no admin file reachable`.
- [ ] **Step 5: Upgrade probe** — copy of `D:/0_CAPSTONE/verify/data/basa_local.db` → v38: rows kept, `aral_classes.grade_level` present, `grade_band` gone.
- [ ] **Step 6: Verify kit** `D:/0_CAPSTONE/verify/c5/` (offline device like c3/c4): a Grade 7 KS3 Basic class, a Grade 7 mixed class; a G9 learner refused then placed with `other-grade`; enrol-proposed from another grade's section; the notices; README notes c3/c4 used the band model and are superseded.
- [ ] **Step 7: Hand over** — commit `feat(aral): class home grade and mixed programs (SQLite v38)`.

### Task 3: Release and docs

**Files:**
- Modify: `lib/core/release.dart` (`'20261024010000': 'aral_class_grade'`), `README.md` 2b, `CLAUDE.md` (ARAL classes line + data model), `lib/core/CLAUDE.md` (ARAL classes rules, v38), spec (decision 2 → G1-G5; *Changes during implementation*), memory.

- [ ] **Step 1: Owner applies `20261024010000` on the dev cloud.**
- [ ] **Step 2: Update the files**; `flutter test test/core` — PASS.
- [ ] **Step 3: Live check** — fresh scratch device: `sign-in cloud zztest.coord@basa.test …`, `pull-cloud yes`, `aral-class-add 6 2026-2027 7 mixed ZZ G7 mixed {stamp}` then `aral-class-delete` it — Expected: sign-in OK, pull done, class added and deleted locally.
- [ ] **Step 4: Hand over** — commit `docs(aral): class home grade and mixed programs`. Then resume `docs/superpowers/plans/2026-10-23-aral-classes.md` Task 6 on the final model.
