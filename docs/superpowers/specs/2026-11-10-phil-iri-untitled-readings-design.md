# Phil-IRI imported readings without a passage ("Untitled") and comprehension-only readings (R2) — design

Date: 2026-11-10. Status: approved in conversation (owner); this file awaits the owner's review.

## Why

Piece **R2** of the Phil-IRI rules work (R1 = `2026-11-09-phil-iri-rules-update-design.md`), before import Task 6 (`docs/superpowers/plans/2026-11-09-phil-iri-import.md`).

Ma (2026-11-09, answering the import question "a workbook row with words read and time but no passage: skip or keep?"): *"if there is word count and time, assign a generic 'Untitled' to that blank."* And: comprehension alone still gives a reading profile, with word reading shown "not assessed" (= Struggling for scoring, R1 D6).

Today BASA cannot store either: every reading needs a passage (`phil_iri_readings.passage_id` NOT NULL; word count and comprehension questions come from it), and an untimed reading cannot be scored (`philIriScorePassage` throws), so import spec D9 skips both kinds of row.

## Decisions

| # | Decision |
|---|----------|
| D1 | **Import only** (owner). Readings without a passage and comprehension-only readings exist only in imported sessions. Live sessions keep today's rules: one grade-level passage, timed, completion refused without a time. Live support can be added later if ma asks. |
| D2 | **No passage = `passage_id` null** (approach A, owner). "Untitled" is only a display label. Rejected: a seeded "Untitled" passage per grade (fake content rows on every server, still needs per-reading counts, shows up in passage lists). |
| D3 | Untitled readings come from **ma's workbook only** (`import_source = 'workbook'`). The scoresheet file always names a passage code; a blank code stays a refused row. |
| D4 | Untitled **word count**: typed per reading (`imported_word_count`), required for a timed whole text or silent reading (an untimed one has comprehension only; final review I1), not allowed when a passage is set (the passage's count wins, import D7). A one-minute Untitled reading needs none (accuracy over words read). |
| D5 | Untitled **comprehension**: `imported_correct` over `imported_total`, the total being the round block's comprehension header maximum (8 or 20) (owner). No readable maximum → imported without comprehension, flagged. With a passage the total stays the passage's number of questions (unchanged). |
| D6 | **Comprehension-only** reading (passage or Untitled; no time, no words read): allowed on imported sessions (workbook and scoresheet). No schema change (both fields already nullable). |
| D7 | A reading with no word reading scores **word reading = Struggling, assumed** (R1 D6), through Table 8, for the passage's own result too. Accuracy, speed, score and wpm stay null. |
| D8 | **Status:** word reading assessed = the round's own reading has a word reading (not merely "has a reading"). A comprehension-only round is therefore **carried over** (it has a result, but not a complete assessment): ma's "assessed = complete word reading + comprehension entry" and her chart arithmetic (carried over = labelled − newly assessed). The FLT toggle (`comprehensionOptional`) still needs the word reading. |
| D9 | Carrying: a reading with no word reading adds nothing to the oral/silent maxima, so an earlier round's word reading carries as today; comprehension carries as today. Adjusted grade unchanged: a comprehension-only round uses its own % (R1 D8). |
| D10 | Workbook rows (import spec D9 amended in the same commit): passage blank + words read + time → **Untitled** (whole text/silent: the words-read cell is the word count; one minute: words read); comprehension only → **comprehension-only** reading, miscue counts on such a row dropped and flagged; passage only, nothing else → still skipped as incomplete. |
| D11 | Preview: Untitled readings are **"import, flagged: no passage (Untitled)"**. Passage matching (D7) and the lower-grade / round-clash / re-read checks (D8) don't apply to them. The comparison with the workbook's cached levels still runs. |
| D12 | Display: wherever a reading's passage title is shown (session view, console, screens), a null passage shows **"Untitled"**. Corrected 2026-11-12 (final review minor): learner history shows no passage titles at all, so it has nothing to show as "Untitled". |
| D13 | Results stay computed from raw readings with the current rules (bands spec D8 amended, R1 D17); nothing derived is stored. |

## Changes

### Storage
Cloud migration `supabase/migrations/20261110020000_phil_iri_untitled_readings.sql` (`App update required on all devices: yes`: older apps cannot read a reading without a passage). Ends with its `basa_migrations` row; id added to `lib/core/release.dart`; README 2b line.

1. `phil_iri_readings.passage_id` drops NOT NULL. Null only when the session's `import_source = 'workbook'`.
2. New `imported_word_count integer` (> 0): only with a null passage; required when the method is `whole_text` or `silent` and the passage is null.
3. New `imported_total integer` (> 0): only with a null passage and together with `imported_correct`; `imported_correct <= imported_total`. With a passage, `imported_correct <= questions` stays as today.
4. `check_phil_iri_reading`: null-passage branch skips the passage-readable, active, grade, test-type and no-repeat lookups (imported sessions already skip active/test-type/no-repeat; the grade has nothing to compare). The "keeps its session, passage and method" update rule already uses `is distinct from`.
5. `check_phil_iri_miscue`: a reading with no passage takes only miscues without a position. `check_phil_iri_answer`: a reading with no passage takes no answers.
6. RLS: reading policies go through the session (`phil_iri_assessment_writable`), not the passage; checked on PG18 with `RETURNING` (coordinator insert of a null-passage reading passes; tutor live insert refused). No new table or view, so no grants.

SQLite v42: rebuild `phil_iri_readings` (nullable `passage_id`, the two columns, same CHECKs) with the v39/v41 recipe and the `legacy_alter_table` guard; device triggers in `phil_iri_local_schema.dart` mirror points 2–5. Sync column lists (`sync_upload_rules.dart` and the apply side) carry the two columns; how `sync_apply` copies columns is checked in the plan, not assumed.

Model `PhilIriReading`: `passageId` → `int?`, new `importedWordCount`, `importedTotal`, getter `isUntitled`.

### Scoring (`lib/core/services/phil_iri_results.dart`)
- `philIriScorePassage`: `wordCount` optional (passage count or `importedWordCount`; not needed for one minute); new `allowNoWordReading` (imported sessions only): no time (whole text/silent) or no words read (one minute) → result with no word reading (D7). Without it an untimed reading still throws.
- `PhilIriPassageResult`: word reading fields nullable, new `wordReadingAssumed`.
- `philIriRoundResults`: D8 and D9.
- `PhilIriViewModel._scoreReading`: word count from the passage or `importedWordCount`; comprehension total from the questions, or `importedTotal` when there is no passage; passes `allowNoWordReading` for imported sessions. Finalize writes nulls into the (already nullable) result columns.
- Other readers of `PhilIriPassageResult` (console, `srp_viewmodel.dart`) handle null word reading.

### Import
- `lib/core/models/phil_iri_import.dart`: `PhilIriImportReading.passage` nullable (null = Untitled), new `wordCount`, `correctTotal`.
- Import plan Tasks 6 (workbook reader), 8 (writer) and 9 (preview) amended with D10, D11 and the writer's new columns. Done in this piece's last task so Task 6 starts from the amended text.
- Import spec D9 amended (D10 above).

### Display
"Untitled" for a null passage in the session view, learner history and console output; note in `docs/handoff/screens/phil-iri.md`.

## Testing
- Unit (TDD): Untitled whole text (typed count), one minute (no count), silent; comprehension only (null word reading, assumed Struggling through Table 8, adjusted from its own %); `imported_correct/imported_total`; live untimed reading still throws.
- Round status (`test/core/services/phil_iri_round_status_test.dart`): comprehension-only round = carried over; earlier oral reading carries; nothing earlier = assumed Struggling; FLT toggle doesn't make it assessed.
- SQLite: v41 → v42 keeps readings; device triggers (null passage refused on live and scoresheet sessions, word count required for Untitled whole text/silent, total ≥ correct, no answers or positioned miscues on Untitled); sync lists carry the columns.
- PG18: fresh build (baseline + all migrations); the same trigger cases as coordinator with `RETURNING`; tutor live null-passage insert refused; grants test passes.
- Each task: `dart analyze`, `flutter test --concurrency=2`, `check_tutor_imports`, `check_vm_boundary`. Owner applies the migration on dev after devices sync (sign-in refused until then); full command pass; verify kit `D:/0_CAPSTONE/verify/phil-iri-untitled/`.

## Out of scope
Live Untitled or comprehension-only readings (D1); Untitled in the scoresheet file (D3); the content fix (G7 A–D any round, next piece).

## Docs
`lib/core/CLAUDE.md` (Phil-IRI notes, v42), `CLAUDE.md` (Phil-IRI line), README 2b, `docs/handoff/screens/phil-iri.md`, import spec D9.
