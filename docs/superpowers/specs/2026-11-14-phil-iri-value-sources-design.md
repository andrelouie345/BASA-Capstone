# Phil-IRI value sources (carried / actual) and the ranking list — design

Date: 2026-11-14. Owner + ma (reading coordinator). Brainstorm 2026-11-13/14.
Execution: native (inline), owner decision 2026-11-13.

## Why

Phil-IRI results carry up: a round's result is the best so far (highest oral
accuracy and speed, higher comprehension, the GST carrying into BOSY). Ma keeps
carry-up, but when she generates a list she wants to choose the **actual**
values: each round's own reading only. She also wants a new list: the lowest N
learners by one measure.

What carry-up does and does not affect today (checked 2026-11-13):

- Uses carried values: NLA Form 2b bands, BOSY masterlist, SRP candidates, ARAL
  (proposals, automatic updates and exits, implementation report), the
  dashboard's Phil-IRI band trend (built from Form 2b), the learner history and
  the tutor's `phil-iri-results` (the carried line).
- Does not: progress monitoring, reminders and dashboard completion count only
  rounds the learner was assessed in (`NlaReportViewModel.assessedIn` = status
  assessed, spec 2026-11-09 D11). No switch for them (D2).

Scoring does not change. `PhilIriRoundResult` already holds both values: the
top-level fields are carried, `actual` / `actualProfile` /
`actualAdjustedLevel` / `actualLevelsDown` are the round's own reading (in
BOSY the GST fills a missing comprehension).

## Decisions

- **D1 Six switches**, each `carried` or `actual`, keys in `report_settings`
  (jsonb, school row, then region row, then default):

  | Key | Default | Read by |
  |---|---|---|
  | `values_aral` | carried | ARAL proposals, automatic updates/exits, implementation report |
  | `values_bosy_masterlist` | carried | BOSY masterlist |
  | `values_form2b` | carried | NLA Form 2b and the dashboard band trend (`trend-bands`) |
  | `values_srp` | carried | SRP candidates |
  | `values_learner_pages` | carried | tutor's `phil-iri-results`, learner history |
  | `values_ranking` | **actual** | ranking list (D9) |

- **D2** No switch for progress, reminders or dashboard completion (already
  actual). The band trend follows `values_form2b` so the chart and the form
  never disagree.
