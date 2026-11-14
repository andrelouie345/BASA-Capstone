# Phil-IRI (English, Grades 4–10)

### GST (Group Screening Test)
Build: both    Roles: tutor / coordinator / admin
Purpose: record a learner's GST score (total, or literal/inferential/critical) and list a section's.
Calls:
- `PhilIriViewModel.recordGst(...)` → `PhilIriGstResult`; `gstForSection(sectionId, schoolYear:)` → `List<PhilIriGstResult>`
- `PhilIriViewModel.gstPassed(g)` → `bool`; `PhilIriGstResult.wholePercent` → `int`
Live previews: none.
Errors: grade outside 4–10, score out of range, another school (ViewModelException).
Console: `phil-iri-gst`, `phil-iri-gst-list`

### Section Phil-IRI sessions
Build: both    Roles: tutor / coordinator / admin
Purpose: a section's sessions (per round), open one.
Calls:
- `PhilIriViewModel.loadForSection(sectionId, schoolYear:, round:)` → session list; `refresh()`; `getSession(id)` → `PhilIriAssessment?`
- rounds: `PhilIriRound.values` (`label`)
Console: `phil-iri-sessions`, `phil-iri-session`

### Assessment session (reading, miscues, answers, rubric)
Build: both    Roles: tutor / coordinator / admin
Purpose: start a session, pick a passage, time the reading (whole text / one minute / silent), mark miscues on the passage's words, answer the questions, score the rubric, complete or discard.
Calls:
- `PhilIriViewModel.startSession(...)` → `PhilIriAssessment`; `availablePassages(assessmentId, ...)` → `List<PhilIriPassage>` (any round may use any listed passage; this round's booklet passages come right after oral follow-ups, so show the list in the order given)
- `startReading(...)` → `PhilIriReading` (method: `PhilIriReadingMethod`); `saveTiming(readingId, readingSeconds:|wordsRead:)`; `saveObservation(readingId, PhilIriObservation)`; `deleteReading(id)`; `readings(assessmentId)`
- `markMiscue(...)`, `updateMiscue(m)`, `removeMiscue(id)`, `miscues(readingId)` (miscue types: `PhilIriMiscueType.values`, `label`)
- `answer(...)`, `answers(readingId)`; `passage(id)`, `questions(passageId)`, `collection(id)`
- `rubricCriteria(collectionId)`, `rubricScores(assessmentId)`, `scoreRubric(...)`
- `complete(id)`, `reopen(id)`, `discard(id)`, `silentReadingFollowedUp(readingId)`
- `scoreReading(readingId)` → `PhilIriPassageResult` (type from `core/models/phil_iri_types.dart`) — the reading's result from what is saved, local and immediate
- `PhilIriReading.isTimed`, `PhilIriObservation.labels`
Live previews: `scoreReading` after each save (no extra call needed).
Errors: locked by a pending upload, passage already used (no-repeat), round closed (ViewModelException).
Console: `phil-iri-start`, `phil-iri-passages-for`, `phil-iri-read`, `phil-iri-time`, `phil-iri-observe`, `phil-iri-reading-delete`, `phil-iri-miscue`, `phil-iri-miscue-update`, `phil-iri-miscue-remove`, `phil-iri-answer`, `phil-iri-rubric`, `phil-iri-criteria`, `phil-iri-passage-show`, `phil-iri-complete`, `phil-iri-reopen`, `phil-iri-discard`, `phil-iri-score`

### Learner results
Build: both    Roles: tutor / coordinator / admin
Calls:
- `PhilIriViewModel.learnerResults(...)` → `PhilIriLearnerResults` (rounds: `PhilIriRoundResult`; types from `core/models/phil_iri_types.dart`)
- `wordReadingPercent`, `comprehensionPercent`, `adjustedLevelLabel`, `levelsDownLabel`, `actualAdjustedLevelLabel`, `actualLevelsDownLabel` (getters on `PhilIriPassageResult` / `PhilIriRoundResult`)
Console: `phil-iri-results`
- Since 2026-11-14 the learner page shows ONE kind of values, the school's choice (`PhilIriLearnerResults.values`, report setting `values_learner_pages`, default carried): print `philIriValuesLabel(values)` ("Values: carried (best so far)" / "Values: actual (each round's own reading)") above the rounds, one line per round from `results.view(round)` (`PhilIriRoundView`), the end result from `results.endView()`. Under actual a round without a reading of its own has `notAssessedThisRound` true: show **"Not assessed this round"**. `silentOnly` = the word reading 100% comes from a silent reading (not a measured accuracy). Don't show a second "true score" line any more (spec `docs/superpowers/specs/2026-11-14-phil-iri-value-sources-design.md` D11).
Levels: `PhilIriLevel` has five values, shown with `.label`: Independent, Instructional, Frustration, **Struggling**, Non-Reader (since 2026-10-29). On a result, `accuracyLevel` is the word recognition band, `wordReadingLevel` the word reading profile, `profile` the reading profile. Show the label that comes back; don't hard-code a list of levels. Since 2026-11-09 comprehension can also be **Struggling** (0-40%).

