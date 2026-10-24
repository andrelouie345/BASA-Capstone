# Admin: users, schools, sections, learners, assignments, SF1 import, login logs

All screens here are admin build only (admins and coordinators), except the learner lists marked "both".

### Users
Build: admin    Roles: admin / coordinator (school-bound: own school; superadmin: all)
Purpose: list accounts, create one (shows the temporary password once), activate/deactivate.
Calls:
- ✅ `UserViewModel.loadAll()` → `items: List<User>`
- ✅ `UserViewModel.create(email:, fullName:, role:, schoolId:)` → `String?` (temporary password), then `lastMirrorWarning` (class E: ADMIN-G4)
- ✅ `UserViewModel.setActive(id, isActive)`; `findByEmail(email)` → `User?`
Live previews: none.
Errors: forbidden role/school, email taken (ViewModelException); server errors (COMMON-G1).
Console: `user-list`, `user-create`, `user-set-active`

### Tutor assignments
Build: admin    Roles: admin / coordinator
Purpose: assign tutors to sections, remove an assignment, list by tutor or by section.
Calls:
- ✅ `TutorSectionAssignmentViewModel.assign(tutorId:, sectionId:)` → `TutorSectionAssignment`; `unassign(id)`; `lastMirrorWarning` (class E: ADMIN-G4)
- ✅ `loadForTutor(tutorId)`, `loadForSection(sectionId)` → `items` (with `section`, `tutorFullName`, `tutorEmail`)
Live previews: none.
Console: `assign-section`, `unassign-section`, `list-tutor-sections`, `list-section-tutors`

### Schools
Build: both (list) / admin (edit)    Roles: superadmin creates/deletes; school-bound admins see their own
Calls:
- ✅ `SchoolViewModel.loadAll()` → `items`; `create(...)` → `({School school, bool created})`; `update(school)`; `delete(id)`
- ✅ region name: `Region.byId(regionId)` (model)
Console: `school-list`, `school-create`, `school-update`, `school-delete`

### Sections
Build: both (list) / admin (edit)    Roles: admin / coordinator edit; tutors see their sections
Calls:
- ✅ `SectionViewModel.loadAll()` → `items` (online); `localSections()` → `List<Section>` (device); `getById(id)`
- ✅ `create(...)` → `({Section section, bool created})`; `update(...)`; `delete(id)` (grade level normalized; non-numeric refused)
Console: `section-list`, `list-sections`, `section-create`, `section-update`, `section-delete`

### Learners and roster CSV
Build: both    Roles: all (RLS-scoped)
Calls:
- ✅ `StudentViewModel.loadAll(sort:)` / `loadForSection(sectionId)` → `items` (online); `localStudents(sectionId)` (device)
- ✅ `StudentViewModel.rosterCsv(sectionId)` → `String` (the screen saves it)
Console: `student-list`, `student-list-section`, `list-students`, `export-section`

### SF1 import
Build: admin    Roles: admin / coordinator (own school)
Purpose: pick an SF1 workbook, check the column map, try it, import it, then resolve conflicts.
Calls:
- ✅ `ImportViewModel.columnMap` (`Sf1ColumnMap`, class T) `.toMap()`, `.set(field, value)` → `String?`
- ✅ `previewRow(filePath, rowIndex)`, `trial(filePath)` → `Sf1TrialResult`, `import(filePath)` → `Sf1ImportResult` (class P + T: ADMIN-G3)
- ✅ `loadPendingConflicts()` → `pendingConflicts`; `getConflict(id)`; `resolve(id, 'skip'|'update')`; `resolveAll(action)`
Live previews: none.
Errors: another school's file, unreadable workbook (ViewModelException).
Console: `column-map-show`, `column-map-set`, `import-preview`, `import-trial`, `import-students`, `list-conflicts`, `show-conflict`, `resolve-conflict`, `resolve-conflicts-all`

