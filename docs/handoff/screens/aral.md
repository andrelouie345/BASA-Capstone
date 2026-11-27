# ARAL-Reading

### Roster (section / school / tutor)
Build: both (view) / admin (edit)    Roles: view all (tutor: own sections and classes); edit admin / coordinator
Purpose: who is in ARAL, their program, class, status; enroll, refer, place, exit, notes.
Calls:
- `AralViewModel.roster(sectionId:, schoolYear:)`, `schoolRoster(...)`, `tutorRoster(...)` → `List<AralEnrollment>`; `getEnrollment(id)`
- names: `AralViewModel.learnerNames(sectionId)`, `classNames(schoolId)` → `Map<int, String>`; `AralSessionViewModel.learnerNames(enrollments)`
- admin: `propose(sectionId:, schoolYear:)` → `List<AralCandidate>`; `enroll(...)`, `enrollProposed(...)`, `refer(...)`, `setPlacement(id, keyStage, track)`, `moveToSection(id)`, `exit(id, reason, on:)`, `reactivate(id)`, `setNotes(id, notes)`, `remove(id)`
- `programSettings(schoolId)` → `AralProgramSettings` (type from `core/models/aral_types.dart`)
- admin: `applyResults(...)`, `applySchoolResults(...)` → `List<AralUpdate>`
Errors: not eligible, class full, wrong grade/school, locked (ViewModelException).
Console: `aral-roster`, `aral-propose`, `aral-enroll`, `aral-enroll-proposed`, `aral-refer`, `aral-placement`, `aral-move`, `aral-exit`, `aral-reactivate`, `aral-notes`, `aral-remove`, `aral-update`

### Tutors
Build: both    Roles: all
Calls:
- `AralViewModel.tutors(schoolId:, schoolYear:)` → `List<({User tutor, int classes, int activeLearners})>`
Console: `aral-tutors`

