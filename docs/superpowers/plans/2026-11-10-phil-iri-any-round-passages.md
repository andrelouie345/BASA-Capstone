# Phil-IRI passages in any round Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the round ↔ `test_type` passage rule from the cloud trigger, the SQLite trigger and the ViewModel, keep `test_type` as a label that only orders the passage list.

**Architecture:** One cloud migration replaces `check_phil_iri_reading()` without its `test_type` block; SQLite v43 is a version bump that recreates the Phil-IRI triggers without the round block; `PhilIriViewModel` drops the refusal and the list filter and sorts instead. No table, column, seed or policy changes.

**Tech Stack:** Dart/Flutter (pure-Dart core), sqflite_common_ffi, Supabase Postgres (PG18 throwaway cluster for tests).

**Spec:** `docs/superpowers/specs/2026-11-10-phil-iri-any-round-passages-design.md`

## Global Constraints

- Migration file `supabase/migrations/20261110030000_phil_iri_any_round_passages.sql`; header line `App update required on all devices: yes`; idempotent; ends by inserting its own `basa_migrations` row (`app_update_required` = true); id added to `lib/core/release.dart` as `'20261110030000': 'phil_iri_any_round_passages'`; README 2b lists it.
- SQLite `version: 43`, comment `// v43: Phil-IRI reading trigger no longer checks the round's test type (no table change; the bump makes onUpgrade recreate the triggers); cloud 20261110030000.`
- Unchanged: `test_type` column/CHECK/seeds, active-passage, own-grade, no-repeat (oral follow-up exception), one reading per session, Untitled and imported-session exemptions.
- List order (D4): follow-ups, then `p.testType == session.round.passageTestType`, then the rest, each group in today's order.
- Owner rules: no git by the implementer; stop after each task for owner verification and commit message. `flutter test --concurrency=2` (slow disk). Bold caps **DO NOT PLAY RESOURCE INTENSIVE GAMES** on steps that run the suite or the pass.

## Review Focus

- A silent reading's oral follow-up whose passage has another round's label still comes first (follow-up beats label) — Task 1 order test covers it.
- An unlabelled (null) passage in a graded collection and a non-graded collection (FRB) passage both still appear (in "the rest") — Task 1 list test.
- An older device's local DB at v42 opened by the new build accepts a cross-round reading (trigger really recreated, not left from v42) — Task 1 v43 test.
- No-repeat still refuses a cross-round text already read in an earlier round — Task 1 VM test and PG18 step.
- An imported session keeps working exactly as before (it already skipped the rule) — existing v40 test stays green apart from the flipped line.

---

### Task 1: Drop the round rule (cloud, SQLite, ViewModel)

**Files:**
- Create: `supabase/migrations/20261110030000_phil_iri_any_round_passages.sql`
- Modify: `lib/core/release.dart`, `README.md` (section 2b), `lib/core/data/local/local_database.dart:29-80` (comment + `version: 43`), `lib/core/data/local/phil_iri_local_schema.dart:599-609` (delete the v16 round block in the readings trigger), `lib/core/models/phil_iri_assessment.dart:46-49` (delete `allowsPassageTestType`; keep `passageTestType`), `lib/viewmodels/phil_iri_viewmodel.dart:317-345, 376-379`
- Test: create `test/viewmodels/phil_iri_any_round_test.dart` (setup modelled on `test/viewmodels/phil_iri_flt_counts_test.dart`), create `test/core/data/phil_iri_any_round_v43_test.dart` (modelled on `phil_iri_readings_v42_test.dart`), modify `test/core/data/phil_iri_import_v40_test.dart:165-166`
- PG18: scratchpad `pg/any_round_steps.sql` (stubs + baseline + migrations in order, new one twice; recipe in memory `pg-test-harness`)

**Interfaces:**
- Consumes: `PhilIriRound.passageTestType` (`'pre'|'mosy'|'post'`), `PhilIriViewModel.availablePassages(int assessmentId, {PhilIriReadingMethod method})`, `startReading(...)`.
- Produces: same signatures; `PhilIriRound.allowsPassageTestType` no longer exists.

