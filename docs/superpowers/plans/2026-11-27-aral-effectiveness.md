# ARAL effectiveness (no-improvement alerts + progress trend) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flag ARAL learners who are not improving to their class tutor and coordinator, and chart per round the share of ARAL learners up / same / down since their start.

**Architecture:** One pure-Dart rule (`lib/core/services/aral_effectiveness_rules.dart`) decides "no improvement" from a `classProgress` row, the learner's attendance and their latest check-in. `AralClassViewModel.noImprovement` applies it per class; `ReminderViewModel` turns it into tutor reminder lines and coordinator class notices; `TrendViewModel.aralProgress` counts `classProgress(atRound:)` rows per round. Nothing stored, no migration, both builds.

**Tech Stack:** Dart, sqflite_common_ffi (device copy), flutter_test (pure-Dart tests), console commands.

**Spec:** `docs/superpowers/specs/2026-11-27-aral-effectiveness-design.md`

## Global Constraints

- No table, no migration, no SQLite version change; `lib/core/` and `lib/viewmodels/` never import Flutter.
- Messages: plain words, no ids, fields or commands (wording rule 2026-11-17). No "carried"/"actual" in anything a tutor reads.
- Only learners placed in an ARAL class this school year and active on the day (`aralActiveOn`) are flagged; exited never.
- Signal A: change `same` or `down` AND attended (mark `present` only) >= `AralRuleSettings.checkinAfterSessions[0]` sessions of the enrollment dated on or before the latest round's assessment date.
- Signal B: latest **complete** check-in (`aralLatestCheckin` over both checkpoints) not passing today's `passPct`.
- `notAssessedYet` / `noStartingResult` rows never trigger A.
- Trend: no attendance minimum; same change computation as `classProgress`; scopes section/school/region; `TutorScope` refused.
- Repo is public: roles only, no people's names. Every task report and commit names the objective(s): iii, iv (M1-13).
- Run `dart analyze`, `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart` after each task; never run `dart analyze` alongside `flutter test` (slow machine).

## Review Focus

- A learner moved to another class mid-year: counted once (one roster row), alerts on the current class only. -> Task 2 test `moved learner appears once`.
- A class mixing Grade 3 (CRLA) and Grade 4 (Phil-IRI) learners: the trend's CRLA chart ignores the Phil-IRI rows and vice versa. -> Task 4 test `mixed class split by instrument`.
- A check-in started but not finished (incomplete) below the pass mark: no B alert. -> Task 1 test `incomplete check-in ignored` (rule takes only complete ones) and Task 2 test.
- Attendance marked after the latest round (sessions dated later): they don't count toward A's minimum. -> Task 2 test `attendance after the round not counted`.
- `atRound` at or before the learner's starting round (e.g. MOSY #1 for a MOSY #1 start): `notAssessedYet`, not counted at that round. -> Task 2 test `atRound not after start`.

---

### Task 1: The rule and its models

**Files:**
- Modify: `lib/core/models/aral_progress.dart` (add `latestAssessedOn`, new types)
- Create: `lib/core/services/aral_effectiveness_rules.dart`
- Test: `test/core/services/aral_effectiveness_rules_test.dart`

