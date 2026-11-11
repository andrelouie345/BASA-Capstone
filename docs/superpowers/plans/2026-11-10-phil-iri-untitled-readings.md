# Phil-IRI imported Untitled and comprehension-only readings (R2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Imported Phil-IRI sessions can hold a reading with no passage ("Untitled", typed word count, comprehension over a stored total) and a reading with comprehension but no word reading; both score and get a round status.

**Architecture:** `phil_iri_readings.passage_id` becomes nullable (workbook imports only) with two new raw columns, `imported_word_count` and `imported_total`, enforced by the cloud triggers and the device triggers alike. Scoring (`phil_iri_results.dart`) learns "no word reading" (assumed Struggling, R1 D6); the session ViewModel feeds it. Nothing derived is stored.

**Tech Stack:** Dart (pure, no Flutter in `core/` and `viewmodels/`), sqflite_common_ffi (SQLite v42), Postgres/Supabase migration, PG18 throwaway harness.

**Spec:** `docs/superpowers/specs/2026-11-10-phil-iri-untitled-readings-design.md` (D1–D13). Import spec D9 is already amended.

## Global Constraints

- Migration `supabase/migrations/20261110020000_phil_iri_untitled_readings.sql`, header `App update required on all devices: yes`; ends with its `basa_migrations` row (`app_update_required = true`); id added to `lib/core/release.dart`; README 2b line. Never edit the baseline.
- SQLite version 41 → **42**.
- `passage_id` null **only** when the session's `import_source = 'workbook'` (D3). Live sessions and scoresheet imports keep a required passage.
- `imported_word_count` > 0, only with a null passage, required for `whole_text`/`silent` with a null passage (D4).
- `imported_total` > 0, only with a null passage, only together with `imported_correct`, `imported_correct <= imported_total` (D5). With a null passage, `imported_correct` needs `imported_total`.
- A reading with no passage takes no answers and only miscues without a position.
- Untimed readings score only in imported sessions (`import_source` not null); live sessions still refuse completion untimed (D1, D6).
- Display label for a null passage: exactly `Untitled` (D12).
- No new table or view → no grants; RLS unchanged (goes through the session), verified on PG18 with `RETURNING`.
- After every task: `dart analyze` (0 errors), `flutter test --concurrency=2`, `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart`. No git commands by the implementer; stop after each task for the owner (CLAUDE.local.md); give a commit message. Backend branch `excelsior`.
- Steps that run the suite or the command pass carry: **DO NOT PLAY RESOURCE INTENSIVE GAMES**.

## Review Focus

1. **The cloud miscue check after a null passage**: today it inner-joins the reading to `phil_iri_passages`, so with no passage `v_import` stays null and even an imported unpositioned miscue is refused. Expect: imported unpositioned miscue accepted, positioned refused. PG18 test in Task 1.
2. **A positioned miscue on an Untitled reading on the device**: the device position check compares against a NULL word count and silently passes. Expect: refused. SQLite test in Task 1.
3. **Untitled reading with `imported_correct` but no `imported_total`** (the reader found no header maximum and the writer forgot to drop the count): expect a CHECK failure, never a reading scored over a null total. Test in Task 1 (both sides).
4. **A live ViewModel call on an Untitled reading** (`saveTiming`, `saveObservation`, `markMiscue`, `answer`, `silentReadingFollowedUp`, through `_requireOpenReading`/`_requirePassage(null)`): expect a `ViewModelException` "This reading was imported without a passage (Untitled) and cannot be edited here.", never a null-check crash. Test in Task 2.
5. **`_blockedTexts` / `_silentReadingFollowedUp` when the learner has an Untitled reading in another session**: a live reading of any real passage must not crash or be blocked by it. Test in Task 2.

---

### Task 1: Storage (cloud migration, SQLite v42, model)

**Files:**
- Create: `supabase/migrations/20261110020000_phil_iri_untitled_readings.sql`
- Modify: `lib/core/release.dart`, `README.md` (2b), `lib/core/data/local/phil_iri_local_schema.dart` (`_readingsTableSql`, `rebuildPhilIriReadingsForV42`, reading/miscue triggers), `lib/core/data/local/local_database.dart` (version 42, upgrade step), `lib/core/models/phil_iri_reading.dart`, `tool/command_pass/scenarios/` t1 version lines (the file holding the `basa_migrations` / release expectations; find with `grep -rn 20261110010000 tool/command_pass/scenarios`)
- Test: new `test/core/data/phil_iri_readings_v42_test.dart`; PG18 script in the session scratchpad (`pg/r2/`, recipe in memory `pg-test-harness`)

