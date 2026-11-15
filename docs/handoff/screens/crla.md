# CRLA (Grades 1–3)

### Section CRLA list
Build: both    Roles: tutor (own sections, class learners) / coordinator / admin
Purpose: a section's CRLA attempts and results for a year, per learner.
Calls:
- `CrlaViewModel.loadForSection(sectionId, schoolYear:)` → `assessments`; `loadResultsForSection(...)` → `results: List<CrlaResult>`; `loadResultsForStudent(studentId)`; `refresh()`
- learner names: `StudentViewModel.localStudents(sectionId)` (results carry `studentId`)
Live previews: none.
Errors: not signed in.
Console: `crla-results`

### Start a CRLA attempt
Build: both    Roles: tutor / coordinator / admin
Purpose: start an attempt for a learner: variant (mother tongue / Filipino / English), language, round.
Calls:
- `CrlaViewModel.startAssessment(studentId:, sectionId:, schoolYear:, subjectVariant:, language:, round:, administeredBy:)` → `CrlaAssessment`
- `crlaSubjectVariants`, `crlaDefaultLanguage(variant)` (`core/models/crla_variant.dart`); `startAssessment` fills the default language (mt has none: it needs one, e.g. Cebuano)
- rounds: `CrlaRound.values` (`label`)
- stories / languages: `CrlaViewModel.loadStories(regionId, language:, grade:)` → `stories`
Live previews: none.
Errors: not Grades 1–3, section of another school, round closed (ViewModelException / server refusal).
Console: `crla-start`, `crla-stories`

### Part 1 and Part 2 entry
Build: both    Roles: tutor / coordinator / admin
Purpose: enter Part 1 (standard or English) and Part 2 (story, miscues, time, comprehension).
Calls:
- `CrlaViewModel.savePart1Standard(...)`, `savePart1English(...)`, `savePart2Fluency(assessmentId:, storyNo:, miscues:, wordsRead:, timeMinutes:, timeSeconds:, comprehensionCorrect:, ...)`
- `getAssessment(id)`, `getResult(id)` → `CrlaResult?` (profile after saving)
- `effectiveThresholds(schoolId)` → `CrlaThresholds` (type from `core/models/crla_types.dart`)
- `storiesForAttempt(assessmentId)` → `List<CrlaStory>` (story 1 first): the stories this attempt's Part 2 can be read from (school's region, attempt's language, section's grade; the same match Part 2 is scored with). Show them by the story number field ("1 · title (N words)"); empty = the region has no story list, so words read is typed. Which story a learner reads is the coordinator's call (they tell tutors); the help page "Story number and words read" explains it.
Live previews: none. Not available yet: a profile / wpm preview before saving (the profile is shown after saving).
Errors: locked by a pending upload, words= needed where the region has no story (ViewModelException).
- `removeAttempt(assessmentId)`: removes an attempt started by mistake (wrong learner, test, language or round) with its Part 1 and Part 2. Only an attempt made on this device and not uploaded (negative id), the learner's latest for that test in that section and year, not waiting in an upload, not used by an ARAL roster entry. Offer the button only for a negative id; the ViewModel refuses the rest with a message to show as is (`crlaRemoveUploadedMessage` for an uploaded one). **Warning to show** (confirm dialog, and on the help page): only the learner's latest one, and only before it is uploaded; once on the server it stays (ask the coordinator).
Console: `crla-part1`, `crla-part2`, `crla-attempt-stories`, `crla-remove`

### CRLA thresholds
Build: both (view) / admin (edit)    Roles: view all; set/reset admin / coordinator
Calls:
- `CrlaThresholdViewModel.thresholdLayers(schoolId)` → `CrlaThresholdLayers` (`region`, `school`, `effective`, `defaults`)
- `saveThresholds(...)`, `resetSchoolThresholds(schoolId)`, `regenerate(assessmentIds)` → `int`; `lastMirrorWarning` → `String?`
Console: `crla-thresholds`, `crla-threshold-set`, `crla-threshold-reset`, `crla-regenerate`

### Scoresheet export (CRLA2 template)
Build: both    Roles: tutor / coordinator / admin
Purpose: fill the blank DepEd CRLA2 scoresheet of the section's grade with a round's results.
Calls:
- `CrlaExportViewModel.exportScoresheet(sectionId, templateBytes, round:, teacher:)` → `CrlaScoresheetExport` (`bytes`, `learners`, `resultsByVariant`, `notes`); the screen saves `bytes`
Console: `crla-export`

### Scoresheet import
Build: admin    Roles: admin / coordinator
Purpose: read a filled CRLA2 scoresheet into assessments: preview, then import.
Calls:
- `CrlaImportViewModel.preview(sectionId, bytes, round:, again:)` → `CrlaImportPreview` (rows with outcome/problems; `file: CrlaScoresheetFile`, `row: CrlaScoresheetRow`; types from `core/models/crla_types.dart`)
- `importScoresheet(...)` → `CrlaImportResult`
Console: `crla-import-preview`, `crla-import`