### Login logs
Build: admin    Roles: admin / coordinator
Purpose: recent sign-in attempts (device + server, tagged), or one user's.
Calls:
- ✅ `LoginLogViewModel.loadRecent(limit:, cloud:)`, `loadForUser(userId, cloud:)` → `items: List<SourcedLoginLog>`, `cloudError` — but the caller must build the cloud repository (ADMIN-G1)
Errors: none from the ViewModel today (ADMIN-G1).
Console: `login-recent`, `login-history`, `login-log` (dev tool: records a fake attempt)

### First admin (bootstrap)
Build: admin    Roles: nobody signed in (once per server)
Purpose: create the first admin of a new cloud/LAN server.
Calls:
- 🆕 `AdminBootstrapViewModel.bootstrap(target, email, fullName)` → `String?` (temporary password) — ADMIN-G2
Console: `bootstrap-admin`

## Gaps

**ADMIN-G1** (I, R, G) — `login-recent`/`login-history` build `LoginLogRepositorySupabase(authVm.client!)` in the command, and the sign-in + admin/coordinator checks are only in the command. `LoginLogViewModel` takes repositories (`useRepository`, `cloud:`) and checks nothing.
Fix: `LoginLogViewModel` gets the `AuthViewModel` and a cloud-repository factory in its constructor (wiring, like the other ViewModels); `loadRecent({int limit = 50})` and `loadForUser(String userId)` call `requireOnlineSession()` and refuse non-admin/coordinator with `ViewModelException('Forbidden: admin or coordinator only.')`; `record(...)` checks `requireActiveSession()` + the same role. `useRepository` and the `cloud:` parameter go away. Console output unchanged.
Removes baseline: `core/console/commands/login_commands.dart -> core/data/remote/login_log_repository_supabase.dart`
Decision: fix (owner 2026-10-24, as recommended).

**ADMIN-G2** (I, R) — `bootstrap-admin` picks the cloud/LAN profile from the config store, builds a `SupabaseClient` and an `AdminBootstrapService`, then a ViewModel, all in the command.
Fix: `AdminBootstrapViewModel` is built once in `wire_admin.dart` with the config store and a client factory; `bootstrap(String target, String email, String fullName)` → `String?` does the profile choice ("<target>.url not set" refusal as `ViewModelException`) and builds the client. Command only parses arguments.
Removes baseline: `core/console/commands/admin_bootstrap_commands.dart -> core/data/remote/supabase_config.dart`, `... -> core/services/admin_bootstrap_service.dart`, `... -> package:supabase/supabase.dart`
Decision: fix (owner 2026-10-24, as recommended).

**ADMIN-G3** (P, T) — SF1 import takes a file path all the way down (`.xls` files are converted on disk by `xls_to_xlsx_converter`); `Sf1ColumnMap`, `Sf1TrialResult`, `Sf1ImportResult` are service types.
Fix options: (a) bytes overloads `previewRowBytes(bytes, fileName, rowIndex)`, `trialBytes(bytes, fileName)`, `importBytes(bytes, fileName)` that write a temp file inside the ViewModel and call the path versions; (b) defer: SF1 import is a desktop admin task (the `.xls` converter needs a desktop tool anyway), and a desktop file picker gives a path. Plus the T export either way: `core/models/sf1.dart` with `export '../services/sf1_importer.dart' show Sf1TrialResult, Sf1ImportResult;` and `export '../services/sf1_column_map.dart' show Sf1ColumnMap;`. Recommend (b) + the export.
Decision: (b) (owner 2026-10-24): the path API stays (desktop admin task); add the type export only.

**ADMIN-G4** (E) — `user_viewmodel.dart:145` and `tutor_section_assignment_viewmodel.dart:109` put `$e` in `lastMirrorWarning`.
Fix: spec rule (sentence kept without `($e)`, exception to the logger).
Decision: fix (owner 2026-10-24, as recommended).

