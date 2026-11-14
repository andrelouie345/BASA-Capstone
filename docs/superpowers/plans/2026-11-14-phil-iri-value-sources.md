# Phil-IRI Value Sources and Ranking List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Owner chose native execution (superpowers:executing-plans).**

**Goal:** Six school switches (carried / actual) decide which Phil-IRI values each list shows, plus a new lowest-N ranking list.

**Architecture:** The switches are keys in the existing `report_settings` jsonb (school -> region -> default). One pure function, `philIriRoundView`, turns a round result into what a list shows under a switch; every list reads its switch from the device copy and calls it. Scoring (`philIriRoundResults`) is unchanged except for one new flag (`wordReadingSilentOnly`). The ranking list is a new admin-only ViewModel on top of `reportResults`.

**Tech Stack:** Dart (pure, no Flutter in `core/`), sqflite_common_ffi, Supabase Postgres, `flutter test`, the developer console, the command pass.

**Spec:** `docs/superpowers/specs/2026-11-14-phil-iri-value-sources-design.md` (D1-D12). Read it first.

## Global Constraints

- Keys and defaults exactly: `values_aral`, `values_bosy_masterlist`, `values_form2b`, `values_srp`, `values_learner_pages` default `carried`; `values_ranking` default `actual`. Stored values: the strings `"carried"` / `"actual"` only.
- Migration `20261114010000_report_settings_values.sql`, header `App update required on all devices: no`; ledger row last; id in `lib/core/release.dart`; README 2b lists it. No table/view/policy change (re-read the `report_settings` policies in the baseline + later migrations before writing it; leave them).
- No SQLite change, no version bump.
- Header/label copy: `Values: carried (best so far)` / `Values: actual (each round's own reading)`; Form 2b under actual adds `; not assessed this round counted as 3-LD Frustration`. Not-assessed flag text: `Not assessed this round`.
- `core/` never imports Flutter; command files and `lib/ui/` import only ViewModels/models (VM boundary); new admin-only code listed in `tool/check_tutor_imports.dart`, `[admin-release]`.
- After every task: `dart analyze` (no errors), `flutter test --concurrency=2`, `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart`. **DO NOT PLAY RESOURCE INTENSIVE GAMES while the suite or the command pass runs.**
- No git commands by Claude: each task ends with a commit message written to `D:/0_CAPSTONE/verify/carry-up/t<N>/commit_msg.txt` for the owner (conventional commit, body, follow-ups, `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`), plus a verify kit in the same folder (ids filled, expected output).
- Present any decision not settled by the spec to the owner before building it.

## Review Focus

1. **A learner moved between sections mid-year** — the view must use the same `reportResults(sectionId)` the list already uses; a reading under the old section counts the same under both values. Test in Task 3 (BOSY masterlist, learner with a reading stored under another section of the same school/year still shows that reading under actual).
2. **asOf before a round's reading** — under actual, a round whose only reading is dated after asOf is "not assessed this round" (not the reading). Test in Task 2 (`view` with a session outside `sessions` because of asOf).
3. **A school with no `report_settings` row and no region row** — every list must use the defaults (ranking actual, the rest carried), never throw. Test in Task 1 (fallback) and Task 4 (ranking default).
4. **A stored value from a newer app the device doesn't know** (e.g. a typo row written by hand before the CHECK) — `ReportSettings.fromMap` reads anything but `"actual"` / `"carried"` as the key's default. Test in Task 1.
5. **Ranking n larger than the learners with a value** — the list shows everyone ranked, no error, `tiedPastN` false. Test in Task 4.

---

### Task 1: The six switches (model, migration, settings ViewModel, console)

**Files:**
- Modify: `lib/core/models/report_setting.dart` (enums + six fields + keys)
- Create: `supabase/migrations/20261114010000_report_settings_values.sql`
- Modify: `lib/core/release.dart` (add `'20261114010000': 'report_settings_values'`)
- Modify: `lib/viewmodels/report_settings_viewmodel.dart` (layers + setter)
- Modify: `lib/core/console/commands/report_settings_commands.dart` (two commands)
- Modify: `test/core/wiring/admin_commands.txt`
- Modify: `README.md` section 2b (migration line)
- Create: `test/viewmodels/value_sources_test.dart`
- Create: `D:/0_CAPSTONE/verify/carry-up/t1/pg18_values.sql` (PG18 check, recipe in memory `pg-test-harness`)

