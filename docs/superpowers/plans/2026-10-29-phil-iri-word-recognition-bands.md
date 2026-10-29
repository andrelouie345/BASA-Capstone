# Phil-IRI word recognition bands and Table 8 profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Score Phil-IRI readings with DepEd's new word recognition bands (Non-Reader ≤35, Struggling 36–55, Frustration 56–89) and ma's Table 8 profile lookups, storing Struggling as its own level.

**Architecture:** The rules stay pure Dart in `phil_iri_rules.dart` / `phil_iri_results.dart` (two constant lookup tables replace today's word-reading and profile rules). The new stored value `struggling` needs a cloud migration (widened CHECKs, app update required) and a SQLite v39 rebuild of `phil_iri_readings`. Reports use one shared "not grade level ready" predicate.

**Tech Stack:** Dart (pure, no Flutter in core), sqflite_common_ffi, Supabase Postgres migrations, flutter_test, PG18 throwaway harness, the console command pass.

**Spec:** `docs/superpowers/specs/2026-10-29-phil-iri-word-recognition-bands-design.md` (decisions D1–D10, the two lookup tables).

## Global Constraints

- Band defaults: `nonReaderMax` 35, new `wordReadingStrugglingMax` 55 (key `word_reading_struggling_max`), `wordReadingInstructionalMin` 90, `wordReadingIndependentMin` 97 (unchanged). Whole percents, rounded half up as today.
- The two lookups are the spec's tables exactly, fixed (not thresholds).
- Stored value for the new level: `struggling` (enum `PhilIriLevel.struggling`, label `'Struggling'`).
- Finalized sessions keep their stored levels and snapshot: no backfill, no re-scoring (D8).
- Migration id `20261029010000`, name `phil_iri_struggling_level`, header `App update required on all devices: yes` plus the "Apply only when all work is finalized…" line (README 2b rule); last statement = its `basa_migrations` row (`true`); same commit adds it to `lib/core/release.dart`.
- SQLite version 38 → 39.
- `core/` never imports Flutter. Backend only: no UI files.
- After each task: `dart analyze` (no errors), `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart`. **DO NOT PLAY RESOURCE INTENSIVE GAMES** while tests and the command pass run.
- Owner rules: no git commands by Claude; each task ends with the commit message for the owner. Ask the owner to close any open BASA console before console/pass runs.

## Review Focus

1. A session finalized before the update (stored `frustration`/`nonReader`, snapshot with `non_reader_max` 50 and no struggling key) still shows its stored levels; the results code must not re-score it — Task 1 test `finalized snapshot without struggling key loads with 55` + Task 2 upgrade test keeps stored levels.
2. A pulled cloud row with `profile = 'struggling'` on a v39 device and `PhilIriLevel.fromString('struggling')` — Task 1 test `fromString parses struggling`.
3. Thresholds a school edits after the update: `phil-iri-threshold-set word_reading_struggling_max 30` with `non_reader_max` 35 must be refused (bands must increase) — Task 1 test `validate refuses struggling max at or below non-reader max`.
4. A one-minute or silent reading at the band edges (35/36, 55/56, 89/90) — Task 1 band-edge tests.
5. The end-of-year "best round" when one round is Struggling and another Frustration: Frustration wins — Task 1 test `end result prefers Frustration over Struggling`.

---

### Task 1: Rules, results, reports and console

**Files:**
- Modify: `lib/core/services/phil_iri_rules.dart` (enum, thresholds, accuracy level, both lookups, remove `philIriIsStrugglingReader`)
- Modify: `lib/core/services/phil_iri_results.dart` (remove `isStrugglingReader`, adjusted level, `_rank`, new predicate)
- Modify: `lib/viewmodels/nla_report_viewmodel.dart:486`, `lib/viewmodels/srp_viewmodel.dart:215` (use the predicate)
- Modify: `lib/core/console/commands/phil_iri_commands.dart:438-447` (drop the "· Struggling Reader" suffix)
- Create: `test/core/services/phil_iri_table8_test.dart`
- Modify: `test/core/services/phil_iri_result_getters_test.dart` (drop `isStrugglingReader:` arguments)

**Interfaces:**
- Produces: `PhilIriLevel.struggling` (between `frustration` and `nonReader`, label `'Struggling'`); `PhilIriThresholds.wordReadingStrugglingMax` (int, default 55, map key `word_reading_struggling_max`); `philIriWordReadingLevel(PhilIriLevel accuracy, PhilIriSpeed speed) -> PhilIriLevel` (Lookup 1); `philIriPassageProfile(PhilIriLevel wordReading, PhilIriLevel comprehension) -> PhilIriLevel` (Lookup 2); `bool philIriNotGradeReady(PhilIriLevel? profile)` in `phil_iri_results.dart` (true for frustration, struggling, nonReader).
- Removed: `philIriIsStrugglingReader`, `PhilIriPassageResult.isStrugglingReader`, `PhilIriRoundResult.isStrugglingReader`.

- [ ] **Step 1: Write the failing tests** in `test/core/services/phil_iri_table8_test.dart`:
  - `lookup 1 every cell`: loop over the spec's Lookup 1 table (5 accuracy rows × 4 speeds) and `expect(philIriWordReadingLevel(a, s), want)`.
  - `lookup 2 every cell`: the spec's Lookup 2 table (5 × 3) with `philIriPassageProfile`.
  - `comprehension struggling or non-reader is an error`: `expect(() => philIriPassageProfile(PhilIriLevel.instructional, PhilIriLevel.struggling), throwsArgumentError)` and the same for `nonReader`.
  - `band edges`: `philIriAccuracyLevel(0.35)` nonReader, `0.36` struggling, `0.55` struggling, `0.56` frustration, `0.89` frustration, `0.90` instructional, `0.97` independent; and `0.355` → 36 → struggling (rounding).
  - `struggling adjusted level equals frustration's`: for comprehension 0.20, 0.27, 0.40, 0.60, 0.79 and grade 7, `philIriAdjustedLevel(PhilIriLevel.struggling, 7, c) == philIriAdjustedLevel(PhilIriLevel.frustration, 7, c)`; `philIriAdjustedLevel(PhilIriLevel.nonReader, 7, 0.9) == 0`.
  - `end result prefers Frustration over Struggling`: two given rounds (mosy1 profile struggling, mosy2 profile frustration, no EOSY) → `philIriEndResult(...)!.round == PhilIriRound.mosy2`; and frustration in mosy1, struggling in mosy2 → mosy1.
  - `not grade ready`: `philIriNotGradeReady` true for frustration, struggling, nonReader; false for instructional, independent, null.
  - `finalized snapshot without struggling key loads with 55`: `PhilIriThresholds.fromMap({'non_reader_max': 50}).wordReadingStrugglingMax == 55` and `.nonReaderMax == 50`.
  - `defaults`: `PhilIriThresholds.defaults.nonReaderMax == 35`, `.wordReadingStrugglingMax == 55`, `toMap()['word_reading_struggling_max'] == 55`.
  - `validate refuses struggling max at or below non-reader max`: `PhilIriThresholds(nonReaderMax: 35, wordReadingStrugglingMax: 30).validate` throws `ArgumentError`; `wordReadingStrugglingMax: 90` (= instructional min) throws too.
  - `fromString parses struggling`: `PhilIriLevel.fromString('struggling') == PhilIriLevel.struggling` and `fromString('Struggling')` too.
  - `scorePassage uses the table`: `philIriScorePassage(wordCount: 60, method: PhilIriReadingMethod.oneMinute, wordsRead: 60, countedMiscues: 7, comprehensionCorrect: 3, comprehensionTotal: 10)` → `accuracyLevel` frustration, `speed` struggling, `wordReadingLevel` struggling, `profile` struggling (the command pass's learner B).

- [ ] **Step 2: Run them to see them fail**
  Run: `flutter test test/core/services/phil_iri_table8_test.dart`
  Expected: compile errors (`struggling`, `wordReadingStrugglingMax`, `philIriNotGradeReady` undefined).

- [ ] **Step 3: Implement the rules** in `phil_iri_rules.dart`:
  - enum order `independent, instructional, frustration, struggling, nonReader`.
  - `PhilIriThresholds`: field `wordReadingStrugglingMax` (comment: `≤ this: Struggling (above Non-Reader)`), constructor default 55, `nonReaderMax` default 35, `toMap`/`fromMap` key `word_reading_struggling_max`; `validate()` word-reading order becomes `[nonReaderMax, wordReadingStrugglingMax, wordReadingInstructionalMin, wordReadingIndependentMin]`.
  - `philIriAccuracyLevel`: `≤ nonReaderMax` nonReader, `≤ wordReadingStrugglingMax` struggling, `≥ independentMin` independent, `≥ instructionalMin` instructional, else frustration.
  - Lookups as `const Map<PhilIriLevel, Map<PhilIriSpeed, PhilIriLevel>>` / `Map<PhilIriLevel, Map<PhilIriLevel, PhilIriLevel>>` copied from the spec; the function throws `ArgumentError` for a comprehension that isn't independent/instructional/frustration.
  - Update the file header comment (Table 8 replaces "Independent needs Fast" and "profile = comprehension level"; cite the spec) and delete `philIriIsStrugglingReader` with its doc.

- [ ] **Step 4: Implement results and callers**
  - `phil_iri_results.dart`: remove `isStrugglingReader` (both classes, constructors, the two assignment sites); `philIriAdjustedLevel`: `case PhilIriLevel.frustration || PhilIriLevel.struggling:`; `_adjusted`'s GST branch condition becomes `(profile == frustration || profile == struggling)`; `_rank`: independent 4, instructional 3, frustration 2, struggling 1, nonReader 0, null −1; add `bool philIriNotGradeReady(PhilIriLevel? profile)`. Update the doc comments that say "a Struggling Reader is not a Non-Reader" to the new meaning.
  - `nla_report_viewmodel.dart:486` and `srp_viewmodel.dart:215`: `if (!philIriNotGradeReady(profile)) continue;`.
  - `phil_iri_commands.dart`: remove both `isStrugglingReader` suffixes.
  - `phil_iri_result_getters_test.dart`: remove the `isStrugglingReader:` arguments.
  - Run `dart analyze`; fix any other non-exhaustive `switch` over `PhilIriLevel` (treat `struggling` like `frustration` unless the switch is a label).

- [ ] **Step 5: Run tests**
  Run: `flutter test test/core/services/` then `flutter test`
  Expected: all pass (suite ≈ 296 + the new tests).

- [ ] **Step 6: Checks + commit message**
  Run `dart analyze`, both tool checks. Give the owner:
  `feat(phil-iri): Table 8 profiles and the Struggling word recognition band`

### Task 2: Storage — cloud migration and SQLite v39

**Files:**
- Create: `supabase/migrations/20261029010000_phil_iri_struggling_level.sql`
- Modify: `lib/core/release.dart` (add `'20261029010000': 'phil_iri_struggling_level'`)
- Modify: `lib/core/data/local/phil_iri_local_schema.dart` (`_readingsTableSql` CHECKs; new `rebuildPhilIriReadingsForV39`)
- Modify: `lib/core/data/local/local_database.dart` (version 39, comment, upgrade call)
- Modify: `tool/command_pass/scenarios/21_t1.pass:12-13` (latest migration id)
- Modify: `README.md` 2b (migration line)
- Create: `test/core/data/phil_iri_readings_v39_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1 at the type level (the stored strings are `PhilIriLevel.name`).
- Produces: `Future<void> rebuildPhilIriReadingsForV39(Database db)` and `Future<void> stripSavedNonReaderMaxForV39(Database db)` in `phil_iri_local_schema.dart`.

- [ ] **Step 1: Write the failing SQLite test** `phil_iri_readings_v39_test.dart`, pattern of `aral_classes_v38_test.dart`: build a v38-shaped `phil_iri_readings` (today's `_readingsTableSql` text with the old CHECKs, plus `row_version INTEGER`) with one finalized row (`accuracy_level 'frustration'`, `word_reading_level 'nonReader'`, `profile 'nonReader'`, `row_version 7`), and a `phil_iri_thresholds` row with settings `{"non_reader_max":50,"speed_slow_max":120}`; run the v38→v39 upgrade path (`rebuildPhilIriReadingsForV39`, `createPhilIriLocalSchema`, `stripSavedNonReaderMaxForV39`). Assert:
  - `keeps the finalized row`: same id, levels, `row_version` 7.
  - `accepts struggling`: an insert with `profile = 'struggling'` succeeds; `profile = 'other'` throws.
  - `drops the saved non-reader cut-off`: the thresholds row's settings decode to `{"speed_slow_max":120}`.
  - `no-op without the tables`: on an empty database both functions return without error.

- [ ] **Step 2: Run it to see it fail**
  Run: `flutter test test/core/data/phil_iri_readings_v39_test.dart`
  Expected: FAIL (`rebuildPhilIriReadingsForV39` undefined).

- [ ] **Step 3: Implement the device side**
  - `_readingsTableSql`: `accuracy_level`, `word_reading_level`, `profile` CHECK lists gain `'struggling'` (comprehension unchanged).
  - `rebuildPhilIriReadingsForV39`: same shape as the v26 function (drop triggers that mention the table, create `phil_iri_readings_v39`, copy, drop, rename), but the column list comes from `PRAGMA table_info(phil_iri_readings)` (so `row_version` is copied; add `row_version INTEGER` to the new table with `ALTER TABLE` when the old one has it, before copying), as `rebuildAralClassesForV38` does. It returns early when the table doesn't exist.
  - `stripSavedNonReaderMaxForV39(Database db)`: `UPDATE phil_iri_thresholds SET settings = json_remove(settings, '$.non_reader_max')`, returning early when the table doesn't exist.
  - `local_database.dart`: `version: 39`, a `// v39:` comment line (spec, cloud 20261029010000); in `onUpgrade` right after the v26 line: `if (oldVersion >= 26 && oldVersion < 39) await rebuildPhilIriReadingsForV39(db);` (a device older than v26 is rebuilt by v26, which already uses the widened `_readingsTableSql`) and, after `createPhilIriLocalSchema`, `if (oldVersion < 39) await stripSavedNonReaderMaxForV39(db);`.

- [ ] **Step 4: Run the SQLite test**
  Run: `flutter test test/core/data/phil_iri_readings_v39_test.dart`
  Expected: PASS.

- [ ] **Step 5: Write the cloud migration** `20261029010000_phil_iri_struggling_level.sql`: header (purpose, spec path, idempotent, `App update required on all devices: yes`, the "Apply only when all work is finalized…" line, D8 note: finalized rows untouched); for each of `phil_iri_readings_accuracy_level_check`, `phil_iri_readings_word_reading_level_check`, `phil_iri_readings_profile_check`: `alter table … drop constraint if exists …; alter table … add constraint … check (col = any (array['independent','instructional','frustration','struggling','nonReader']))`; `update public.phil_iri_thresholds set settings = settings - 'non_reader_max' where settings ? 'non_reader_max';`; last statement the ledger row `('20261029010000', 'phil_iri_struggling_level', true)`. No table/view created (grant test stays green), no policy touched.

- [ ] **Step 6: Test the migration on the PG18 harness** (memory `pg-test-harness`: stubs + every migration + seeds, the new one twice). Checks, as postgres:
  - insert a reading with `profile 'struggling'` (and the two other columns) succeeds; `'other'` fails with a check violation;
  - a `phil_iri_thresholds` row seeded with `{"non_reader_max":50,"speed_slow_max":120}` before the migration ends as `{"speed_slow_max":120}`;
  - `select * from basa_migrations where id = '20261029010000'` → `app_update_required = true`.
  Stop the cluster and delete `pgdata` after.

- [ ] **Step 7: Release list, scenario, README**
  `release.dart` line; `21_t1.pass` lines 12–13 → `20261029010000`; README 2b: append the migration to the list with "app update required: **yes**, apply only when every device has synced and every upload is decided".

- [ ] **Step 8: Run tests + checks**
  Run: `flutter test` (includes `migration_grants_test.dart`, `command_sets_test.dart`), `dart analyze`, both tool checks.
  Expected: all pass.

- [ ] **Step 9: Commit message**
  `feat(phil-iri,supabase,sqlite): store the Struggling level (migration 20261029010000, SQLite v39)`

### Task 3: Command pass, docs, dev apply

**Files:**
- Modify: `tool/command_pass/scenarios/24_t4.pass` (header lines 5–10; lines 111, 165, 174, 179)
- Modify: `tool/command_pass/scenarios/33_a3.pass` (header lines 15–20; lines 204, 228, 230)
- Modify: `lib/core/CLAUDE.md` (Phil-IRI scoring notes), `CLAUDE.md` (Phil-IRI line: bands + Table 8 + spec path; SQLite v39 where versions are mentioned)
- Modify: `docs/handoff/screens/phil-iri.md` (and `reports.md` if it lists levels): five levels incl. Struggling; no `isStrugglingReader`
- Create: verify kit `D:/0_CAPSTONE/verify/phil-iri-bands/` (memory `verify-kits`)

**Interfaces:**
- Consumes: Task 1's levels and console output format (`_resultText`, `_roundText` unchanged apart from the removed suffix); Task 2's migration.

- [ ] **Step 1: Update the scenario expectations that Table 8 changes** (recompute each with the spec's lookups; header comments say why):
  - t4 learner A (99% Independent, Average, comp 80% Independent): word reading **Independent** (Ind × Average), profile Independent → line 111 `-> Independent;`, line 174 `WR 99% Independent, …`.
  - t4 learner B (88% Frustration, Struggling speed, comp 30%/50% Frustration): word reading **Struggling**, profile **Struggling** → lines 165, 179.
  - a3 (100% Independent, 120 wpm, comp 100% Independent): with speed Average the word reading becomes **Independent** → lines 204, 228 `-> Independent;`; with speed Slow it stays Instructional → line 230 unchanged. Profile Independent in all three.

- [ ] **Step 2: Docs** — `lib/core/CLAUDE.md`, `CLAUDE.md`, handoff screen docs as listed in Files; README already done in Task 2.

- [ ] **Step 3: Owner applies the migration on dev** — ask the owner to make sure no device has unsent work, then run `20261029010000_phil_iri_struggling_level.sql` twice in the SQL editor. Wait for confirmation. (Until then every build with Task 2 refuses to sign in to dev.)

- [ ] **Step 4: Full command pass**
  Ask the owner to close any open BASA console; run `dart run tool/command_pass/run.dart` (background). Expected: 0 failed, every command covered. A failure on a level line: recompute it with the spec's lookups; fix the expectation only when the new value is what Table 8 gives, otherwise it is a bug in Task 1.

- [ ] **Step 5: Verify kit** `D:/0_CAPSTONE/verify/phil-iri-bands/`: console files (as `zztest.tutor@basa.test`) that start a session, read with the four t4/a3 cases plus one 30% (Non-Reader) and one 45% (Struggling word recognition, Fast speed) reading, score them, and show results; expected outputs from Claude's own run; README with what each line shows.

- [ ] **Step 6: Commit message**
  `test(phil-iri),docs: Table 8 expectations in the command pass; docs for the Struggling level`
