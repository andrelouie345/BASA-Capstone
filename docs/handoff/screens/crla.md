# CRLA (Grades 1–3)

### Section CRLA list
Build: both    Roles: tutor (own sections, class learners) / coordinator / admin
Purpose: a section's CRLA attempts and results for a year, per learner.
Calls:
- ✅ `CrlaViewModel.loadForSection(sectionId, schoolYear:)` → `assessments`; `loadResultsForSection(...)` → `results: List<CrlaResult>`; `loadResultsForStudent(studentId)`; `refresh()`
- ✅ learner names: `StudentViewModel.localStudents(sectionId)` (results carry `studentId`)
Live previews: none.
Errors: not signed in.
Console: `crla-results`

### Start a CRLA attempt
Build: both    Roles: tutor / coordinator / admin
Purpose: start an attempt for a learner: variant (mother tongue / Filipino / English), language, round.
Calls:
- ✅ `CrlaViewModel.startAssessment(studentId:, sectionId:, schoolYear:, subjectVariant:, language:, round:, administeredBy:)` → `CrlaAssessment`
- 🆕 variant list + default language per variant — CRLA-G1
- ✅ rounds: `CrlaRound.values` (`label`)
- ✅ stories / languages: `CrlaViewModel.loadStories(regionId, language:, grade:)` → `stories`
Live previews: none.
Errors: not Grades 1–3, section of another school, round closed (ViewModelException / server refusal).
Console: `crla-start`, `crla-stories`

### Part 1 and Part 2 entry
Build: both    Roles: tutor / coordinator / admin
Purpose: enter Part 1 (standard or English) and Part 2 (story, miscues, time, comprehension).
Calls:
- ✅ `savePart1Standard(...)`, `savePart1English(...)`, `savePart2Fluency(assessmentId:, storyNo:, miscues:, wordsRead:, timeMinutes:, timeSeconds:, comprehensionCorrect:, ...)`
- ✅ `getAssessment(id)`, `getResult(id)` → `CrlaResult?` (profile after saving)
- ✅ `effectiveThresholds(schoolId)` → `CrlaThresholds` (class T: CRLA-G3)
Live previews: a profile/wpm preview before saving has no call — CRLA-G4 (M).
Errors: locked by a pending upload, words= needed where the region has no story (ViewModelException).
Console: `crla-part1`, `crla-part2`

### CRLA thresholds
Build: both (view) / admin (edit)    Roles: view all; set/reset admin / coordinator
Calls:
- ✅ `CrlaThresholdViewModel.thresholdLayers(schoolId)` → `CrlaThresholdLayers` (`region`, `school`, `effective`) — default missing: CRLA-G2
- ✅ `saveThresholds(...)`, `resetSchoolThresholds(schoolId)`, `regenerate(assessmentIds)` → `int`; `lastMirrorWarning` (class E: CRLA-G5)
Console: `crla-thresholds`, `crla-threshold-set`, `crla-threshold-reset`, `crla-regenerate`

### Scoresheet export (CRLA2 template)
Build: both    Roles: tutor / coordinator / admin
Purpose: fill the blank DepEd CRLA2 scoresheet of the section's grade with a round's results.
Calls:
- ✅ `CrlaExportViewModel.exportScoresheet(sectionId, templateBytes, round:, teacher:)` → `CrlaScoresheetExport` (`bytes`, `learners`, `resultsByVariant`, `notes`); the screen saves `bytes`
Console: `crla-export`

### Scoresheet import
Build: admin    Roles: admin / coordinator
Purpose: read a filled CRLA2 scoresheet into assessments: preview, then import.
Calls:
- ✅ `CrlaImportViewModel.preview(sectionId, bytes, round:, again:)` → `CrlaImportPreview` (rows with outcome/problems; `file: CrlaScoresheetFile`, `row: CrlaScoresheetRow`: class T, CRLA-G3)
- ✅ `importScoresheet(...)` → `CrlaImportResult`
Console: `crla-import-preview`, `crla-import`

## Gaps

**CRLA-G1** (N) — The variants (`mt`, `fil`, `eng`) and their default language (fil → Tagalog, eng → English, mt must be named) are only in `crla-start`'s argument code. A screen's form needs both, and the rule would otherwise be rebuilt in a widget.
Fix: `core/models/crla_variant.dart`: `const crlaSubjectVariants = ['mt', 'fil', 'eng'];` and `String? crlaDefaultLanguage(String variant)` (same mapping); `startAssessment`'s `language` becomes optional and the ViewModel fills the default (ViewModelException "The mt variant needs a language (e.g. Cebuano)." when missing); the command uses both. No console text changes.
Decision: (open)

**CRLA-G2** (I, N) — `crla-thresholds` reads `CrlaThresholds.defaults` from `crla_rules.dart` to show each key's default.
Fix: `CrlaThresholdLayers.defaults` (`CrlaThresholds`, = `CrlaThresholds.defaults`), per COMMON-G2.
Removes baseline: `core/console/commands/crla_threshold_commands.dart -> core/services/crla_rules.dart`
Decision: (open)

**CRLA-G3** (T) — `CrlaThresholds` (`crla_rules.dart`), `CrlaScoresheetFile`, `CrlaScoresheetRow` (`crla_scoresheet.dart`) are service types in ViewModel results.
Fix: `core/models/crla_types.dart` with `export '../services/crla_rules.dart' show CrlaThresholds;` and `export '../services/crla_scoresheet.dart' show CrlaScoresheetFile, CrlaScoresheetRow;`.
Decision: (open)

**CRLA-G4** (M) — No preview of wpm / reading profile while Part 2 is typed (the profile comes from the results view after saving).
Fix: deferred (no console capability; the screen shows `getResult` after saving).
Decision: (open)

**CRLA-G5** (E) — `crla_threshold_viewmodel.dart:237` puts `$e` in `lastMirrorWarning`.
Fix: spec rule.
Decision: (open)