**Interfaces:**
- Produces: `PhilIriReading.passageId` is `int?`; new `int? importedWordCount`, `int? importedTotal` (map keys `imported_word_count`, `imported_total`, written only when non-null like `imported_correct`); `bool get isUntitled => passageId == null`. `rebuildPhilIriReadingsForV42(Database db)` (replaces the v41 call: upgrade runs it for `26 <= oldVersion < 42`; the v41 function is deleted, as v41 folded v39).

- [ ] **Step 1: Failing SQLite tests** in `phil_iri_readings_v42_test.dart` (fresh db through `LocalDatabase`, seeded section/learner/passage as in `phil_iri_import_v40_test.dart`):
  - `untitled whole text on a workbook session is stored`: insert `passage_id` null, method `whole_text`, `reading_seconds` 90, `imported_word_count` 120, `imported_correct` 5, `imported_total` 8 → row read back via `PhilIriReading.fromMap` has `isUntitled`, `importedWordCount == 120`, `importedTotal == 8`.
  - `untitled one minute needs no word count`: `words_read` 70, no count → stored.
  - `comprehension-only reading with a passage is stored untimed`: workbook session, passage set, no seconds/words, `imported_correct` 3 → stored.
  - refusals (each `expect(..., throwsA(isA<DatabaseException>()))`): null passage on a live session; on a `scoresheet` session; Untitled `whole_text` without `imported_word_count`; `imported_word_count` with a passage; `imported_total` without `imported_correct`; Untitled with `imported_correct` 5 and no `imported_total`; `imported_correct` 9 > `imported_total` 8; a positioned miscue (`word_index` 3) on an Untitled reading; an answer row on an Untitled reading.
  - accepted: an unpositioned miscue on an Untitled reading.
  - `v41 database upgrades to v42 keeping readings`: build a v41 file (create at 41 through the existing creators as `phil_iri_readings_v41_test.dart` does), insert a reading, reopen at 42 → reading intact, `PRAGMA table_info` shows `passage_id` notnull 0 and both new columns.
- [ ] **Step 2: Run** `flutter test test/core/data/phil_iri_readings_v42_test.dart` → FAIL (NOT NULL / missing columns).
- [ ] **Step 3: Device schema.** `_readingsTableSql`: `passage_id INTEGER REFERENCES phil_iri_passages(id)` (nullable), `imported_word_count INTEGER CHECK (imported_word_count > 0)`, `imported_total INTEGER CHECK (imported_total > 0)`, plus table CHECKs:
  `CHECK (passage_id IS NULL OR (imported_word_count IS NULL AND imported_total IS NULL))`,
  `CHECK (passage_id IS NOT NULL OR method = 'one_minute' OR imported_word_count IS NOT NULL)`,
  `CHECK (imported_total IS NULL OR (imported_correct IS NOT NULL AND imported_correct <= imported_total))`,
  `CHECK (passage_id IS NOT NULL OR imported_correct IS NULL OR imported_total IS NOT NULL)`.
  `rebuildPhilIriReadingsForV42` = the v41 body with temp table `phil_iri_readings_v42`. `local_database.dart`: version 42 with the comment line (cloud 20261110020000), upgrade `if (oldVersion >= 26 && oldVersion < 42) await rebuildPhilIriReadingsForV42(db);`.
  Triggers in `createPhilIriLocalSchema`: `check_phil_iri_reading_ins` first raises `'A reading without a passage belongs to a session imported from the workbook'` when `NEW.passage_id IS NULL AND $sessionImport IS NOT 'workbook'`; `'No such passage'` only when `NEW.passage_id IS NOT NULL`; the passage-based checks already compare NULL safely, but add `NEW.passage_id IS NOT NULL AND` to the active, own-grade, round and no-repeat WHEREs so the intent is explicit. `importedCorrectCheck`'s question-count line applies only when `NEW.passage_id IS NOT NULL`. `miscueCheck` gains `'A reading without a passage takes only miscues without a position'` when `NEW.word_index IS NOT NULL AND (SELECT passage_id FROM phil_iri_readings WHERE id = NEW.reading_id) IS NULL`. Answers: the existing passage-match check already refuses (question passage = NULL is not true); keep, test covers it.