**Interfaces:**
- Produces (in `report_setting.dart`):
  ```dart
  enum PhilIriValues { carried, actual }          // .name is the stored string
  enum PhilIriValueList {
    aral('values_aral', 'aral', PhilIriValues.carried),
    bosyMasterlist('values_bosy_masterlist', 'bosy-masterlist', PhilIriValues.carried),
    form2b('values_form2b', 'form2b', PhilIriValues.carried),
    srp('values_srp', 'srp', PhilIriValues.carried),
    learnerPages('values_learner_pages', 'learner-pages', PhilIriValues.carried),
    ranking('values_ranking', 'ranking', PhilIriValues.actual);
    final String key; final String cliName; final PhilIriValues defaultValue;
  }
  String philIriValuesLabel(PhilIriValues v); // 'Values: carried (best so far)' / 'Values: actual (each round's own reading)'
  ```
  `ReportSettings` gains `final Map<PhilIriValueList, PhilIriValues> valueSources` (every list present) and `PhilIriValues valueSource(PhilIriValueList l)`; `fromMap` reads each key, anything but `"carried"`/`"actual"` -> the list's default.
- Produces (in `ReportSettingsViewModel`):
  `Future<Map<PhilIriValueList, ({PhilIriValues? region, PhilIriValues? school, PhilIriValues effective})>> valueSourceLayers(int? schoolId)` (same checks as `fltCountsLayers`);
  `Future<ReportSetting> setValueSource(int? schoolId, PhilIriValueList list, PhilIriValues values)` (via `_setKey(_writer(schoolId), …, list.key, values.name)`).

