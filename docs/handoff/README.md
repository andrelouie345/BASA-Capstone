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

Run them (**DO NOT PLAY RESOURCE INTENSIVE GAMES WHILE THE APP BUILDS AND RUNS.**): `flutter run --flavor admin -t lib/main.dart` or `flutter run --flavor tutor -t lib/main_tutor.dart` (Android needs `--flavor`; Windows ignores it).

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
- **Without the app** (**DO NOT PLAY RESOURCE INTENSIVE GAMES WHILE IT RUNS.**): `dart run lib/console/main.dart` (admin) or `dart run lib/console/main_tutor.dart` (tutor).

Release builds have no console.

## Examples to replace

These exist only to show how things fit together. Restyle or replace them in your own style:
- **`ExampleScreen`** (`lib/ui/example/example_screen.dart`): the worked example (Dashboard home) — scope lookup, a ViewModel call, loading / error / result states. Debug build only, opened from the debug console. Replace it with the real screen.
- **`BasaHomeScreen`** (`lib/app_shell.dart`): placeholder home that shows one text value. Replace it with the real home screen and navigation.
- **`BasaStartupErrorApp`** (`lib/app_shell.dart`): shown when the data folder cannot be prepared. Keep what it does; restyle it freely.

The debug console (`lib/ui/debug/`) is a developer tool, not an app screen: leave it as it is.

## Light and dark mode

The app needs both a **light mode** and a **dark mode**. Neither is built yet: the `MaterialApp` in `lib/app_shell.dart` sets no `theme` or `darkTheme`. Add both there, and in every screen take colours from the theme (`Theme.of(context).colorScheme`), never hard-coded colours, so each screen works in both.

The colours are **customizable**, for each mode, with **defaults preset**:
- You choose the colour names and their default values, in one Dart file under `lib/ui/` (e.g. `lib/ui/theme/basa_colors.dart`).
- The user's changes and their choice of light / dark / follow the device are saved **on the device** (not per user) by `ThemeSettingsViewModel` (`BasaScope.of(context).theme`), in `theme_settings.json` next to the server settings. Only changed colours are saved; everything else uses your defaults.
- The app shell reads the saved settings at start-up, builds both themes from defaults + changes, and rebuilds after the user changes something.

Calls and details: `screens/auth.md` (*Colours*). Rows 57 and 58 in `checklist.md`.

## Setting up Claude Code

The backend was built with Claude Code and the **Superpowers** plugin: every piece went *brainstorm → written plan → build task by task → review*, with tests and console checks before anything was called done. Use the same plugins so your Claude Code works the same way. In Claude Code, run:

```
/plugin install superpowers@claude-plugins-official
/plugin install frontend-design@claude-plugins-official
```

and in a terminal (the Flutter team's official plugin):

```
claude plugin marketplace add flutter/agent-plugins
claude plugin install dart-flutter@dart-flutter
```

If a command fails, run `/plugin`, open **Discover** and search for the name. Restart Claude Code after installing.

Also install **claude-win-notify** (Windows notifications when Claude Code finishes, asks a question or waits for your approval). In Claude Code: `/plugin` → **Discover** → search `claude-win-notify`. If it isn't listed, follow the install steps in its README (github.com/MT-SUPER-POWER/claude-win-notify; needs Windows 10 1809 or later, Node.js and git).

**Tests take a while.** `flutter test` takes about **8–9 minutes** on a laptop, and all four checks before a PR about 10. That is normal: the suite is mostly backend tests, and it must run in full. Let it finish (don't close the terminal), and let the notifier tell you when Claude Code is done instead of watching it. **DO NOT PLAY RESOURCE INTENSIVE GAMES WHILE THE TESTS RUN.**

| Plugin | What it gives you |
|--------|-------------------|
| **superpowers** | the working method: `brainstorming` (design a screen with you before code), `writing-plans`, `executing-plans`, `systematic-debugging`, `test-driven-development`, `requesting-code-review`, `verification-before-completion` (run it and show the output before saying it's done) |
| **frontend-design** | UI design guidance: a clear visual direction, typography, layout, so screens don't look like a default template |
| **dart-flutter** | the Dart and Flutter MCP server: Claude Code sees analyzer errors, runs tests and inspects the running app (widget tree, hot reload) |
| **claude-win-notify** | a Windows notification when Claude Code is done or needs you, so a long test run doesn't need watching |

A good way to start a screen: *"Use brainstorming to design the <screen> screen from docs/handoff/screens/<file>.md"*. Claude Code reads `lib/ui/CLAUDE.md` (the UI rules) by itself.

## Not using Claude Code?

Everything here still works with another AI tool (Copilot, Cursor, Gemini, a free-tier chat) or with no AI at all. The guide, `checklist.md`, `screens/` and the example screen are plain files for people to read.

- **Give it the UI rules.** Only Claude Code reads `lib/ui/CLAUDE.md` by itself. Paste it into the chat when you start, or copy it into your tool's own instruction file (Copilot: `.github/copilot-instructions.md`; Cursor: `.cursor/rules/`; many tools: `AGENTS.md`). Don't commit those copies: keep `lib/ui/CLAUDE.md` the one source.
- **Keep the context small.** Free tiers forget long conversations. For each screen, give it only `lib/ui/CLAUDE.md`, that screen's block from `screens/<module>.md`, and `lib/ui/example/example_screen.dart`. Not the whole repo.
- **Trust the checks, not the AI.** Run the four checks below before every PR, whatever wrote the code. If the AI imports something a screen must not (a service, the database, an admin file), `check_vm_boundary` or `check_tutor_imports` fails and names it.
- **Same branch rules.** Your work goes on your own branch made from `excelsior`, and the PR goes into `excelsior` (see *Opening a PR*).

## Checks before every PR

**DO NOT PLAY RESOURCE INTENSIVE GAMES WHILE THESE RUN.** A busy computer can slow the tests down or crash them.

```
dart analyze
flutter test
dart run tool/check_tutor_imports.dart
dart run tool/check_vm_boundary.dart
```

`dart analyze` must show no errors (old warnings are accepted). The other three must pass. `flutter test` alone takes about 8–9 minutes.

## Opening a PR

1. Make your branch from **`excelsior`** (not `main`).
2. Push your branch to GitHub.
3. On GitHub, open a pull request **into `excelsior`** (not `main`).
4. Run the checks above first.
5. The backend owner reviews it before it is merged.

## Next

- `checklist.md` — pick a screen, put your name on it.
- `screens/` — what that screen needs.
- `lib/ui/example/example_screen.dart` — the worked example.
- `lib/ui/CLAUDE.md` — the UI rules for Claude Code.
