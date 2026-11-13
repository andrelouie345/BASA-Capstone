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
Purpose: one learner's progress by school year, from the records on this device: section, CRLA profile per round and test, Phil-IRI results, the ARAL entry (class, tutor, attendance, 16th/32nd check-in), Summer Remediation class. Open it from the Learners screen (student id) or a search box (LRN). IRIP and the readability log are not repeated: link to their screens.
Calls:
- `AdminScope.of(context).learnerHistory.history(studentId)` / `historyByLrn(lrn)` → `LearnerHistory`: `student`, `years` (latest first), `scopeNote` (show it when not null: "Only your school's records are shown.")
- Each `LearnerHistoryYear`: `schoolYear`, `enrollments` (at most one: section name, grade, school (null = school not on this device), status), `crla` (round → test → profile; tests are "MT (<language>)", "Filipino", "English" in that order; null profile = "no profile"), `philIri` (one `LearnerHistoryPhilIri` per section, two after a section move: `sectionName`, `results` = `PhilIriLearnerResults`, or `results` null and `unavailable` = the note to show), `aral` (0 or 1 `LearnerHistoryAral`: `enrollment` (program, entered/exited + reason, `basisSource`, `referredBy`/`referralReason`), `className` (null = waiting for a class), `tutorName`, `attendance.label`, `checkin16`/`checkin32` = passed / failed / notTaken / unavailable, `unavailable` = the note to show when the check-ins can't be read), `srp` (class, tutor, room) and `isEmpty` (show "No assessments recorded")
- SF1 leavers (since 2026-11-13): each enrollment also has `leftOn` / `leftNote` (set when archived: status `transferred_out` / `dropped_out`), and each year has `moves` (`LearnerHistoryMove`: `movedOn`, from/to section id and name, `source` = decided from the old section's SF1 / confirmed from the new section's SF1 / restored into another section / transferred in from another school). Show them with the section line. A transfer (`isTransfer`, since 2026-11-13) also has `fromSchoolName`, `fromStatus` and `fromLeftOn` (the other school's archive): show "Transferred in <date> from <school> (<section>, transferred out <date>)".
- A part that can't be read on this device comes with a note starting "Not available on this device: "; show the note there and the rest of the history as usual.
Errors: not signed in; `Forbidden: only an admin or coordinator can view learner history.`; `Forbidden: that learner is not in your school.`; `Learner not found on this device. Download the latest data first (pull-cloud).`; `No learner with LRN <lrn> on this device. Download the latest data first (pull-cloud).`; `Enter an LRN.` (ViewModelException).
Console: `learner-history`, `learner-history-lrn`

### SF1 import
Build: admin    Roles: admin / coordinator (own school)
Purpose: pick an SF1 workbook, check the column map, try it, import it, then resolve conflicts.
Calls:
- `ImportViewModel.columnMap` (`Sf1ColumnMap`, from `core/models/sf1.dart`) `.toMap()`, `.set(field, value)` → `String?`
- `previewRow(filePath, rowIndex)`, `trial(filePath)` → `Sf1TrialResult`, `import(filePath)` → `Sf1ImportResult` (types from `core/models/sf1.dart`). Takes a file path: SF1 import is a desktop admin task. Not available yet: a bytes version for phones.
- `loadPendingConflicts()` → `pendingConflicts`; `getConflict(id)`; `resolve(id, 'skip'|'update')`; `resolveAll(action)`
- `resolve(id, 'update')` → `ConflictResolution`. Three outcomes besides the plain update:
  - **refused** (ViewModelException) when the learner is already enrolled this year at this school: the message names `sf1-move` / `sf1-restore` (show it as is);
  - **a transfer** (SF1 leavers D15) when the learner is enrolled this year at another school: `transferredFrom` (`schoolName`, `sectionName`) is set. Say "Transferred in from <school> (<section>); this year's records stay at <school>."
    - A school's admin/coordinator can transfer only a learner the other school already archived, of the same grade, whose last name, first name and birth date on the SF1 match. Anything else gets one neutral refusal ("…can't be transferred in by your school: skip this conflict, or ask the superadmin to decide it"); show it as is.
    - Learners still active at the other school: the superadmin's screen only (`sf1-leavers.md`, *Cross-school transfers*).
    - An older SF1 of the school the learner left gets "this learner was transferred to another school on <date>: skip this conflict" while they are active at the other school; once that school archives them, they come back under the rules above.
    - An identity mismatch has no override, even for the superadmin: fix the name or birth date at the learner's school first.
  - `deviceWarning` set: saved on the server, but this device's copy wasn't updated (pull).
Live previews: none.
Errors: another school's file, unreadable workbook (ViewModelException).
Learners who are missing from the file, moving from another section or returning: see `sf1-leavers.md` (the trial result's `missing`, `wouldMove`, `wouldReturn`; the import's `waiting`, `lastImportWarning`).
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
