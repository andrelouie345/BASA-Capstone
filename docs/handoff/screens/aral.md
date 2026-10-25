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
Purpose: classes of a school year (at most 15 active learners), their roster, placing and unplacing learners.
Calls:
- `AralClassViewModel.classes(schoolId:, schoolYear:)`, `getClass(id)`, `classRoster(id)`, `activeCount(id)`
- admin: `createClass(...)`, `editClass(c)`, `deleteClass(id)`, `place(enrollmentId, classId, otherGrade:)`, `unplace(enrollmentId)`
- `AralClassViewModel.classCap` → `int` (15) for "n/15 active"
- `AralSessionViewModel.classSummary(classId)` → `AralClassSummary`
Errors: class full, other grade without confirmation, sessions exist on delete (ViewModelException); other errors: the error rule in `common.md`.
Console: `aral-classes`, `aral-class-show`, `aral-class-summary`, `aral-class-add`, `aral-class-edit`, `aral-class-delete`, `aral-class-place`, `aral-class-unplace`

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
Purpose: the 16th/32nd-session check-in: start, answer items (letters or open items), result Met / Not met.
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