Assessment status (since 2026-11-09): each `PhilIriRoundResult` has `status` (`PhilIriRoundStatus.assessed` / `carriedOver` / `notAssessed`), `wordReadingAssessed`, `comprehensionAssessed` and `wordReadingAssumed`. When `wordReadingAssumed` is true there was no word reading yet: show word recognition and speed as **"Not assessed"** (the word reading profile shows Struggling, the level it counts as). Show "carried over" next to a round whose numbers come from an earlier round or the GST. The progress report row (`ProgressSectionReport`) has `carriedOver` and `notAssessed` next to `assessed`; dashboard round tiles (`RoundSnapshot.carriedOver`, null for CRLA); tutor reminders have a new kind `TutorReminderKind.noGst` (learners without a GST at BOSY).

Imported readings (since 2026-11-10): a reading imported from ma's workbook may have **no passage** (`PhilIriReading.isUntitled`, `passageId` null): show its title as **"Untitled"** and its word count from `importedWordCount`; there are no words to tap, no questions to answer, and the ViewModel refuses edits of it ("This reading was imported without a passage (Untitled) and cannot be edited here."), though it can be deleted. A reading may also have **comprehension only**: its `PhilIriPassageResult.wordReadingAssumed` is true and word recognition, speed, accuracy and word reading level are null: show them as **"Not assessed"**, as for a round's `wordReadingAssumed`.

A workbook reading **on a passage** has no answer rows: its comprehension is the count `PhilIriReading.importedCorrect` over the passage's questions (`questions(passageId).length`, the total the score uses). When `importedCorrect` is not null, show "Comprehension: 8/10 (imported, no per-question answers)" instead of the question list (don't show every question as not answered). Its miscues have no word position (`PhilIriMiscue.wordIndex` null): list them as "position not recorded" with their type, not on the passage's words.

### Finalize
Build: admin    Roles: admin / coordinator
Calls:
- `PhilIriViewModel.finalize(assessmentId)` → `PhilIriAssessment`; `finalizeRound(...)` → `PhilIriRoundClosure`
Console: `phil-iri-finalize`, `phil-iri-finalize-round`

### Content (collections, passages, questions, rubric)
Build: both (read) / admin (edit)    Roles: read all; edit admin / coordinator (superadmin for regional content)
Calls:
- `PhilIriContentViewModel.loadCollections(activeOnly:)` → `collections`; `getCollection`, `createCollection`, `updateCollection`, `setCollectionActive`, `promoteCollection`, `deleteCollection`
- `criteria`, `addCriterion`, `updateCriterion`, `deleteCriterion`
- `passages(collectionId, activeOnly:)`, `getPassage`, `addPassage`, `updatePassage`, `setPassageActive`, `deletePassage`
- `questions`, `addQuestion`, `updateQuestion`, `deleteQuestion`
- `lastMirrorWarning` → `String?`
Errors: passage in use, wrong grade/collection (ViewModelException).
Console: `phil-iri-collections`, `phil-iri-passages`, `phil-iri-passage-show`, `phil-iri-collection-add`/`-edit`/`-activate`/`-promote`/`-delete`, `phil-iri-criterion-add`/`-update`/`-delete`, `phil-iri-passage-add`/`-edit`/`-activate`/`-delete`, `phil-iri-question-add`/`-update`/`-delete`
Note: `phil-iri-passage-add`/`-edit` read the passage text from a file path in the console; the ViewModel takes the text (`PhilIriPassage`), so a screen passes the typed or picked text.

### Phil-IRI thresholds
Build: both (view) / admin (edit)
Calls:
- `PhilIriContentViewModel.thresholdLayers(schoolId)` → `PhilIriThresholdLayers` (`region`, `school`, `effective`, `defaults`)
- `PhilIriContentViewModel.saveThresholds(...)`, `resetSchoolThresholds(schoolId)`; `PhilIriViewModel.effectiveThresholds(schoolId)` → `PhilIriThresholds` (type from `core/models/phil_iri_types.dart`)
Console: `phil-iri-thresholds`, `phil-iri-threshold-set`, `phil-iri-threshold-reset`
