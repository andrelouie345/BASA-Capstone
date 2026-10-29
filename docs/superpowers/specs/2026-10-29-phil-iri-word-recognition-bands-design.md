# Phil-IRI word recognition bands and Table 8 profiles — design

Date: 2026-10-29. Status: approved in conversation (owner, reading coordinator "ma"); this file awaits the owner's review.

## Why

DepEd's updated Phil-IRI rules (relayed by ma, 2026-10-25 and 2026-10-29):

1. Word recognition (oral reading accuracy) gets a new band, **Struggling**, and a lower Non-Reader cut-off.
2. The word reading profile and the reading profile come from a fixed table ("Table 8. Student's Reading Profile Per Passage"), not from today's rules (word reading: Independent needs a Fast speed; reading profile = the comprehension level, Non-Reader overriding).

Phil-IRI only (Grades 4–10). CRLA's Part 1 levels (Full / Moderate / Light Refresher) are not touched.

## Decisions (owner and ma)

| # | Decision |
|---|----------|
| D1 | Word recognition bands (whole percents, rounded as today): **Non-Reader ≤ 35**, **Struggling 36–55**, **Frustration 56–89**, Instructional and Independent unchanged (90–96, ≥ 97). The bands describe word recognition only; reading speed plays no part in them. |
| D2 | These are DepEd's values, so they become the **defaults** (`PhilIriThresholds.defaults`). Regions and schools can still adjust them as today. |
| D3 | Saved threshold rows: a saved `non_reader_max` is dev data, not a choice to keep. The migration removes the key from every `phil_iri_thresholds` row so the new default applies (owner, decision B = no). |
| D4 | Word reading profile and reading profile follow Table 8 exactly (two fixed lookups below). Not adjustable. |
| D5 | Silent readings go through the lookups too (word recognition 100% = Independent, so their speed now matters). Intended: silent reading is for learners known to recognize words, and speed matters. |
| D6 | A **Struggling** reading profile: adjusted grade level from the comprehension % exactly as Frustration (never below Grade 1). Reports count it **with Frustration**. |
| D7 | A **Non-Reader** reading profile (≤ 35%) keeps today's treatment: adjusted grade 0, its own BOSY masterlist group, the furthest ARAL report group (ma, answer 1 = B). |
| D8 | Sessions **finalized before** the update keep the results they were scored with (stored levels and threshold snapshot). Open and new sessions are scored with the new rules (owner, decision A). |
| D9 | The old "Struggling Reader" flag (Frustration word recognition + Struggling speed) is removed: Table 8's Struggling level replaces it. |
| D10 | Struggling is stored as a level of its own (`struggling`), so finalized results keep it exactly. Rejected: storing it as `frustration` and re-deriving it on read (breaks D8 for frozen results). |

## The two lookups (Table 8)

Lookup 1: word recognition × reading speed → **word reading profile**.

| Word recognition ↓ / Speed → | Fast | Average | Slow | Struggling |
|---|---|---|---|---|
| Independent | Independent | Independent | Instructional | Frustration |
| Instructional | Instructional | Instructional | Instructional | Struggling |
| Frustration | Frustration | Frustration | Frustration | Struggling |
| Struggling | Struggling | Struggling | Struggling | Struggling |
| Non-Reader | Non-Reader | Non-Reader | Non-Reader | Non-Reader |

Lookup 2: word reading profile × comprehension level → **reading profile**.

| Word reading profile ↓ / Comprehension → | Independent | Instructional | Frustration |
|---|---|---|---|
| Independent | Independent | Instructional | Frustration |
| Instructional | Independent | Instructional | Frustration |
| Frustration | Instructional | Frustration | Frustration |
| Struggling | Struggling | Struggling | Struggling |
| Non-Reader | Non-Reader | Non-Reader | Non-Reader |

Comprehension levels stay Independent / Instructional / Frustration (no Struggling or Non-Reader comprehension). A reading without comprehension (e.g. FLT) counts comprehension as 0 = Frustration, as today. With only a word reading or only a comprehension known (`_profile` in `phil_iri_results.dart`), the known one is used as today.

## Changes

