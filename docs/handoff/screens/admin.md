# Admin: users, schools, sections, learners, assignments, SF1 import, login logs

All screens here are admin build only (admins and coordinators), except the learner lists marked "both".

### Users
Build: admin    Roles: admin / coordinator (school-bound: own school; superadmin: all)
Purpose: list accounts, create one (shows the temporary password once), activate/deactivate.
Calls:
- `UserViewModel.loadAll()` → `items: List<User>`
- `UserViewModel.create(email:, fullName:, role:, schoolId:)` → `String?` (temporary password), then `lastMirrorWarning` → `String?` (saved online but not copied onto the device; show it as a warning)
- `UserViewModel.setActive(id, isActive)`; `findByEmail(email)` → `User?`
Live previews: none.
Errors: forbidden role/school, email taken (ViewModelException); server errors (error rule in `common.md`).
Console: `user-list`, `user-create`, `user-set-active`

### Tutor assignments
Build: admin    Roles: admin / coordinator
Purpose: assign tutors to sections, remove an assignment, list by tutor or by section.
Calls:
- `TutorSectionAssignmentViewModel.assign(tutorId:, sectionId:)` → `TutorSectionAssignment`; `unassign(id)`; `lastMirrorWarning` → `String?`
- `loadForTutor(tutorId)`, `loadForSection(sectionId)` → `items` (with `section`, `tutorFullName`, `tutorEmail`)
Live previews: none.
Console: `assign-section`, `unassign-section`, `list-tutor-sections`, `list-section-tutors`

### Schools
Build: both (list) / admin (edit)    Roles: superadmin creates/deletes; school-bound admins see their own
Calls:
- `SchoolViewModel.loadAll()` → `items`; `create(...)` → `({School school, bool created})`; `update(school)`; `delete(id)`
- region name: `Region.byId(regionId)` (model)
Console: `school-list`, `school-create`, `school-update`, `school-delete`

### Sections
Build: both (list) / admin (edit)    Roles: admin / coordinator edit; tutors see their sections
Calls:
- `SectionViewModel.loadAll()` → `items` (online); `localSections()` → `List<Section>` (device); `getById(id)`
- `create(...)` → `({Section section, bool created})`; `update(...)`; `delete(id)` (grade level normalized; non-numeric refused)
Console: `section-list`, `list-sections`, `section-create`, `section-update`, `section-delete`

### Learners and roster CSV
Build: both    Roles: all (RLS-scoped)
Calls:
- `StudentViewModel.loadAll(sort:)` / `loadForSection(sectionId)` → `items` (online); `localStudents(sectionId)` (device)
- `StudentViewModel.rosterCsv(sectionId)` → `String` (the screen saves it)
Console: `student-list`, `student-list-section`, `list-students`, `export-section`

### Learner history
Build: admin    Roles: admin / coordinator (own school; superadmin: any learner)
Purpose: one learner's progress by school year, from the records on this device: section, CRLA profile per round and language, Phil-IRI results, each ARAL entry (class, tutor, attendance, 16th/32nd check-in), Summer Remediation class. Open it from the Learners screen (student id) or a search box (LRN). IRIP and the readability log are not repeated: link to their screens.
Calls:
- `AdminScope.of(context).learnerHistory.history(studentId)` / `historyByLrn(lrn)` → `LearnerHistory`: `student`, `years` (latest first), `scopeNote` (show it when not null: "Only your school's records are shown.")
- Each `LearnerHistoryYear`: `schoolYear`, `enrollments` (section name, grade, school, status), `crla` (round → language → profile; null profile = "no profile"), `philIri` (one `LearnerHistoryPhilIri` per section: `sectionName`, `results` = `PhilIriLearnerResults`), `aral` (`LearnerHistoryAral`: `enrollment`, `className` (null = waiting for a class), `tutorName`, `attendance.label`, `checkin16`/`checkin32` = passed / failed / notTaken), `srp` (class, tutor, room) and `isEmpty` (show "No assessments recorded")
Errors: not signed in; `Forbidden: only an admin or coordinator can view learner history.`; `Forbidden: that learner is not in your school.`; `Learner not found on this device. Download the latest data first (pull-cloud).` (ViewModelException).
Console: `learner-history`, `learner-history-lrn`

### SF1 import
Build: admin    Roles: admin / coordinator (own school)
Purpose: pick an SF1 workbook, check the column map, try it, import it, then resolve conflicts.
Calls:
- `ImportViewModel.columnMap` (`Sf1ColumnMap`, from `core/models/sf1.dart`) `.toMap()`, `.set(field, value)` → `String?`
- `previewRow(filePath, rowIndex)`, `trial(filePath)` → `Sf1TrialResult`, `import(filePath)` → `Sf1ImportResult` (types from `core/models/sf1.dart`). Takes a file path: SF1 import is a desktop admin task. Not available yet: a bytes version for phones.
- `loadPendingConflicts()` → `pendingConflicts`; `getConflict(id)`; `resolve(id, 'skip'|'update')`; `resolveAll(action)`
Live previews: none.
Errors: another school's file, unreadable workbook (ViewModelException).
Console: `column-map-show`, `column-map-set`, `import-preview`, `import-trial`, `import-students`, `list-conflicts`, `show-conflict`, `resolve-conflict`, `resolve-conflicts-all`

### Login logs
Build: admin    Roles: admin / coordinator
Purpose: recent sign-in attempts (device + server, tagged), or one user's.
Calls:
- `LoginLogViewModel.loadRecent({limit = 50})`, `loadForUser(userId)` → then `items: List<SourcedLoginLog>`, `cloudError: String?` (set when the server's log could not be read; `items` then holds this device's log only)
Errors: not signed in online; `Forbidden: admin or coordinator only.` (ViewModelException).
Console: `login-recent`, `login-history`, `login-log` (dev tool: records a fake attempt)

### First admin (bootstrap)
Build: admin    Roles: nobody signed in (once per server)
Purpose: create the first admin of a new cloud/LAN server.
Calls:
- `AdminBootstrapViewModel.bootstrap(target, email, fullName)` → `String?` (temporary password)
Console: `bootstrap-admin`
