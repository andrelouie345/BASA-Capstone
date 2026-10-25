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
- **The checks pass before every PR** (below), and PRs go into `excelsior`, not `main`.

## Yours to decide

Layout, widgets, theming (colours, fonts, the light and dark themes themselves), navigation and routing, the home screen, how a screen keeps its state, folders under `lib/ui/mobile/` and `lib/ui/windows/`, how big screens are split.

## Examples to replace

- `lib/ui/example/example_screen.dart` — **`ExampleScreen`**, the worked example (Dashboard home): scope lookup, a ViewModel call, loading / error / empty / result states, a refusal shown as is, theme colours only. **Debug build only**: opened from the debug console's header button. Replace it with the real screen.
- `lib/app_shell.dart` — **`BasaHomeScreen`**: placeholder home showing one text value. Replace it with the real home screen.
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
