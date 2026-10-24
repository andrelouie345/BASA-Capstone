# ARAL-Reading

### Roster (section / school / tutor)
Build: both (view) / admin (edit)    Roles: view all (tutor: own sections and classes); edit admin / coordinator
Purpose: who is in ARAL, their program, class, status; enroll, refer, place, exit, notes.
Calls:
- ✅ `AralViewModel.roster(sectionId:, schoolYear:)`, `schoolRoster(...)`, `tutorRoster(...)` → `List<AralEnrollment>`; `getEnrollment(id)`
- ✅ names: `AralViewModel.learnerNames(sectionId)`, `classNames(schoolId)` → `Map<int, String>`; `AralSessionViewModel.learnerNames(enrollments)`
- ✅ admin: `propose(sectionId:, schoolYear:)` → `List<AralCandidate>`; `enroll(...)`, `enrollProposed(...)`, `refer(...)`, `setPlacement(id, keyStage, track)`, `moveToSection(id)`, `exit(id, reason, on:)`, `reactivate(id)`, `setNotes(id, notes)`, `remove(id)`
- ✅ `programSettings(schoolId)` → `AralProgramSettings` (class T: ARAL-G5)
- ✅ admin: `applyResults(...)`, `applySchoolResults(...)` → `List<AralUpdate>`
Errors: not eligible, class full, wrong grade/school, locked (ViewModelException).
Console: `aral-roster`, `aral-propose`, `aral-enroll`, `aral-enroll-proposed`, `aral-refer`, `aral-placement`, `aral-move`, `aral-exit`, `aral-reactivate`, `aral-notes`, `aral-remove`, `aral-update`

### Tutors
Build: both    Roles: all
Calls:
- ✅ `AralViewModel.tutors(schoolId:, schoolYear:)` → `List<(User, int, int)>` (tutor, classes taught, active learners) — positional record: ARAL-G6
Console: `aral-tutors`

### Classes
Build: both (view) / admin (edit)    Roles: view all; edit admin / coordinator
Purpose: classes of a school year (at most 15 active learners), their roster, placing and unplacing learners.
Calls:
- ✅ `AralClassViewModel.classes(schoolId:, schoolYear:)`, `getClass(id)`, `classRoster(id)`, `activeCount(id)`
- ✅ admin: `createClass(...)`, `editClass(c)`, `deleteClass(id)`, `place(enrollmentId, classId, otherGrade:)`, `unplace(enrollmentId)`
- 🆕 the class cap (15) for "n/15 active" — ARAL-G1
- ✅ `AralSessionViewModel.classSummary(classId)` → `AralClassSummary`
Errors: class full, other grade without confirmation, sessions exist on delete (ViewModelException); unknown database errors are rethrown raw (ARAL-G8).
Console: `aral-classes`, `aral-class-show`, `aral-class-summary`, `aral-class-add`, `aral-class-edit`, `aral-class-delete`, `aral-class-place`, `aral-class-unplace`

### Sessions and attendance
Build: both    Roles: the class tutor (write); others read
Purpose: log a session for a class, mark attendance on its sheet, edit/delete, see a learner's attendance and a tutor's summary.
Calls:
- ✅ `AralSessionViewModel.logSession(...)`, `editSession(...)`, `deleteSession(id)`, `getSession(id)`
- ✅ `tutorSessions(...)`, `classSessions(classId)`, `schoolSessions(...)`
- ✅ `sheet(sessionId)` → `List<AralSheetLine>`; `mark(sessionId, enrollmentId, AralMark, note:)`, `markRest(sessionId, mark)`, `unmark(...)`
- ✅ `learnerAttendance(enrollmentId)` → `(AralAttendanceSummary, List<(AralSession, AralAttendance)>)`; `tutorSummary(...)` → `AralTutorSummary`
- ✅ setups: `AralSetup.values` (`label`); marks: `AralMark.values`
Errors: one session per class per date, date not real, not the class tutor (ViewModelException).
Console: `aral-log`, `aral-session-edit`, `aral-session-delete`, `aral-sessions`, `aral-class-sessions`, `aral-sheet`, `aral-mark`, `aral-mark-rest`, `aral-unmark`, `aral-attendance`, `aral-tutor-summary`

