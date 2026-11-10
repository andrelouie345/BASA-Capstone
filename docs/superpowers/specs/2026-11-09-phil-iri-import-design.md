# Phil-IRI import (ma's workbook and BASA scoresheet files) — design

Date: 2026-11-09. Status: approved in conversation (owner); this file awaits the owner's review.

## Why

Phil-IRI results can only be entered live in BASA today. Two sources hold results BASA must take in for the module to be complete:

1. **ma's workbook** (`GradeE07_Phil-IRI-ARAL Reading Assessments_shared.xlsx`, v26.0531Lite): one workbook per grade, one sheet per section, GST plus five round blocks (BOSY, MOSY 1–3, EOSY). Schools that used it before BASA should continue in BASA where the workbook stopped.
2. **The DepEd Teacher Scoresheet** (paper). A filled scoresheet never exists as a file (its own instructions say to input the scores into the workbook), so BASA provides a **scoresheet file**: a per-section .xlsx template laid out like the paper, which teachers (or an AI tool) fill in from the paper.

Hard rule (owner): the import takes **raw data only, never summaries**. Every level, profile, adjusted grade, ARAL placement and report is computed by BASA from the raw readings, exactly as for live readings. Phil-IRI only: the ARAL roster follows from the imported results through the automatic update.

## What the sources hold (census of the G7 sample, 2026-11-09)

40 section sheets, 29 with learners, 1,289 learners; GST score for 1,251; BOSY 1,253 readings, MOSY 1 1,140, MOSY 2 129 (three sections, none with comprehension; open question 3), MOSY 3 1, EOSY 0. Reading method per sheet and round: mostly One-Minute Reading, a few sections Whole-Text. No LRN anywhere; learners are named, in a male block (rows 14–63) and a female block (65–114). No dates. The workbook's catalog (`TextSelect` on `AlphaList`: set, text, word count) has its own word counts.

