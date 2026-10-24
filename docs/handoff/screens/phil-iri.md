# Phil-IRI (English, Grades 4–10)

### GST (Group Screening Test)
Build: both    Roles: tutor / coordinator / admin
Purpose: record a learner's GST score (total, or literal/inferential/critical) and list a section's.
Calls:
- ✅ `PhilIriViewModel.recordGst(...)` → `PhilIriGstResult`; `gstForSection(sectionId, schoolYear:)` → `List<PhilIriGstResult>`
- ✅ `PhilIriViewModel.gstPassed(g)` → `bool`; `PhilIriGstResult.wholePercent` → `int` — PHILIRI-G1
Live previews: none.
Errors: grade outside 4–10, score out of range, another school (ViewModelException).
Console: `phil-iri-gst`, `phil-iri-gst-list`

### Section Phil-IRI sessions
Build: both    Roles: tutor / coordinator / admin
Purpose: a section's sessions (per round), open one.
Calls:
- ✅ `loadForSection(sectionId, schoolYear:, round:)` → session list; `refresh()`; `getSession(id)` → `PhilIriAssessment?`
- ✅ rounds: `PhilIriRound.values` (`label`)
Console: `phil-iri-sessions`, `phil-iri-session`

### Assessment session (reading, miscues, answers, rubric)
Build: both    Roles: tutor / coordinator / admin
Purpose: start a session, pick a passage, time the reading (whole text / one minute / silent), mark miscues on the passage's words, answer the questions, score the rubric, complete or discard.
Calls:
- ✅ `startSession(...)` → `PhilIriAssessment`; `availablePassages(assessmentId, ...)` → `List<PhilIriPassage>`
- ✅ `startReading(...)` → `PhilIriReading` (method: `PhilIriReadingMethod`); `saveTiming(readingId, readingSeconds:|wordsRead:)`; `saveObservation(readingId, PhilIriObservation)`; `deleteReading(id)`; `readings(assessmentId)`
- ✅ `markMiscue(...)`, `updateMiscue(m)`, `removeMiscue(id)`, `miscues(readingId)` (miscue types: `PhilIriMiscueType.values`, `label`)
- ✅ `answer(...)`, `answers(readingId)`; `passage(id)`, `questions(passageId)`, `collection(id)`
- ✅ `rubricCriteria(collectionId)`, `rubricScores(assessmentId)`, `scoreRubric(...)`
- ✅ `complete(id)`, `reopen(id)`, `discard(id)`, `silentReadingFollowedUp(readingId)`
- ✅ `scoreReading(readingId)` → `PhilIriPassageResult` (class T: PHILIRI-G2) — the reading's result from what is saved, local and immediate
- ✅ `PhilIriReading.isTimed`, `PhilIriObservation.labels` — PHILIRI-G3
Live previews: `scoreReading` after each save (no extra call needed).
Errors: locked by a pending upload, passage already used (no-repeat), round closed (ViewModelException).
Console: `phil-iri-start`, `phil-iri-passages-for`, `phil-iri-read`, `phil-iri-time`, `phil-iri-observe`, `phil-iri-reading-delete`, `phil-iri-miscue`, `phil-iri-miscue-update`, `phil-iri-miscue-remove`, `phil-iri-answer`, `phil-iri-rubric`, `phil-iri-criteria`, `phil-iri-passage-show`, `phil-iri-complete`, `phil-iri-reopen`, `phil-iri-discard`, `phil-iri-score`

### Learner results
Build: both    Roles: tutor / coordinator / admin
Calls:
- ✅ `learnerResults(...)` → `PhilIriLearnerResults` (rounds: `PhilIriRoundResult`, class T: PHILIRI-G2)
- ✅ `wordReadingPercent`, `comprehensionPercent`, `adjustedLevelLabel`, `levelsDownLabel`, `actualAdjustedLevelLabel`, `actualLevelsDownLabel` (getters on `PhilIriPassageResult` / `PhilIriRoundResult`) — PHILIRI-G2
Console: `phil-iri-results`

### Finalize
Build: admin    Roles: admin / coordinator
Calls:
- ✅ `finalize(assessmentId)` → `PhilIriAssessment`; `finalizeRound(...)` → `PhilIriRoundClosure`
Console: `phil-iri-finalize`, `phil-iri-finalize-round`