### IRIP
Build: both    Roles: the class tutor (write); others read
Calls:
- ✅ `AralIripViewModel.targets(program)`, `plan(enrollmentId)` → `AralIripPlan`; `startCycle(id)`, `nextWeek(id, strand:, targetId:)`, `rate(weekId, status, on:, notes:)`, `clearRating`, `setNotes`, `changeTarget`, `deleteWeek`
- ✅ statuses/programs/strands: `AralIripStatus`, `AralIripProgram`, `AralIripStrand` (models)
Console: `aral-irip`, `aral-irip-targets`, `aral-irip-start`, `aral-irip-next`, `aral-irip-rate`, `aral-irip-unrate`, `aral-irip-notes`, `aral-irip-target`, `aral-irip-delete`

### Check-ins
Build: both (take) / admin (report, cut-off)    Roles: class tutor takes them; admin / coordinator report
Purpose: the 16th/32nd-session check-in: start, answer items (letters or open items), result Met / Not met.
Calls:
- ✅ `AralCheckinViewModel.tools()`, `items(toolId)`, `learnerCheckins(enrollmentId)` → `AralLearnerCheckins`; `result(checkinId)` → `AralCheckinResult` (`score: AralCheckinScore`, `passPct`; class T: ARAL-G5)
- ✅ `startCheckin(...)`, `editCheckin(...)`, `deleteCheckin(id)`, `answerChoices(...)`, `markOpen(...)`, `clearAnswer(...)`
- 🆕 Met / Not met and the percent text — ARAL-G2
- ✅ admin: `checkinReport(...)` → `AralCheckinReport`; `checkinReportCsv(...)` → `String`
Console: `aral-checkin-tools`, `aral-checkin-items`, `aral-checkins`, `aral-checkin`, `aral-checkin-start`, `aral-checkin-edit`, `aral-checkin-delete`, `aral-checkin-answers`, `aral-checkin-mark`, `aral-checkin-clear`, `aral-checkin-report`, `aral-export-checkins`

### ARAL settings
Build: both (view) / admin (set)    Roles: view all; set admin / coordinator
Purpose: check-in cut-off, SHARP (foundational program), KS1 extended, idle-session days; region and school layers.
Calls:
- ✅ `settingLayers(schoolId)` → `AralCheckinSettingLayers`; `foundationalProgramLayers`, `ks1ExtendedLayers`, `idleSessionDaysLayers` → records `(region, school, effective)` — defaults missing: ARAL-G4
- ✅ admin: `setPassPct`, `setFoundationalProgram`, `setKs1Extended`, `setIdleSessionDays`, `resetSchoolSettings(schoolId)`
- ✅ `localSettings(schoolId)` → `AralCheckinSettings`, `localSessionSettings(schoolId)` → `AralSessionSettings` (class T: ARAL-G5)
Console: `aral-checkin-cutoff`, `aral-checkin-cutoff-set`, `aral-checkin-cutoff-reset`, `aral-sharp`, `aral-sharp-set`, `aral-ks1-extended`, `aral-ks1-extended-set`, `aral-idle-days`, `aral-idle-days-set`

### Materials and recommendations
Build: both (read, recommend) / admin (catalog)    Roles: all read; catalog admin / coordinator
Calls:
- ✅ `AralMaterialViewModel.catalog(activeOnly:)`, `material(id)`, `recommendations(enrollmentId)` → `AralRecommendation`
- ✅ admin: `addMaterial(...)`, `updateMaterial(...)`, `setActive(id, active)`, `deleteMaterial(id)`, `setSchoolLink(materialId, schoolId, link)`, `sectionRecommendations(...)`; `lastMirrorWarning` (class E: ARAL-G7)
Console: `aral-materials`, `aral-recommend`, `aral-recommend-section`, `aral-material-add`, `aral-material-set`, `aral-material-active`, `aral-material-delete`, `aral-material-school-link`

### Readability log (SHARP only)
Build: both    Roles: class tutor
Calls:
- ✅ `AralReadabilityViewModel.available(schoolId)` → `bool`; `entries(enrollmentId)`; `add(...)`, `update(...)`, `delete(id)` (entry carries `AralReadability`, class T: ARAL-G5)
Live previews: Flesch ease / grade of a typed text before saving has no call — ARAL-G9 (M).
Console: `aral-readability`, `aral-readability-add`, `aral-readability-set`, `aral-readability-delete`