- [ ] **Step 1: Write the failing VM tests** in `phil_iri_any_round_test.dart`, Grade 7 learner, passages of grade 7 labelled `pre`, `mosy`, `post` and null, plus one non-graded collection passage:
  - `BOSY lists every label, own-round label first`: `availablePassages(bosy)` holds all five; the `pre` passage is first; the other three graded passages follow in `getForLevel` order, then the non-graded passage last (today's graded-before-non-graded order).
  - `BOSY accepts a post passage; MOSY 1 accepts a pre passage; EOSY accepts a mosy passage`: `startReading` succeeds.
  - `follow-up first even with another label`: silent reading of the `post` passage in BOSY attempt 1; oral BOSY attempt 2's `availablePassages(method: wholeText)` starts with that `post` passage, then `pre`.
  - `no-repeat across rounds still refuses`: read `post` in BOSY; `startReading` in EOSY with it throws `contains('has already read')`.
  - `own grade still refuses`: a grade 6 `pre` passage throws `contains('reads a Grade 7 passage')`.
- [ ] **Step 2: Write the failing SQLite tests**: in `phil_iri_import_v40_test.dart` replace line 166 with `await reading(await session('bosy'), 105);` (accepted) and rename the test to `'an imported session skips the no-repeat and active checks, keeps the own grade; no round check for any session'`. In `phil_iri_any_round_v43_test.dart`: build a DB carrying the v42 trigger (create schema, then re-create the old `check_phil_iri_reading` trigger text with the round block, copied from git `HEAD:lib/core/data/local/phil_iri_local_schema.dart`), confirm a live BOSY reading of a `post` passage is refused, run `createPhilIriLocalSchema` (what onUpgrade does), confirm it is accepted; and `const` check `LocalDatabase` version is 43 if the file exposes it, else skip that assertion.
- [ ] **Step 3: Run them**: `flutter test test/viewmodels/phil_iri_any_round_test.dart test/core/data/phil_iri_import_v40_test.dart test/core/data/phil_iri_any_round_v43_test.dart` — Expected: FAIL (round refusals, list filtered).
- [ ] **Step 4: Implement**: delete the v16 block (comment + `SELECT RAISE(ABORT, 'This round does not use this passage …')` statement) from the readings trigger; bump `version: 43` + comment; delete `allowsPassageTestType` and its doc comment; in `startReading` delete the round refusal; in `availablePassages` drop the round `.where` and return follow-ups, then `p.testType == session.round.passageTestType`, then the rest (stable, today's order inside each group); rewrite its doc comment (no round filter; order per D4; `test_type` is a booklet label).
- [ ] **Step 5: Run them**: same command — Expected: PASS.
- [ ] **Step 6: Write the migration**: header in the style of `20261110020000` (purpose, idempotent, newer than 20261110020000, `App update required on all devices: yes (a rule change: older apps refuse a passage from another round that the server accepts)`, apply-only-when-finalized line, spec path, ma 2026-11-09 quote); body = `create or replace function public.check_phil_iri_reading()` copied verbatim from `20261110020000` lines 74-178 minus `v_test_type` (declaration, select-into column) and the `if v_test_type is not null … end if;` block; `basa_migrations` insert `on conflict (id) do nothing` like the previous migrations. Add the id to `release.dart` and a sentence to README 2b ("`20261110030000` (Phil-IRI passages may be read in any round; app update required: yes)").
- [ ] **Step 7: PG18**: steps file: as superadmin, a live BOSY session (grade 7 section) inserts a reading of a `post` grade-7 passage → accepted; same learner, EOSY reading of the same passage → refused (no-repeat message); grade 6 passage → refused (own grade). Run the migration twice. Expected: 3/3 as stated, both migration runs clean. Stop + delete pgdata.
- [ ] **Step 8: Update the t1 scenario**: `tool/command_pass/scenarios/21_t1.pass` lines 12-13 → `20261110030000`.
- [ ] **Step 9: Docs**: `lib/core/CLAUDE.md` (v43 note next to the v42 one; Phil-IRI passages: any round, `test_type` = label + list order); `CLAUDE.md` Phil-IRI line (one clause: since 2026-11-10 `20261110030000` any grade-level passage in any round, `test_type` only orders the list); `docs/handoff/screens/phil-iri.md` only if it describes round-filtered passages.
- [ ] **Step 10: Full checks** **DO NOT PLAY RESOURCE INTENSIVE GAMES**: `dart analyze` (0 errors), `flutter test --concurrency=2` (all pass), `dart run tool/check_tutor_imports.dart` and `dart run tool/check_vm_boundary.dart` (OK). Grep `allowsPassageTestType` and `This round does not use this passage` in `lib/` and `test/` → none.
- [ ] **Step 11: Kit + stop**: `D:/0_CAPSTONE/verify/phil-iri-any-round/t1` (offline console steps: BOSY session lists pre first then the rest, starts a reading of a post passage; SQL to run on dev later: `select position('v_test_type' in prosrc) = 0 from pg_proc where proname = 'check_phil_iri_reading';` → `true`). Give the owner the commit message; do NOT apply the migration on dev yet.

### Task 2: Import docs, dev apply, command pass

**Files:**
- Modify: `docs/superpowers/specs/2026-11-09-phil-iri-import-design.md` (D8 row, line ~55-57 question 1 marked answered by this piece, outcome list item 5, FAQ item 7), `docs/superpowers/plans/2026-11-09-phil-iri-import.md:251-252`
- Possibly modify: command pass scenarios that expect the round refusal or a round-filtered list (found by the pass)

**Interfaces:**
- Consumes: Task 1 migration applied on dev.

- [ ] **Step 1: Import spec/plan text**: D8 → "re-reads are imported, flagged in the preview; lower-grade passages are skipped" (no round clash; cite this spec D9); outcome item 5 `import, flagged (re-read)`; FAQ item 7 drops "round clash"; question 1 → "Answered (ma, 2026-11-09) and done 2026-11-10: any round (spec 2026-11-10-phil-iri-any-round-passages)". Plan line 251 → `` `re-read is imported, flagged` ``; line 252 drops "round-clash".
- [ ] **Step 2: Owner applies** `20261110030000` on dev (every device synced, uploads decided), runs the kit's SQL check → `true`.
- [ ] **Step 3: Full command pass** **DO NOT PLAY RESOURCE INTENSIVE GAMES**: check for an open BASA console first; `dart run tool/command_pass/run.dart` → expected clean (all batches, 0 failures). Fix any scenario line that expected a round refusal or a round-filtered list, rerun those batches with `--run r<N> <batch>`.
- [ ] **Step 4: Kit + stop**: finish `D:/0_CAPSTONE/verify/phil-iri-any-round` (t2: online dev steps), give the commit message, then the final whole-branch review.
