# ARAL Class Tutors (reminders by class, learner progress) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MOSY/EOSY reminders for ARAL class learners go to their class tutor (grouped by class), each class lists every learner's change from their ARAL starting round to their latest round, and CRLA's "latest attempt" stops picking an old section's attempt.

**Architecture:** Everything is computed on the device from stored results; no table, migration or SQLite change. One shared CRLA latest-attempt rule feeds the ARAL report, the dashboard trend, learner history and the new progress list. `ReminderViewModel.tutorReminders` gains the hand-over; `AralClassViewModel.classProgress` is new.

**Tech Stack:** Dart (pure core), sqflite_common_ffi device copy, console command framework, command pass.

**Spec:** `docs/superpowers/specs/2026-11-27-aral-class-tutor-design.md` (approved 2026-11-27).

## Global Constraints

- No new tables, no migration, no SQLite version change, no RLS change.
- Both builds (tutor and admin); `dart run tool/check_tutor_imports.dart` and `dart run tool/check_vm_boundary.dart` OK after every task.
- Messages follow the 2026-11-17 wording rule (plain words; no field, id, table or console command names).
- A tutor's view never says "carried" or "actual": the progress row carries no values label.
- MOSY rounds: CRLA `mosy`; Phil-IRI `mosy1`, `mosy2`, `mosy3`. EOSY: `eosy`. BOSY reminders unchanged.
- Profile scales: CRLA `aralCrlaProfileOrder` (Low Emerging 0 ... At Grade Level 4), the grade's CRLA language only (`aralCrlaBasisVariant`); Phil-IRI profile rank Struggling/Non-Reader 0, Frustration 1, Instructional 2, Independent 3.
- Phil-IRI values follow `PhilIriValueList.aral` (`PhilIriViewModel.valueSource`).
- Executor: no git commands; commit messages go to the owner; every report and commit message has an `Objective:` line.

## Review Focus

1. A tutor who is both the section tutor and the class tutor: the learner shows once (on the class line), not twice. Test in Task 3 (`section tutor who also tutors the class sees the learner once`).
2. A learner whose roster row has no starting round (referral, older rows): starts at BOSY (Grade 1 CRLA: MOSY), never an error. Test in Task 2 (`no recorded starting round starts at BOSY`).
3. A Grades 1-3 learner whose starting-round CRLA was in another language than the grade's: "no starting result", not that other language's profile. Test in Task 2 (`starting attempt in another language is not used`).
4. Two CRLA attempts on the same day in two sections: the higher attempt number wins, then the later-made one (a device-made row, id < 0, is later than any pulled row). Test in Task 1 (`same day: attempt number, then the later-made row`).
5. A Phil-IRI learner under `carried` values with no MOSY reading of their own: "not assessed yet", not "same" from the carried BOSY. Test in Task 2 (`carried values without an own reading: not assessed yet`).

---

### Task 1: One CRLA latest-attempt rule (spec D3)

**Files:**
- Modify: `lib/core/services/crla_rules.dart` (new function), `lib/core/services/aral_rules.dart` (`aralCrlaLearnerProfile` uses it), `lib/viewmodels/learner_history_viewmodel.dart` (`_crlaByRound` uses it)
- Test: `test/core/services/crla_latest_attempt_test.dart` (new), `test/viewmodels/learner_history_test.dart` (one case)

**Interfaces:**
- Produces: `CrlaResult? crlaLatestAttempt(Iterable<CrlaResult> results)` — latest `assessedAt` (date part), then highest `attemptNo`, then the later-made row (an id < 0 is later than any id > 0; among negatives the more negative is later; among positives the higher is later). Null for an empty input.