### Implementation report and roster files
Build: admin    Roles: admin / coordinator
Calls:
- ✅ `AralReportViewModel.implementationReport(...)` → `AralImplementationReport` (rows per section) — grade and school totals missing: ARAL-G3
- ✅ `implementationReportXlsx(template:, ...)` → `(bytes, notes)`; `implementationReportCsv(...)` → `String`
- ✅ `AralViewModel.rosterCsv(...)`; `AralRosterImportViewModel.preview(schoolId, year, bytes, fileName)`, `importRoster(...)`
Console: `aral-report`, `aral-export-report`, `aral-export-report-csv`, `aral-export-roster`, `aral-import-roster-preview`, `aral-import-roster`

## Gaps

**ARAL-G1** (I, N) — "n/15 active" reads `aralClassCap` from `aral_rules.dart` in `aral_command_helpers.dart`.
Fix: `AralClassViewModel.classCap` getter (`int`, = `aralClassCap`).
Removes baseline: `core/console/commands/aral_command_helpers.dart -> core/services/aral_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).

**ARAL-G2** (I, N) — Met / Not met (`AralCheckinScore.passes(passPct)`) and the percent text are made in `aral_checkin_command_helpers.dart`.
Fix: `AralCheckinResult.met` (`bool`, = `score.passes(passPct)`) and `AralCheckinScore.wholePercent` (`int`, same rounding as `toStringAsFixed(0)`). The report rows get the same if they carry a score (checked in the batch).
Removes baseline: `core/console/commands/aral_checkin_command_helpers.dart -> core/services/aral_checkin_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).

**ARAL-G3** (N) — The implementation report's grade subtotals (when a grade has more than one section) and the school total are summed in `aral-report`. The DepEd layout shows them, so a screen needs them too.
Fix: `AralImplementationReport.gradeTotals` → `Map<int, AralReportTotals>` and `.schoolTotal` → `AralReportTotals` (new small class in `aral_report_viewmodel.dart`: `enrolment`, `bosy`/`mosy` per column, `bosyTotal`, `mosyTotal`, `exitedGradeLevelReady`, `exitedOther`, `exited`, `bosyMinusMosy`), same sums as the command; the command prints from them.
Decision: fix (owner 2026-10-24, as recommended).

**ARAL-G4** (I, N) — Setting defaults: the check-in cut-off and idle days come from `AralCheckinSettings.defaults` / `AralSessionSettings.defaults`; SHARP and KS1-extended defaults ("off") are fixed text in the command.
Fix: per COMMON-G2: `AralCheckinSettingLayers.defaults`; the three record results gain a `defaults` field (`bool` / `int`), from the same constants.
Removes baseline: `core/console/commands/aral_checkin_commands.dart -> core/services/aral_checkin_rules.dart`, `core/console/commands/aral_checkin_commands.dart -> core/services/aral_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).

**ARAL-G5** (T) — Service types in results: `AralCheckinScore`, `AralCheckinScoring`, `AralCheckinSettings` (`aral_checkin_rules.dart`); `AralPlacement`, `AralProgramSettings`, `AralRankKey`, `AralSessionSettings` (`aral_rules.dart`); `AralReadability` (`aral_readability.dart`).
Fix: `core/models/aral_types.dart` exports them.
Decision: fix (owner 2026-10-24, as recommended).

**ARAL-G6** (N) — `AralViewModel.tutors` returns a positional record `(User, int, int)`; a screen has to know which int is which.
Fix: named record `({User tutor, int classes, int activeLearners})`; its one caller (`aral-tutors`) updated.
Decision: fix (owner 2026-10-24, as recommended).

**ARAL-G7** (E) — `aral_material_viewmodel.dart:383` puts `$e` in `lastMirrorWarning`.
Fix: spec rule.
Decision: fix (owner 2026-10-24, as recommended).

**ARAL-G8** (E) — `AralClassViewModel._write` rethrows unknown database errors as they are (after turning known ones into `ViewModelException`).
Found: rethrowing the original exception is what every other ViewModel does; with COMMON-G1 a screen shows one fixed sentence for any non-`ViewModelException`, so the raw text never reaches the user.
Fix: no code change if COMMON-G1 is accepted (log the error before rethrowing, one line); otherwise wrap it in `ViewModelException(unexpectedErrorMessage)`.
Decision: no code change beyond logging the error before the rethrow, since COMMON-G1 is accepted (owner 2026-10-24).

**ARAL-G9** (M) — No Flesch preview of a typed text before saving a readability entry.
Fix: deferred (no console capability; the entry shows its scores after saving).
Decision: deferred: no console capability; the entry shows its scores after saving (owner 2026-10-24).