- [ ] **Step 4: Model.** `PhilIriReading` per Interfaces; `fromMap` reads `passage_id as int?`.
- [ ] **Step 5: Run** the new test file → PASS; then `flutter test --concurrency=2` (**DO NOT PLAY RESOURCE INTENSIVE GAMES**). `passageId` is now nullable: make the minimal compile fixes in `phil_iri_viewmodel.dart` and `phil_iri_commands.dart` with `!` (every reading these paths see still has a passage until an import writes one; Task 2 replaces each `!` with real handling). `dart analyze` 0 errors, suite green at the end of this task.
- [ ] **Step 6: Cloud migration** (copy the header style of `20261110010000`): `alter column passage_id drop not null`; add both columns with `if not exists` and the four CHECKs named `phil_iri_readings_untitled_*`; `create or replace` of `check_phil_iri_reading` (from `20261109010000` §3) with a null-passage branch at the top after the writable check: refuse unless the session's `import_source = 'workbook'` (`'a reading without a passage belongs to a session imported from the workbook'`), then skip `phil_iri_passage_readable`, the passage lookups and the no-repeat query, keep the `imported_correct` checks except the question count (which runs only with a passage); `check_phil_iri_miscue` with **left** joins to passages, raising `'a reading without a passage takes only miscues without a position'` for a positioned miscue on a null passage; `check_phil_iri_answer` unchanged (the null comparison already refuses; test it). End with the `basa_migrations` insert. `release.dart` gets the id; README 2b line ("yes: readings without a passage; update every device first").
- [ ] **Step 7: PG18** (harness: auth stubs + baseline + every migration in order, fresh build): as a coordinator, insert with `RETURNING` an Untitled whole-text reading on a workbook session (passes), an unpositioned miscue on it (passes), a positioned miscue (refused), an answer (refused); a null-passage reading on a live session as tutor (refused) and as coordinator (refused); Untitled with `imported_correct` and no `imported_total` (refused); comprehension-only with passage, untimed (passes). Run `flutter test test/supabase/migration_grants_test.dart` → PASS. Record N/N in the task report.
- [ ] **Step 8: t1 scenario version lines** for the new migration id (same edit the FLT piece made for `20261110010000`).
- [ ] **Step 9: Checks + verify kit** `D:/0_CAPSTONE/verify/phil-iri-untitled/t1/` (the PG18 SQL with expected lines; SQLite check script). Stop for the owner; commit message `feat(phil-iri,sqlite): readings without a passage for workbook imports (storage)`. Do **not** ask the owner to apply the migration on dev until Task 3.

### Task 2: Scoring, status and the session ViewModel

**Files:**
- Modify: `lib/core/services/phil_iri_results.dart`, `lib/viewmodels/phil_iri_viewmodel.dart`, `lib/core/console/commands/phil_iri_commands.dart` (`_resultText` and the reading line only as needed to compile and print "not assessed"/"Untitled"; full display pass is Task 3), `lib/viewmodels/srp_viewmodel.dart` (only if it stops compiling)
- Test: `test/core/services/phil_iri_round_status_test.dart`, `test/core/services/phil_iri_table8_test.dart` (scorePassage cases), `test/viewmodels/phil_iri_imported_scoring_test.dart`