### Content (collections, passages, questions, rubric)
Build: both (read) / admin (edit)    Roles: read all; edit admin / coordinator (superadmin for regional content)
Calls:
- ✅ `PhilIriContentViewModel.loadCollections(activeOnly:)` → `collections`; `getCollection`, `createCollection`, `updateCollection`, `setCollectionActive`, `promoteCollection`, `deleteCollection`
- ✅ `criteria`, `addCriterion`, `updateCriterion`, `deleteCriterion`
- ✅ `passages(collectionId, activeOnly:)`, `getPassage`, `addPassage`, `updatePassage`, `setPassageActive`, `deletePassage`
- ✅ `questions`, `addQuestion`, `updateQuestion`, `deleteQuestion`
- ✅ `lastMirrorWarning` (class E: PHILIRI-G5)
Errors: passage in use, wrong grade/collection (ViewModelException).
Console: `phil-iri-collections`, `phil-iri-passages`, `phil-iri-passage-show`, `phil-iri-collection-add`/`-edit`/`-activate`/`-promote`/`-delete`, `phil-iri-criterion-add`/`-update`/`-delete`, `phil-iri-passage-add`/`-edit`/`-activate`/`-delete`, `phil-iri-question-add`/`-update`/`-delete`
Note: `phil-iri-passage-add`/`-edit` read the passage text from a file path in the console; the ViewModel takes the text (`PhilIriPassage`), so a screen passes the typed or picked text. Not a gap.

### Phil-IRI thresholds
Build: both (view) / admin (edit)
Calls:
- ✅ `thresholdLayers(schoolId)` → `PhilIriThresholdLayers` — default missing: PHILIRI-G4
- ✅ `saveThresholds(...)`, `resetSchoolThresholds(schoolId)`; `PhilIriViewModel.effectiveThresholds(schoolId)` → `PhilIriThresholds` (class T: PHILIRI-G2)
Console: `phil-iri-thresholds`, `phil-iri-threshold-set`, `phil-iri-threshold-reset`

## Gaps

**PHILIRI-G1** (I, N) — `phil-iri-gst` decides "passed / below the cut-off" itself: it guesses the grade group from the max score (40 → 7, else 4), calls `philIriGstPassed` with the school's thresholds, and rounds with `philIriWholePercent`. `philIriGstPassed` throws a raw `ArgumentError` on bad input. A screen can't show the verdict.
Fix: `PhilIriViewModel.gstPassed(PhilIriGstResult g)` → `Future<bool>` (same grade-group rule, school thresholds, same function); `PhilIriGstResult.wholePercent` getter (`int`, same rounding). `gst-list` can stay as it is (no verdict today).
Removes baseline: `core/console/commands/phil_iri_commands.dart -> core/services/phil_iri_rules.dart` (with PHILIRI-G2, G3)
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 6).

**PHILIRI-G2** (I, T, N) — `PhilIriPassageResult`, `PhilIriRoundResult` (`phil_iri_results.dart`), `PhilIriLevel`, `PhilIriThresholds` (`phil_iri_rules.dart`) are service types in results. The console makes their percents with `philIriWholePercent` and the adjusted-level / levels-down text with `philIriAdjustedLevelLabel` / `philIriLevelsDownLabel`.
Fix: `core/models/phil_iri_types.dart` exports those four types; getters on the result classes (in their own files, calling the same functions): `PhilIriPassageResult.wordReadingPercent`, `.comprehensionPercent` (`int?`), `PhilIriRoundResult.wordReadingPercent`, `.comprehensionPercent`, `.adjustedLevelLabel` (`String?`), `.levelsDownLabel` (`String?`). The commands use them.
Removes baseline: `core/console/commands/phil_iri_commands.dart -> core/services/phil_iri_results.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 6).

**PHILIRI-G3** (N) — Whether a reading is timed yet (`_timed`: one-minute needs words read, the others need seconds) and the observation labels (`_observationText`) are command code.
Fix: `PhilIriReading.isTimed` getter; `PhilIriObservation.labels` → `List<String>` (same wording). The miscue position text ("before word 3") stays console layout.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 6).

**PHILIRI-G4** (I, N) — `phil-iri-thresholds` reads `PhilIriThresholds.defaults` from `phil_iri_rules.dart`.
Fix: `PhilIriThresholdLayers.defaults`, per COMMON-G2.
Removes baseline: `core/console/commands/phil_iri_content_commands.dart -> core/services/phil_iri_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 6).

**PHILIRI-G5** (E) — `phil_iri_content_viewmodel.dart:682` puts `$e` in `lastMirrorWarning`.
Fix: spec rule.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 6).
