# lib/ui — rules for screens

For the UI team and their Claude Code. Start with `docs/handoff/README.md` (the start-here guide); what each screen needs is in `docs/handoff/screens/`, the list of screens in `docs/handoff/checklist.md`. The backend (models, ViewModels, database, sync, console) is not built here: if a screen needs something no ViewModel offers, ask the backend owner, don't work around it.

## Fixed rules (the backend depends on them)

- **ViewModels only through the scopes.** `BasaScope.of(context)` → `AppViewModels` (both builds, `lib/ui/basa_scope.dart`); `AdminScope.of(context)` → `AdminViewModels` (admin build only, `lib/ui/admin/admin_scope.dart`). Never build a ViewModel, repository or Supabase client in a screen, and never touch `AuthViewModel.client`.
- **Imports.** Files in `lib/ui/` import only `lib/viewmodels/`, `lib/core/models/`, the Dart SDK, Flutter and UI packages. Never `lib/core/services/`, `lib/core/data/`, `lib/core/wiring/`, `lib/core/repositories/`, `supabase`, `sqflite` (`dart run tool/check_vm_boundary.dart` fails).
- **No console command strings in screens.** Call the ViewModel method the screen block names; the `Console:` line is only for seeing real output.
- **Errors.** `ViewModelException` → show `message` as is. Anything else → show `unexpectedErrorMessage` (`lib/core/models/messages.dart`) and log the detail with `debugPrint`; never show raw exception text.
- **ViewModels are request/response.** No `ChangeNotifier`, no streams: the screen keeps its loading / error / result state and calls again after a change. Read the ViewModel from the scope before any `await` (don't use `context` across one).
- **Admin screens only under `lib/ui/admin/`.** The tutor build must not reach them (`dart run tool/check_tutor_imports.dart` fails). A screen in both builds never imports from `lib/ui/admin/`.
- **Debug-only code behind `basaHasConsole`** (`lib/app_shell.dart`). Release builds have no console and no example screen.
- **Light and dark mode, customizable colours.** The app needs both (not built yet: `theme` + `darkTheme` + `themeMode` on the `MaterialApp` in `lib/app_shell.dart`), built from the UI's default colours plus the user's saved changes (`ThemeSettingsViewModel`, per device; see `docs/handoff/screens/auth.md#colours-light-and-dark-mode`). Screens take colours from `Theme.of(context).colorScheme`, never hard-coded colours.
- **The checks pass before every push** (below). UI work is pushed to `frontend_dev` (not `main`, not `excelsior`).
- **One screen per conversation.** Suggest `/clear` (or a new chat) once a screen is pushed; the docs carry what the next one needs.

## Yours to decide

Layout, widgets, theming (colours, fonts, the light and dark themes themselves), navigation and routing, the home screen, how a screen keeps its state, folders under `lib/ui/mobile/` and `lib/ui/windows/`, how big screens are split.

## Home and navigation

`lib/ui/home/`: `HomeScreen` (the signed-in home: a navigation rail on wide screens, a bottom bar or drawer on phones) shows the sections and screen cards listed in `home_sections.dart` (`basaHomeSections()`, both builds); the admin build adds its own in `lib/ui/admin/admin_home_sections.dart` (`adminHomeSections()`, passed in by `lib/main.dart`). Every checklist screen has a `HomeEntry` with a `builder`; an entry without one opens "Coming soon". Don't import `lib/ui/admin/` from `home_sections.dart`.

**"Both (view) / admin (edit)" screens.** Several admin-only methods live in shared ViewModels (school/section edits, calendar, thresholds, ARAL roster and classes, settings, materials, SRP, Phil-IRI content). A screen in both builds must not call them, or they are compiled into the tutor build (`tool/admin_markers.txt`, checked by `build_release.ps1`). So the shared screen only shows data and takes an optional editor (e.g. `SchoolsScreen({SchoolsEditor? editor})`); the editor is implemented under `lib/ui/admin/` (`AdminSchoolsEditor`) and the admin home entry passes it (`_adminVersions` in `admin_home_sections.dart`). Shared helpers: `lib/ui/common/screen_kit.dart` (`LoadView`, `runAction`/`runStep`, dialogs, export folder), `csv_table.dart`, `school_year_scope.dart`. Tests: `test/ui/screens_smoke_test.dart` opens every entry of both builds; `screens_data_test.dart` checks lists with data.

## Examples to replace

- `lib/ui/example/example_screen.dart` — **`ExampleScreen`**, the worked example (Dashboard home): scope lookup, a ViewModel call, loading / error / empty / result states, a refusal shown as is, theme colours only. **Debug build only**: opened from the debug console's header button. Replace it with the real screen.
- `lib/app_shell.dart` — **`BasaStartupErrorApp`**: shown when the data folder can't be prepared. Keep what it does, restyle it freely.

Leave `lib/ui/debug/` (the developer console) as it is.

## Checks

**DO NOT PLAY RESOURCE INTENSIVE GAMES WHILE THESE RUN.** A busy computer can slow the tests down or crash them.

```
dart analyze
flutter test
dart run tool/check_tutor_imports.dart
dart run tool/check_vm_boundary.dart
```

`dart analyze` must show no errors (old warnings are accepted); the other three must pass.