**Interfaces:**
- Consumes: Task 1's `PhilIriReading.passageId` (`int?`), `importedWordCount`, `importedTotal`, `isUntitled`.
- Produces:
  - `philIriScorePassage({int? wordCount, required PhilIriReadingMethod method, int? readingSeconds, int? wordsRead, required int countedMiscues, int? comprehensionCorrect, int? comprehensionTotal, PhilIriThresholds t, bool allowNoWordReading = false})`. Word reading is recorded when whole text/silent has `readingSeconds` (and then `wordCount` is required, `ArgumentError` otherwise) or one minute has `wordsRead > 0`. Not recorded + `allowNoWordReading` → result with no word reading; not recorded + false → `ArgumentError` as today.
  - `PhilIriPassageResult`: `wordReadingScore`, `wordsPerMinute`, `accuracyLevel`, `speed`, `wordReadingLevel` become nullable; new `final bool wordReadingAssumed` (true iff no word reading); `wordReadingPercent` → `int?`. With no word reading: `profile = _profile(PhilIriLevel.struggling, compLevel)`.
  - `philIriRoundResults`: an own reading with `wordReadingAssumed` adds nothing to the oral/silent maxima; `wordReadingAssessed = own != null && !own.wordReadingAssumed`. `actual` profile/adjusted for such a round use its own result as is.
  - `PhilIriViewModel`: untimed readings of an imported session are scored (learner results and finalize); `complete()` skips the timing checks when `session.importSource != null`; `_requireOpenReading` on an Untitled reading throws `ViewModelException('This reading was imported without a passage (Untitled) and cannot be edited here.')`, except `deleteReading`, which checks the open session via `_findReading` + `_requireOpenSession` so an Untitled reading can still be removed; `silentReadingFollowedUp` returns null for an Untitled reading. Every `!` added in Task 1 is gone.

- [ ] **Step 1: Failing unit tests (scoring)**, in `phil_iri_table8_test.dart` or a new group in the round status file:
  - `untitled whole text uses the typed word count`: `wordCount: 120, readingSeconds: 60, countedMiscues: 6` → `wordReadingScore == 114/120`, `wordsPerMinute == 120`.
  - `one minute needs no word count`: `wordsRead: 70, countedMiscues: 7` → score `63/70`.
  - `whole text with seconds but no word count throws ArgumentError`.
  - `no word reading with allowNoWordReading`: `method: wholeText`, no seconds, `comprehensionCorrect: 6, comprehensionTotal: 8, allowNoWordReading: true` → `wordReadingLevel == null`, `wordReadingAssumed`, `comprehensionLevel` = level of 0.75, `profile == philIriPassageProfile(PhilIriLevel.struggling, that level)`.
  - `no word reading without the flag still throws`.
- [ ] **Step 2: Failing round tests** (`phil_iri_round_status_test.dart`):
  - `comprehension-only round is carried over`: BOSY oral reading (assessed), MOSY 1 comprehension-only → MOSY 1 `status == carriedOver`, `wordReadingAssessed == false`, `comprehensionAssessed == true`, word reading level = BOSY's, comprehension = higher of the two (carry rule).
  - `comprehension-only with nothing earlier`: only MOSY 1 comprehension-only, no GST → `wordReadingLevel == struggling`, `wordReadingAssumed`, `status == carriedOver`.
  - `FLT toggle does not make a comprehension-only round assessed`: `comprehensionOptional: {mosy1}` → still `carriedOver`.
  - `comprehension-only round adjusts from its own percent`: Frustration-band comprehension → `adjustedLevel` from that % (R1 D8).
- [ ] **Step 3: Failing ViewModel tests** (`phil_iri_imported_scoring_test.dart`, same seeding as its existing tests):
  - `untitled workbook reading scores with imported total`: session `import_source = 'workbook'`, reading `passageId: null, method: wholeText, readingSeconds: 60, importedWordCount: 120, importedCorrect: 6, importedTotal: 8` → `learnerResults` round has comprehension 0.75 and a word reading.
  - `comprehension-only imported reading is scored, not skipped`: passage set, untimed, `importedCorrect: 4` → round `status == carriedOver`, comprehension known.
  - `complete() accepts an untimed imported session; a live untimed session is still refused` (message unchanged).
  - `finalize stores null word reading columns for a comprehension-only reading`.
  - Review Focus 4: each of `saveTiming`, `saveObservation`, `markMiscue`, `answer` on the Untitled reading throws the exact message above; `silentReadingFollowedUp` returns null; `deleteReading` on it (open imported session) succeeds.
  - Review Focus 5: learner with an Untitled reading in BOSY starts a live MOSY 1 reading of a real passage → succeeds (`_blockedTexts` skips null passages).