- **D3 One value per list, never side by side** (ma). The switch decides which
  value a list shows; every list header and export names it ("Values: actual
  (each round's own reading)" / "Values: carried (best so far)").
- **D4 Who sets them:** admin build only. A school's admin or coordinator sets
  their own school; the superadmin sets the region or any school (same rules
  as the FLT switch, `ReportSettingsViewModel`). Tutors only read them from the
  device copy (needed for `phil-iri-results`).
- **D5 No own reading = not assessed** (ma, 2026-11-14, every list): under
  `actual`, a learner without a reading of their own in the round (a BOSY with
  only the GST included) gets the not-assessed stand-in
  (`philIriNotAssessedResult`: Struggling, 3 levels down), flagged "not
  assessed this round", ranked weakest where a list ranks.
- **D6 Latest round under actual** (ARAL updates/exits and the implementation
  report): the latest round the learner actually read in (a finished reading
  dated by asOf), scored on that reading alone. The not-assessed stand-in
  applies only when there is no reading at all that year, as today.
- **D7 Stored ARAL results:** a placement or update keeps storing its basis
  level as now; its reason text says which values it came from ("… (actual)").
  Changing a switch never rewrites stored placements; the next automatic
  update uses the new setting.
- **D8 Form 2b under actual** (owner, option B): a learner not read in a
  conducted round counts in **3-LD Frustration** (the stand-in), so the bands
  add up to the enrolment. The export header says so ("Values: actual; not
  assessed this round counted as 3-LD Frustration"). Under carried, Form 2b is
  unchanged (a learner with no comprehension at all is in no band).
  Amended 2026-11-14 (owner, option A, found while writing scenario a9):
  under actual, a learner who read in the round but has 0% or a blank
  comprehension counts in 3-LD Frustration too (otherwise they would count
  less than a learner who didn't read, and the bands would not add up).
  Carried keeps ma's rule (0 or none = in no band).
- **D9 Ranking list:** admin build only (admin/coordinator of the school, or
  the superadmin); scope one section, one grade of the school, or the whole
  school (Grades 4-10); values from `values_ranking` (default actual).
- **D10 Ranking blocks** (owner, option B): learners without a value for the
  measure never take a place in the top N; they go in a second block with a
  reason (D12).
- **D11 Learner pages** follow `values_learner_pages`: one line per round in
  the chosen values; under actual a round without an own reading shows "Not
  assessed this round".

## Design

### Shared rule

`PhilIriValues { carried, actual }` and `PhilIriValueList` (the six keys)
live in `lib/core/models/report_setting.dart` (the settings model reads them;
services may import models). A pure function in
`lib/core/services/phil_iri_results.dart`:

```

/// The round as a list shows it under [values]. carried: [r] unchanged.
/// actual: [r]'s own reading only (accuracy, wpm, comprehension from r.actual;
/// profile/adjusted level/levels down from actualProfile/actualAdjustedLevel/
/// actualLevelsDown); without an own reading ([ownReading] false) the
/// not-assessed stand-in for [learnerGrade], flagged notAssessedThisRound.
PhilIriRoundView philIriRoundView(PhilIriRoundResult r, PhilIriValues values,
    {required bool ownReading, required int learnerGrade})
```

`PhilIriRoundView` is a small read-only class with what lists read:
`round`, `values`, `notAssessedThisRound`, `wordReadingScore`,
`wordsPerMinute`, `silent` (the value comes from a silent reading only),
`wordReadingAssumed`, `comprehensionScore`, `profile`, `adjustedLevel`,
`levelsDown` and the existing label getters. Under carried it copies the
round result's fields; `silent` is true when the carried word reading is the
silent-only 1.0.

Callers:

- `PhilIriReportResults.view(round, values)`: `ownReading` = the round is in
  `sessions` (a finished reading counted by asOf; a GST-only BOSY has none).
- `PhilIriReportResults.latestView(among, values)`: carried = `latest(among)`
  as today; actual = the latest round in `sessions` among [among].
- `PhilIriLearnerResults` (tutor page, learner history): `view(round, values)`
  with `ownReading` = `round.given`.
- `PhilIriViewModel.valueSource(schoolId, key)` and the same in each list's
  ViewModel read the switch (school -> region -> default) from the device
  copy, like `_noComprehensionCountsFlt`.

`ReportSettings` gets the six keys as `PhilIriValues` values
(`valueSource(list)`); `PhilIriRoundView` is re-exported from
`core/models/phil_iri_types.dart` (VM boundary rule).

### Per list under actual

- **ARAL proposals** (`AralViewModel._philIriCandidate`): BOSY view. No own
  BOSY reading (GST only, or only later rounds) -> stand-in, proposed,
  rank key 0, reason "Not assessed this round (actual values)". Under carried:
  unchanged (incl. "No finished Phil-IRI BOSY yet").
- **ARAL updates/exits** (`_latestPhilIri`): `latestView(PhilIriRound.values)`.
- **ARAL implementation report** (`aral_report_viewmodel.dart`, `res.latest`):
  `latestView(rounds, values_aral)`.
- **BOSY masterlist**: BOSY view; no own BOSY reading -> listed, flagged not
  assessed, stand-in profile and levels, comprehension blank.
- **NLA Form 2b**: per conducted round the view's comprehension band, Non-Reader
  -> 3-LD Frustration as now; not assessed this round -> 3-LD Frustration (D8).
  GST columns unchanged (the GST is its own measure). The progress columns of
  the same report are unchanged (D2).
- **Band trend** (`TrendViewModel.bandDistribution`): reads the Form 2b report,
  so it follows `values_form2b` with no code of its own beyond passing it on.
- **SRP candidates**: EOSY view for profile, levels and all three ranking
  values (comprehension, accuracy, wpm). No own EOSY reading -> not assessed,
  flagged, ranked weakest (rank key 0). Under carried: unchanged (EOSY's own
  comprehension when there is one, else carried).
- **Learner history** (`LearnerHistoryViewModel`): the Phil-IRI line per round
  from the view; "(carried)" mark only under carried.
- **Tutor's `phil-iri-results`**: header line "Values: …"; one line per round
  from the view (the separate "true score" line goes away); in-progress
  sessions show as today.

### Ranking list

`PhilIriRankingViewModel` (new file `lib/viewmodels/phil_iri_ranking_viewmodel.dart`,
admin build only, `ScopedLogger`, `requireActiveSession` first):

```
Future<PhilIriRanking> rank({
  required int schoolId, required String schoolYear, required PhilIriRound round,
  required PhilIriRankMeasure measure,   // accuracy | wpm | comprehension
  int n = 10,                            // >= 1
  int? sectionId, int? grade,            // at most one; neither = whole school
  DateTime? asOf,
})
```

- Access and sections: `NlaReportViewModel.reportSections` (Grade 4-10
  sections of the school; tutors refused). `grade` = every section of that
  grade; a grade outside 4-10 or with no section is refused with a sentence.
- Values: `values_ranking` of the school (D1). Each learner: `reportResults`
  (asOf) -> `view(round, values)`.
- **Block 1**: learners with a value for the measure, lowest first. Ranks as
  `srpRanks`: equal values share a rank (1, 2, 2, 4); every learner with rank
  <= n is in, so the list may run past n (`PhilIriRanking.tiedPastN`).
  Display order within a rank: last name, first name. Row: rank, student
  (name, LRN), grade, section, value (accuracy/comprehension as whole percent
  as reports round them, wpm to one decimal), profile from the same view.
- **Block 2** (D10), by name, each with a reason (D12).
- `PhilIriRanking` holds the header: school, year, round, measure, scope,
  n, values, asOf.
- `exportCsv(PhilIriRanking)` -> CSV text (the console writes the file): header
  lines, then block 1 rows, then block 2 rows with a reason column.

**D12 block 2 reasons:**
- `not assessed this round`: actual, no own reading; carried, nothing at all
  (the round has no result).
- `silent reading: no accuracy`: measure accuracy and the value comes from a
  silent reading only (both modes: a silent 100% is not a measured accuracy).
- `comprehension only, no word reading`: an imported reading without word
  reading (`wordReadingAssumed`), measures accuracy and wpm.
- `no comprehension entry`: measure comprehension, blank comprehension.

Whole-school scope ranks Grades 4-10 together; the list shows each learner's
grade (asked by ma; not a like-for-like comparison).

### Settings ViewModel

`ReportSettingsViewModel`:
- `valueSourceLayers(int? schoolId)` -> per list: stored region value,
  stored school value, effective value (same checks as `fltCountsLayers`).
- `setValueSource(int? schoolId, PhilIriValueList list, PhilIriValues values)`
  (online; same write rules as `setFltCounts`: superadmin region/any school,
  school admin or coordinator own school). No per-key clear, as for the other
  keys (`resetSchool` clears a school's row).

### Cloud

Migration `supabase/migrations/20261114010000_report_settings_values.sql`:
header `App update required on all devices: no` (new optional keys; an older
app ignores them = carried, today's behaviour; an older app also ignores
`values_ranking`, which only the new list reads). Guard (stop when a stored
value of any of the six keys is not "carried"/"actual", listing the rows),
then one CHECK per key (`not (settings ? k) or settings ->> k in ('carried','actual')`
with `jsonb_typeof = 'string'`), then its `basa_migrations` row; id added to
`lib/core/release.dart`. No table/view/policy change: no grants; the existing
`report_settings` policies are re-read before writing the migration and stay
as they are. README 2b lists it.

Device: no SQLite change, no version bump (report_settings mirrors jsonb as
text; the app enforces the two values).

### Console

Admin build (the wholly admin `report_settings_commands.dart`, and a new
wholly admin `phil_iri_ranking_commands.dart` added to the list in
`tool/check_tutor_imports.dart`):

- `value-sources [school=<id>]`
- `value-source-set <aral|bosy-masterlist|form2b|srp|learner-pages|ranking> carried|actual [school=<id>|region]`
- `phil-iri-rank <schoolId> <year> <round> accuracy|wpm|comprehension [n=10] [section=<id>|grade=<g>] [asof=YYYY-MM-DD]`
- `phil-iri-rank-export <same arguments> <path.csv>`

Both builds: `phil-iri-results` prints per D11. Admin console +4 commands;
tutor console unchanged. `test/core/wiring/admin_commands.txt` updated on
purpose. `[admin-release]` gets `PhilIriRankingViewModel`; `[admin]` gets one
distinctive string of `setValueSource`'s refusal if it is new text.

## Errors

- Bad switch value or list name: refused with the allowed words.
- Ranking: n < 1, both `section` and `grade`, a section not of the school/year
  or not Grade 4-10, a grade outside 4-10 or without sections: refused with a
  sentence. Tutors: the `reportSections` refusal.
- Setting a switch offline: `requireOnlineSession` refusal (as FLT).

## Testing

- Pure Dart (`test/`):
  - `philIriRoundView`: carried copy; actual with own reading; actual without
    (stand-in, flag); GST-only BOSY; silent-only under both; comprehension-only
    import; `latestView` under actual skips rounds without an own reading.
  - Each list under both values: ARAL proposal and update (exit only on the own
    latest reading), implementation report, BOSY masterlist (GST-only flagged),
    Form 2b (not assessed -> 3-LD Frustration, bands sum to enrolment under
    actual; carried unchanged), trend bands follow Form 2b, SRP (no EOSY ->
    weakest), learner history, `phil-iri-results` text.
  - Ranking: ties share rank, cut at n keeps ties, block 2 reasons, grade and
    school scope, default actual, refusals.
  - Settings: fallback school -> region -> default; ranking default actual;
    write rules.
  - `session_guard_test.dart` for the new ViewModel's public methods.
- PG18: the migration's guard and CHECKs (accept carried/actual/absent; refuse
  other strings, numbers, booleans).
- Command pass: new scenario sets each switch, runs each list once per value,
  ranking with ties and block 2, refusals (tutor, other school, bad value);
  full pass clean before commit.
- Verify kit `D:/0_CAPSTONE/verify/carry-up/`.
- `dart analyze`, `flutter test`, `check_tutor_imports`, `check_vm_boundary`.

## Docs

`CLAUDE.md` (module checklist line, Data model `report_settings` keys, console
counts), `lib/core/CLAUDE.md` (Phil-IRI value sources paragraph),
`docs/handoff/screens/` (switch menu + ranking screen; screens built later
with the leavers screens, owner order 2026-11-13), the guide's Reports page,
README 2b (migration).

## Out of scope

- Screens (later, with the SF1 leavers screens, on `don`).
- A region-wide ranking scope.
- Changing scoring, carry-up itself, progress/reminders/dashboard completion.
- Re-scoring stored ARAL placements when a switch changes (D7).