- [ ] **Step 1: Failing tests** in `crla_latest_attempt_test.dart`: `moved mid-year: the new section's attempt 1 (later date) beats the old section's attempt 2`; `same day: attempt number, then the later-made row` (two same-date results attempt 1 ids 40 and -3 -> id -3; attempt 2 vs 1 same date -> attempt 2); `empty -> null`; and in `aral_ks1_rules_test.dart` style: `aralCrlaLearnerProfile follows the latest attempt for a moved learner` (old section attempt 2 'Low Emerging Reader' on 2026-08-01, new section attempt 1 'Developing Reader' on 2026-09-15, round bosy -> 'Developing Reader'). In `learner_history_test.dart`: the same pair -> the history's BOSY line shows the new section's profile.
- [ ] **Step 2: Run** `flutter test test/core/services/crla_latest_attempt_test.dart test/core/services/aral_ks1_rules_test.dart test/viewmodels/learner_history_test.dart` — FAIL (function missing; old pick).
- [ ] **Step 3: Implement** `crlaLatestAttempt`; replace the two hand-written picks with it (learner history keeps grouping by round and variant first, then picks with the rule).
- [ ] **Step 4: Run** the same tests — PASS; then `flutter test test/core/services test/viewmodels/learner_history_test.dart test/viewmodels/aral_report_totals_test.dart` — PASS.
- [ ] **Step 5: Commit message** `fix(crla): latest attempt by date, then attempt number (learner moved mid-year)`.

### Task 2: Class progress (spec D2)

**Files:**
- Create: `lib/core/models/aral_progress.dart`
- Modify: `lib/viewmodels/aral_class_viewmodel.dart` (new dependencies + `classProgress`), `lib/core/wiring/wire_tutor.dart` (pass them)
- Test: `test/viewmodels/aral_class_progress_test.dart` (new), `test/viewmodels/session_guard_test.dart` (add `classProgress`)

**Interfaces:**
- Consumes: Task 1 `crlaLatestAttempt` (through `aralCrlaLearnerProfile`).
- Produces:
  - `enum AralProgressChange { up, same, down, notAssessedYet, noStartingResult }` with `String get label` ('Up', 'Same', 'Down', 'Not assessed yet', 'No starting result').
  - `class AralProgressNumbers { final double? correctWordsPct; final double? wpm; final double? comprehension; }` — CRLA: correct words % (0-100), wpm, comprehension = questions right (count); Phil-IRI: word recognition %, wpm, comprehension %.
  - `class AralLearnerProgress { final AralEnrollment enrollment; final String learnerName /* "LAST, First" */; final int grade; final String instrument /* 'CRLA' | 'Phil-IRI' */; final String startRound; final String? startProfile; final AralProgressNumbers? startNumbers; final String? latestRound; final String? latestProfile; final AralProgressNumbers? latestNumbers; final AralProgressChange change; bool get exited; }`
  - `Future<List<AralLearnerProgress>> AralClassViewModel.classProgress(int classId, {String? asOf})` — learners placed in the class this school year (active and exited), by last name; `asOf` default today (YYYY-MM-DD, local).
  - `AralClassViewModel` constructor gains `required CrlaResultRepository crlaResults, required PhilIriViewModel philIri`.

- [ ] **Step 1: Failing tests** (`aral_class_progress_test.dart`, device fixture like `crla_digitized_test.dart`: one school, a Grade 2 and a Grade 7 section, a class holding learners of both, results inserted as pulled rows): `CRLA up: Low Emerging at BOSY -> Developing at MOSY`; `CRLA same`; `CRLA down`; `Phil-IRI up: Frustration -> Instructional, numbers before and after`; `not assessed yet: no reading after the starting round`; `no recorded starting round starts at BOSY`; `Grade 1 starts at MOSY` (basis 'mosy', MOSY Low Emerging, EOSY High Emerging -> up); `starting attempt in another language is not used` (G2 BOSY attempt in 'eng' only -> no starting result); `carried values without an own reading: not assessed yet` (report_settings values_aral = carried); `actual values without an own reading: not assessed yet, not the stand-in`; `an exited learner stays on the list, marked exited`; `the row has no carried/actual wording` (`toString()` and labels contain neither word). Add `classProgress` to the `AralClassViewModel` signed-out list in `session_guard_test.dart`.
- [ ] **Step 2: Run** `flutter test test/viewmodels/aral_class_progress_test.dart` — FAIL (missing).
- [ ] **Step 3: Implement.** Start round = `basisRound ?? (grade == 1 ? 'mosy' : 'bosy')`. CRLA: profiles from `aralCrlaLearnerProfile` per round on or before `asOf`; latest = the last of the rounds after the start that has one. Phil-IRI: `philIri.reportResults(...)`; the latest round after the start that has an own reading (status assessed), shown with the `values_aral` view of that round; no own reading after the start = not assessed yet. Change by rank (Global Constraints).
- [ ] **Step 4: Run** the test file and `session_guard_test.dart` — PASS; `dart analyze lib test` no errors; both tool checks OK.
- [ ] **Step 5: Commit message** `feat(aral): each class learner's change since their ARAL starting round`.