### Classes
Build: both (view) / admin (edit)    Roles: view all; edit admin / coordinator
Purpose: classes of a school year (at most the school's maximum of active learners, 15 unless the school set another), their roster, placing and unplacing learners.
Calls:
- `AralClassViewModel.classes(schoolId:, schoolYear:)`, `getClass(id)`, `classRoster(id)`, `activeCount(id)`
- admin: `createClass(...)`, `editClass(c)`, `deleteClass(id)`, `place(enrollmentId, classId, otherGrade:)`, `unplace(enrollmentId)`
- `AralClassViewModel.classMax(schoolId)` → `Future<int>` (the school's maximum, 15 by default) for "n/15 active"; `classMin(schoolId)` → `Future<int>` (0 = no minimum). A class can hold more than the maximum when the school lowered it later: show it as over the maximum (the coordinator's reminders say so).
- `AralSessionViewModel.classSummary(classId)` → `AralClassSummary`
- ARAL memo: `AralClassViewModel.suggestClassName(schoolId:, schoolYear:, grade:)` → `String` (`ARAL-R-G7-02`: prefill the name field of a new class; the name stays free text). Session type: `createClass(sessionType:)` / `editClass(c.copyWith(sessionType: () => …))`, `AralSessionType.pullOut` "Pull-out" / `beforeAfter` "Before/after class" / null (blank).
- The adviser rule (school setting `adviser_tutors_own_class` off): `place` and `editClass` (tutor change) refuse in a plain sentence naming the learner and section; enrolling with a class leaves the learner waiting and `AralViewModel.lastWarning` says why.
- Sessions: `AralSessionViewModel.logSession` / `editSession` refuse past the school's daily limit for the tutor's type ("An internal tutor holds at most 2 ARAL sessions a day at this school…").
Errors: class full, other grade without confirmation, adviser rule, sessions exist on delete (ViewModelException); other errors: the error rule in `common.md`.
Console: `aral-classes`, `aral-class-show`, `aral-class-summary`, `aral-class-add`, `aral-class-edit`, `aral-class-delete`, `aral-class-place`, `aral-class-unplace`

### Class progress (2026-11-27)
Build: both    Roles: the class's tutor / coordinator / admin
Spec: `docs/superpowers/specs/2026-11-27-aral-class-tutor-design.md` (D2).
Purpose: per class, how each learner has moved since they entered ARAL ("has ARAL helped so far?"). One row per learner
placed in the class this year, exited ones marked.
```
ARAL-R-G7-01                                    as of 27 Nov 2026
CRUZ, Ana     G7 Phil-IRI  BOSY Frustration  -> MOSY #1 Instructional   Up
              comprehension 50% -> 70%, wpm 62 -> 80
REYES, Ben    G7 Phil-IRI  BOSY Frustration  -> -                       Not assessed yet
```
Calls:
- `AralClassViewModel.classProgress(classId, asOf:)` → `List<AralLearnerProgress>` (`core/models/aral_progress.dart`), by
  name: `learnerName`, `grade`, `instrument` (CRLA / Phil-IRI), `startRoundLabel` + `startProfile` + `startNumbers`,
  `latestRoundLabel` + `latestProfile` + `latestNumbers` (null = nothing after the start), `change`
  (`AralProgressChange`: up / same / down / not assessed yet / no starting result, `label` to show), `exited`.
- Numbers (`AralProgressNumbers`): CRLA correct words %, wpm, comprehension (questions right); Phil-IRI word
  recognition %, wpm, comprehension %. Any may be null: show "-".
- The change is by reading profile (the official step); show the numbers under it so a learner who improved inside one
  profile isn't read as "no progress". Never label values carried/actual on this screen.
Errors: a tutor's class not theirs (ViewModelException); other errors: the error rule in `common.md`.
Console: `aral-class-progress`

### No improvement (beside class progress)
Build: both    Roles: the class tutor; admin / coordinator of the school
Purpose: the class's learners who show no improvement, with the reason, so the tutor can adjust the IRIP.
```
ARAL-R-G7-01: 2 learners with no improvement
CRUZ, Ana | Grade 7 Phil-IRI | Same since BOSY: Frustration -> Frustration (MOSY #1)
REYES, Ben | Grade 7 Phil-IRI | Check-in after session 16: 50%, pass mark 75%
```
Calls:
- `AralClassViewModel.noImprovement(classId, asOf:)` -> `List<AralNoImprovement>` (`core/models/aral_progress.dart`),
  by name: `progress` (the learner's `AralLearnerProgress`, as on class progress), `reasons`
  (`List<AralNoImprovementReason>`: `kind` round / checkin, `message` to show; one learner can have both).
- A learner is listed when (a) their latest round is Same or Down since their ARAL start after at least the school's
  first check-in point (16) of sessions attended (present only) up to that round's date, or (b) their latest complete
  check-in is below the pass mark. Exited learners are not listed. Empty list = show "No learner needs attention".
Errors: a tutor's class not theirs (ViewModelException); other errors: the error rule in `common.md`.
Console: `aral-no-improvement`

### Sessions and attendance
Build: both    Roles: the class tutor (write); others read
Purpose: log a session for a class, mark attendance on its sheet, edit/delete, see a learner's attendance and a tutor's summary.
Calls:
- `AralSessionViewModel.logSession(...)`, `editSession(...)`, `deleteSession(id)`, `getSession(id)`
- `tutorSessions(...)`, `classSessions(classId)`, `schoolSessions(...)`
- `sheet(sessionId)` → `List<AralSheetLine>`; `mark(sessionId, enrollmentId, AralMark, note:)`, `markRest(sessionId, mark)`, `unmark(...)`
- `learnerAttendance(enrollmentId)` → `(AralAttendanceSummary, List<(AralSession, AralAttendance)>)`; `tutorSummary(...)` → `AralTutorSummary`
- setups: `AralSetup.values` (`label`); marks: `AralMark.values`
Errors: one session per class per date, date not real, not the class tutor (ViewModelException).
Console: `aral-log`, `aral-session-edit`, `aral-session-delete`, `aral-sessions`, `aral-class-sessions`, `aral-sheet`, `aral-mark`, `aral-mark-rest`, `aral-unmark`, `aral-attendance`, `aral-tutor-summary`

### IRIP
Build: both    Roles: the class tutor (write); others read
Calls:
- `AralIripViewModel.targets(program)`, `plan(enrollmentId)` → `AralIripPlan`; `startCycle(id)`, `nextWeek(id, strand:, targetId:)`, `rate(weekId, status, on:, notes:)`, `clearRating`, `setNotes`, `changeTarget`, `deleteWeek`
- statuses/programs/strands: `AralIripStatus`, `AralIripProgram`, `AralIripStrand` (models)
Console: `aral-irip`, `aral-irip-targets`, `aral-irip-start`, `aral-irip-next`, `aral-irip-rate`, `aral-irip-unrate`, `aral-irip-notes`, `aral-irip-target`, `aral-irip-delete`

### Check-ins
Build: both (take) / admin (report, cut-off)    Roles: class tutor takes them; admin / coordinator report
Purpose: the first and second check-in (after session 16 and 32 unless the school set other sessions; the forms and saved check-ins still call them 16 and 32): start, answer items (letters or open items), result Met / Not met.
Calls:
- `AralCheckinViewModel.tools()`, `items(toolId)`, `learnerCheckins(enrollmentId)` → `AralLearnerCheckins`; `result(checkinId)` → `AralCheckinResult` (`score: AralCheckinScore`, `passPct`; types from `core/models/aral_types.dart`)
- `startCheckin(...)`, `editCheckin(...)`, `deleteCheckin(id)`, `answerChoices(...)`, `markOpen(...)`, `clearAnswer(...)`
- `AralCheckinResult.passed` → `bool` (Met / Not met); per part `score.passes(passPct)`; `AralCheckinScore.wholePercent` → `int`
- admin: `checkinReport(...)` → `AralCheckinReport`; `checkinReportCsv(...)` → `String`
Console: `aral-checkin-tools`, `aral-checkin-items`, `aral-checkins`, `aral-checkin`, `aral-checkin-start`, `aral-checkin-edit`, `aral-checkin-delete`, `aral-checkin-answers`, `aral-checkin-mark`, `aral-checkin-clear`, `aral-checkin-report`, `aral-export-checkins`

### ARAL settings
Build: both (view) / admin (set)    Roles: view all; set admin / coordinator
Purpose: check-in cut-off, SHARP (foundational program), KS1 extended, idle-session days; region and school layers.
Calls:
- `AralCheckinViewModel.settingLayers(schoolId)` → `AralCheckinSettingLayers`; `foundationalProgramLayers`, `ks1ExtendedLayers`, `idleSessionDaysLayers` → records `(region, school, effective, defaults)`; `AralCheckinSettingLayers.defaults`
- admin: `setPassPct`, `setFoundationalProgram`, `setKs1Extended`, `setIdleSessionDays`, `resetSchoolSettings(schoolId)`
- `localSettings(schoolId)` → `AralCheckinSettings`, `localSessionSettings(schoolId)` → `AralSessionSettings` (types from `core/models/aral_types.dart`)
Console: `aral-checkin-cutoff`, `aral-checkin-cutoff-set`, `aral-checkin-cutoff-reset`, `aral-sharp`, `aral-sharp-set`, `aral-ks1-extended`, `aral-ks1-extended-set`, `aral-idle-days`, `aral-idle-days-set`

School ARAL rules (same screen, a part of its own; ARAL memo settings):
- Fields (key, what to show, allowed values): `class_max_learners` "Class maximum" 1-50; `class_min_learners` "Class minimum" 0-50 (0 = none); `session_max_minutes` "Longest session (minutes)" 1-120 (blank = not set); `sessions_weekdays_only` "Weekdays only" on/off; `class_min_sessions_per_week` "Sessions a week (at least)" 0-7; `basis_round` "Choose new learners from" BoSY/MoSY; `checkin_after_sessions` "Check-ins after sessions" two numbers, first < second, 1-200; `irip_weeks` "IRIP weeks" 1-26. Key names: `AralRuleSettings.keys` and the `*Key` constants.
- Read: `AralCheckinViewModel.ruleSettingLayers(key, schoolId)` → `(region, school, effective, defaults)` per key (online); `localRuleSettings(schoolId)` → `AralRuleSettings` (this device's copy, offline).
- admin: `setRuleSetting(schoolId, key, value)` (value `null` removes the school's value: "Use the region value / default"); `ruleSettingValue(key, text)` turns typed text into a value. Refusals are plain sentences (range, minimum above maximum, not your school).
- Elsewhere: `AralClassViewModel.classMax(schoolId)` / `classMin(schoolId)`, `AralViewModel.ruleSettings(schoolId)`, `AralIripStrandState.cycleLength`; coordinator notices `AralClassNoticeKind.overMax`, `underMin`, `fewSessionsThisWeek`; tutor reminder `TutorReminderKind.fewSessionsThisWeek`.
- ARAL memo, people (same part): `adviser_tutors_own_class` "Advisers tutor their own learners" on/off (default on); `internal_tutor_max_sessions_per_day` "Internal tutor: sessions a day" 1-10 (blank = no limit); `external_tutor_max_minutes_per_day` "External tutor: minutes a day" 1-600 (blank = no limit).
Console: `aral-setting`, `aral-setting-set`

### Materials and recommendations
Build: both (read, recommend) / admin (catalog)    Roles: all read; catalog admin / coordinator
Calls:
- `AralMaterialViewModel.catalog(activeOnly:)`, `material(id)`, `recommendations(enrollmentId)` → `AralRecommendation`
- admin: `addMaterial(...)`, `updateMaterial(...)`, `setActive(id, active)`, `deleteMaterial(id)`, `setSchoolLink(materialId, schoolId, link)`, `sectionRecommendations(...)`; `lastMirrorWarning` → `String?`
Console: `aral-materials`, `aral-recommend`, `aral-recommend-section`, `aral-material-add`, `aral-material-set`, `aral-material-active`, `aral-material-delete`, `aral-material-school-link`

### Readability log (SHARP only)
Build: both    Roles: class tutor
Calls:
- `AralReadabilityViewModel.available(schoolId)` → `bool`; `entries(enrollmentId)`; `add(...)`, `update(...)`, `delete(id)` (entry carries `AralReadability`; type from `core/models/aral_types.dart`)
Live previews: none. Not available yet: Flesch ease / grade of a typed text before saving.
Console: `aral-readability`, `aral-readability-add`, `aral-readability-set`, `aral-readability-delete`

### Implementation report and roster files
Build: admin    Roles: admin / coordinator
Calls:
- `AralReportViewModel.implementationReport(...)` → `AralImplementationReport` (rows per section; `gradeTotals` → `Map<int, AralReportTotals>`, `schoolTotal` → `AralReportTotals`)
- `implementationReportXlsx(template:, ...)` → `(bytes, notes)`; `implementationReportCsv(...)` → `String`
- `AralViewModel.rosterCsv(...)`; `AralRosterImportViewModel.preview(schoolId, year, bytes, fileName)`, `importRoster(...)`
Console: `aral-report`, `aral-export-report`, `aral-export-report-csv`, `aral-export-roster`, `aral-import-roster-preview`, `aral-import-roster`

### ARAL Forms 1, 2 and 4 (Reading)
Build: admin    Roles: admin / coordinator of the school; superadmin
Purpose: the Division Memorandum 180 s. 2026 forms saved as .xlsx from the device copy (BASA's own layout; blanks for hand entry are listed at the foot of each form). Forms 3, 5 and 6 are not in BASA (separate tutor-management system).
Fields: school year; Form 1: class (one, or every class); Form 4: as-of date (default today).
Calls:
- `AralFormsViewModel.form1Xlsx(schoolId:, schoolYear:, classId:)`, `form2Xlsx(schoolId:, schoolYear:)`, `form4Xlsx(schoolId:, schoolYear:, asOf: 'YYYY-MM-DD')` → `List<int>` (save with the file picker)
- preview on screen, if wanted: `form1(...)` → `List<AralForm1>`, `form2(...)` → `AralForm2`, `form4(...)` → `AralForm4` (`notes` / `blanks` are plain sentences to show under it)
Errors: tutors refused ("Not allowed: …"); Form 1 with no classes ("This school has no ARAL classes for 2026-2027 yet."); a bad date (ViewModelException).
Console: `aral-form1`, `aral-form2`, `aral-form4`