### Rules (`lib/core/services/phil_iri_rules.dart`)
- `PhilIriLevel` gets `struggling('Struggling')`, between `frustration` and `nonReader`.
- `PhilIriThresholds`: `nonReaderMax` default 35; new `wordReadingStrugglingMax` (default 55, key `word_reading_struggling_max`); `validate()` checks `nonReaderMax < wordReadingStrugglingMax < wordReadingInstructionalMin < wordReadingIndependentMin`. A snapshot without the new key loads with the default (fromMap already falls back).
- `philIriAccuracyLevel`: ≤ nonReaderMax Non-Reader, ≤ strugglingMax Struggling, < instructionalMin Frustration, then Instructional / Independent.
- `philIriWordReadingLevel(accuracy, speed)`: Lookup 1 as a constant table.
- `philIriPassageProfile(wordReading, comprehension)`: Lookup 2 as a constant table. Comprehension Non-Reader / Struggling stays an `ArgumentError`.
- `philIriIsStrugglingReader` removed (D9).
- `philIriComprehensionLevel` unchanged.

### Results (`lib/core/services/phil_iri_results.dart`)
- `isStrugglingReader` removed from `PhilIriPassageResult` and `PhilIriRoundResult`.
- `philIriAdjustedLevel`: `struggling` computed exactly as `frustration` (D6). `_adjusted`'s GST branch treats Struggling like Frustration.
- `_rank`: Independent 4, Instructional 3, Frustration 2, Struggling 1, Non-Reader 0 (the end result picks the better round).
- Levels down: unchanged (`nonReader:` flag still only for Non-Reader).

### Reports (D6, D7)
- BOSY masterlist (`nla_report_viewmodel.dart`) and SRP candidates (`srp_viewmodel.dart`): the "not grade level ready" filter takes `frustration`, `struggling` and `nonReader`. Masterlist group: Non-Reader as today; Struggling goes by levels down (2-LD / 3-LD) like Frustration.
- ARAL report (`aral_report_viewmodel.dart`): only Non-Reader goes to the furthest group (as today); Struggling by levels down.
- NLA Form 2b counts and the GST blocks use comprehension % and GST scores, not the profile: unchanged.
- Any other `switch` over `PhilIriLevel` found by `dart analyze` gets the Struggling case treated as Frustration unless it is a label.

### Storage: migration + device schema
- Cloud migration `20261029010000_phil_iri_struggling_level.sql`, **App update required on all devices: yes** (a new stored value old apps can't read; new defaults change results). Apply only when all work is finalized (README rule).
  - `phil_iri_readings` CHECKs on `accuracy_level`, `word_reading_level`, `profile` allow `'struggling'` (drop + re-add the three constraints; `comprehension_level` unchanged).
  - `update phil_iri_thresholds set settings = settings - 'non_reader_max'` (D3).
  - No table or view created, so no new grants; RLS unchanged (no policy touched). Ledger row + `lib/core/release.dart`.
- SQLite v39: rebuild `phil_iri_readings` with the widened CHECKs, the same copy-and-rename as v26 (`phil_iri_local_schema.dart`: copies every column, re-creates the triggers that read the table, runs before the creators). The local thresholds mirror drops `non_reader_max` from its rows too (the next pull replaces them anyway).
- Finalized readings keep their stored levels and snapshot (D8): no backfill.

### Console and docs
- `phil_iri_commands.dart`: the "· Struggling Reader" suffix goes; the levels print as before (Struggling appears as a level).
- Command pass `24_t4.pass`: the reading at 88% / 60 wpm / 30% comprehension becomes word reading **Struggling** (Frustration × Struggling speed) and profile **Struggling**; update its expectations and the header comment. Other scenario lines are checked by running `t4` and the Phil-IRI-reading batches.
- `docs/handoff/screens/phil-iri.md` (and `reports.md` where levels are listed): a fifth level, Struggling; no `isStrugglingReader`.
- `lib/core/CLAUDE.md` Phil-IRI notes and the root `CLAUDE.md` migration list; README 2b line for the migration.

## Testing
- Unit tests (new `test/core/services/phil_iri_table8_test.dart`): every cell of both lookups; the band edges 35/36, 55/56, 89/90; Struggling adjusted grade = Frustration's for the same comprehension; Non-Reader still 0; `_rank` order; a snapshot without `word_reading_struggling_max` loads with 55. Update `phil_iri_result_getters_test.dart` (flag removed).
- PG18 harness: migration twice; a `struggling` profile inserts; an unknown value is refused; `non_reader_max` removed from a seeded row.
- SQLite: an upgrade test from v38 with a finalized reading keeps its row and stored levels (pattern of `aral_classes_v38_test.dart`).
- Full command pass after the owner applies the migration on dev.

## Not included
- Re-scoring finalized sessions (D8).
- Any change to CRLA, the NLA band cut-offs or the GST conversion.
- Showing the word recognition band separately from the word reading profile in reports (the level fields already carry both: `accuracyLevel` = band, `wordReadingLevel` = profile).
