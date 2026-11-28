# Phil-IRI (English, Grades 4–10)

### GST (Group Screening Test)
Build: both    Roles: tutor / coordinator / admin
Purpose: record a learner's GST score (total, or literal/inferential/critical) and list a section's.
Calls:
- `PhilIriViewModel.recordGst(...)` → `PhilIriGstResult`; `gstForSection(sectionId, schoolYear:)` → `List<PhilIriGstResult>`
- `PhilIriViewModel.gstPassed(g)` → `bool`; `PhilIriGstResult.wholePercent` → `int`
- `PhilIriViewModel.removeGst(gstId)`: removes a GST recorded by mistake (wrong learner or score; a wrong score can also just be retaken, the newest counts). Only one recorded on this device and not uploaded (negative id), the learner's latest in that section and year, not waiting in an upload. Offer the button only for a negative id; refusals are shown as is (`philIriGstRemoveUploadedMessage` for an uploaded one). **Warning to show** (confirm dialog, and on the help page): only the learner's latest one, and only before it is uploaded; once on the server it stays (ask the coordinator).
Live previews: none.
Errors: grade outside 4–10, score out of range, another school (ViewModelException).
Console: `phil-iri-gst`, `phil-iri-gst-list`, `phil-iri-gst-remove`

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

### Timed reading: the digitized oral reading (2026-11-26, consultation item M1-01)
Build: both    Roles: tutor / coordinator / admin
Spec: `docs/superpowers/specs/2026-11-26-phil-iri-timed-reading-design.md` (owner's layout below).
Purpose: the tutor times the reading in BASA and taps miscues on the passage while the learner reads aloud from the
printed copy (the tutor keeps the screen). Every timer tap is kept as the reading's timing log (evidence the reading was
given live); BASA works out the seconds from it.

Layout (owner): mobile first; tap a word and a drawer slides up from the bottom with the miscue types.
```
+-------------------------------+
| Grade 7 . MOSY #1 . 02:14  ||  |  timer, Pause/Resume, Stop
| The [boat] drifted slowly     |
| toward the shore while the    |  passage as tappable words;
| fishermen ~~pulled~~ their    |  marked words highlighted
+-------------------------------+
|  "pulled"                     |  drawer on tap
|  Mispronunciation  Omission   |  types from PhilIriMiscueType.values
|  Substitution  Insertion ...  |
|  [ ] Self-corrected  Said: __ |
|  Remove miscue        Done    |
+-------------------------------+
```
Calls (`PhilIriViewModel`; each returns `PhilIriTimerState` from `core/models/phil_iri_timer_event.dart`):
- `startTimer(readingId)`, `pauseTimer(readingId)`, `resumeTimer(readingId)`, `stopTimer(readingId)` (whole text /
  silent: saves the reading time), `resetTimer(readingId)` (Restart: ask "Time this reading again? The first timing
  stays in the record."; clears the time).
- `timer(readingId)` when the screen opens or every second while running: `status` (none / running / paused /
  stopped), `elapsed` (reading time, pauses left out; show as mm:ss), `label` ("Timed in BASA" / "Time typed in"),
  `minuteEndNeeded`, `events` (the log, for a coordinator's detail view). The timer survives the app closing: just
  call `timer` again.
- One minute: the timer stops by itself at 60 s of reading (`timer` adds the stop when it is due; don't offer Stop).
  When `minuteEndNeeded`, ask "Tap the last word the learner read" and call `setMinuteEnd(readingId, wordIndex)`
  (`wordIndex` = position in `PhilIriPassage.words`, 0 = the first word).
- Miscues as before: `markMiscue(readingId:, wordIndex:, type:, spokenText:, selfCorrected:)`; an insertion goes
  BEFORE the tapped word; tapping a marked word opens the same drawer (`updateMiscue` / `removeMiscue`).
Errors (show `ViewModelException.message` as is): "The timer is already stopped.", "This time is earlier than the
timer's last tap; check the device clock.", "This reading is timed in BASA; restart the timer to time it again." (the
typed time field is refused once timed), "Stop the reading timer before completing the session.", "The one-minute
timer stops by itself at 60 seconds.".
Typed timing (`saveTiming`) stays for readings without a timer (schools that test on paper).
Built 2026-11-28 in `lib/ui/phil_iri/reading_screen.dart` (`_TimerBar`, `_MiscueDrawer`); tests `test/ui/phil_iri_reading_screen_test.dart`. The screen is the assessor's only (tutor, coordinator or admin): no learner side (reading coordinator, 2026-11-28).
Console: `phil-iri-timer-start|pause|resume|stop|reset <readingId> [time]`, `phil-iri-timer <readingId>`,
`phil-iri-minute-end <readingId> <wordIndex>`.

### Learner results
Build: both    Roles: tutor / coordinator / admin
Calls:
- `PhilIriViewModel.learnerResults(...)` → `PhilIriLearnerResults` (rounds: `PhilIriRoundResult`; types from `core/models/phil_iri_types.dart`). Show rounds through `view(round)` / `endView()` (the school's carried/actual switch); `showValues` false (a tutor) = never say which values: see `value-sources.md`
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