- [ ] **Step 4: Run** those three test files → FAIL.
- [ ] **Step 5: Implement** per Interfaces. ViewModel specifics: `_scoreReading` takes the word count from the passage, or `importedWordCount` when Untitled; comprehension total from the passage's questions (unchanged), or `importedTotal` with `importedCorrect` when Untitled (no total → blank); passes `allowNoWordReading: session.importSource != null` (look the session up once per call; `learnerResults` already has it). The two `continue // not timed yet` lines in `learnerResults` skip only when `importSource == null`. FLT check (`_noComprehensionCountsFlt` branch) skips Untitled readings (no collection). `_blockedTexts` / `_silentReadingFollowedUp`: `if (r.passageId == null) continue;`. Finalize writes the nullable fields as they are.
- [ ] **Step 6: Run** the three files → PASS; `flutter test --concurrency=2` (**DO NOT PLAY RESOURCE INTENSIVE GAMES**); fix other users broken by nullable fields (`srp_viewmodel.dart` already null-safe at line 224; console `_resultText` prints `word reading not assessed` when `wordReadingAssumed`). Checks. Kit `D:/0_CAPSTONE/verify/phil-iri-untitled/t2/`: no console command creates an imported session yet, so the kit is a SQL script that inserts one workbook session with an Untitled and a comprehension-only reading into a copy of a fresh `./data` database, then the console's Phil-IRI learner results command on it with the expected lines. Stop for the owner; commit message `feat(phil-iri): score Untitled and comprehension-only imported readings`.

### Task 3: Display, console, import plan amendments, docs, rollout

**Files:**
- Modify: `lib/core/models/phil_iri_import.dart` (Step 2a), `lib/core/console/commands/phil_iri_commands.dart` (session listing at ~line 109: `Reading N: Untitled (M words typed)` for a null passage; `vm.passage` called only with a non-null id), `docs/superpowers/plans/2026-11-09-phil-iri-import.md` (Tasks 6, 8, 9), `lib/core/CLAUDE.md` (Phil-IRI notes, v42), `CLAUDE.md` (Phil-IRI line: R2 sentence with the spec path), `docs/handoff/screens/phil-iri.md` (null passage shows "Untitled"; `wordReadingAssumed` on a passage result shows "Not assessed"), `tool/command_pass/scenarios/*` only where printed output changes (expect none outside t1)
- Test: console output covered by a new case in an existing console test if one prints session readings (`grep -rln "Reading .*: passage" test`); otherwise the command pass

- [ ] **Step 1: Console display** per Files; the reading line for an Untitled reading prints `Reading <id>: Untitled (<n> words, typed)` or `Reading <id>: Untitled` (one minute).
- [ ] **Step 2a: Import model** (`lib/core/models/phil_iri_import.dart`): `PhilIriImportReading.passage` → `PhilIriImportPassageRef?` (null = Untitled), new `final int? wordCount` and `final int? correctTotal`; fix the existing callers/tests (`grep -rln PhilIriImportReading lib test`). Test: a model test constructing an Untitled reading (`passage: null, wordCount: 120, correctCount: 5, correctTotal: 8`) round-trips its fields.
- [ ] **Step 2b: Import plan amendments** (text only): Task 6 rules — a block with words read + time and a blank passage → Untitled reading (`passage: null`; whole text/silent: words-read cell → `wordCount`; comprehension → `correctCount` + `correctTotal` = header maximum, none → comprehension dropped + flagged); comprehension only → comprehension-only reading, miscue counts dropped + flagged; passage only → skipped incomplete. Task 5 model note: `PhilIriImportReading.passage` nullable, new `int? wordCount`, `int? correctTotal`. Task 8: writes `passage_id` null, `imported_word_count`, `imported_total`. Task 9: Untitled outcome "import, flagged: no passage (Untitled)", D7/D8 checks skipped for it. Scoresheet: blank passage code stays a problem; comprehension-only rows import.
- [ ] **Step 3: Docs** per Files.
- [ ] **Step 4: Owner applies** `20261110020000` on dev after every device has synced (app update **yes**; sign-in refused until applied). Give the owner the GC line.
- [ ] **Step 5: Full command pass**, new run (**DO NOT PLAY RESOURCE INTENSIVE GAMES**; ~8–9 min): `dart run tool/command_pass/run.dart` → report clean (last: r28 374/374). Fix scenario lines only where output legitimately changed.
- [ ] **Step 6: Kit** `D:/0_CAPSTONE/verify/phil-iri-untitled/README.md` (what to check: v42 upgrade on the owner's device copy, PG18 lines, the pass run). Stop for the owner; commit message `docs(phil-iri): Untitled readings display, import plan amendments, R2 docs`. Then the final whole-branch review (fresh reviewer, the three R2 commits + spec commit).
