# Phil-IRI rules update (R1): comprehension Struggling, "not assessed", who counts as assessed — design

Date: 2026-11-09. Status: approved in conversation (owner, reading coordinator "ma"); this file awaits the owner's review.

## Why

Ma's workbook revisions and answers of 2026-11-09 (relayed by the owner) change live Phil-IRI rules, not just the workbook import:

1. Comprehension gets a **Struggling** band (0–40).
2. **"Not assessed" is a monitoring label; for scoring it means Struggling** (word recognition / word reading, and comprehension unless a higher carried % exists).
3. A learner counts as **assessed** in a round only with words read, reading time and a comprehension entry (0 counts) in that round. A carried score or label never counts; a GST alone at BOSY is not an assessment.
4. On Form 2, a **Non-Reader** is counted once in **3 Levels Down, Frustration**.
5. Every learner must have a GST and a reading, no exceptions.

This is piece **R1** of three, all before import Task 6 (plan `docs/superpowers/plans/2026-11-09-phil-iri-import.md`):

- **R1 (this spec):** rules on data BASA already stores.
- **R2 (own spec):** readings without a passage ("Untitled" + typed word count) and comprehension-only readings (storage change).
- **Content fix:** Grade 7 A–D passages become any-round (ma: any grade-level passage in any round, each once per learner).

Design goal (owner): BASA has caught up with ma's current work; later updates from her should be small. Every rule therefore lives in two files (`phil_iri_rules.dart`: bands and Table 8; `phil_iri_results.dart`: carrying and status) and nothing derived is stored.

Sources: ma's messages of 2026-11-09 (session transcript 83fcb11d); `sample-files/charts and tables/` (Table 8, GST alternative conversion); `sample-files/updated ARAL workbooks/` (Grade 7–10, sheet `01` formulas AF, AK, AL, AN, AS, HO–HS; `Bases` B3:F9).

## Decisions

