# Start here: building BASA's screens

This guide is for the UI team and for the Claude Code you work with. The backend (models, ViewModels, database, sync) is done and tested. Your job is the screens. Everything a screen needs is already a ViewModel call.

## What BASA is

BASA helps tutors run DepEd reading assessments and the ARAL-Reading program:
- **CRLA** for Grades 1–3,
- **Phil-IRI** (English) for Grades 4–10,
- **ARAL-Reading** classes, sessions, check-ins and reports, built on both results.

It works **offline first**: the data lives on the device and is sent to the server when there is a connection.

## Two apps from one codebase

| App | Entry point | Who uses it |
|-----|-------------|-------------|
| Admin build ("BASA") | `lib/main.dart` | admins and coordinators |
| Tutor build ("BASA Tutor") | `lib/main_tutor.dart` | tutors |

The tutor build must not contain admin code. Screens only admins and coordinators use go under `lib/ui/admin/`; a tutor-build screen never imports anything from there (a check refuses it, see *Checks before every PR*).

Run them: `flutter run --flavor admin -t lib/main.dart` or `flutter run --flavor tutor -t lib/main_tutor.dart` (Android needs `--flavor`; Windows ignores it).

## How a screen talks to the backend (MVVM)

BASA uses **MVVM**: the **Model** is plain data (a learner, an assessment, a report), the **ViewModel** does the work (checks the rules, reads and saves data), the **View** is your screen. A screen never touches the database or the rules itself; it asks a ViewModel and shows what comes back.

1. **Get the ViewModels** from the widget tree:
   ```dart
   final vms = BasaScope.of(context);          // both builds: vms.crla, vms.aralClass, vms.auth, vms.dashboard, ...
   final admin = AdminScope.of(context);       // admin build only, screens under lib/ui/admin/: admin.users, admin.sf1Import, ...
   ```
2. **Call a method** and wait for the answer:
   ```dart
   final years = await vms.dashboard.schoolYears();
   final summary = await vms.dashboard.summary(years.first);
   ```
3. **Show the model** that comes back. ViewModels don't notify you of changes (no `ChangeNotifier`, no streams): your screen keeps its own loading / error / result state, and calls the method again after the user changes something.
4. **Show errors with one rule:**
   - a `ViewModelException` → show its `message` as it is (it is written for the user);
   - anything else (a server or database error) → show `unexpectedErrorMessage` (from `lib/core/models/messages.dart`) and log the detail with `debugPrint`. Never show the raw error text.

A screen imports only `lib/viewmodels/`, `lib/core/models/`, Flutter and UI packages. It never imports `lib/core/services/`, `lib/core/data/`, `lib/core/wiring/`, `lib/core/repositories/`, `supabase` or `sqflite` (a check refuses it).

Which calls each screen needs: `screens/` (one file per module). Every screen to build: `checklist.md`.

## Offline, in the user's words

1. **Sign in online** the first time (later, the device's owner can sign in offline for a while).
2. **Download the latest data** (the console calls this `pull-cloud`): the device gets everything this user may see.
3. **Work offline**: assessments, sessions, check-ins are saved on the device.
4. **Send my work** (`sync-upload`): the unsent work goes to the server as one upload.
5. An **approver** (coordinator or admin) accepts or rejects it, unless the school approves automatically. Until then, those records are read-only on the device.

The screens for this are in `screens/sync.md`. Messages from the ViewModels already speak this language, with the console command in brackets, e.g. `Download the latest data (pull-cloud).`

## See the real output first: the console

Every screen block ends with a `Console:` line. Run that command to see what the ViewModel call returns with real data before you build the screen.
- **In the app (debug builds only):** press `~` three times quickly, or tap the top-left corner five times within two seconds. Type `help` for the command list.
- **Without the app:** `dart run lib/console/main.dart` (admin) or `dart run lib/console/main_tutor.dart` (tutor).

Release builds have no console.

## Examples to replace

These exist only to show how things fit together. Restyle or replace them in your own style:
- **`ExampleScreen`** (`lib/ui/example/example_screen.dart`, added with the example screen): the worked example (Dashboard home) — scope lookup, a ViewModel call, loading / error / result states. Debug build only, opened from the debug console. Replace it with the real screen.
- **`BasaHomeScreen`** (`lib/app_shell.dart`): placeholder home that shows one text value. Replace it with the real home screen and navigation.
- **`BasaStartupErrorApp`** (`lib/app_shell.dart`): shown when the data folder cannot be prepared. Keep what it does; restyle it freely.

The debug console (`lib/ui/debug/`) is a developer tool, not an app screen: leave it as it is.

## Light and dark mode

The app needs both a **light mode** and a **dark mode**. Neither is built yet: the `MaterialApp` in `lib/app_shell.dart` sets no `theme` or `darkTheme`. Add both there (following the phone's or computer's setting), and in every screen take colours from the theme (`Theme.of(context).colorScheme`), never hard-coded colours, so each screen works in both. It is a row in `checklist.md`.

## Checks before every PR

**DO NOT PLAY RESOURCE INTENSIVE GAMES WHILE THESE RUN.** A busy computer can slow the tests down or crash them.

```
dart analyze
flutter test
dart run tool/check_tutor_imports.dart
dart run tool/check_vm_boundary.dart
```

`dart analyze` must show no errors (old warnings are accepted). The other three must pass.

## Opening a PR

1. Make your branch from **`excelsior`** (not `main`).
2. Push your branch to GitHub.
3. On GitHub, open a pull request **into `excelsior`** (not `main`).
4. Run the checks above first.
5. The backend owner reviews it before it is merged.

## Next

- `checklist.md` — pick a screen, put your name on it.
- `screens/` — what that screen needs.
- `lib/ui/example/example_screen.dart` — the worked example (added with the example screen).
- `lib/ui/CLAUDE.md` — the UI rules for Claude Code (added with the example screen).
