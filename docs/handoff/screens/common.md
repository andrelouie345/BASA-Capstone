# Common: what every screen needs

## Rules every screen follows

- A screen gets its ViewModels from the widget tree: `BasaScope.of(context)` → `AppViewModels` (both builds, `lib/ui/basa_scope.dart`; short names: `.crla`, `.aralClass`, `.auth`, ...) and, in admin-build screens only (under `lib/ui/admin/`), `AdminScope.of(context)` → `AdminViewModels` (`.users`, `.sf1Import`, `.syncReview`, ...). The bundles hold ViewModels only (no repositories).
- A screen calls ViewModels and reads models. It never imports `core/services/`, `core/data/`, `core/wiring/`, `core/repositories/`, `supabase` or `sqflite` (`dart run tool/check_vm_boundary.dart` fails the build).
- ViewModels are request/response: none is a `ChangeNotifier` or a stream. The screen owns its loading, error and refresh state, and calls the method again after a change.
- The build is fixed by the entry point: `lib/main.dart` (admin build: admins, coordinators) or `lib/main_tutor.dart` (tutor build). A tutor-build screen never imports an admin file (`dart run tool/check_tutor_imports.dart`).
- Every ViewModel method checks the sign-in itself. Refusals come as `ViewModelException`; its `message` is written for the user and is shown as is.

### Signed-in user
Build: both    Roles: all
Purpose: show who is signed in, their role and school; choose what the screen offers.
Calls:
- `AuthViewModel.currentUser` → `User?` (`email`, `fullName`, `role`, `schoolId`; superadmin = admin with `schoolId == null`)
- `AuthViewModel.isSignedIn`, `isOffline`, `mustChangePassword` → `bool`
- `SchoolViewModel.loadAll()` then `items` → `List<School>` — the school's name for `schoolId`
Live previews: none.
Errors: none (getters).
Console: `whoami`

### Pickers
Build: both    Roles: all
Purpose: choose a school, section, class, learner, school year, round or region by name.
Calls:
- `SchoolViewModel.loadAll()` → `items: List<School>` (schools the user may see)
- `SectionViewModel.localSections()` → `List<Section>` (device copy; `Section.toString()` = grade + name) and `loadAll()` → `items` (online)
- `StudentViewModel.localStudents(sectionId)` → `List<Student>`; `loadForSection(sectionId)` (online)
- `AralClassViewModel` class list (see `aral.md`)
- `DashboardViewModel.schoolYears()` → `List<String>` (latest first)
- rounds: `PhilIriRound.values`, `CrlaRound.values` (`core/models/`, each has `label`)
- regions: `Region` (`core/models/region.dart`, `Region.byId`)
Live previews: none.
Errors: not signed in.
Console: `school-list`, `list-sections`, `section-list`, `list-students`, `student-list-section`, `aral-classes`, `dashboard-years`

### Online / offline and pending work
Build: both    Roles: all
Purpose: show whether the device works offline, what waits to be uploaded, and that records in a pending upload are read-only.
Calls:
- `AuthViewModel.isOffline` → `bool`
- `SyncViewModel.preview()` → `SyncPreview` (unsent work), `uploads()` → `List<SyncUploadRow>` (see `sync.md`)
- Not available yet: asking "is this record locked by a pending upload?" before the user edits it. The ViewModel refuses the write, and its message says so.
Live previews: none.
Errors: a write on a locked record is refused by the ViewModel (message shown as is).
Console: `sync-preview`, `sync-status`

### Version refusal
Build: both    Roles: all
Purpose: when sign-in is refused because the server and the app are on different BASA releases, say which side must update.
Calls:
- `AuthViewModel.signIn(...)` → `String?` error (the refusal text), `versionWarning` → `String?`
Live previews: none.
Errors: the refusal text itself.
Console: `sign-in`, `version-check`

### Error display
Build: both    Roles: all
Purpose: one rule for showing failures.
Calls: any.
Errors: `ViewModelException` → show `message`. Any other exception (server or database error) → show `unexpectedErrorMessage` (`core/models/messages.dart`) and log the detail (`debugPrint`); never show the exception text.
Console: the console prints `"<what> failed: $e"`; a screen must not.