| # | Decision |
|---|----------|
| D1 | Comprehension bands (whole percents, rounded as today): **Struggling ≤ 40**, Frustration 41–58, Instructional 59–79, Independent ≥ 80. New adjustable threshold `comprehensionStrugglingMax`, default 40 (key `comprehension_struggling_max`). A comprehension of 0 is Struggling, never Non-Reader. |
| D2 | Table 8 lookup 2 gets a **Struggling comprehension column**: Struggling for every word reading row; the Non-Reader row stays Non-Reader (owner, answer A). Ma's Table 8 has no such column (it predates D1; "struggling" comprehension appears only on a Non-Reader row). On ma's list to confirm. Lookup 1 is unchanged. |
| D3 | A Non-Reader's comprehension level stays as scored (the tutor sees e.g. "Struggling, 20%"); the reading profile is already Non-Reader. How screens label it is the UI's choice (ma's conversion sheet, note 2). |
| D4 | Assessment status per round, from that round's own reading only: **word reading assessed** = the reading has words read and a reading time (every live scored reading has both: whole text/silent = passage words + time, one-minute = words read + 60 s); **comprehension assessed** = a comprehension entry (0 counts, blank does not, e.g. FLT). Round status **assessed** = both; **carried over** = not assessed but the round has a result (earlier round or GST; a GST-only BOSY lands here); **not assessed** = no result at all (the D9 stand-in is not a result: such a learner is not assessed, never carried over). |
| D5 | **Silent readings count** as word reading assessed (ma's check: words, time, comprehension; no miscue requirement). Their 100% still only stands in until an oral reading exists (unchanged). |
| D6 | **No word reading yet** (none this round, none earlier): word reading profile = **Struggling**, flagged `wordReadingAssumed`; accuracy and speed stay empty. Table 8 then gives a Struggling profile (owner, Q5: ma's words + Table 8, not the workbook's formula AS, which profiles from comprehension alone). |
| D7 | Blank comprehension: the carried higher % as today (workbook AK = MAX); with none at all it counts as 0 = Struggling. |
| D8 | **Adjusted grade when the round's comprehension is blank** uses the **carried %** (ma: "unless there is a carried over score and it's higher"). Today: 0% outside BOSY, the GST in BOSY. When a comprehension is entered, the round's own % is used (workbook rule of 2026-10-18, unchanged). The GST-only BOSY branch (GST starting grade, never at or above grade level for Frustration/Struggling) is unchanged. |
| D9 | **Nothing in the whole year** (no GST, no reading): the stand-in becomes **Struggling, exactly 3 levels down** (never below Grade 1), still flagged `notAssessed` (owner, answer A). Reports count it with Frustration, so 3-LD totals do not move. Ma: every learner must have a GST and a reading; this stays a stand-in, not a result. Her workbook gives Grade 1 here (a blank GST read as 0%); on ma's list. |
| D10 | Adjusted grade for a Struggling profile: unchanged (comprehension % like Frustration, cut-offs 79/40/28/25 from her GST conversion sheet). Reports keep counting Struggling with Frustration. |
| D11 | `NlaReportViewModel.assessedIn` (the one definition read by progress, reminders and the dashboard) becomes "rounds whose status is assessed". `PhilIriReportResults.counted` keeps its meaning (rounds with a reading or GST; results need it). |
| D12 | Progress report: per round, by sex, **assessed**, **carried over**, **not assessed** (CSV too). Done % = assessed ÷ enrolled, so a GST-only BOSY or a carried result no longer counts towards done. |
| D13 | Tutor reminders: "not assessed" learners per round use the new `assessedIn` (carried-over learners are listed). **New BOSY line:** learners with no GST once the BOSY window is open or closed, listed even when they have read. |
| D14 | Coordinator reminders and dashboard round tiles: the assessed count follows D11; each round tile also shows the **carried-over** count. |
| D15 | Form 2b stays on comprehension % bands, with two fixes: a **Non-Reader** profile counts once in **3-LD Frustration** whatever the comprehension; the GST comprehension profile block counts comprehension **Struggling under Frustration**. |
| D16 | BOSY masterlist / SRP: no code change. Consequence of D6: a learner with only a GST at BOSY is Struggling and therefore listed as not grade level ready until the reading is in (accepted by the owner). ARAL report and roster placement: no change. |
| D17 | Results stay computed from raw readings with the current rules (bands spec D8, amended); the assessment status is never stored. |
| D18 | Import spec D9 amended (same commit): a workbook row with words read + time but no comprehension imports as a word reading (comprehension not assessed); rows with only comprehension, or without a passage, stay skipped until R2. |

## Changes

### Rules (`lib/core/services/phil_iri_rules.dart`)
- `PhilIriThresholds.comprehensionStrugglingMax` (default 40, key `comprehension_struggling_max`, `toMap`/`fromMap` with the usual fallback); `validate()` checks `comprehensionStrugglingMax < comprehensionInstructionalMin < comprehensionIndependentMin`.
- `philIriComprehensionLevel`: `≤ comprehensionStrugglingMax` → `struggling`, then Frustration / Instructional / Independent as today.
- `_profileTable`: each row gets `_s:` → Struggling (Non-Reader row → Non-Reader). `philIriPassageProfile` keeps the `ArgumentError` for a Non-Reader comprehension only.

### Results (`lib/core/services/phil_iri_results.dart`)
- New `enum PhilIriRoundStatus { assessed, carriedOver, notAssessed }`.
- `PhilIriRoundResult` gets `wordReadingAssessed`, `comprehensionAssessed`, `wordReadingAssumed` (bools, default false) and `status` (default `notAssessed`).
- `philIriRoundResults`: sets the D4 flags from the round's own reading; with comprehension known but no word reading so far, sets `wordReadingLevel = struggling`, `wordReadingAssumed = true` (accuracy, speed, scores null); adjusted level for a given round with a blank own comprehension uses the carried % (D8); `status` per D4. The header comment gets the new rules.
- `philIriNotAssessedResult`: profile `struggling`, 3 levels down (D9).

### ViewModels
- `NlaReportViewModel`: `assessedIn` per D11; progress adds `carriedOver` / `notAssessed` counts per round (D12) and CSV columns; Form 2b fixes (D15).
- `ReminderViewModel`: no-GST BOSY line for tutors (D13); counts via `assessedIn`.
- `DashboardViewModel`: `RoundSnapshot.carriedOver` (D14).
- Console: thresholds commands accept the new key; progress, reminders and dashboard output print the new counts/line; Phil-IRI result lines print "Not assessed" for an assumed word reading.

### Storage
- Cloud migration `supabase/migrations/20261109020000_phil_iri_rules_update.sql` (`App update required on all devices: yes`): drop and re-add `phil_iri_readings_comprehension_level_check` allowing `'struggling'`; insert its `basa_migrations` row (`app_update_required = true`). No new tables/views, so no grants; RLS policies unaffected (checked on PG18 with `RETURNING`). Id added to `lib/core/release.dart`; README 2b line.
- SQLite v41: rebuild `phil_iri_readings` with the widened CHECK as v39 did (with the `legacy_alter_table` guard), triggers recreated by `createPhilIriLocalSchema`.
- Saved thresholds and snapshots: nothing to migrate (missing key = 40).

## Testing
- Unit (TDD): Table 8 Struggling column for every row; comprehension edges 40/41, 58/59; `validate()`; snapshot without the key; new `test/core/services/phil_iri_round_status_test.dart` (assessed; carried from an earlier round; GST-only BOSY = carried over + Struggling + assumed, adjusted from the GST; FLT = word reading assessed only; blank comprehension adjusted from the carried %; silent counts; nothing all year = Struggling, 3 down, flagged).
- ViewModel tests: progress counts, the no-GST reminder, Form 2b Non-Reader and GST Struggling, dashboard carried count; existing tests that assumed "GST alone counts" updated.
- PG18: fresh build (baseline + all migrations), Struggling comprehension insert as tutor and coordinator with `RETURNING`; grants test passes. SQLite v40 → v41 upgrade keeps readings.
- Each task: `dart analyze`, `flutter test`, `check_tutor_imports`, `check_vm_boundary`. Command pass: new expectations for t4/a3 (levels), progress, reminders and dashboard lines; full run after the owner applies the migration on dev; verify kit `D:/0_CAPSTONE/verify/phil-iri-rules/`.

## Docs
`lib/core/CLAUDE.md` (Phil-IRI rules notes, v41), `CLAUDE.md` (Phil-IRI line), README 2b, `docs/handoff/screens/phil-iri.md` (status, assessed flags, carried-over column for the screens), import spec D9 (D18).

## Questions on ma's list (do not block R1)
Open:
- D2: what a Struggling comprehension gives for each word reading row (BASA: Struggling for every row; Non-Reader stays).
- FLT, resolved by the owner 2026-11-10 as a toggle: report_settings key `no_comprehension_counts_FLT` (school -> region -> off, **default off**; migration `20261110010000`, app update no; console `flt-counts`). On: a reading from a collection with `has_comprehension` false counts as assessed with words read and time (`PhilIriLearnerResults.comprehensionOptional` -> `philIriRoundResults(comprehensionOptional:)`); scoring unchanged. Still for ma: should schools turn it on, and is the FLT given to every learner or only to new enrollees/transferees?
- Blank answers (found 2026-11-10 while building the toggle, owner approved): a reading with no answer recorded at all is a blank comprehension (not 0 of N), so it is not assessed and its score takes the carried %; one recorded answer, even "x", is an entry (0 counts).
- Display (owner/UI): progress and dashboard show carried/not-assessed counts for rounds not yet open or not scheduled (e.g. "EOSY NOT SCHEDULED · carried 3"); blank them, or keep them?

Answered:
- D9 (no GST and no reading: Grade 1 as in the workbook, or 3 levels down): ma, 2026-11-09: every learner must have a GST and a reading, no exceptions. BASA keeps the 3-levels-down stand-in, flagged, and chases the gap with the BOSY no-GST reminder (D13).
