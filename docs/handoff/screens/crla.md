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

### Digitized CRLA: mark it in BASA (2026-11-27, consultation item M1-02)
Build: both    Roles: tutor (own sections at BOSY, ARAL class learners) / coordinator / admin
Spec: `docs/superpowers/specs/2026-11-27-crla-digitized-design.md`.
Purpose: the tutor gives CRLA from the tablet instead of the paper record form. A split screen: the learner's side
shows the items or the story large; the tutor's side has the marks, the timer and the questions with the accepted
answers. Every mark and timer tap is kept, and BASA works out the Part 1 / Part 2 totals, levels and profile from them.
Region X forms only for now (19 forms: Grades 1-3, every language on the DepEd tool); elsewhere the tutor types the
totals as before.

Layout (suggested, landscape tablet):
```
+---------------------------+----------------------------+
|  LEARNER                  |  TUTOR  Task 1  6/10       |
|                           |  1 Naglalaba  [right][wrong]|
|     Naglalaba si Tatay    |  2 si         [right][wrong]|
|     sa palanggana.        |  ...           [self-corr.] |
|                           |  [Done with Task 1]         |
+---------------------------+----------------------------+
|  Isang Kakaibang Araw     |  01:20 / 2:00  [Pause][Stop]|
|  Iba't ibang tao ang      |  miscues 2 . words read 94  |
|  ~~sumasakay~~ sa jeepney |  Q1 Sino ang kasama ...?    |
|  ni Tatay.                |     accepted: wala, mag-isa |
|                           |     [right][wrong][N/A]     |
+---------------------------+----------------------------+
```
Calls (`CrlaViewModel`; marks and taps return `CrlaDigitizedState` from `core/models/crla_form.dart`):
- `form(assessmentId)` -> `CrlaForm`: `items[CrlaTask]` (item number, text, `answerKey` for Grade 1 rhyming pairs),
  `stories` (`CrlaFormStory`: `sentences` for the learner's side, `words` = the tappable words, 0-based,
  `questions` with `afterSentence` and `acceptedAnswers`), `timeLimitSeconds`. Refused with `crlaNoFormMessage` where
  the region has no form: then show the typed entry above.
- `digitized(assessmentId)` -> the state to draw: `task1Score`, `task1Done`, `task2` (the Task 2 the Task 1 score leads
  to; null = the test ends, English Task 1 = 0), `task2Score`, `storyNo`, `timerStatus`, `elapsed`, `timedSeconds`,
  `lastWordNeeded`, `lastWordReached`, `miscues`, `wordsRead`, `comprehension`, `label` ("Marked in BASA" / "Totals
  typed in"), and every mark in `evidence`.
- Part 1: `markItem(id, task, itemNo, correct:, selfCorrected:)`, `unmarkItem(id, task, itemNo)`, `closeTask(id, task)`
  ("Done": the items not marked are wrong, as on paper). Task 2 opens once every Task 1 item is marked. A Task 1
  change that switches the Task 2 (low <-> high, or English to 0) is refused with "This changes which Task 2 is given;
  confirm to clear its marks." Ask the tutor, then repeat the call with `confirm: true`.
- Part 2: `startStoryTimer(id, storyNo)` picks the story (1 or 2) and starts the time; `pauseStoryTimer`,
  `resumeStoryTimer`, `stopStoryTimer` (the learner finished), `resetStoryTimer` (Restart: ask "Time this story again?
  The first timing stays in the record."). `toggleWord(id, wordIndex)` marks a miscue, again removes it;
  `kind: CrlaWordMarkKind.selfCorrected` for a self-correction (recorded, not counted). `answerQuestion(id, questionNo,
  CrlaAnswerMark.correct | incorrect | notAsked)`.
- While the timer runs, call `storyTimer(id)` about once a second for the clock: at the grade's limit (`timeLimitSeconds`)
  it stops itself, dated at the limit (also when the app was closed). Then `lastWordNeeded` is true: ask "Tap the last
  word the learner reached" and call `setLastWordReached(id, wordIndex)`. Part 2 is saved only after that.
- `saveObservation(id, learnerExperienceRating:, observationLevel:, remarks:)`: the typed fields of Part 2 (after the
  story is timed).
- A marked attempt refuses the typed saves above (`crlaTypedRefusal`), and an attempt with typed totals can't be marked
  (start a new attempt instead). `removeAttempt` removes the marks too.
Live previews: the state after every call (task scores, miscues, words read, comprehension); the profile from
`getResult(id)`.
Errors: shown as they come (`ViewModelException`): "Finish Task 1 first.", "Task 1 is 0: the test ends here.", "This
Task 2 is not the one Task 1 leads to.", "Start the timer on a story first.", "That word is after the last word
reached.", "A word after the last word reached is marked; remove that mark first.", "The learner finished before the
time limit: the whole story counts.", "This attempt is already on the server: change its last Part 1 mark instead of
removing it.", the timer's order and clock refusals, the pending-upload lock. Sending (`SyncViewModel.upload`) refuses
while a story timing isn't finished and names the learners ("Finish the CRLA story timing of ... first (stop the timer,
or tap the last word reached), then send."): show it as is.
Built 2026-11-28: `lib/ui/crla/crla_marking_screen.dart` (`CrlaMarkingScreen`), opened with "Mark in BASA" from `CrlaEntryScreen` where the form exists and the attempt has no typed totals; tests `test/ui/crla_marking_screen_test.dart`. **No learner side** (reading coordinator, 2026-11-28: the assessor must not show any action a learner might feel judged by): the layout sketch above is the assessor's two columns, not a split screen for the learner.
Console: `crla-form`, `crla-digitized`, `crla-mark`, `crla-unmark`, `crla-task-done`, `crla-word`, `crla-timer-start`,
`crla-timer-pause`, `crla-timer-resume`, `crla-timer-stop`, `crla-timer-reset`, `crla-timer`, `crla-last-word`,
`crla-answer`, `crla-observe`

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
