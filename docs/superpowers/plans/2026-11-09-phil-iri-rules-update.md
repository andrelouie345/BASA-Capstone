# Phil-IRI Rules Update (R1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Comprehension Struggling band, Table 8's Struggling column, per-round assessment status ("not assessed" = Struggling for scoring), and the new "assessed" rule in progress, reminders, dashboard and Form 2b.

**Architecture:** All rules stay in `phil_iri_rules.dart` (bands, Table 8) and `phil_iri_results.dart` (carrying, status); the status is computed in `philIriRoundResults` and never stored. ViewModels only read `PhilIriRoundResult.status` and the one definition `NlaReportViewModel.assessedIn`. Storage only widens one CHECK (cloud migration + SQLite v41).

**Tech Stack:** Dart (pure, no Flutter in `lib/core` / `lib/viewmodels`), sqflite_common_ffi, Supabase Postgres migrations, PG18 test harness, console command pass.

**Spec:** `docs/superpowers/specs/2026-11-09-phil-iri-rules-update-design.md` (D1–D18).

## Global Constraints

- Owner rules (CLAUDE.local.md): no git commands; each task ends with a commit message for the owner, then STOP for the owner's verification before the next task.
- Comprehension bands: Struggling ≤ 40, Frustration 41–58, Instructional 59–79, Independent ≥ 80; key `comprehension_struggling_max`, default 40.
- Migration id `20261109020000`, file `supabase/migrations/20261109020000_phil_iri_rules_update.sql`, header `App update required on all devices: yes`; SQLite version 41.
- The status is never stored (D17). Results are always recomputed from raw readings.
- After every task: `dart analyze` (0 errors), `flutter test`, `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart`.
- Before any console or command-pass run: ask the owner to close any open BASA console/app (memory: open-console-check). Steps that run the full suite or the pass carry **DO NOT PLAY RESOURCE INTENSIVE GAMES**.

## Review Focus

1. A learner whose only reading is in MOSY 1 (nothing at BOSY, no GST): BOSY is *not assessed*, MOSY 1 *assessed*, MOSY 2 *carried over* — never a crash or a carried BOSY. (Task 2 test `first reading in MOSY 1`.)
2. `asOf` before a reading's date: that round is not assessed in progress and reminders, even though the reading exists. (Task 4 test `asOf before the reading`.)
3. A finalized snapshot or saved threshold row without `comprehension_struggling_max` loads with 40 and validates. (Task 2 test `snapshot without the key`.)
4. The school total of the progress report sums the new carried/not-assessed counts across sections. (Task 4 test `school total sums carried and not assessed`.)
5. CRLA dashboard tiles have no carried count; the console line must not print `null`. (Task 4 test `CRLA tile has no carried count`.)

---

### Task 1: Storage — comprehension level may be 'struggling'

Comes first: once Task 2 lands, finalizing a session can store `comprehension_level = 'struggling'`, which today's CHECKs refuse.

**Files:**
- Create: `supabase/migrations/20261109020000_phil_iri_rules_update.sql`
- Modify: `lib/core/data/local/phil_iri_local_schema.dart` (`_readingsTableSql` comprehension CHECK; v41 rebuild), `lib/core/data/local/local_database.dart` (version 41, upgrade step, header comment), `lib/core/release.dart`, `README.md` (2b), `tool/command_pass/scenarios/21_t1.pass` (version lines)
- Test: `test/core/data/local/phil_iri_readings_v41_test.dart`

**Interfaces:**
- Produces: `Future<void> rebuildPhilIriReadingsForV41(Database db)` in `phil_iri_local_schema.dart`.