**Interfaces:**
- Produces:
  - `AralLearnerProgress.latestAssessedOn` (`String?`, YYYY-MM-DD; null when `latestRound` is null), optional constructor parameter.
  - `enum AralNoImprovementKind { round, checkin }`
  - `class AralNoImprovementReason { final AralNoImprovementKind kind; final String message; const AralNoImprovementReason(this.kind, this.message); }`
  - `class AralNoImprovement { final AralLearnerProgress progress; final List<AralNoImprovementReason> reasons; const AralNoImprovement(this.progress, this.reasons); }` (all three in `aral_progress.dart`)
  - `class AralCheckinOutcome { final int afterSession; final AralCheckinScore score; final int passPct; final bool complete; const AralCheckinOutcome(...); }` in the rules file (`afterSession` = the school's session number for that checkpoint).
  - `List<AralNoImprovementReason> aralNoImprovementReasons(AralLearnerProgress p, {required int attendedBeforeLatest, required int minAttended, AralCheckinOutcome? latestCheckin})`

- [ ] **Step 1: Write the failing tests** (`aral_effectiveness_rules_test.dart`, build `AralLearnerProgress` values directly):
  - `same after enough sessions` -> one `round` reason, message exactly `Same since BOSY: Frustration -> Frustration (MOSY #1)` (start `bosy` Frustration, latest `mosy1` Frustration, attended 16, min 16).
  - `down` -> `Down since BOSY: Developing Reader -> High Emerging Reader (MOSY)` (CRLA, latest `mosy`).
  - `too few attended` -> attended 15, min 16 -> no reasons.
  - `up` -> no round reason; `notAssessedYet` and `noStartingResult` -> no round reason.
  - `failed check-in` -> `AralCheckinOutcome(afterSession: 16, score: AralCheckinScore(9, 20, 20), passPct: 75, complete: true)` -> one `checkin` reason `Check-in after session 16: 45%, pass mark 75%`.
  - `incomplete check-in ignored` -> same but `complete: false` -> none; `passed check-in` (15/20 = 75%) -> none.
  - `both reasons` -> round first, check-in second.
  - `exited learner` -> enrollment with `exitedOn` set -> none.

- [ ] **Step 2: Run** `flutter test test/core/services/aral_effectiveness_rules_test.dart` — Expected: FAIL (missing names).

- [ ] **Step 3: Implement** the types and `aralNoImprovementReasons`. Round message: `'${p.change.label} since ${p.startRoundLabel}: ${p.startProfile} -> ${p.latestProfile} (${p.latestRoundLabel})'`. Check-in message: `'Check-in after session ${o.afterSession}: ${o.score.wholePercent}%, pass mark ${o.passPct}%'`; pass/fail via `score.passes(passPct)`.

- [ ] **Step 4: Run** the test — Expected: PASS. Then `dart analyze` (0 errors).

- [ ] **Step 5: Commit message** (owner commits): `feat(aral): no-improvement rule for ARAL learners` (objectives iii, iv).

---

### Task 2: `AralClassViewModel` — `atRound`, `latestAssessedOn`, `noImprovement`, console

**Files:**
- Modify: `lib/viewmodels/aral_class_viewmodel.dart` (constructor gets `required AralCheckinViewModel checkins`; `classProgress`, `_crlaProgress`, `_philIriProgress`; new `noImprovement`)
- Modify: `lib/core/wiring/wire_tutor.dart` (build `aralCheckinVm` before `aralClassVm`, pass it)
- Modify: `lib/core/console/commands/aral_class_commands.dart` (`aral-no-improvement`)
- Modify: `test/core/wiring/tutor_commands.txt`, `test/core/wiring/admin_commands.txt` (+1 each, sorted as the files are)
- Test: `test/viewmodels/aral_no_improvement_test.dart` (fixture in the style of `aral_class_progress_test.dart`; check-in tools/items seeded as in `test/viewmodels/learner_history_test.dart`)

**Interfaces:**
- Consumes: Task 1 types and `aralNoImprovementReasons`.
- Produces:
  - `Future<List<AralLearnerProgress>> classProgress(int classId, {String? asOf, String? atRound})` — with `atRound` (a `CrlaRound`/`PhilIriRound` name): the "latest" is that round only (an own assessed result in it, on or before `asOf`), else `notAssessedYet`; a round name not of the row's instrument, or not after its start, -> `notAssessedYet`. Without it: unchanged.
  - `latestAssessedOn` filled: CRLA `CrlaResult.assessedAt` (date part); Phil-IRI `res.sessions[latestRound]!.assessedAt`.
  - `Future<List<AralNoImprovement>> noImprovement(int classId, {String? asOf})` — learners active on `asOf` (default today) with at least one reason, by name. Attendance via `AralSessionRepository.getAttendanceForEnrollment` joined to the session date (`findSession`, or the class's sessions from `getByClass` keyed by id — sessions of the learner's earlier class count too), `mark == present`, date <= `latestAssessedOn`. Latest check-in: `checkins.learnerCheckins(e.id!)` -> `aralLatestCheckin(results)` -> `AralCheckinOutcome(afterSession: rules.checkinAfterSessions[aralCheckinCheckpoints.indexOf(r.tool.checkpoint)], score: r.score, passPct: r.passPct, complete: r.complete)`; `minAttended` = `rules.checkinAfterSessions[0]` (`aralLocalRuleSettings`). Same access as `classProgress` (`_readable`).
  - Console: `aral-no-improvement <classId> [asof=YYYY-MM-DD]` (same arg parsing as `aral-class-progress`). Output: first line `<class name>: <n> learner(s) with no improvement` (`0 learners` allowed), then per learner `LAST, First | Grade g <instrument> | <reason>; <reason>`.

- [ ] **Step 1: Write the failing tests** in `aral_no_improvement_test.dart`:
  - `same after 16 attended` -> flagged with the round reason; `same after 15 attended` -> not flagged.
  - `attendance after the round not counted` -> 16 present marks, 2 of them dated after the MOSY #1 assessment -> not flagged.
  - `absent and excused do not count` -> 16 marks with 1 excused -> not flagged.
  - `failed complete check-in` -> flagged with `Check-in after session 16: …`; `incomplete check-in ignored`.
  - `exited learner not flagged`; `up learner not flagged`; `not assessed yet not flagged`.
  - `moved learner appears once` -> roster row moved from another class into this one: one row in `noImprovement` and `classProgress`; the sessions attended in the old class count.
  - `atRound not after start` -> `classProgress(_class, asOf: …, atRound: 'mosy1')` for a `mosy1` start -> `notAssessedYet`; `atRound` picks that round's result although a later round exists.
  - `tutor of another class refused` (`ViewModelException`, `This ARAL class is not one of your classes.`).
  - Wiring/command test: the command list files contain `aral-no-improvement` (the existing list tests fail until added).

- [ ] **Step 2: Run** `flutter test test/viewmodels/aral_no_improvement_test.dart test/viewmodels/aral_class_progress_test.dart test/core/wiring` — Expected: new tests FAIL, existing progress tests PASS.

- [ ] **Step 3: Implement** the signatures above; keep `classProgress`'s existing output identical when `atRound` is null.

- [ ] **Step 4: Run** the same tests — Expected: PASS. Then `dart analyze`, `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart` (all OK).

- [ ] **Step 5: Commit message:** `feat(aral): learners with no improvement per ARAL class` (objectives iii, iv).

---

### Task 3: Reminders — tutor lines and coordinator notices

**Files:**
- Modify: `lib/viewmodels/reminder_viewmodel.dart` (`ReminderLearner.reasons`, `TutorReminderKind.noImprovement`, `AralClassNoticeKind.noImprovement`, `tutorReminders`, `_aralNotices`; constructor gets `required AralClassViewModel aralClasses`)
- Modify: `lib/core/wiring/wire_tutor.dart` (pass `aralClassVm` to `ReminderViewModel`)
- Modify: `lib/core/console/commands/reminder_commands.dart` (print each flagged learner's reasons under the line)
- Test: `test/viewmodels/aral_no_improvement_reminders_test.dart`

**Interfaces:**
- Consumes: `AralClassViewModel.noImprovement(classId, {asOf})` (Task 2).
- Produces:
  - `ReminderLearner.reasons` (`List<String>`, `const []` from the existing constructor via initializer) and `const ReminderLearner.flagged(this.studentId, this.lrn, this.name, int this.enrollmentId, this.reasons)`.
  - `TutorReminderKind.noImprovement`, placed right after `checkinDue` in the enum (display order). One per tutor class (`classes` of the year with `tutorId == tutorId`) with >= 1 flagged learner; `aralClass` set; message `ARAL class <name>: <n> learner(s) show(s) no improvement.` (`1 learner shows`, `3 learners show`).
  - `AralClassNoticeKind.noImprovement` (last in the enum): one notice per class of the school with >= 1 flagged learner (classes with or without a tutor); message `Class "<name>": <n> learner(s) show(s) no improvement.`; `aralClass` and `learners` set.
  - Reminder day = the method's `today` / `day`, passed as `asOf`.

- [ ] **Step 1: Write the failing tests:** tutor gets one `noImprovement` line per own class with flagged learners, ordered after `checkinDue` lines, learners carry reasons; no line for a class with none flagged; another tutor's class not in this tutor's list; coordinator's `SchoolReminders.aral` has the notice for every class (also a tutorless one), exact messages above.

- [ ] **Step 2: Run** `flutter test test/viewmodels/aral_no_improvement_reminders_test.dart test/viewmodels/aral_class_reminders_test.dart` — Expected: new FAIL, existing PASS.

- [ ] **Step 3: Implement.** Console `reminders-tutor` / `reminders-coordinator`: under a no-improvement line, each learner as `  LAST, First: <reason>; <reason>`.

- [ ] **Step 4: Run** the tests + `test/core/console` reminder tests — PASS; `dart analyze`, both tool checks OK.

- [ ] **Step 5: Commit message:** `feat(reminders): no-improvement alerts for ARAL class tutors and coordinators` (objectives iii, iv).

---

### Task 4: Trend — `aralProgress` and `trend-aral-progress`

**Files:**
- Modify: `lib/viewmodels/trend_viewmodel.dart` (constructor gets `required AralClassViewModel aralClasses`; new `aralProgress`)
- Modify: `lib/core/wiring/wire_tutor.dart` (pass `aralClassVm`)
- Modify: `lib/core/console/commands/trend_admin_commands.dart` (`trend-aral-progress`)
- Modify: `test/core/wiring/admin_commands.txt` (+1)
- Test: `test/viewmodels/aral_progress_trend_test.dart`

**Interfaces:**
- Consumes: `classProgress(classId, {asOf, atRound})`, `AralClassViewModel.classes({schoolId, schoolYear})`.
- Produces: `Future<TrendChart> aralProgress(TrendScope scope, String schoolYear, {required String instrument, DateTime? asOf})` — `instrument` is `AralLearnerProgress.crla` or `.philIri` (else `ViewModelException`). Rounds: CRLA `mosy`, `eosy`; Phil-IRI `mosy1`-`mosy3`, `eosy`. Per round R: every class of the scope's schools this year, `classProgress(c.id, asOf:, atRound: R)`, rows of `instrument` (section scope: `enrollment.sectionId` in the scope's sections), one per enrollment id, change `up`/`same`/`down` only; n = their count; rounds with n = 0 left out. x label `<round label> (n = <n>)` (`AralLearnerProgress.roundLabel`); series `Up`, `Same`, `Down` as % of n, one decimal. Title `ARAL progress since the start (<instrument>) — <scope name> — <year>`. Scope via the existing `_resolve`; `TutorScope` -> `ViewModelException` (as the other non-activity trends).
  - Console: `trend-aral-progress <scope> <year> crla|phil-iri [asof=YYYY-MM-DD]`, printed like `trend-aral-exits`.

- [ ] **Step 1: Write the failing tests:** school scope, Phil-IRI: 4 learners at MOSY #1 (2 up, 1 same, 1 down) -> label `MOSY #1 (n = 4)`, Up 50.0, Same 25.0, Down 25.0; `mixed class split by instrument` (a Grade 3 CRLA learner in the same class is in the CRLA chart only); a round nobody has is left out; section scope counts only that section's learners; `TutorScope` refused; bad instrument refused; no attendance minimum (a learner with 0 sessions is counted).

- [ ] **Step 2: Run** `flutter test test/viewmodels/aral_progress_trend_test.dart` — Expected: FAIL.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run** the test + `test/core/wiring` — PASS; `dart analyze`, both tool checks OK.

- [ ] **Step 5: Commit message:** `feat(trends): ARAL learners up / same / down since their start, per round` (objectives iii, iv).

---

### Task 5: Docs, command pass, verify kit

**Files:**
- Modify: `docs/handoff/screens/aral.md` (no-improvement list beside class progress), `docs/handoff/screens/dashboard.md` (trend + the reminder line and notice)
- Modify: `CLAUDE.md` (module checklist line for M1-13; console counts tutor 153 / admin 304 — recount from the list files), `lib/core/CLAUDE.md` if it lists the ARAL rules (one line: the no-improvement rule lives in `aral_effectiveness_rules.dart`)
- Modify: `tool/command_pass/scenarios/24_t4.pass` (tutor: `aral-no-improvement {class_1}` + `asof` refusal + a tutor reminders line if the fixture flags one) and the admin batch that runs `trend-aral-exits` (`35_a5.pass`: `trend-aral-progress school:{school} {year} phil-iri`, bad-instrument refusal, `tutor:me` refusal)
- Create: `D:\0_CAPSTONE\verify\aral-effectiveness\README.md` (off repo: ids filled, expected output)

- [ ] **Step 1:** Write the docs and pass steps.
- [ ] **Step 2:** **DO NOT PLAY RESOURCE INTENSIVE GAMES.** Run `flutter test` (full) — Expected: 0 failed. Then `dart run tool/command_pass/run.dart` — Expected: 0 failed, coverage includes both new commands.
- [ ] **Step 3:** Consultation log M1-13 note (built; trend + alerts), agenda "Next things" progress; verify kit.
- [ ] **Step 4: Commit message:** `docs(aral): no-improvement alerts and progress trend handoff, command pass` (objectives iii, iv).
