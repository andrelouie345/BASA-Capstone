# Phil-IRI Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import Phil-IRI GST results and readings, raw data only, from ma's workbook and from a BASA scoresheet file, into the device copy, ready for the normal upload.

**Architecture:** Two pure-Dart readers (workbook, scoresheet) turn a file into one `PhilIriImportPlan`; one admin-build `PhilIriImportViewModel` matches learners and passages, checks every rule, previews, and writes each learner in one device transaction through a local-only writer. One migration (cloud + SQLite v40) adds the imported mark, position-less miscues, the workbook correct count and a synced one-time lock table.

**Tech Stack:** Dart (no Flutter in `lib/core` / `lib/viewmodels`), sqflite_common_ffi (SQLite), Supabase Postgres (PG18 for tests), `archive` + `xml` packages, `XlsxWorkbook` (`lib/core/services/xlsx_cells.dart`), `table_reader.dart`.

**Spec:** `docs/superpowers/specs/2026-11-09-phil-iri-import-design.md` (D1–D19). Read it before any task.

## Global Constraints

- Branch `excelsior`, backend only. **Never run git.** Each task ends by giving the owner the commit message; the owner verifies and commits, then the next task starts (CLAUDE.local.md). Remind the owner to `/clear` after each task.
- Raw data only: never import a level, profile, adjusted grade or any formula result as a result. Cached workbook levels are read only for the D7 comparison.
- `lib/core` and `lib/viewmodels` never import Flutter. Commands and `lib/ui` import only ViewModels, models and their framework (`dart run tool/check_vm_boundary.dart`).
- Admin build only: the ViewModel and command file must not be reachable from `lib/main_tutor.dart` (`dart run tool/check_tutor_imports.dart`).
- Migration file: `supabase/migrations/20261109010000_phil_iri_import.sql`; header line `App update required on all devices: yes`; ends with its `basa_migrations` row; id added to `lib/core/release.dart`; README section 2b lists it; grants per the 20261025 rule (select/insert/update/delete to `authenticated, service_role`; nothing to `anon`).
- Every rule in both places: cloud trigger/RLS **and** the device trigger.
- `import_source` values exactly `'workbook'`, `'scoresheet'`; null = live.
- Learner names from ma's real workbook are never printed, committed or quoted; the real file is read only from the scratchpad, with masking.
- After every task: `dart analyze` (no errors), `flutter test` (all pass), both tool checks. Steps that run the full test suite, the command pass or a release build carry: **DO NOT PLAY RESOURCE INTENSIVE GAMES**.
- Before any console or verify-kit run: ask the owner to close any open BASA console (memory: open-console-check).
- Each task ends with a verify kit under `D:\0_CAPSTONE\verify\phil-iri-import\<task>\` (ids filled in, expected output; memory: verify-kits).

## Review Focus

1. **A one-minute round whose words-read cell still holds the formula's 0** (teacher typed nothing) must be *incomplete, skipped*, never a reading with `words_read = 0` (the CHECK `words_read > 0` would throw mid-import). Test in Task 6.
2. **Two learners with the same normalized name in one section** must both become *needs a pick*, never an automatic match. Test in Task 9.
3. **A comprehension count above the BASA passage's question count** (header says 20, passage has 10) must be *unreadable, skipped* with sheet/row/column, never a DB error. Test in Task 9.
4. **Excel-mangled scoresheet values**: an LRN typed as a number (`1.23456789012E11` or lost leading zero), a date as an Excel serial, a time as an Excel day fraction (`0.1076388…` = 2:35) must read correctly or be named unreadable. Test in Task 7.
5. **Passage titles that differ only in case/punctuation** ("Get up, Jacky!" vs "Get Up, Jacky!", "10A -Pre Butuan…" spacing) must match the BASA passage. Test in Task 9.

---

### Task 1: Cloud migration

**Files:**
- Create: `supabase/migrations/20261109010000_phil_iri_import.sql`
- Modify: `lib/core/release.dart` (add `'20261109010000': 'phil_iri_import'`), `README.md` section 2b
- Test: PG18 throwaway harness in the scratchpad (memory: pg-test-harness): baseline + every later migration + this one; script `pg/import.sql`, not committed.

**Interfaces:**
- Produces (server): `phil_iri_assessments.import_source text check (import_source in ('workbook','scoresheet'))`; `phil_iri_readings.imported_correct integer check (imported_correct >= 0)`; `phil_iri_miscues.word_index` nullable; table `public.phil_iri_workbook_imports(id bigint generated always as identity primary key, school_id bigint not null references schools, section_id bigint not null references sections, school_year text not null, imported_by uuid references users(id), imported_at timestamptz not null default now(), row_version bigint not null default 1, unique (section_id, school_year))`.

- [ ] **Step 1: Write the PG test script** asserting, each as one `do $$ … $$` block that raises on failure:
  - `tutor_cannot_set_import_source`: a tutor (helpers set `request.jwt.claims`) inserting an assessment with `import_source = 'workbook'` → error.
  - `coordinator_imported_session_skips_round_and_repeat`: coordinator inserts an imported BOSY session for a Grade 7 learner, reading a `mosy` passage → accepted; a second imported session reading the same text → accepted; a **live** session reading that text afterwards → `already read`.
  - `imported_reading_keeps_own_grade`: imported Grade 7 session reading a level-2 passage of a grade-leveled collection → `a Grade 7 learner reads a Grade 7 passage`.
  - `null_word_index_only_imported`: miscue with `word_index null` on a live reading → error; on an imported reading → accepted.
  - `imported_correct_rules`: on a `scoresheet` session → error; on `workbook` above the passage's question count → error; together with an answer row → error (both orders).
  - `import_source_immutable`: update of `import_source` → `only the status of a Phil-IRI assessment can change`.
  - `lock_unique_and_rls`: second lock for the same section/year → unique violation; tutor select → 0 rows; other school's coordinator insert → RLS error; insert with `RETURNING *` by the right coordinator → 1 row (F14).
  - `lock_travels_in_sync`: `sync_apply` of an upload holding a new imported session + its lock row applies both; a second upload with another lock for the same section/year → upload status `error`, nothing applied.
  - `grants`: `has_table_privilege('anon','public.phil_iri_workbook_imports','select')` is false.
- [ ] **Step 2: Run it against the harness without the new migration** → fails at the first block (column `import_source` does not exist).
- [ ] **Step 3: Write the migration.** Header comment as in `20261029010000_phil_iri_struggling_level.sql` (what, why, RLS, `App update required on all devices: yes`). Contents:
  - columns above; replace `phil_iri_assessments_before_insert()` (keep the body; add: `import_source` non-null requires `is_superadmin() or (current_user_role() in ('admin','coordinator') and current_user_school_id() = new.school_id)` — use the helper names the baseline uses for own-school checks) and `phil_iri_assessments_before_update()` (add `new.import_source` to the immutable tuple).
  - replace `check_phil_iri_reading()`: read the session's `import_source`; when non-null skip the active, test-type and no-repeat blocks; own-grade unchanged. Add `imported_correct` checks there (source must be `workbook`; ≤ `count(*)` of the passage's questions; no rows in `phil_iri_answers` for this reading).
  - replace the miscue check function (baseline line ~596): when `new.word_index is null`, require the reading's session `import_source is not null`, skip the position check.
  - answers insert check: refuse when the reading has `imported_correct` set.
  - lock table, RLS (select/insert: `is_superadmin()` or own-school admin/coordinator; checked on the row's own columns), no update/delete policy, grants, `row_version` + `sync_row_version` trigger.
  - add `phil_iri_workbook_imports` to the synced-table arrays and `sync_key_column`/`sync_ref_columns`/`sync_check_payload`/`sync_apply` definitions exactly as `20261023040000_aral_classes.sql` did for `aral_classes` (copy the latest definitions, add the table after `phil_iri_rubric_scores`).
  - final `insert into basa_migrations … ('20261109010000','phil_iri_import', true)` like the previous migrations.
- [ ] **Step 4: Run the PG script** (twice: the migration is idempotent) → all blocks pass. Run `flutter test test/supabase/migration_grants_test.dart` → PASS.
- [ ] **Step 5: Owner applies the migration on the dev cloud** (SQL Editor) after every device has synced (README *Keeping BASA up to date*). Verify kit: `D:\0_CAPSTONE\verify\phil-iri-import\t1\` with the read-only checks (columns exist, policies listed, ledger row).
- [ ] **Step 6: Commit message for the owner:**
  ```
  feat(phil-iri,db): mark imported sessions; miscues without position; workbook import lock

  - phil_iri_assessments.import_source (workbook|scoresheet), set only by an
    admin/coordinator of the school or the superadmin, never changed
  - imported sessions skip the round, no-repeat and active-passage checks;
    the own-grade check stays (spec D8)
  - phil_iri_miscues.word_index nullable for imported sessions only (D3)
  - phil_iri_readings.imported_correct for workbook sessions (no answers)
  - phil_iri_workbook_imports: one-time lock per section and year, synced,
    RLS own school / superadmin, no update or delete
  App update required on all devices: yes
  ```

### Task 2: Device schema v40, models, sync lists

**Files:**
- Modify: `lib/core/data/local/local_database.dart` (version 39 → 40), `lib/core/data/local/phil_iri_local_schema.dart`, `lib/core/data/pull_tables.dart`, `lib/core/data/local/sync_local_schema.dart` (`_originTables`), `lib/core/services/sync_review_lines.dart`, `lib/core/models/phil_iri_assessment.dart`, `lib/core/models/phil_iri_reading.dart`, `lib/core/models/phil_iri_miscue.dart`, every caller that reads `PhilIriMiscue.wordIndex` as non-null (grep), `lib/core/CLAUDE.md`
- Create: `lib/core/models/phil_iri_workbook_import.dart`
- Test: `test/core/data/phil_iri_import_v40_test.dart`

**Interfaces:**
- Produces: `PhilIriAssessment.importSource` (`PhilIriImportSource?`, map key `import_source`); `enum PhilIriImportSource { workbook, scoresheet }` with `.value` and `fromValue` (in `phil_iri_workbook_import.dart`, exported); `PhilIriReading.importedCorrect` (`int?`, `imported_correct`); `PhilIriMiscue.wordIndex` → `int?` (null = "position not recorded"); `class PhilIriWorkbookImport { final int? id; final int schoolId; final int sectionId; final String schoolYear; final String? importedBy; final String? importedAt; toMap/fromMap }`.

- [ ] **Step 1: Write the failing tests** in `phil_iri_import_v40_test.dart` (pattern: `phil_iri_readings_v39_test.dart`, v39 tables built by hand then `LocalDatabase.instance` upgrades):
  - `v39 miscues survive the rebuild with row_version` — rows and `row_version` equal before/after; `word_index` column `notnull = 0` (`PRAGMA table_info`).
  - `null position refused on a live reading` / `accepted on an imported reading` (local trigger message `Word position is outside the passage` stays for bad positions; new message `A miscue without a position belongs to an imported reading`).
  - `imported session skips round and repeat checks, keeps own grade` (same three cases as Task 1, SQLite triggers).
  - `imported_correct refused on scoresheet and live sessions, above the question count, and with answers` (messages as Task 1, sentence case like the existing local ones).
  - `import_source cannot change` → `Only the status of a Phil-IRI assessment can change`.
  - `lock table is synced` — `syncedTables.containsKey('phil_iri_workbook_imports')`, a local insert writes a `sync_changes` row, `origin` column exists, second lock for the same section/year → UNIQUE error.
- [ ] **Step 2: Run** `flutter test test/core/data/phil_iri_import_v40_test.dart` → FAIL (no column / version 39).
- [ ] **Step 3: Implement.** `rebuildPhilIriMiscuesForV40(Database db)` in `phil_iri_local_schema.dart` copying the v39 readings pattern (old column list kept, `legacy_alter_table` on, triggers dropped and recreated by the creator); called in `local_database.dart` before `createPhilIriLocalSchema` when `oldVersion < 40`; `ALTER TABLE … ADD COLUMN` for `import_source` / `imported_correct` guarded by `PRAGMA table_info`; triggers updated as in Task 1; lock table created in the creator with `origin` and `UNIQUE (section_id, school_year)`. Lists: `pullOrder` (after `phil_iri_rubric_scores`), `pullClearOrder` (before `phil_iri_rubric_scores`), `syncedTables` (after `phil_iri_rubric_scores`, key `id`; comment count 18 → 19), `_originTables`, `sync_review_lines.dart` label `('workbook import', 'workbook imports')`. Models' `toMap`/`fromMap`. Callers of `wordIndex` (e.g. `_miscueText` in `phil_iri_commands.dart`) print `position not recorded` for null.
- [ ] **Step 4: Run** the new test and the whole suite (**DO NOT PLAY RESOURCE INTENSIVE GAMES**) `flutter test` → PASS; `dart analyze`; both tool checks → OK.
- [ ] **Step 5: Verify kit** `t2\`: open an old copy of the verify database (v39) in the admin console, `pull-cloud`, list a session's miscues; expected output in the kit.
- [ ] **Step 6: Commit message:**
  ```
  feat(phil-iri,sqlite): v40 imported sessions, position-less miscues, workbook lock

  - phil_iri_miscues rebuilt with a nullable word_index (rows and row_version kept)
  - import_source / imported_correct columns and the same rules as the cloud
  - phil_iri_workbook_imports mirrored and synced (19 synced tables)
  - models: PhilIriAssessment.importSource, PhilIriReading.importedCorrect,
    PhilIriMiscue.wordIndex nullable ("position not recorded")
  ```

### Task 3: Scoring reads the imported correct count

**Files:**
- Modify: `lib/viewmodels/phil_iri_viewmodel.dart:812-833`
- Test: `test/viewmodels/phil_iri_imported_scoring_test.dart`

**Interfaces:**
- Consumes: `PhilIriReading.importedCorrect` (Task 2).

- [ ] **Step 1: Failing test** (wiring as `phil_iri_screen_calls_test.dart`, coordinator offline owner; seed one 8-question level-7 passage, an imported workbook session with `importedCorrect: 5`, one-minute, `wordsRead: 120`, 3 counted miscues with null positions): `importedCorrect scores like five right answers` → the reading's result `comprehensionScore == 5 / 8` and `wordReadingScore == 117 / 120`.
- [ ] **Step 2: Run** → FAIL (`comprehensionScore` is 0).
- [ ] **Step 3: Implement:** when `r.importedCorrect != null`, `correct = r.importedCorrect!` and skip the answers lookup; `total` stays the passage's question count.
- [ ] **Step 4: Run** → PASS; `dart analyze`.
- [ ] **Step 5: Commit message:** `feat(phil-iri): score a workbook reading from its imported correct count`

### Task 4: Minimal .xlsx writer

**Files:**
- Create: `lib/core/services/xlsx_writer.dart`
- Test: `test/core/services/xlsx_writer_test.dart`

**Interfaces:**
- Produces: `class XlsxSheetSpec { final String name; final Map<String, Object?> cells; /* "B2" -> String|num */ final Set<int> textColumns; /* 1-based, cell format "@" */ final Map<String, String> listValidations; /* "D2:D500" -> "Codes!\$A\$2:\$A\$7" */ final List<double>? columnWidths; }` and `List<int> writeXlsx(List<XlsxSheetSpec> sheets)` (inline strings, one style for text columns, workbook-level only what Excel needs to open it).

- [ ] **Step 1: Failing test** `round trip through XlsxWorkbook` → `XlsxWorkbook.decode(writeXlsx([...]))` gives back sheet names in order, `readSheet` values (text, int, double), and `'00123'` in a text column stays `'00123'`; `the validation is in the sheet XML` (zip entry `xl/worksheets/sheet1.xml` contains `<dataValidation type="list"` and the range).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** with `archive` (`ZipEncoder`) and `xml`: `[Content_Types].xml`, `_rels/.rels`, `xl/workbook.xml`, `xl/_rels/workbook.xml.rels`, `xl/styles.xml` (numFmt 49 for text columns), one `xl/worksheets/sheetN.xml` per spec.
- [ ] **Step 4: Run** → PASS. Owner opens the test's output file in Excel once (kit `t4\open-me.xlsx`): opens without a repair prompt, the drop-down works.
- [ ] **Step 5: Commit message:** `feat(xlsx): minimal workbook writer with text columns and drop-down lists`

### Task 5: Import plan model and header labels

**Files:**
- Create: `lib/core/models/phil_iri_import.dart`, `lib/core/services/phil_iri_import_headers.dart`
- Test: `test/core/services/phil_iri_import_headers_test.dart`

**Interfaces:**
- Produces (`phil_iri_import.dart`):
  - `class PhilIriImportRef { final String sheet; final int row; final String? column; }` (`toString()` → `sheet 03, row 17, column AV`)
  - `class PhilIriLearnerKey { final String? lrn; final String? name; final String? sex; /* 'M'|'F' */ }`
  - `class PhilIriImportSectionRef { final String sheet; final String? depedSchoolId; final String? schoolYear; final int? grade; final String? sectionName; final bool empty; }`
  - `class PhilIriImportPassageRef { final String raw; final int? level; final String? code; final String? title; }`
  - `class PhilIriImportGst { final PhilIriImportRef ref; final PhilIriLearnerKey learner; final int score; final int? max; final String? date; }`
  - `class PhilIriImportReading { final PhilIriImportRef ref; final PhilIriLearnerKey learner; final PhilIriRound round; final String? date; final PhilIriImportPassageRef passage; final PhilIriReadingMethod method; final int? seconds; final int? wordsRead; final Map<PhilIriMiscueType, int> miscues; final int selfCorrected; final List<String?>? answers; final int? correctCount; final String? workbookProfile; final int? workbookAdjustedLevel; }`
  - `class PhilIriImportSkip { final PhilIriImportRef ref; final PhilIriLearnerKey learner; final PhilIriRound? round; final String reason; }`
  - `class PhilIriImportProblem { final PhilIriImportRef ref; final String message; }`
  - `class PhilIriHeaderIssue { final String field; final String block; final List<String> found; }`
  - `class PhilIriImportPlan { final PhilIriImportSource source; final List<PhilIriImportSectionRef> sections; final List<PhilIriImportGst> gst; final List<PhilIriImportReading> readings; final List<PhilIriImportSkip> skipped; final List<PhilIriImportProblem> problems; final List<PhilIriHeaderIssue> headerIssues; }`
- Produces (`phil_iri_import_headers.dart`): `class PhilIriImportHeaders { static Future<PhilIriImportHeaders> load(String directory); Map<String, String> get labels; String label(String field); Future<String?> set(String field, String label); Future<void> reset(); }` persisted to `<dir>/phil_iri_import_headers.json` (only changed labels stored), modelled on `Sf1ColumnMap`. Field names (exact, dotted): `wb.name`, `wb.gst`, `wb.selection`, `wb.wordsRead`, `wb.mispronunciation`, `wb.omission`, `wb.substitution`, `wb.insertion`, `wb.reversal`, `wb.repetition`, `wb.time`, `wb.minutes`, `wb.seconds`, `wb.comprehension`, `wb.method`, `wb.adjProfile`, `wb.adjLevel`, `wb.block.bosy` … `wb.block.eosy`, `ss.lrn`, `ss.round`, `ss.date`, `ss.passage`, `ss.method`, `ss.time`, `ss.wordsRead`, `ss.selfCorrected`, `ss.gst`, `ss.q` (prefix of Q1…Q20) plus one `ss.<miscueType.name>` per `PhilIriMiscueType`.
- Default workbook labels are ma's exact headers (her spellings): `NAME OF STUDENT`, `GST Raw Score`, `SELECTION`, `# of Words Read`, `Mispronounciation`, `Omission / Deletion`, `Substitution`, `Insertion`, `Reversal/Hesitation`, `Repetition / Self-orrection`, `Total Time Reading the Text`, `mm`, `ss`, `Reading Comprehension (Percent Score)`, `Reading Method`, `Adj. Reading Profile`, `Adj. Grade Level`, block titles `IRA FOR GST RESULTS VALIDATION/PRETEST`, `MIDDLE OF SCHOOL YEAR ASSESSMENT (MOSY #1)` (#2, #3), `END OF SCHOOL YEAR ASSESSMENT (EOSY) / POSTTEST`. Labels compare with `normalizeHeader` (`table_reader.dart`), so case, spaces, slashes and line breaks don't matter.