### Task 3: Reminders hand-over (spec D1)

**Files:**
- Modify: `lib/viewmodels/reminder_viewmodel.dart`
- Test: `test/viewmodels/aral_class_reminders_test.dart` (new)

**Interfaces:**
- Produces: tutor reminders of kinds `openAssessment` / `overdueAssessment` with `aralClass` set (and `section` null) for class lines; message `'<instrument> <round label> <when>: <n> of <m> learner(s) of ARAL class <class name> not assessed.'` (same `<when>` wording as section lines).

- [ ] **Step 1: Failing tests**: `at MOSY a placed learner leaves the section line and appears on the class line`; `BOSY is unchanged`; `a class without a tutor keeps its learners on the section line`; `a learner who exited ARAL goes back to the section line`; `section tutor who also tutors the class sees the learner once`; `a mixed-grade class gets a CRLA line and a Phil-IRI line`; `coordinator reminders are unchanged` (same counts before/after placing).
- [ ] **Step 2: Run** `flutter test test/viewmodels/aral_class_reminders_test.dart` — FAIL.
- [ ] **Step 3: Implement.** Hand-over set per year = learners active (`aralActiveOn`) in any class of that year with a tutor (`AralClassRepository.getBySchool`, `AralEnrollmentRepository.getBySection` / roster). Section lines: for MOSY/EOSY rounds drop them. Class lines: for each of the tutor's classes, group its active learners by instrument (by their section's grade) and school calendar round; "assessed" per learner in their own section, as section lines.
- [ ] **Step 4: Run** the new test plus `test/viewmodels/aral_session_rules_test.dart test/viewmodels/phil_iri_assessed_counts_test.dart` — PASS.
- [ ] **Step 5: Commit message** `feat(reminders): MOSY and EOSY of ARAL class learners go to their class tutor`.

### Task 4: Console, handoff, docs, command pass, demo row (spec D4)

**Files:**
- Modify: `lib/core/console/commands/aral_class_commands.dart` (`aral-class-progress <classId> [asof=YYYY-MM-DD]`, both builds, `strictDateArg`), `test/core/wiring/tutor_commands.txt` + `admin_commands.txt` (+1 each: tutor 151 -> 152, admin 301 -> 302), `test/tool/command_pass/coverage_test.dart` totals, a command-pass batch with ARAL classes and results (executor picks; ledger the choice) gets `aral-class-progress` and a `reminders-tutor` class-line expectation, `docs/handoff/screens/aral.md` (class progress; reminders by class), `tool/demo_data/phases/report.dart` (walkthrough row: a class tutor's `aral-class-progress`), `CLAUDE.md` (ARAL line, command counts), `lib/core/CLAUDE.md` (D3 rule; hand-over in the reminders note)
- Test: `test/core/console/aral_class_progress_command_test.dart` (new: one row printed as `LAST, First | Grade 7 Phil-IRI | BOSY Frustration -> MOSY #1 Instructional | Up | wpm 62 -> 80, comprehension 50% -> 70%`; refusal for a bad date)

- [ ] **Step 1:** wiring + command test fail on the missing name; **Step 2:** implement; **Step 3:** `flutter test` (full) and `dart run tool/command_pass/run.dart` — 0 failed (**DO NOT PLAY RESOURCE INTENSIVE GAMES**); **Step 4:** consultation log (agenda "Next things" #2 progress; M1-13 note that its alerts can read `classProgress`), verify kit `D:\0_CAPSTONE\verify\aral-class-tutor\README.md`.
- [ ] **Step 5: Commit message** `feat(aral): class progress command, screen handoff and command pass`.