- [ ] **Step 1: Write failing tests** in `test/viewmodels/value_sources_test.dart` (setup as `phil_iri_flt_counts_test.dart`: temp `AppContext`, `wireTutor(ctx, wireShared(ctx))` plus the admin wiring's `ReportSettingsViewModel`, `seedOfflineOwner`, rows inserted straight into the local `report_settings`):
  - `defaults`: no rows -> `ReportSettings.fromMap({}).valueSource(l) == l.defaultValue` for all six (ranking actual, rest carried).
  - `school over region`: region `{values_srp: actual}`, school `{values_srp: carried}` -> layers `(region: actual, school: carried, effective: carried)`; school row without the key -> effective actual.
  - `unknown value reads as default`: `{values_aral: 'Actual'}` and `{values_aral: true}` -> carried.
  - `setValueSource refuses offline / tutor / other school` with the existing `_writer` texts (`requireOnlineSession` message; `'Forbidden: only an admin or coordinator sets the report settings.'`; `"Forbidden: you can only set your own school's report settings."`).
- [ ] **Step 2: Run** `flutter test test/viewmodels/value_sources_test.dart` — expect compile failure (`PhilIriValueList` undefined).
- [ ] **Step 3: Implement** the enums, fields and `fromMap` in `report_setting.dart` (also extend the file's header comment with the six keys); `valueSourceLayers` / `setValueSource` in the ViewModel.
- [ ] **Step 4: Run** the test file — PASS.
- [ ] **Step 5: Console** in `report_settings_commands.dart`, same shape as `flt-counts`:
  - `value-sources <region|schoolId>` -> one line per list: `<cliName>: region <v|->[ · school <v|->] · applies <v>`.
  - `value-source-set <region|schoolId> <aral|bosy-masterlist|form2b|srp|learner-pages|ranking> <carried|actual>` -> `<cliName> values for <who> are now <v>. Devices get it after their next pull-cloud.` + `warn()`. Bad list/value -> usage text listing the allowed words.
  Add both names to `test/core/wiring/admin_commands.txt` (sorted as the file is).
- [ ] **Step 6: Migration** `20261114010000_report_settings_values.sql`, modelled line by line on `20261110010000_report_settings_flt.sql`: header (why, spec path, `App update required on all devices: no` with the reason: an older app ignores the keys = carried; only the new list reads `values_ranking`), guard `do $$` listing rows where any of the six keys is present and not (`jsonb_typeof = 'string'` and value in `('carried','actual')`), six `drop constraint if exists` / `add constraint report_settings_values_<suffix>` checks, ledger insert `('20261114010000', 'report_settings_values', false)`. Add the id to `release.dart`; README 2b line.
- [ ] **Step 7: PG18** `pg18_values.sql`: baseline + migrations to 20261114010000 apply; insert `{values_aral:"actual"}` OK, `{values_ranking:"carried"}` OK, `{}` OK; `{values_srp:"Actual"}`, `{values_form2b:1}`, `{values_learner_pages:true}` each refused by its constraint; a second run of the migration is a no-op; with a bad row present the guard raises and changes nothing. Run it; all expectations met.
- [ ] **Step 8: Full checks** (Global Constraints list). `flutter test --concurrency=2` green; `check_vm_boundary` (commands import only `report_setting.dart` model + VM).
- [ ] **Step 9: Kit + commit message** in `D:/0_CAPSTONE/verify/carry-up/t1/` (console: `value-sources region`, `value-source-set <school> ranking carried`, bad value refusal; owner applies the migration on dev with the PG18 file's expectations).

### Task 2: The shared rule and the learner pages

**Files:**
- Modify: `lib/core/services/phil_iri_results.dart` (`wordReadingSilentOnly`, `PhilIriRoundView`, `philIriRoundView`)
- Modify: `lib/core/models/phil_iri_types.dart` (re-export `PhilIriRoundView`)
- Modify: `lib/viewmodels/phil_iri_viewmodel.dart` (`valueSource`, `PhilIriReportResults.view/latestView`, `PhilIriLearnerResults.values/view/endView`)
- Modify: `lib/core/console/commands/phil_iri_commands.dart` (`phil-iri-results`, lines ~386-405)
- Modify: `lib/core/console/commands/learner_history_admin_commands.dart` (~line 80)
- Create: `test/core/services/phil_iri_round_view_test.dart`
- Create: `test/viewmodels/phil_iri_learner_pages_values_test.dart`

**Interfaces:**
- Consumes: `PhilIriValues`, `PhilIriValueList`, `ReportSettings.valueSource` (Task 1).
- Produces:
  - `PhilIriRoundResult.wordReadingSilentOnly` (bool, default false): set in `philIriRoundResults` when the carried word reading is the silent-only 1.0 (`oralScore == null && silentWpm != null`).
  - ```dart
    class PhilIriRoundView {
      final PhilIriRound round; final PhilIriValues values;
      final bool notAssessedThisRound;   // actual and no own reading
      final bool notAssessed;            // nothing all year (carried stand-in)
      final double? wordReadingScore, wordsPerMinute, comprehensionScore;
      final bool silentOnly;             // word reading value is a silent 1.0, not a measured accuracy
      final bool wordReadingAssumed;
      final PhilIriLevel? profile; final int? adjustedLevel; final int? levelsDown;
      // getters as PhilIriRoundResult: wordReadingPercent, comprehensionPercent, adjustedLevelLabel, levelsDownLabel
    }
    PhilIriRoundView philIriRoundView(PhilIriRoundResult r, PhilIriValues values,
        {required bool ownReading, required int learnerGrade});
    ```
    carried: copies `r` (`silentOnly = r.wordReadingSilentOnly`, `notAssessed = r.notAssessed`). actual + `ownReading` + `r.actual != null`: `r.actual` fields (`silentOnly = actual.silent`), `actualProfile`, `actualAdjustedLevel`, `actualLevelsDown`. actual otherwise: `philIriNotAssessedResult(r.round, learnerGrade)` copied with `notAssessedThisRound: true`.
  - `PhilIriViewModel.valueSource(int schoolId, PhilIriValueList list) -> Future<PhilIriValues>` (device copy, school -> region -> default; same lookup as `_noComprehensionCountsFlt`; default when `_reportSettings` is null).
  - `PhilIriReportResults.view(PhilIriRound r, PhilIriValues v) -> PhilIriRoundView` (`ownReading: sessions.containsKey(r)`).
  - `PhilIriReportResults.latestView(Iterable<PhilIriRound> among, PhilIriValues v) -> PhilIriRoundView?`: carried = `latest(among)` as a view (null when `latest` is null); actual = the last round of `among` in `sessions`, as a view; null when none.
  - `PhilIriLearnerResults` gains `final PhilIriValues values` (set by `learnerResults` from `values_learner_pages` of the section's school), `view(PhilIriRound r)` (`ownReading: round.given`), `endView()` (carried: `end`; actual: the last round with `given`, null when none).

- [ ] **Step 1: Failing pure tests** `phil_iri_round_view_test.dart` (build results with `philIriRoundResults` and `PhilIriPassageResult`s as `phil_iri_round_status_test.dart` does):
  - carried copy equals the round result's fields.
  - actual with own reading: BOSY 80% comp, MOSY1 50% comp -> MOSY1 actual comprehension 0.5, carried 0.8.
  - actual without own reading (MOSY1 missing): `notAssessedThisRound` true, profile struggling, adjusted = grade - 3 (min 1).
  - GST-only BOSY: actual -> `notAssessedThisRound` (caller passes `ownReading: false`).
  - silent-only: carried `silentOnly` true and word reading 1.0; actual `silentOnly` true.
  - comprehension-only import: `wordReadingAssumed` true, word reading null under actual.
- [ ] **Step 2: Run** — fails (undefined).
- [ ] **Step 3: Implement** in `phil_iri_results.dart`; re-export in `phil_iri_types.dart`.
- [ ] **Step 4: Run** — PASS. Also run `test/core/services/phil_iri_round_status_test.dart` (unchanged results).
- [ ] **Step 5: Failing VM test** `phil_iri_learner_pages_values_test.dart` (setup as the FLT test, one Grade 7 learner, BOSY and MOSY1 sessions finished, MOSY2 none):
  - `reportResults(...).view(mosy2, actual).notAssessedThisRound` true; `view(mosy2, carried)` = MOSY1's carried.
  - asOf before MOSY1's date -> `view(mosy1, actual).notAssessedThisRound` true (Review Focus 2).
  - `latestView(PhilIriRound.values, actual)!.round == mosy1`.
  - `learnerResults(...).values` follows a `values_learner_pages: actual` school row; default carried.
- [ ] **Step 6: Implement** the VM members; **Step 7: Run** — PASS.
- [ ] **Step 8: Console text.** `phil-iri-results`: after the GST line print `philIriValuesLabel(r.values)`; per round one line from `r.view(round)` (carried: `(carried) ` prefix when `!round.given && profile != null`, as now; actual and `notAssessedThisRound`: `Not assessed this round`); remove the `true score:` line; `End result:` from `r.endView()`. Learner history: same label line per Phil-IRI block, rounds from `view`, `(carried)` mark only under carried. Update any test that pins the old `true score:` text (`grep -rn "true score" test tool/command_pass`) and the `phil-iri-results` lines in `tool/command_pass/scenarios/*.pass` that expect it.
- [ ] **Step 9: Full checks**; kit `t2` (console `phil-iri-results` under both values via `value-source-set … learner-pages`) + commit message.

### Task 3: The four report switches (ARAL, BOSY masterlist, Form 2b + trend, SRP)

**Files:**
- Modify: `lib/viewmodels/aral_viewmodel.dart` (`_philIriCandidate` ~313, `_latestPhilIri` ~848)
- Modify: `lib/viewmodels/aral_report_viewmodel.dart` (~360-372)
- Modify: `lib/viewmodels/nla_report_viewmodel.dart` (`NlaReport`, `nlaReportCsv`, `_section`, `BosyMasterlist`, `bosyMasterlistCsv`, `bosyMasterlist`)
- Modify: `lib/viewmodels/srp_viewmodel.dart` (`SrpList`, `srpListCsv`, `candidates`)
- Modify: the console commands that print these (`nla_report_commands.dart` for `nla-report`/`bosy-masterlist`, `srp_admin_commands.dart` for `srp-list`, `aral_admin_commands.dart` for `aral-propose`, `aral_report_commands.dart`): one `philIriValuesLabel` line under each heading
- Create: `test/viewmodels/report_value_sources_test.dart`

**Interfaces:**
- Consumes: `PhilIriViewModel.valueSource`, `PhilIriReportResults.view/latestView`, `PhilIriRoundView` (Task 2).
- Produces: `NlaReport.values`, `BosyMasterlist.values`, `SrpList.values`, `AralImplementationReport` (the existing report class) `.values` — each a `PhilIriValues` read once per call from the school's switch. CSV decision (present to owner at task start): each of the three CSVs (`nlaReportCsv`, `bosyMasterlistCsv`, `srpListCsv`) and the ARAL report export gets a last column `Values` holding `carried` / `actual` (Form 2b under actual: `actual; not assessed this round counted as 3-LD Frustration`), keeping the table shape importable; screens/console print `philIriValuesLabel` above the table.

Behaviour (spec *Per list under actual*; under carried every list is byte-for-byte today's output):
- ARAL proposals: `values_aral`; actual -> `view(bosy, actual)`; `notAssessedThisRound` -> the stand-in candidate (proposed, rank key `AralRankKey(0,0,0)`, basis level `aralNotAssessedLevel`, reason `Not assessed this round (actual values): counted as Struggling, 3 levels down (Grade <g>)`).
- ARAL updates/exits: `latestView(PhilIriRound.values, values_aral)`; null -> unchanged (stays as placed); reason text gets ` (actual)` under actual (D7).
- ARAL implementation report: `group(rounds)` uses `latestView(rounds, values_aral)`; actual and null -> `aralReportNotAssessed`.
- BOSY masterlist: `values_bosy_masterlist`; actual -> `view(bosy, actual)`; `notAssessedThisRound` -> entry with `notAssessed: true`, stand-in profile/levels, comprehension null.
- Form 2b (`_section`): `values_form2b`; per conducted round `view(round, v)`; band = 3-LD Frustration when `profile == nonReader` or `notAssessedThisRound`, else `nlaBand(view.comprehensionScore)`. GST and progress columns unchanged. Trend bands need no change (they read `report`); confirm with a test.
- SRP: `values_srp`; actual -> `view(eosy, actual)` for profile, levels and `SrpRankKey(comprehension ?? 0, wordReadingScore ?? 0, wordsPerMinute ?? 0)`; `notAssessedThisRound` -> `_Draft(st, true, null, stand-in …, SrpRankKey(0,0,0))`.

- [ ] **Step 1: Failing tests** in `report_value_sources_test.dart` (one Grade 7 section; learners: A BOSY 85% comp then MOSY1 40%; B GST only; C BOSY 30% only; D read in all five rounds, EOSY 90%; E with a BOSY reading stored under another section of the same school and year (Review Focus 1)):
  - carried output unchanged: compare `nlaReportCsv`, `bosyMasterlistCsv`, `srpListCsv` (without the new column) to the current output computed before the change — write these expectations first from today's code.
  - BOSY masterlist actual: B listed with `notAssessed` true; E shows its own reading.
  - Form 2b actual MOSY1: A in the 3-LD band of 40%; B and C in 3-LD Frustration; the bands of a conducted round sum to the enrolment; carried MOSY1: A in GLR (85%).
  - `TrendViewModel.bandDistribution` follows `values_form2b` (its MOSY1 counts change with the switch).
  - SRP actual: C (no EOSY) `notAssessed` and rank 1; D not listed (EOSY 90% ready).
  - ARAL: actual proposal for B = stand-in; carried proposal for B = GST-based (today). Update under actual for A judged on MOSY1's own reading; implementation report MOSY column for A from MOSY1 actual.
- [ ] **Step 2: Run** — fail. **Step 3: Implement** list by list. **Step 4: Run** — PASS.
- [ ] **Step 5: Console labels**; update `test/` expectations and command-pass lines that pin these outputs' headers if any (`grep -rn "bosy-masterlist\|srp-list\|nla-report\|aral-propose" tool/command_pass/scenarios`).
- [ ] **Step 6: Full checks**; kit `t3` + commit message.

### Task 4: The ranking list

**Files:**
- Create: `lib/viewmodels/phil_iri_ranking_viewmodel.dart`
- Create: `lib/core/console/commands/phil_iri_ranking_commands.dart`
- Modify: `lib/core/wiring/wire_admin.dart` (build `philIriRankingVm`, register it as `'PhilIriRankingViewModel'`, `registerPhilIriRankingCommands(r, a.philIriRankingVm)`), `lib/viewmodels/admin_viewmodels.dart` (`philIriRanking` field)
- Modify: `tool/check_tutor_imports.dart` (both new files), `tool/admin_markers.txt` (`[admin-release]` + `PhilIriRankingViewModel`), `test/core/wiring/admin_commands.txt`
- Modify: `test/viewmodels/session_guard_test.dart` (new public methods)
- Create: `test/viewmodels/phil_iri_ranking_test.dart`

**Interfaces:**
- Consumes: `NlaReportViewModel.reportSections`, `PhilIriViewModel.reportResults`, `PhilIriViewModel.valueSource`, `PhilIriRoundView`, `srpRanks`-style ranking (write a local `rankAscending(List<double>) -> List<int>`; do not reuse `SrpRankKey`).
- Produces:
  ```dart
  enum PhilIriRankMeasure { accuracy, wpm, comprehension }
  enum PhilIriRankReason { notAssessedThisRound, silentNoAccuracy, comprehensionOnly, noComprehension }
  // labels: 'not assessed this round', 'silent reading: no accuracy',
  //         'comprehension only, no word reading', 'no comprehension entry'
  class PhilIriRankRow { final Student student; final int grade; final Section section;
    final int rank; final double value; final PhilIriLevel? profile; }
  class PhilIriUnranked { final Student student; final int grade; final Section section; final PhilIriRankReason reason; }
  class PhilIriRanking { final int schoolId; final String schoolYear; final PhilIriRound round;
    final PhilIriRankMeasure measure; final int n; final int? sectionId; final int? grade;
    final PhilIriValues values; final String asOf;
    final List<PhilIriRankRow> ranked; final List<PhilIriUnranked> unranked;
    bool get tiedPastN => ranked.length > n; }
  Future<PhilIriRanking> rank({required int schoolId, required String schoolYear, required PhilIriRound round,
      required PhilIriRankMeasure measure, int n = 10, int? sectionId, int? grade, DateTime? asOf});
  String philIriRankingCsv(PhilIriRanking r);
  ```
  Measure value from the view: accuracy = `wordReadingScore` (reason `silentNoAccuracy` when `silentOnly`, `comprehensionOnly` when `wordReadingAssumed`); wpm = `wordsPerMinute` (`comprehensionOnly` when `wordReadingAssumed`); comprehension = `comprehensionScore` (`noComprehension` when null). `notAssessedThisRound`, or carried with `notAssessed`/no profile -> `notAssessedThisRound`. Ranked: ascending, equal values share a rank, keep every row with rank <= n; order within a rank by last then first name (uppercase). Unranked by last then first name. Refusals: `n < 1` -> `'Learners to list is at least 1 (got <n>).'`; both section and grade -> `'Give a section or a grade, not both.'`; grade outside 4-10 or no section of it -> `'School <id> has no Grade <g> section for <year>.'`; section problems and tutors via `reportSections`.
  CSV: header row `Rank, LRN, Learner, Sex, Grade, Section, <Measure label>, Profile, Reason, Values`; ranked rows then unranked rows (rank blank, value blank, reason label); accuracy/comprehension as `progressPercent`, wpm one decimal.

- [ ] **Step 1: Failing tests** `phil_iri_ranking_test.dart` (two Grade 7 sections + one Grade 8; learners with comprehension 30%, 40%, 40%, 50%, 60%, one silent-only, one comprehension-only import, one with no MOSY1 reading):
  - default values = actual with no settings row (Review Focus 3).
  - comprehension, n=2, grade 7: ranks `[1, 2, 2]` (the two 40% tied at 2 both kept), `tiedPastN` true.
  - accuracy: the silent-only learner unranked `silentNoAccuracy` (under carried too); comprehension-only import unranked `comprehensionOnly` for accuracy and wpm.
  - MOSY1 actual: the learner without a MOSY1 reading unranked `notAssessedThisRound`; under carried they rank on the carried value.
  - school scope includes the Grade 8 learner; section scope only that section.
  - n=50 with 6 valued learners -> 6 ranked, `tiedPastN` false (Review Focus 5).
  - refusals: n=0, section+grade, grade 3, tutor (reportSections text).
  - `philIriRankingCsv` first line and one row of each block.
- [ ] **Step 2: Run** — fail. **Step 3: Implement** the ViewModel (logger `ScopedLogger(logger, 'PhilIriRankingViewModel')`, `_requireSignIn` first as `requireActiveSession`). **Step 4: Run** — PASS.
- [ ] **Step 5: Console** (`phil_iri_ranking_commands.dart`):
  - `phil-iri-rank <schoolId> <year> <round> <accuracy|wpm|comprehension> [n=<N>] [section=<id>|grade=<g>] [asof=YYYY-MM-DD]` -> header lines (school, year, round, measure, scope, `philIriValuesLabel`), ranked lines `#<rank> <Last>, <First> (LRN) G<g> <section>: <value>[ · <profile>]`, `<k> shown: <t> tied at rank <n>` when `tiedPastN`, then `Not ranked (<count>):` lines with reasons.
  - `phil-iri-rank-export <same arguments> <path.csv>` -> writes `philIriRankingCsv`, prints the path and counts.
  Dates via `strictDateArg`.
- [ ] **Step 6: Wiring, markers, command list, session guard**; **Step 7: Full checks**; kit `t4` + commit message.

### Task 5: Command pass scenario, docs, final review

**Files:**
- Create: `tool/command_pass/scenarios/39_a9.pass` (follow `37_a7.pass` style and setup helpers)
- Modify: `CLAUDE.md` (module checklist line, Data model `report_settings` keys, admin console count +4), `lib/core/CLAUDE.md` (a *Phil-IRI value sources* paragraph: keys, `philIriRoundView`, where each list reads it, D5/D8), `docs/handoff/screens/` new `value-sources.md` (switch menu in admin settings; ranking screen inputs/blocks; labels), the guide's Reports page (add the switches and the ranking list, in its plain style)

- [ ] **Step 1: Scenario** `39_a9.pass`: superadmin sets each of the six switches for the run's school and back; `value-sources` shows them; refusals (tutor `value-source-set` -> unknown command in tutor build; coordinator of another school; bad value); with fixture Phil-IRI data (reuse the a7 workbook fixture steps), each list once under carried and once under actual (`nla-report`, `bosy-masterlist`, `srp-list`, `aral-propose`, the ARAL implementation report, `phil-iri-results` as tutor), `phil-iri-rank` with ties and a non-ranked block, `phil-iri-rank-export`.
- [ ] **Step 2: Owner applies `20261114010000` on dev** (ask; wait). Then full pass `dart run tool/command_pass/run.dart` — clean (all batches, both command lists covered). **DO NOT PLAY RESOURCE INTENSIVE GAMES.**
- [ ] **Step 3: Docs** as listed.
- [ ] **Step 4: Full checks**; kit `t5` + commit message.
- [ ] **Step 5: Final whole-branch review** by one fresh reviewer on the most capable model (native execution's end gate), findings presented to the owner before any fix.