Raw (typed) cells per learner: name, GST raw score (out of 40 for Grade 7); per round: passage ("SELECTION", e.g. `7C Dust`), words read (typed over the formula in one-minute rounds), miscue counts (Mispronunciation, Omission/Deletion, Substitution, Insertion, Reversal/Hesitation, Repetition/Self-correction), minutes and seconds, comprehension correct (out of the column header's maximum, 8 or 20). Everything else is formulas (levels, profiles, "Enrolled", SRP lists): not imported.

Academic history (age, elementary school, address), the Readability sheet and the tutor/adviser/teacher names per section are not imported (D17).

## Decisions (owner, 2026-11-09)

| # | Decision |
|---|----------|
| D1 | Two sources: ma's workbook, and a BASA scoresheet file laid out like the DepEd Teacher Scoresheet (B). |
| D2 | Scoresheet answers are the **letters the learner chose**; BASA marks them from the answer key. A blank answer imports as not answered (counts as wrong, as in live use); the preview flags it. No more effort than that: teachers should record every answer (guide warning). |
| D3 | Miscues are tallies by type in both sources: each counted miscue becomes a miscue row with **no word position** ("position not recorded"). No invented positions. Scoring, reports and miscue counts work unchanged. |
| D4 | Workbook miscue columns keep the **workbook's counting**: Reversal/Hesitation → counted `reversal` rows; Repetition/Self-correction → self-corrected rows (not counted). An import does not change a learner's word recognition. The scoresheet file uses BASA's own miscue types. |
| D5 | Workbook learners are matched by **name within the section** (case, spacing, punctuation and "Last, First M." order ignored), sex as a cross-check. A single clear match is taken; no match, two matches or a sex mismatch → the coordinator picks or skips in the preview. The section must exist in BASA (SF1 imported first). Scoresheet files match by LRN. |
| D6 | Workbook dates: **one date per round**, proposed from the round calendar (start of the round's window), changeable; a round the calendar doesn't hold needs a typed date. The GST takes the BOSY date. Scoresheet rows carry their own (required) date. |
| D7 | Passages: **BASA's passage and word count** are used. Matched by level and title, active passages first (an inactive passage only when no active one matches: history may use a passage switched off since), the workbook's code as a tie-breaker (`7C` ↔ `C1`, `7A2` ↔ `A2`). The preview lists every learner whose BASA level differs from the level the workbook itself computed (its cached values). |
| D8 | Live passage rules vs imported history (option C): **round clashes and re-reads are imported, flagged in the preview**; **lower-grade passages are skipped**, listed. The own-grade rule stays: a Grade 2 passage scored as a Grade 7 result is meaningless (BASA and the workbook both count the adjusted level from the learner's grade). Imported readings still count for the no-repeat rule of later live readings. No notes are kept on the reading; the guide warns (FAQ). |
| D9 | Amended 2026-11-09 by the rules update spec (`2026-11-09-phil-iri-rules-update-design.md`, D18): a round with words read and time but **no comprehension imports as a word reading** (comprehension not assessed). A round with a passage but no time/words read is **skipped as incomplete**, listed. Rows with only a comprehension, or with words read and time but no passage, stay skipped until R2 (readings without a passage / comprehension-only), then import. BASA shows a skipped learner as not assessed in that round, and the tutor assesses live (which also avoids the workbook's re-read). |
| D10 | Workbook import is a **one-time switch per section and school year**. A second import of the same section and year is refused. The warning is shown **before** the import button (not after). |
| D11 | Scoresheet import is **repeatable, never overwriting**: a learner and round BASA already has (completed or finalized) is skipped, listed; a live session in progress is never touched. |
| D12 | Imported sessions are **completed**, not finalized; the coordinator finalizes through the existing screen (and can still discard a wrongly matched one before that). |
| D13 | Approach 1: **two readers, one shared importer** (below). Rejected: two standalone importers (rules written twice); converting the workbook into a scoresheet file (the workbook has correct counts, not answer letters, and needs name matching and the lock). |
| D14 | Header labels are found by **label, not column letter**, and are **editable before import** (device-saved overrides, like `Sf1ColumnMap`): a coordinator's renamed header is fixed in the preview's Headers step, no app release. Only a restructured round block needs code. |
| D15 | Workbook: **the whole workbook in one pass**; the coordinator ticks the sections to import. |
| D16 | The scoresheet template is **made by BASA per section** (learners pre-listed), copy-paste friendly, with a fill-in section and AI-tool tips in the guide. |
| D17 | **Phil-IRI only** (GST and readings). Not imported: the Readability sheet (per grade; BASA logs readability per ARAL learner), academic history (no learner fields), section staff names (not accounts), anything computed. |
| D18 | No auto sync. The order is: import → upload → tutors download before assessing that round (guide). |
| D19 | (Added 2026-11-09, while planning.) One upload carries at most `maxPackageBytes` (6 MB, `sync_upload_rules.dart`); a whole grade (G7 sample: ~2,400 sessions and readings plus one row per counted miscue) likely exceeds it. The import works **in batches that fit one upload**: the preview estimates each ticked section's upload size plus the device's unsent work; when the ticked sections don't fit, the import refuses and says how many do ("import these, upload, then the rest"). The one-time lock greys out imported sections next time. Sync is not changed. Rejected: splitting uploads in sync (touches the approved sync design); raising the limit (measured only to 8 MB, self-hosted servers may be stricter). |

## Questions for ma (all answered 2026-11-09; kept as the record)

Open questions now live in the rules update spec (`2026-11-09-phil-iri-rules-update-design.md`, *Questions on ma's list*).

Source of every figure: `sample-files/GradeE07_Phil-IRI-ARAL Reading Assessments_shared.xlsx`, the 29 section sheets with learners (of `01`–`40`), read with masking (no names) on 2026-11-09. Columns: BOSY passage `S`, MOSY 1 `AV`, MOSY 2 `BY`; each round block's passage list is the set picked in its header (`R10` BOSY, `AU10` MOSY 1, `BX10` MOSY 2, `DA10` MOSY 3, `ED10` EOSY; the drop-down is `XLOOKUP(R13, AlphaList!K13:AC13, ...)`).

1. **Which passages BOSY uses.**
   - Workbook: the BOSY block is titled "IRA FOR GST RESULTS VALIDATION/PRETEST", and **all 29 sections** set it to the general **"Phil-IRI"** list (`AlphaList!V`: graded passages 2A–7D, including 7A2 and 7D2), not the "Pretest" list (`AlphaList!Y`, whose Grade 7 entry is "7E-Pre Lili the Lizard and Koko the Gecko"). 1,238 learners read "7C Dust"; 13 read "7A2 Diving" (all in sheet `21`); none read Lili.
   - BASA: the active pool files the Grade 7 A–D passages as **MOSY** passages and only `G7Pre` (Lili) as BOSY (`supabase/seeds/phil_iri_graded_passages_pool.sql` header: "'mosy' = MOSY 1-3: G7 A1-D2 (the 2018 level-7 passages)", her classification of 2026-10-15; Dust is `G7C1`, line 1149; Diving `G7A2`, line 1002).
   - Question: for the BOSY IRA (GST validation), should Grade 7 learners read the A–D graded passages (as her workbook does), Lili (as BASA has it), or either? If A–D, the fix is content only: set those passages to "any round" (`test_type` null), like levels 2–6; the clash then disappears for imports and live use. Same question for Grades 8–10 once their workbooks are seen.
   - Cost of each answer: "A–D may be read in BOSY" = data only, in two places: (a) the seed file (`'mosy'` → null for G7 A1–D2), so every new server (cloud or a school's LAN server) is right from the start, since the filing comes from the seed; (b) a one-off update on servers that already exist (the content command `phil-iri-passage-edit <passageId> test -`, once per passage, or a short SQL snippet in the README's seed section), because the seed leaves existing passages alone. A read passage's round may still change (`lock_phil_iri_read_passage` locks only text, word count, level and collection). "Lili only" = nothing: BASA already works that way; imports flag the workbook's Dust readings (D8).
   - Either way the import reproduces the workbook's readings as given: round clashes are imported (D8), the flag is a preview line only.
   - **Answered (ma, 2026-11-09):** any grade-level passage may be used in BOSY, MOSY and EOSY, each passage only once per learner. So: the content fix (G7 A–D `test_type` null, seed + existing servers), a follow-up piece after R2.
2. **Lower-grade passages.** (Cost: "count at the passage's level" = a rule change, not data: adjusted level in `phil_iri_results.dart`, the own-grade check in cloud and device, and with them reports, ARAL placement and NLA counts; a migration marked `App update required: yes`. "Keep counting from the learner's grade" = nothing.)
   - Workbook: 4 readings below Grade 7: sheet `20` (two BOSY "2A Pam's Cat", one MOSY 1 "4C-Pre Anansi's Web") and sheet `05` (one MOSY 1 "3D Waiting for Her Sister"). The "Phil-IRI" list offers levels 2–7, so a teacher can pick them.
   - Both sides count the adjusted level from the learner's grade, not the passage's: the workbook's formula (`AN14`: Instructional → `$M$7`, the current grade; Independent → `$M$7+1`; Frustration → `$M$7` minus 1–4 by comprehension) and BASA (`phil_iri_results.dart`, "the adjusted grade level is counted from the learner's grade"). A Grade 7 learner Instructional on Pam's Cat shows as Grade 7 level.
   - The Teacher Scoresheet's own instructions (`Phil-IRI Graded Passages for Assessment_TeacherScoresheet.docx`, first page) do this on purpose: "if Juan, a Grade 7 student, is reported as three grade levels below, he should have a copy of the Level 4 Phil-IRI text".
   - Question: should a reading of a lower-grade passage count at the **passage's** level (Instructional on Grade 4 = adjusted level 4)? That changes live BASA, not just imports: its own piece. Until then D8 skips them.
   - **Answered (ma, 2026-11-09):** those 4 readings are incorrect: passages must be grade-level appropriate, not picked by adjusted level (the adjusted level only guides tutorial materials). D8's skip stands; no passage-level scoring.
3. **MOSY 2 rows.** (Cost: nothing for any answer; it only sets the FAQ wording.) 129 MOSY 2 passages in three sections, MOSY 2 not done anywhere yet:
   - Sheet `05`: 48 rows, passage only (the "time" is the formula's automatic 1 minute for one-minute reading; no words read, miscues or comprehension).
   - Sheet `20`: 47 rows, passage only.
   - Sheet `21`: 34 rows with words read and miscues typed but no comprehension: looks like readings in progress.
   - 127 of the 129 are "7D2 Ecosystems", the same passage those learners read in MOSY 1.
   - Question: are sheets `05` and `20` the passage written in ahead of time, and is sheet `21` a re-read of Ecosystems (MOSY 2 reading the MOSY 1 passage again)? D9 skips all 129 as incomplete either way; the question is whether the plan for MOSY 2 was a re-read, which BASA refuses live.
   - **Answered indirectly (ma, 2026-11-09):** each passage is used only once per learner, so a MOSY 2 re-read of Ecosystems is not intended; a reading is complete with words read and time (comprehension may come separately). Effect after D9's amendment: sheets `05`/`20` (passage only) stay skipped; sheet `21` rows with words read and time import as word readings and are flagged as re-reads (D8). FAQ wording follows this.

## Architecture

```
ma's workbook ──► PhilIriWorkbookReader ──┐
                                          ├──► PhilIriImportPlan ──► PhilIriImportViewModel ──► device copy ──► upload
scoresheet .xlsx ► PhilIriScoresheetReader┘   (raw entries,           preview / import
                                               problems)              (one set of checks)
```

Readers only turn a file into raw entries plus what they couldn't read. The importer does matching, rule checks, preview and writing, the same for both sources. A new workbook version is a reader change (or a header override), never an importer change.

## Database (one migration, cloud and device)

Migration header `App update required on all devices: yes` (older apps can't read a miscue without a position). Ends with its `basa_migrations` row; id added to `lib/core/release.dart`; README 2b lists it. Local database v39 → v40. Every rule below is enforced in the cloud (triggers/RLS) **and** the device triggers.

1. **`phil_iri_assessments.import_source`** text, null = live, else `workbook` or `scoresheet`. Set at insert, never changed (joins the "only the status can change" rule of `phil_iri_assessments_before_update` and the device trigger). **Only an admin/coordinator of the school or the superadmin may insert it non-null** (cloud: in the insert trigger; device: the ViewModel, as for finalizing), otherwise a tutor could skip the rules.
2. **Reading check** (`check_phil_iri_reading`, device `check_phil_iri_reading_ins`): for a session with `import_source` set, the **round** (test type), **no-repeat** and **active passage** checks are skipped. The **own-grade** check stays. The no-repeat check of live readings keeps seeing imported readings.
3. **`phil_iri_miscues.word_index` nullable.** Null only when the reading's session has `import_source` set; the position check runs only when a position is given.
4. **`phil_iri_readings.imported_correct`** integer, null or 0..(passage's question count). Only on a `workbook` session, and never together with answer rows for that reading. Scoring (`PhilIriViewModel`, today `correct = answers.where(isCorrect).length`, total = the passage's questions) uses it as the correct count when set.
5. **New table `phil_iri_workbook_imports`** (id, school_id, section_id, school_year, imported_by, imported_at; unique (section_id, school_year)): the one-time lock. Synced: written on the device in the same transaction as the section's sessions and sent in the same upload, so the server's unique key refuses a second coordinator's upload in one transaction; mirrored by pull so the preview greys locked sections out. RLS: select and insert for the superadmin and the school's own admin/coordinator; no update or delete (unlocking is a deliberate superadmin SQL step). Grants in the same migration (select/insert/update/delete to `authenticated, service_role`; nothing to `anon`); `migration_grants_test` covers it. The SELECT policy checks the row's own columns (F14: `sync_apply` inserts with `RETURNING`).

`sync_apply` / the sync table lists gain the new table and columns (the sync spec's table order: the lock row after the section's sessions).

## Components (pure Dart, `lib/core/`)

- **`models/phil_iri_import.dart`** — `PhilIriImportPlan`: sections (DepEd school ID, school year, grade, section name, or empty), GST entries (learner key, score, max), readings (learner key, round, date or null, passage reference: code/title/level, method, seconds or words read, miscue counts per type + self-corrected, answer letters Q1..Qn or a correct count), problems (sheet, row, column, message), header issues (field, block, headers found). Each entry keeps its source (sheet, row). Learner key: LRN (scoresheet) or name + sex (workbook).
- **`services/phil_iri_workbook_reader.dart`** — reads cells with `XlsxWorkbook` (`xlsx_cells.dart`; cached values of formula cells for the D7 comparison). Section sheets found by content, not by name (any number). Fields found by header label per round block through `PhilIriImportHeaders`; before reading learners it checks every needed header exists in every block and otherwise returns header issues (never guesses a column). Reads typed cells only, plus the workbook's own saved levels. Applies D4 and D9.
- **`services/phil_iri_scoresheet_reader.dart`** — reads the template's table with `table_reader.dart` (headers case/space-insensitive; dates `YYYY-MM-DD`, `M/D/YYYY`, Excel serial); times `m:ss` or seconds; answer letters any case; extra spaces ignored. Rounds `GST` (score only), `BOSY`, `MOSY1`–`MOSY3`, `EOSY`.
- **`services/phil_iri_import_headers.dart`** — header labels of both readers: built-in defaults (ma's current layout, her spellings kept, e.g. "Mispronounciation"), device overrides in `<data dir>/phil_iri_import_headers.json`, reset. Follows `Sf1ColumnMap`.
- **`services/phil_iri_scoresheet_template.dart`** — writes a section's template: Learners table (LRN as text, name, sex; one row per reading), Codes sheet (rounds, methods, the grade's passage codes, miscue types), Instructions sheet. No merged cells, no formulas to keep. Drop-down lists only if the current .xlsx tooling can write data validation (checked in the plan, not assumed); the Codes sheet otherwise.

## `PhilIriImportViewModel` (admin build, `wire_admin.dart`)

Admin/coordinator of the school or the superadmin, signed in; tutors refused (refusal string in `tool/admin_markers.txt` `[admin]`). Offline on the device copy, like the CRLA import. Own `ScopedLogger`.

**`previewWorkbook(bytes)`, `previewScoresheet(sectionId, bytes)`** — nothing written:

1. Header issues first (the Headers step); nothing else is checked until resolved. After a pick, sample values of the chosen column (numbers and codes, never names).
2. Per section (workbook): importable / empty / not in BASA (names the section to create) / already imported (locked); the one-time warning text for the screen to show before the button.
3. Learners: matched, or needs a pick with candidates.
4. Rounds (workbook): proposed date per round from the round calendar.
5. Per reading one outcome: **import**; **import, flagged** (round clash, re-read); **skipped** with the reason (incomplete, lower-grade passage, passage not in BASA, already assessed this round, live session in progress, unreadable value with row and column). Blank answers are flagged, not skipped.
6. GST: imported unless the learner already has a GST that school year.
7. Levels that differ from the workbook (D7).
8. Upload size (D19): estimated bytes per section and for the device's unsent work, against `maxPackageBytes`.

**`import(preview, choices)`** — choices: ticked sections, learner picks, round dates. Rebuilds the preview with the choices first; if anything changed since it was shown (e.g. a pulled session), stops and asks for a fresh preview. Refuses when the ticked sections plus the unsent work exceed one upload (D19), naming how many fit. One device transaction per learner: session(s) created in progress with `import_source`, reading, miscue rows (no position), answers or `imported_correct`, then completed; the GST result. One lock row per workbook section in the same transaction as its last learner. Returns created session ids and per-row failures with the reason. Then the normal upload (a coordinator's upload is applied at once).

## Console (admin only)

New file `lib/core/console/commands/phil_iri_import_admin_commands.dart` (wholly admin, listed in `tool/check_tutor_imports.dart`); one action per command:

| Command | Does |
|---|---|
| `phil-iri-import-template <sectionId> <out.xlsx>` | writes the section's scoresheet template |
| `phil-iri-import-headers` | lists the header labels (default or changed) |
| `phil-iri-import-headers-set <field> <label>` | changes one label on this device |
| `phil-iri-import-headers-reset` | restores the defaults |
| `phil-iri-import-workbook-preview <file>` | workbook preview |
| `phil-iri-import-workbook <file> sections=… dates=bosy:YYYY-MM-DD,… [picks=<sheet>:<row>=<studentId>,…]` | imports the ticked sections |
| `phil-iri-import-scoresheet-preview <sectionId> <file>` | scoresheet preview |
| `phil-iri-import-scoresheet <sectionId> <file>` | imports it |

Admin console 247 → 255 commands (tutor unchanged, 126): `test/core/wiring/admin_commands.txt`, the coverage test totals, `CLAUDE.md`, a new `tool/command_pass/scenarios/*.pass`.

## UI handoff (groupmates' screens)

Screens call the ViewModel, never the commands. Needed: an import screen under Reports & files (pick file → Headers step if needed → preview per section with ticks, learner picks and round dates → the one-time warning shown **before** the import button → result); a "Download template" action per section; finalizing uses the existing finalize screen. The spec's preview/result models are what the screens show; no screen text is decided here beyond the one-time warning (supplied by the ViewModel).

## Testing

- Readers: small workbooks built inside the tests (made-up names; ma's file is never committed): every round block, both methods, moved columns, renamed header with and without override, missing header, empty sheets/rows, incomplete rounds, the D4 mapping; template written, filled and read back.
- Device rules (SQLite): imported sessions skip only the round, no-repeat and active checks; null word position refused on live sessions; `imported_correct` refused on scoresheet/live sessions and with answers; `import_source` can't change.
- Cloud (throwaway PG18 harness): a tutor setting `import_source` refused; lock uniqueness; inserts with `RETURNING` (F14); grants test.
- ViewModel: matching and picks, duplicates (already assessed / in progress), stale-preview stop, transaction per learner, comparison with the workbook's levels.
- ma's real G7 workbook, read only from the scratchpad: the reader reproduces the census above.
- Command pass on the dev cloud; verify kit `D:\0_CAPSTONE\verify\phil-iri-import\`.
- After every piece: `dart analyze`, `flutter test`, `check_tutor_imports`, `check_vm_boundary`; the release marker scan includes the new refusal.

## Guide (written last, once the screens exist; names marked //(to confirm)// until then)

**Admin guide:** new page `Functions:Importing data`, linked from Home and checklist stage 02; a "Moving from the workbook to BASA" step for mid-year switches.

1. Before you import (SF1 for every section; round calendar set).
2. Importing ma's workbook (ticking sections, picking learners, dates, the one-time warning).
3. Filling in the scoresheet file — simple steps: download the section's template; one row per reading (copy a learner's row for each extra round); copy the paper into the row (round, date, passage code, method, time or words read, miscue counts, each answer letter); leave a cell empty if it isn't on the paper, never guess; save, import, read the preview.
4. Importing a scoresheet file.
5. Using an AI tool for big batches: privacy first (learner names and LRNs are personal data under RA 10173: check the school's/division's rules; an approved account); a ready-made prompt to copy ("Fill one row per scoresheet into this template. Use only codes from the Codes sheet. Copy numbers and answer letters exactly as written. Leave a cell empty if it's unreadable or missing. Never guess."); always check its work against the paper (handwriting misreads that still look plausible pass the preview); small batches, one section at a time.
6. After importing: upload; tutors download before assessing; finalize the imported sessions.
7. FAQ (the warnings): blank answers count as wrong; lower-grade passages skipped; round clash / re-read flags; incomplete rounds skipped and finished live; the one-time switch; "already assessed"; a missing header (Headers step); unmatched learner / section not in BASA; levels differing from the workbook (BASA follows DepEd's current bands and Table 8, the workbook its own cut-offs; and BASA's word counts for whole-text readings); where the dates come from; tutors not seeing results or a learner with two attempts (upload, then download); "too much for one upload" (import some sections, upload, then the rest).

**Tutor guide:** "Every time you work" gains: "After your coordinator imports results, download before assessing."

## Out of scope / follow-ups

- Scoring lower-grade readings at the passage's level (ma, question 2).
- Re-classifying the Grade 7 A–D passages for BOSY (ma, question 1; content only).
- Importing the Readability sheet, academic history, section staff.
- Unlocking a workbook import from the app (superadmin SQL only for now).
- Per-word miscue positions from either source.