- [ ] **Step 1: Failing tests:** `defaults are ma's labels` (`label('wb.mispronunciation') == 'Mispronounciation'`); `set persists and reload sees it`; `set refuses an unknown field` (returns `Unknown header field "wb.nope"`); `reset restores the defaults and deletes the file`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit message:** `feat(phil-iri,import): import plan model and editable header labels`

### Task 6: Workbook reader

**Files:**
- Create: `lib/core/services/phil_iri_workbook_reader.dart`
- Create: `test/helpers/phil_iri_workbook_fixture.dart` (builds ma-layout workbooks with `writeXlsx`, made-up names)
- Test: `test/core/services/phil_iri_workbook_reader_test.dart`

**Interfaces:**
- Consumes: `XlsxWorkbook` (`readSheet`, `isFormula`, `sheetNames`), `PhilIriImportHeaders`, Task 5 models.
- Produces: `PhilIriImportPlan readPhilIriWorkbook(List<int> bytes, PhilIriImportHeaders headers)`.
- Rules the reader owns (spec "Components"): a section sheet = a sheet where the `wb.name` header and all five block titles are found; any other sheet is ignored. Header row search: rows 9–12. A block spans from its title column to the next title's column. Learner rows: below the `MALES` label until `FEMALES` (sex `M`), below `FEMALES` until an empty run of the name column (sex `F`); an empty name cell = no learner. Section ref from the cells right of `Grade and Section`, `School:` (DepEd ID = digits before ` - `), `SY:` and `Current Grade`. Method per block: the value right of the block's `wb.method` cell (`One-Minute Reading` → `oneMinute`, `Whole-Text Reading` → `wholeText`). Words read counts only when **typed** (`!isFormula`) for one-minute; whole text needs `mm`/`ss` typed. Miscues D4: `wb.reversal` → `reversal` counted, `wb.repetition` → `selfCorrected`. Round outcomes (spec D9 as amended by R1 D18 and R2 D10, `2026-11-10-phil-iri-untitled-readings-design.md`): words read + time with a passage → reading (comprehension may be blank: word reading only); **words read + time with a blank passage → Untitled reading** (`passage: null`; whole text/silent: the typed words-read cell → `wordCount`; one minute: `wordsRead`; a comprehension count → `correctCount` with `correctTotal` = the block's comprehension header maximum; no readable maximum → comprehension dropped, problem `comprehension without a maximum, not imported`); **comprehension only** (passage or not, no time/words read) → reading with no `seconds`/`wordsRead` (Untitled when the passage is blank, `correctTotal` as above); miscue counts on such a row are dropped with a problem `miscues without a time, not imported`; a passage with nothing else → `PhilIriImportSkip(reason: 'incomplete: <what is missing>')`. Comprehension max = the number in the comprehension header's sub-row (row 12); kept for Task 9's check.

- [ ] **Step 1: Failing tests** (fixture builds a 3-sheet workbook: one full section, one empty, one with a renamed header):
  - `finds section sheets by content, ignores the rest`; `empty sheet is listed as empty`.
  - `reads GST, both methods, all five blocks` (values equal the fixture's typed cells).
  - `D4 mapping`: reversal 2 + repetition 3 → `miscues[reversal] == 2`, `selfCorrected == 3`.
  - `one-minute words read left as the formula 0 is incomplete` (**Review Focus 1**) → in `skipped`, not in `readings`.
  - `passage with no comprehension imports as word reading only` (R1 D18).
  - `blank passage with words read and time is Untitled` (R2): whole text → `passage == null`, `wordCount` = the typed cell, `correctTotal` = header max; one minute → `wordsRead`, `wordCount == null`.
  - `comprehension only is a reading without timing` (R2), with and without a passage (blank passage: `passage == null`, `wordCount == null`, `correctTotal` = header max); its miscue counts dropped with the problem line.
  - `passage only is incomplete` (sheets `05`/`20` pattern).
  - `moved column is still found` (fixture inserts a column before `SELECTION`).
  - `renamed header gives a header issue with the headers found`; `with an override it reads`.
  - `cached adj profile and level are carried for the comparison`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Real-file check (scratchpad only):** a throwaway script reads ma's G7 workbook and prints counts only: 29 sections, 1,289 learners, 1,251 GST, BOSY 1,253 readings minus incomplete, MOSY 1 1,140 minus incomplete, MOSY 2 all 129 skipped. Numbers go in the kit `t6\README.md`; no names.
- [ ] **Step 6: Commit message:** `feat(phil-iri,import): read ma's workbook (typed cells only, headers by label)`

### Task 7: Scoresheet template and reader

**Files:**
- Create: `lib/core/services/phil_iri_scoresheet_template.dart`, `lib/core/services/phil_iri_scoresheet_reader.dart`
- Test: `test/core/services/phil_iri_scoresheet_test.dart`

**Interfaces:**
- Consumes: `writeXlsx` (Task 4), `(List<String>, List<TableRow>) readTable(List<int> bytes, String fileName)` (reads the **first** sheet only, so `Learners` must be sheet 1), `TableRow.get(List<String> headers)`, `parseSheetDate` (`table_reader.dart`), Task 5 models.
- Produces: `String philIriPassageCode(PhilIriPassage p)` → `'G${p.level}${p.setCode ?? (p.testType == 'pre' ? 'Pre' : p.testType == 'post' ? 'Post' : '')}'` (e.g. `G7C1`, `G7Pre`, the booklet's codes); `List<int> buildPhilIriScoresheetTemplate({required Section section, required List<Student> learners, required List<PhilIriPassage> passages, required PhilIriImportHeaders headers})`; `PhilIriImportPlan readPhilIriScoresheet(List<int> bytes, String fileName, PhilIriImportHeaders headers)`.
- Template: sheet `Learners` (columns in `headers` order: LRN (text), Learner, Sex, Round, Date, Passage, Method, Time, Words read, the seven miscue types, Self-corrected, GST score, Q1…Q20; one row per learner, pre-filled LRN/Learner/Sex); sheet `Codes` (rounds `GST, BOSY, MOSY1, MOSY2, MOSY3, EOSY`; methods `whole text, one minute`; `philIriPassageCode` + title of every active passage of the section's grade; miscue types); sheet `Instructions` (the five steps of spec "Guide" 3, verbatim). Drop-downs for Round, Method, Passage.
- Reader (R2 D3, D6): a blank passage code is a problem (`Passage is required`), never an Untitled reading; a row with answers and no time/words read is a comprehension-only reading. Ignores case and extra spaces; time `m:ss`, whole seconds, or an Excel day fraction (`< 1` → `round(x * 86400)`); answers `a`–`z` any case, blank = null; `GST` rows need only the score and the date; every row needs a date (D6: missing → problem `Date is required`); LRN text kept as typed, a numeric LRN converted to its 12-digit form (`padLeft(12, '0')`); unreadable value → `PhilIriImportProblem` with row and column letter.

- [ ] **Step 1: Failing tests:** `template round trip` (build → fill rows in the test → read back: plan entries equal the filled values); `GST row`; `Excel-mangled values` (**Review Focus 4**: LRN `123456789012.0`, date serial `45883`, time `0.10763888888888888` → `155` s); `unknown round names the row and column`; `blank answer stays null and the row is kept`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. Owner opens a generated template in Excel (kit `t7\`).
- [ ] **Step 5: Commit message:** `feat(phil-iri,import): per-section scoresheet template and its reader`

### Task 8: Local import writer

**Files:**
- Create: `lib/core/repositories/phil_iri_import_writer.dart`, `lib/core/data/local/phil_iri_import_writer_sqlite.dart`
- Test: `test/core/data/phil_iri_import_writer_test.dart`

**Interfaces:**
- Produces: `class PhilIriImportedSession { final PhilIriAssessment assessment; /* importSource set, status inProgress */ final PhilIriReading reading; final List<PhilIriMiscue> miscues; /* wordIndex null */ final List<PhilIriAnswer> answers; }`; `abstract class PhilIriImportWriter { Future<List<int>> writeLearner({required List<PhilIriImportedSession> sessions, PhilIriGstResult? gst, PhilIriWorkbookImport? lock}); Future<bool> isLocked(int sectionId, String schoolYear); }`.
- One `db.transaction` per call: GST, then per session the assessment (negative id via `nextLocalId`), reading, miscues, answers, then `status = completed`, `completed_at = now (UTC ISO)`; then the lock row. Any trigger error rolls the whole learner back and is rethrown.
- R2: an Untitled reading is written with `passage_id` null, `imported_word_count` (whole text/silent), `imported_correct` + `imported_total`, miscues without a position, no answers; a comprehension-only reading with no `reading_seconds`/`words_read`. The v42 triggers refuse anything else (workbook sessions only).

- [ ] **Step 1: Failing tests:** `writes an Untitled and a comprehension-only reading` (R2: row columns as above, session completes; include an Untitled comprehension-only row: `passage_id` null, untimed, no `imported_word_count`); `writes a learner and journals every row` (rows exist, `sync_changes` has them, statuses `completed`); `a failing session rolls the learner back` (second session reads a lower-grade passage → nothing of that learner is left); `lock row written once and isLocked sees it`.
- [ ] **Step 2–4:** Run → FAIL; implement; run → PASS.
- [ ] **Step 5: Commit message:** `feat(phil-iri,import): write one imported learner per device transaction`

### Task 9: `PhilIriImportViewModel` — preview

**Files:**
- Create: `lib/viewmodels/phil_iri_import_viewmodel.dart`, `lib/core/services/phil_iri_import_matching.dart`
- Test: `test/viewmodels/phil_iri_import_preview_test.dart`, `test/core/services/phil_iri_import_matching_test.dart`

**Interfaces:**
- Consumes: Tasks 5–8; `PhilIriViewModel.effectiveThresholds(int schoolId)`; `philIriScorePassage`, `philIriRoundResults`; `RoundCalendarViewModel.effectiveCalendar(int? schoolId, String year)`; `SyncUploadLocalRepository.buildPackage(release: SyncViewModel.release)`; `SyncRecord`, `toServerRow`, `followUpsForNew`, `maxPackageBytes`.
- Produces (matching, pure): `String philIriNameKey(String name)` (lowercase, letters only, words sorted, so "Dela Cruz, Juan M." == "Juan M. Dela Cruz"); `List<Student> philIriNameCandidates(PhilIriLearnerKey key, List<Student> learners)`; `PhilIriPassage? philIriMatchPassage(PhilIriImportPassageRef ref, List<PhilIriPassage> all)` (level + `philIriNameKey(title)`; active first; code as tie-breaker; parses `7C Dust`, `4C-Pre Anansi's Web`, `10A -Pre Butuan…`).
- Produces (ViewModel):
  - `enum PhilIriImportOutcome { import, importFlagged, skipped }`
  - `class PhilIriImportRow { final PhilIriImportReading? reading; final PhilIriImportGst? gst; final Student? student; final List<Student> candidates; final PhilIriPassage? passage; final PhilIriImportOutcome outcome; final List<String> notes; /* flags or the skip reason */ final String? basaProfile; final int? basaAdjustedLevel; }`
  - `class PhilIriImportSectionPreview { final PhilIriImportSectionRef ref; final Section? section; final String status; /* 'importable'|'empty'|'not in BASA'|'already imported' */ final List<PhilIriImportRow> rows; final int uploadBytes; }`
  - `class PhilIriImportPreview { final PhilIriImportPlan plan; final List<PhilIriHeaderIssue> headerIssues; final List<PhilIriImportSectionPreview> sections; final Map<PhilIriRound, String?> proposedDates; final int unsentBytes; final String oneTimeWarning; final String fingerprint; }`
  - `class PhilIriImportChoices { final Set<String> sheets; final Map<String, int> picks; /* learner row's PhilIriImportRef.toString() (column null: "sheet 03, row 17") -> studentId */ final Map<PhilIriRound, String> dates; }`
  - Header step: when `plan.headerIssues` is not empty the preview has **no** sections (nothing else checked) and `PhilIriImportPreview.headerIssues` lists them; `List<String> headerSamples(List<int> bytes, String field, String label, {int count = 5})` returns the first values under `label` in that field's block(s), numbers and codes only (the name column is refused: `Names are not shown here.`).
  - `Future<PhilIriImportPreview> previewWorkbook(List<int> bytes, {PhilIriImportChoices choices})`, `Future<PhilIriImportPreview> previewScoresheet(int sectionId, List<int> bytes, String fileName)`
  - `oneTimeWarning` exact copy: `This makes BASA the record for this section's school year. You can't import this section's workbook again.`
  - Refusal for tutors (also an `[admin]` marker): `Forbidden: only an admin or coordinator imports Phil-IRI results.`

- [ ] **Step 1: Failing matching tests:** `name order and punctuation ignored`; `same name twice gives two candidates` (**Review Focus 2**); `passage titles match across case and punctuation` (**Review Focus 5**: `Get up, Jacky!` ↔ `Get Up, Jacky!`, `10A -Pre Butuan Archeological Sites`); `inactive passage only when no active one matches`.
- [ ] **Step 2: Failing preview tests** (coordinator offline owner; seeded school, Grade 7 section, learners, pool passages; workbook from the Task 6 fixture):
  - `round clash and re-read are imported, flagged`; `lower-grade passage skipped`; `passage not in BASA skipped`.
  - R2: `Untitled reading is imported, flagged` (note `no passage (Untitled)`; passage matching, lower-grade, round-clash and re-read checks skipped for it; `basaProfile` from the typed word count); `comprehension-only reading is imported` (status in BASA: carried over); `Untitled comprehension above its total is unreadable`.
  - `comprehension above the passage's questions is unreadable` (**Review Focus 3**): note names sheet, row, column.
  - `already assessed and in progress live are skipped`; `GST skipped when one exists this year`.
  - `locked section is 'already imported'`; `section missing in BASA is 'not in BASA' with its name`.
  - `proposed dates come from the calendar`; `levels that differ from the workbook are listed` (`basaProfile` vs `workbookProfile`).
  - `upload bytes estimated` (> 0 per importable section; equals the byte length of the would-be `SyncRecord`s' JSON within 5%).
  - `tutor refused` with the exact message.
  - `header issues stop the preview` (no sections); `headerSamples gives the column's first values`; `headerSamples refuses the name column`.
- [ ] **Step 3: Run** → FAIL. **Step 4: Implement.** Thresholds: `effectiveThresholds(section.schoolId)`; GST fraction for `philIriRoundResults` = score / max. **Step 5: Run** → PASS.
- [ ] **Step 6: Commit message:** `feat(phil-iri,import): preview of a workbook or scoresheet import`

### Task 10: `PhilIriImportViewModel` — import, template, headers, wiring

**Files:**
- Modify: `lib/viewmodels/phil_iri_import_viewmodel.dart`, `lib/core/wiring/wire_admin.dart`, `lib/viewmodels/admin_viewmodels.dart`
- Test: `test/viewmodels/phil_iri_import_run_test.dart`

**Interfaces:**
- Produces: `class PhilIriImportResult { final PhilIriImportPreview preview; final List<int> sessionIds; final List<int> gstIds; final Map<String, String> failed; /* ref -> reason */ }`; `Future<PhilIriImportResult> importWorkbook(List<int> bytes, PhilIriImportChoices choices)`; `Future<PhilIriImportResult> importScoresheet(int sectionId, List<int> bytes, String fileName)`; `Future<List<int>> scoresheetTemplate(int sectionId)`; `Map<String, String> headerLabels()`, `Future<String?> setHeader(String field, String label)`, `Future<void> resetHeaders()`. Registered as `'PhilIriImportViewModel'`; `AdminViewModels.philIriImport`.
- Import steps (spec): rebuild the preview with the choices; stale when its `fingerprint` (hash of plan + matched ids + existing session ids) differs → `The data changed since the preview. Preview again before importing.`; a workbook round without a date → `Give a date for <round label>.`; D19: ticked sections' `uploadBytes` + `unsentBytes` > `maxPackageBytes` → `Too much for one upload: <n> of the ticked sections fit (<names>). Import them, upload, then import the rest.`; one `writeLearner` per learner, the lock with the section's last learner.

- [ ] **Step 1: Failing tests:** `imports a workbook section and locks it` (sessions `completed`, `import_source = workbook`, miscues without position, lock row); `second import of the section is refused`; `scoresheet import twice skips what is there`; `stale preview refused`; `missing round date refused`; `too much for one upload refused with how many fit` (set a tiny limit through a constructor parameter `int maxBytes = maxPackageBytes`); `failed learner reported, others imported`; `template lists the section's learners`.
- [ ] **Step 2–4:** Run → FAIL; implement + wire; run → PASS; `dart run tool/check_tutor_imports.dart` → OK.
- [ ] **Step 5: Commit message:** `feat(phil-iri,import): import runs, one-time lock, upload-size batches; wired in the admin build`

### Task 11: Console commands and the build checks

**Files:**
- Create: `lib/core/console/commands/phil_iri_import_admin_commands.dart`
- Modify: `lib/core/wiring/wire_admin.dart` (`registerPhilIriImportCommands`), `tool/check_tutor_imports.dart` (wholly admin list), `tool/admin_markers.txt` (`[admin]`: the Task 9 refusal), `test/core/wiring/admin_commands.txt`, `test/tool/command_pass/coverage_test.dart` (247 → 255), `CLAUDE.md` (counts; module checklist line), new `tool/command_pass/scenarios/37_a7.pass`, `docs/handoff/screens/` (new `phil-iri-import.md`: the ViewModel calls and the preview/result models the screens show, the one-time warning before the button)
- Test: `test/core/wiring/command_sets_test.dart` (existing, picks up the list)

**Interfaces:**
- Consumes: Task 10 ViewModel only (boundary check).
- Produces: the eight commands of spec "Console", output one line per preview row: `IMPORT | FLAG <notes> | SKIP <reason>`, `<sheet row> <learner (masked to initials)> <round> <passage>`, then totals and `upload ≈ <KB> of <limit> KB`.

- [ ] **Step 1:** Add the names to `admin_commands.txt` and the totals → `flutter test test/core/wiring/command_sets_test.dart test/tool/command_pass/coverage_test.dart` → FAIL.
- [ ] **Step 2: Implement** (pattern `crla_import_admin_commands.dart`: `requireActiveSession` guard, usage errors, `$name failed: $e`). `picks=03:17=4512` parses to `{'sheet 03, row 17': 4512}`; `dates=bosy:2026-08-14,mosy1:2026-11-20`.
- [ ] **Step 3: Run** those tests → PASS; `dart analyze`; both tool checks; scenario `37_a7.pass` on the dev cloud (**DO NOT PLAY RESOURCE INTENSIVE GAMES**): template → fill (fixture file shipped in `tool/command_pass/fixtures/`) → preview → import → `sync-upload` → second import refused → tutor `pull-cloud` sees the sessions; `dart run tool/command_pass/run.dart --run r<N> a7` → clean.
- [ ] **Step 4: Verify kit** `t11\` with the console commands, ids and expected output.
- [ ] **Step 5: Commit message:**
  ```
  feat(phil-iri,console): phil-iri-import-* admin commands (8)

  - template, header labels (list/set/reset), workbook and scoresheet preview/import
  - admin console 247 -> 255; tutor unchanged (126); marker for the new refusal
  - command pass scenario a7; screen handoff docs/handoff/screens/phil-iri-import.md
  ```

### Task 12: End-to-end on the dev cloud with a release build

**Files:** none new (kit only).

- [ ] **Step 1:** Owner closes any open console. Admin console on the dev cloud: import two sections of a fixture workbook (not ma's file), upload, finalize one imported session, tutor device pulls and opens the learner's results (console `phil-iri-results`): levels shown, miscue list says `position not recorded`.
- [ ] **Step 2:** `powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 …` on `frontend_dev` after the PR (**DO NOT PLAY RESOURCE INTENSIVE GAMES**): marker scan finds the new `[admin]` refusal in the admin scan build and in no tutor build.
- [ ] **Step 3:** Kit `t12\README.md` with the results. No commit (nothing changed), unless a fix was needed (its own message).

### Task 13: Guide page (after the groupmates' screens exist)

**Files:**
- Create: `tool/installer/guide/admin/Functions/Importing_data.txt`
- Modify: `tool/installer/guide/admin/Home.txt`, `tool/installer/guide/admin/Checklist/02_Before_the_school_year.txt` (link + "Moving from the workbook to BASA" step), `tool/installer/guide/tutor/Checklist/*Every_time*` (the download line)

- [ ] **Step 1:** Write the page exactly as spec "Guide" 1–7 (Zim format: `Content-Type: text/x-zim-wiki`, `Wiki-Format: zim 0.6` header; `[ ]` checkboxes; `[[:Functions:…|…]]` links), button names from the real screens; any name not yet on a screen marked //(to confirm)//. FAQ entries: every item of spec "Guide" 7.
- [ ] **Step 2:** Open the notebook in Zim: page renders, links resolve (kit `t13\`).
- [ ] **Step 3: Commit message:** `docs(guide): importing Phil-IRI data — workbook, scoresheet file, AI tips, FAQ`