- [ ] **Step 1: Write the failing test** `test/core/data/local/phil_iri_readings_v41_test.dart`:
  - `fresh database accepts a struggling comprehension`: open a fresh `AppContext` (pattern of `test/viewmodels/phil_iri_imported_scoring_test.dart`), insert school/section/student/passage/assessment/reading rows with `comprehension_level: 'struggling'`; expect no exception.
  - `v40 readings survive the v41 rebuild`: create a bare DB with the v40 `phil_iri_readings` DDL (copy of today's `_readingsTableSql` with the old comprehension CHECK, plus `row_version INTEGER`), insert one row (id 7, `comprehension_level: 'frustration'`, `row_version: 3`); call `rebuildPhilIriReadingsForV41(db)`; expect the row unchanged (id 7, level, row_version 3) and that an update to `'struggling'` now succeeds.
- [ ] **Step 2: Run** `flutter test test/core/data/local/phil_iri_readings_v41_test.dart` — Expected: FAIL (CHECK constraint failed / function not defined).
- [ ] **Step 3: Implement.** In `_readingsTableSql`, comprehension CHECK becomes `('independent', 'instructional', 'frustration', 'struggling')`. Rename `_copyReadingsForV39(db, old)` to `_copyReadings(db, old, String tempTable)` and make `rebuildPhilIriReadingsForV39` pass `'phil_iri_readings_v39'`; add `rebuildPhilIriReadingsForV41` identical to v39 (legacy_alter_table guard included) with `'phil_iri_readings_v41'`. In `local_database.dart`: `version: 41`; header comment `// v41: phil_iri_readings comprehension_level also allows 'struggling' (rebuildPhilIriReadingsForV41); cloud 20261109020000.`; replace the v39 call line with `if (oldVersion >= 26 && oldVersion < 41) await rebuildPhilIriReadingsForV41(db);` (one rebuild covers v39 too: the table SQL is the widest) and keep `stripSavedNonReaderMaxForV39` as is.
- [ ] **Step 4: Cloud migration.** Header lines like `20261029010000_phil_iri_struggling_level.sql` (purpose, spec path, `App update required on all devices: yes`). Body: `alter table public.phil_iri_readings drop constraint phil_iri_readings_comprehension_level_check; alter table public.phil_iri_readings add constraint phil_iri_readings_comprehension_level_check check (comprehension_level = any (array['independent', 'instructional', 'frustration', 'struggling']));` then `insert into public.basa_migrations (id, name, app_update_required) values ('20261109020000', 'phil_iri_rules_update', true);` (copy the column list from `20261029010000`). Add `'20261109020000'` to `lib/core/release.dart`; README 2b line in the style of the existing ones; `21_t1.pass` version lines updated to the new latest id.
- [ ] **Step 5: Run** the v41 test — PASS. Then `flutter test test/supabase/migration_grants_test.dart` — PASS.
- [ ] **Step 6: PG18 check** (memory: pg-test-harness): fresh build = auth stubs + baseline + every migration in order; then, as a tutor of the section and as its coordinator, `insert into phil_iri_readings (...) values (..., 'struggling', ...) returning id` succeeds; `select * from basa_migrations where id = '20261109020000'` returns `app_update_required = t`. Save the SQL in the scratchpad and in the kit (`D:/0_CAPSTONE/verify/phil-iri-rules/t1/`).
- [ ] **Step 7: Checks** — **DO NOT PLAY RESOURCE INTENSIVE GAMES**: `dart analyze`, `flutter test`, both tool checks. Expected: 0 errors, all tests pass.
- [ ] **Step 8: Hand over.** Tell the owner: do NOT apply on dev yet (apply with Task 3, after devices sync; sign-in to dev is refused by the version check until applied). Commit message:
  ```
  feat(phil-iri,db): comprehension level may be struggling (migration 20261109020000, SQLite v41)
  ```
  with a body listing migration, v41 rebuild, release.dart, README 2b, t1 lines; follow-ups: apply on dev with Task 3.

### Task 2: Rules and round status

**Files:**
- Modify: `lib/core/services/phil_iri_rules.dart`, `lib/core/services/phil_iri_results.dart`, `lib/core/console/commands/phil_iri_commands.dart` (`_roundText`), `lib/viewmodels/aral_viewmodel.dart:328` (stand-in reason text), `lib/viewmodels/phil_iri_viewmodel.dart` (`PhilIriReportResults` doc + `status` helper)
- Test: `test/core/services/phil_iri_table8_test.dart` (extend), create `test/core/services/phil_iri_round_status_test.dart`; update `test/core/services/phil_iri_result_getters_test.dart` if it asserts the Frustration stand-in

**Interfaces:**
- Produces:
  - `PhilIriThresholds.comprehensionStrugglingMax` (int, default 40, map key `comprehension_struggling_max`).
  - `enum PhilIriRoundStatus { assessed, carriedOver, notAssessed }` in `phil_iri_results.dart`.
  - `PhilIriRoundResult` fields `bool wordReadingAssessed`, `bool comprehensionAssessed`, `bool wordReadingAssumed` (all default false), `PhilIriRoundStatus status` (default `notAssessed`).
  - `PhilIriRoundStatus PhilIriReportResults.status(PhilIriRound r)` = `round(r).status`.

- [ ] **Step 1: Failing tests in `phil_iri_table8_test.dart`:**
  - `lookup 2 every cell` table gains a fourth column (comprehension Struggling): `ind: [ind, ins, fru, str]`, `ins: [ind, ins, fru, str]`, `fru: [ins, fru, fru, str]`, `str: [str, str, str, str]`, `non: [non, non, non, non]`.
  - `comprehension bands`: `philIriComprehensionLevel(0)` = str, `(0.40)` = str, `(0.41)` = fru, `(0.58)` = fru, `(0.59)` = ins, `(0.80)` = ind.
  - `validate refuses struggling max at or above instructional min`: `PhilIriThresholds(comprehensionStrugglingMax: 59).validate()` throws (same matcher the file uses for other validate cases).
  - `snapshot without the key`: `PhilIriThresholds.fromMap({'speed_fast_min': 151}).comprehensionStrugglingMax == 40` and `toMap()['comprehension_struggling_max'] == 40`.
- [ ] **Step 2: Failing tests in new `phil_iri_round_status_test.dart`** (Grade 7; readings built with `philIriScorePassage`, `method: oneMinute`, `countedMiscues` as given):
  - `GST-only BOSY is carried over and Struggling`: `philIriRoundResults(learnerGrade: 7, gstScore: 0.9, readings: {})` → BOSY `status == carriedOver`, `wordReadingAssumed`, `accuracyLevel == null`, `speed == null`, `wordReadingLevel == str`, `profile == str`, `adjustedLevel == 6`, `levelsDown == 1`; `wordReadingAssessed`/`comprehensionAssessed` false.
  - `reading with comprehension is assessed`: BOSY reading 120 words read, 0 miscues, comprehension 2/10 → `status == assessed`, both flags true, `comprehensionLevel == str`, `wordReadingLevel == ins`, `profile == str`, `adjustedLevel == 3`.
  - `reading without comprehension: word reading only`: BOSY reading as above with no comprehension, no GST → `wordReadingAssessed`, `!comprehensionAssessed`, `status == carriedOver`, `comprehensionLevel == str`.
  - `blank comprehension adjusts from the carried percent`: BOSY reading 120 words, 0 miscues, comprehension 5/10 (profile Frustration, adjusted 6); MOSY 1 reading 120 words, 0 miscues, no comprehension → MOSY 1 `profile == fru`, `adjustedLevel == 6` (carried 50% → 1 down; today 0% → 3), `status == carriedOver`. (Word reading carries up, so the MOSY 1 reading must not be worse than BOSY's for this case.)
  - `first reading in MOSY 1`: no GST, MOSY 1 reading 120 words, 0 miscues, 8/10 → BOSY `status == notAssessed`, `profile == null`; MOSY 1 `assessed`; MOSY 2 `carriedOver`.
  - `silent reading counts`: BOSY `method: silent`, `readingSeconds: 60`, wordCount 150, comprehension 8/10 → `status == assessed`, `wordReadingAssessed`.
  - `nothing all year`: all five rounds `notAssessed`; `philIriNotAssessedResult(PhilIriRound.bosy, 7)` → `profile == str`, `adjustedLevel == 4`, `levelsDown == 3`, `notAssessed`.
- [ ] **Step 3: Run** both files — Expected: FAIL (missing column / fields / enum).
- [ ] **Step 4: Implement rules** (`phil_iri_rules.dart`): the threshold field in constructor, `toMap`, `fromMap`, and `validate()` (`ordered('Comprehension', [comprehensionStrugglingMax, comprehensionInstructionalMin, comprehensionIndependentMin], 0, 100)`); `philIriComprehensionLevel` returns `struggling` for `pct <= t.comprehensionStrugglingMax`; `_profileTable` rows get `_s: _s` (Non-Reader row `_s: _n`); doc comments updated (no more "Comprehension has no Struggling level").
- [ ] **Step 5: Implement results** (`phil_iri_results.dart`, inside `philIriRoundResults`):
  - flags from `own`: `wordReadingAssessed = own != null` (every scored reading has words + time, spec D4/D5); `comprehensionAssessed = own?.comprehensionScore != null`.
  - when `wrLevel == null && compLevel != null`: `wrLevel = struggling`, `wordReadingAssumed = true` (accuracy, speed, scores stay null); the profile is then `_profile(struggling, compLevel)`.
  - adjusted level for a given round: `frustrationComp = own.comprehensionScore ?? (round == bosy ? null : comp)` — outside BOSY a blank uses the carried %; in BOSY a blank keeps today's GST starting grade branch (the GST is the carried value there; source: ma's workbook sheet 01, AN = `M14` (GST starting grade) when the comprehension cell is blank; confirmed by the owner 2026-11-09).
  - `status`: both flags → `assessed`; else `profile != null` → `carriedOver`; else `notAssessed`.
  - `philIriNotAssessedResult`: `profile: PhilIriLevel.struggling` (still 3 down, `notAssessed: true`). Header comment: replace the "count the learner as Frustration" and "blank counts as 0" bullets with the spec D4–D9 rules.
- [ ] **Step 6: Callers.** `PhilIriReportResults.status(r)`; its `notAssessed` doc says Struggling; `aral_viewmodel.dart:328` text `'Not assessed: counted as Struggling, 3 levels down (Grade …); '`; console `_roundText` prints `WR not assessed` instead of the percent/level when `r.wordReadingAssumed`, and appends ` · carried over` / ` · not assessed` for those statuses.
- [ ] **Step 7: Run** both test files — PASS. Fix `phil_iri_result_getters_test.dart` / other suites that expected the Frustration stand-in or a GST-only BOSY profile from comprehension; list each changed expectation in the ledger.
- [ ] **Step 8: Checks** — **DO NOT PLAY RESOURCE INTENSIVE GAMES**: `dart analyze`, `flutter test`, both tool checks.
- [ ] **Step 9: Hand over** with a verify kit `D:/0_CAPSTONE/verify/phil-iri-rules/t2/` (console steps on fresh data: a GST-only learner shows `WR not assessed … -> Struggling · carried over`; one reading with 2/10 shows Struggling). Note for the owner: command-pass lines in t4/a3 will fail until Task 3. Commit message `feat(phil-iri): comprehension Struggling band, Table 8 column and per-round assessment status`.

### Task 3: Reports, reminders, dashboard

**Files:**
- Modify: `lib/viewmodels/nla_report_viewmodel.dart` (`assessedIn`, `ProgressSectionReport`, progress loop, `progressReportCsv`, Form 2b loop and GST profile), `lib/viewmodels/reminder_viewmodel.dart` (`TutorReminderKind.noGst`, BOSY line), `lib/viewmodels/dashboard_viewmodel.dart` (`RoundSnapshot.carriedOver`), `lib/core/console/commands/nla_report_commands.dart`, `lib/core/console/commands/dashboard_commands.dart`, the reminders console printer (where `TutorReminderKind` is switched on)
- Test: create `test/viewmodels/phil_iri_assessed_counts_test.dart`

**Interfaces:**
- Consumes: Task 2's `PhilIriRoundResult.status`, `PhilIriReportResults.status(r)`.
- Produces: `ProgressSectionReport.carriedOver` and `.notAssessed` (`Map<PhilIriRound, NlaCounts>`, summed in `addAll`); `RoundSnapshot.carriedOver` (`int?`, named optional, null for CRLA); `TutorReminderKind.noGst`.

- [ ] **Step 1: Failing tests** in `phil_iri_assessed_counts_test.dart` (setup as `phil_iri_imported_scoring_test.dart`, signed in as a coordinator of school 1; one Grade 7 section, four learners: A GST 36/40 only; B GST + BOSY reading with 8/10; C BOSY reading with 8/10, no GST; D nothing; an `assessment_calendar` region row with BOSY open on the test's `today`; a tutor assigned to the section for the reminder test):
  - `progress counts assessed, carried and not assessed`: BOSY assessed T = 2 (B, C), carried over T = 1 (A), not assessed T = 1 (D); `share(bosy) == 0.5`.
  - `school total sums carried and not assessed`: `report.total.carriedOver[bosy]!.total == 1`, `.notAssessed[bosy]!.total == 1`.
  - `asOf before the reading`: `progress(asOf:` the day before B's and C's `assessed_at`) → BOSY assessed 0.
  - (Learners E and F below sit in a second Grade 7 section, so the counts above stay as stated; the progress tests pass `sectionIds: {first section}`.)
  - `Form 2b counts a Non-Reader once in 3-LD Frustration`: learner E with a BOSY reading of 120 words, 100 miscues, comprehension 0/10 → `band(bosy, NlaBand.ld3Frustration)` includes E (today: not counted).
  - `GST profile counts Struggling under Frustration`: learner F, a GST of 10/40 → `gstProfile[PhilIriLevel.frustration]` counts it.
  - `tutor reminders list carried-over learners and learners without a GST`: the BOSY not-assessed reminder lists A and D (not B, C); a `noGst` reminder lists C and D.
  - `CRLA tile has no carried count` / `Phil-IRI tile carries the count`: `dashboardVm.summary(...)` round tiles: Phil-IRI BOSY `carriedOver == 1`; a CRLA tile (Grade 1–3 section with a CRLA window) `carriedOver == null`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.**
  - `assessedIn(results)` = rounds whose `results.status(r) == PhilIriRoundStatus.assessed`; doc comment: spec D11.
  - progress loop: per round, add the learner's sex to `assessed`, `carriedOver` or `notAssessed` by `res.status(r)`.
  - `progressReportCsv`: per round `'<R> assessed', '<R> carried over', '<R> not assessed', '<R> %', '<R> status'`.
  - Form 2b: `final rr = res.round(round); final band = rr.profile == PhilIriLevel.nonReader ? NlaBand.ld3Frustration : nlaBand(rr.comprehensionScore);`. GST profile: map `struggling` to `frustration` before `gstProfile[...]`.
  - Reminders: after the per-round loop, for a Phil-IRI section whose BOSY window is open or closed, learners whose `reportResults(...).gst == null` → `TutorReminder(TutorReminderKind.noGst, 'Phil-IRI BOSY: N of M learners of Grade G S have no GST.', learners, section:, instrument:, window:, days:)`. Reuse the per-section results already computed (extend the `philIri` cache to keep the `PhilIriReportResults`, not just the round set).
  - Dashboard: `RoundSnapshot(..., carriedOver: p.total.carriedOver[round]!.total)` for Phil-IRI; CRLA passes nothing.
  - Console: progress round cells `BOSY 2 (50.0%) +1 carried, 1 not assessed DONE`-style (keep the existing fields, add ` · carried N · not assessed N`); dashboard `_round` appends `, N carried over` only when `carriedOver != null`; reminders printer handles `noGst` like `openAssessment`.
- [ ] **Step 4: Run** — PASS; then the whole suite.
- [ ] **Step 5: Checks** — **DO NOT PLAY RESOURCE INTENSIVE GAMES**: `dart analyze`, `flutter test`, both tool checks. Tutor console count stays 126, admin 247 (no new commands).
- [ ] **Step 6: Hand over** with kit `D:/0_CAPSTONE/verify/phil-iri-rules/t3/`. Commit message `feat(phil-iri,reports): assessed vs carried over in progress, reminders, dashboard; Form 2b Non-Reader`.

### Task 4: Command pass, docs, dev rollout

**Files:**
- Modify: `tool/command_pass/scenarios/24_t4.pass`, `33_a3.pass`, `22_t2.pass`, `35_a5.pass` (expectations), `lib/core/CLAUDE.md` (Phil-IRI rules notes, v41), `CLAUDE.md` (Phil-IRI line), `docs/handoff/screens/phil-iri.md` (status, assessed flags, `wordReadingAssumed`, carried-over column, `noGst` reminder)

- [ ] **Step 1:** Update the scenario expectations that the new rules change (levels with comprehension ≤ 40, GST-only BOSY profile, progress/dashboard/reminder lines). Each changed line gets a comment naming the spec decision.
- [ ] **Step 2:** Docs as listed (short; spec path referenced).
- [ ] **Step 3: Owner rollout.** Ask the owner to: make sure every dev device is synced and every upload decided; apply `20261109020000` on the dev project; run `select id, app_update_required from basa_migrations where id = '20261109020000';` and paste the result. Wait.
- [ ] **Step 4: Full command pass** — **DO NOT PLAY RESOURCE INTENSIVE GAMES** (ask the owner to close any open BASA console first): `dart run tool/command_pass/run.dart`. Expected: every batch clean (last clean r23: 371/371); fix scenario lines only where the new rule explains the difference, and ledger each.
- [ ] **Step 5:** Kit `D:/0_CAPSTONE/verify/phil-iri-rules/t4/` (pass run id, what to look at). Commit message `test(phil-iri): command pass and docs for the rules update`.
- [ ] **Step 6:** Final whole-branch review (fresh reviewer) over the four task commits + the spec commit; findings to the owner.
