# Tutor build variant — design

Date: 2026-10-21. Status: approved 2026-10-22; built 2026-10-22/23 (plan `docs/superpowers/plans/2026-10-22-tutor-build.md`). See *Changes during implementation* at the end: it wins over the sections above where they differ.

## Goal

Ship two builds of BASA from one repo: an **admin build** (admins and coordinators) and a **tutor build** that does not contain admin-only code at all, on Android and Windows.

Why (owner): **security / attack surface** — unpacking a tutor APK or EXE must not reveal admin flows, approver calls or admin-only messages — and a **clean product** for tutors (smaller, nothing admin-shaped to reach). RLS stays the real security boundary; the split is defence in depth.

Success:
- The tutor binaries contain none of the admin markers (binary scan), and the admin binaries contain all of them (self-test).
- Nothing reachable from the tutor entry points imports an admin-only file (import walk).
- A tutor can still enter every score: CRLA, Phil-IRI, ARAL attendance, IRIP ratings, check-ins, readability log.
- Both apps install side by side on one phone, each with its own local database.
- Updating BASA is not double work: shared code is written once; one script builds and checks both variants.

Out of scope: iOS/macOS/Linux builds (no Mac; untested), UI (groupmates'), any schema change.

## Background (found 2026-10-21)

- The Android check before this work (same day) fixed: `WidgetsFlutterBinding.ensureInitialized()` first in `main()`; FFI database factory on every platform (Android 10's system SQLite 3.22 overflowed its parser stack on `check_phil_iri_reading_ins`; `package:sqlite3` 3.5.2 bundles SQLite through its build hook); INTERNET permission in the main manifest; debug console opens with 5 taps in the top-left corner.
- `lib/main.dart` (590 lines) and `lib/console/main.dart` (550 lines) each build every repository, ViewModel and command by hand. Every new command is wired twice.
- The Flutter app keeps its data in `getApplicationDocumentsDirectory()` (on Windows: the user's Documents folder, directly). The console uses `./data` under the working directory. Files: `basa_local.db` (+ SQLite side files), `supabase_config.json`, `sf1_column_map.json`.

## Decisions (owner, 2026-10-21)

1. **Split rule = live RLS.** Writes follow the policies (`sample-files/PGPOLICIES.csv`, functions export). A read that RLS allows but the ViewModel refuses to tutors (reports, trends) is admin. Read-only exports a tutor may do: owner picked `crla-export`, `export-section`, `aral-export-roster`; `crla-import` stays admin.
2. **Coordinators use the admin build** (same permissions as admins).
3. **No console in release builds** of either variant. Debug builds (`flutter run`) and the pure-Dart consoles keep it.
4. **Proof = import walk every piece + binary scan per release**, with an admin self-test.
5. **Approach 1:** split command files and wiring; ViewModels stay as they are. Admin methods inside shared ViewModels are dropped by AOT tree shaking; the binary scan proves it. A ViewModel is split only if the scan finds a leak.
6. **Separate apps:** Android flavors `admin` / `tutor`, application ids `enn5.basa.admin` / `enn5.basa.tutor`, names "BASA" / "BASA Tutor"; own data folder per variant.
7. Phil-IRI content **reads** (collections, passages, passage-show, criteria, thresholds) are in the tutor build.

## Structure

```
lib/
  main.dart                  admin app: wireShared + wireTutor + wireAdmin; console only in kDebugMode
  main_tutor.dart            tutor app: wireShared + wireTutor; same rule
  console/main.dart          admin console (pure Dart), data in ./data (unchanged; kits keep working)
  console/main_tutor.dart    tutor console (pure Dart), data in ./data_tutor
  core/wiring/               NEW, pure Dart, never imports Flutter
    app_context.dart         localDb, config, columnMap, session, ConsoleRegistry, ViewModelRegistry, authVm
    wire_shared.dart         wireShared(ctx)  + registerSharedCommands(ctx)  + registerDevCommands(ctx)
    wire_tutor.dart          wireTutor(ctx)   + registerTutorCommands(ctx)
    wire_admin.dart          wireAdmin(ctx)   + registerAdminCommands(ctx)
  core/console/commands/     mixed files split: <x>_commands.dart (tutor/shared) + <x>_admin_commands.dart
android/app/build.gradle.kts flavors admin / tutor
tool/check_tutor_imports.dart
tool/admin_markers.txt
tool/build_release.ps1       (Windows PowerShell, the owner's shell)
```

- `wire*` functions build repositories and ViewModels only (the UI needs them in release). Command registration is separate. The Flutter mains call it as `if (kDebugMode) { registerSharedCommands(ctx); ... }` **at the call site**, so the constant lets the compiler drop all command files from release builds. The consoles always register.
- A ViewModel used by both sides is built in `wireShared` or `wireTutor`; `wireAdmin` builds only admin-only ViewModels and may read the shared ones from the context.
- Each wire function registers its ViewModels in the `ViewModelRegistry` as today (same names).
- The admin build is a superset: admins and coordinators can also assess and log sessions.

### Data folder

- Flutter app: `<documents>/BASA/admin/` and `<documents>/BASA/tutor/`. On Android the documents folder is already private per application id; the subfolder keeps the code the same on both platforms.
- One-time move (admin build, desktop only): if `<documents>/basa_local.db` exists and `<documents>/BASA/admin/basa_local.db` does not, move `basa_local.db` (+ `-journal`/`-wal`/`-shm` if present), `supabase_config.json` and `sf1_column_map.json` into `BASA/admin/`. The move runs before the database is opened. A failure stops startup with a clear message (no half-moved state is opened).
- Android: the old `com.example.basa_capstone` app is a different app; its data is not migrated (development installs only). Uninstall it by hand.
- Tutor build starts empty: Supabase config from dart-defines on first run, else `config-set-*` (debug) — release tutor builds must be built with the `BASA_CLOUD_*` / `BASA_LAN_*` defines.

## Command split

Files that are wholly one side stay as they are. Mixed files keep the tutor/shared part; the admin part moves to `<x>_admin_commands.dart`.

| File | Tutor / shared | Admin (`*_admin_commands.dart`) |
|---|---|---|
| sync | sync-preview, -resolve, -upload, -status, -withdraw | sync-pending, -show, -approve, -reject |
| school | school-list | school-create, -update, -delete |
| section-commands | section-list | section-create, -update, -delete |
| tutor_section | list-tutor-sections | assign-section, unassign-section, list-section-tutors |
| crla_import | crla-export | crla-import, crla-import-preview |
| crla_threshold | crla-thresholds | crla-threshold-set, -reset, crla-regenerate |
| phil_iri | all others (gst, gst-list, start, sessions, session, passages-for, read, time, observe, reading-delete, miscue, miscue-update, miscue-remove, answer, rubric, complete, reopen, discard, score, results) | phil-iri-finalize, phil-iri-finalize-round |
| phil_iri_content | phil-iri-collections, -criteria, -passages, -passage-show, -thresholds | every add / edit / update / delete / activate / promote / threshold-set / threshold-reset |
| aral | aral-roster, aral-tutors | aral-propose, -enroll, -enroll-proposed, -update, -placement, -tutor, -exit, -reactivate, -notes, -remove |
| aral_session | aral-log, -session-edit, -session-delete, -sessions, -sheet, -mark, -mark-rest, -unmark, -attendance, -tutor-summary | aral-tutor-multi |
| aral_checkin | aral-checkin-tools, -items, aral-checkins, aral-checkin, -start, -answers, -mark, -clear, -edit, -delete, aral-checkin-cutoff, aral-sharp, aral-idle-days | aral-checkin-report, -cutoff-set, -cutoff-reset, aral-sharp-set, aral-idle-days-set |
| aral_material | aral-materials, aral-recommend, aral-recommend-section | aral-material-add, -set, -active, -delete, -school-link |
| aral_export | aral-export-roster | aral-export-report, -report-csv, aral-export-checkins; aral-import-roster, -preview |
| calendar | calendar-show | calendar-set, -skip, -clear |
| reminder | reminders-tutor | reminders-coordinator |
| trend | trend-aral-activity | trend-bands, -completion, -crla-profiles, -aral-exits |
| srp | srp-classes (SrpViewModel lets a tutor of the school read) | srp-list, -list-csv, -build, -classes-csv, -class-set, -add, -move, -remove, -class-delete, -classes-clear |

- Wholly admin: `admin_bootstrap`, `user`, `login`, `import` (SF1, column map, conflicts), `nla_report`, `aral_report`, `report_settings`.
- Wholly tutor/shared: `auth`, `version`, `config`, `pull`, `student` (incl. export-section), `crla`, `aral_irip`, `aral_readability`, `dashboard`.
- Dev only (debug builds of both variants, both consoles): `debug`, `text`, `test_data`.

Where a command line is split from a file that holds private helpers (`_int`, `_Usage`, line formatters), the helper is duplicated into the admin file or moved to a small shared helper file; the plan picks per file.

## Checks

### Import walk — `tool/check_tutor_imports.dart` (every piece)

Pure Dart. Starts at `lib/main_tutor.dart` and `lib/console/main_tutor.dart`, follows every `import`/`export`/`part` inside `lib/` (package:basa_capstone/… and relative), and fails (exit 1, listing the import chain) when it reaches a forbidden file:
- any `lib/core/console/commands/*_admin_commands.dart`, the wholly-admin command files above, `lib/core/wiring/wire_admin.dart`;
- admin-only ViewModels/services: sync review (`sync_review_viewmodel.dart`, `sync_review_local_sqlite.dart`), user, admin bootstrap, SF1 import (`import_viewmodel.dart`, `sf1_importer.dart`, `sf1_column_map.dart`, conflict repos), ARAL roster import, ARAL report, NLA report, SRP, CRLA import, login log, report settings ViewModel. The exact list is in the plan, kept at the top of the script.

### Binary scan — inside `tool/build_release.ps1` (per release)

- Builds `flutter build apk --release --flavor admin -t lib/main.dart` and `--flavor tutor -t lib/main_tutor.dart`, and the Windows release EXE for each entry, with the `BASA_*` defines passed through (at least one server required, see Risks).
- Windows has no `--flavor`: both entries build into the same `build/windows/x64/runner/Release` folder with the same EXE name, so the script copies each bundle to `build/dist/windows-admin` / `build/dist/windows-tutor` right after its build (APKs likewise to `build/dist/`). The window title (corrected after review: Flutter on Windows does not apply `MaterialApp.title` to the window, so both Windows apps show the runner title `basa_capstone`; a per-build window title needs native runner code, deferred).
- Scans the compiled Dart code (`lib/arm64-v8a/libapp.so` inside each APK; `data/app.so` in each Windows bundle) for every line of `tool/admin_markers.txt`.
- `admin_markers.txt`: distinctive string literals that only admin code contains — refusal messages of admin-only methods, the admin Edge Function name, approver RPC names, SF1/roster import messages. Not command names (release builds have no commands). One or more per admin file or admin method in a shared ViewModel.
- Pass = **no** marker in either tutor binary **and every** marker in each admin binary (self-test: proves each marker survives compilation and is spelled right). Prints the APK sizes.

## Testing

- Every piece: `dart analyze` (no errors), `dart run tool/check_tutor_imports.dart`, admin console regression (`dart run lib/console/main.dart` from a kit folder — existing kits unchanged).
- Tutor console score-entry run (tutor test account, `lib/console/main_tutor.dart`): CRLA start + part1 + part2; Phil-IRI start → read → miscue → answer → complete; ARAL attendance mark, IRIP rate, check-in answers, readability add; `sync-upload`. All succeed. `phil-iri-finalize`, `aral-enroll`, `sync-approve`, `user-create` → unknown command.
- End: `tool/build_release.ps1` passes; both APKs installed on the LYA L29 side by side, each signs in and keeps its own database; Windows admin build finds the moved data.

## Docs

- `CLAUDE.md`: Layout (`core/wiring/`, the two extra entries, `tool/`), Commands (build/run per variant, the checks), module workflow step "wire into both mains" becomes "wire into `wire_tutor`/`wire_admin` + the matching register function", remove the tutor-build item from *Parked*.
- `lib/core/CLAUDE.md`: where a new command goes (tutor vs admin file), add admin-only files to the import-walk list and a marker to `admin_markers.txt`.
- `README.md`: building and installing the two variants, the data folder move.

## Risks

- **Tree shaking keeps an admin method** (for example one reachable through a dynamic call). Caught by the scan; fix by splitting that ViewModel.
- **A marker that also appears in shared code** would fail the tutor scan falsely; markers are picked from admin-only methods and the plan checks each with a grep over the tutor side.
- **Old Windows data in Documents**: moved once; if both old and new exist, nothing is moved and a warning is logged.
- **Release tutor build without defines** starts with an empty Supabase config and no console to set it; `build_release.ps1` refuses to build unless at least one server is given (`BASA_CLOUD_URL` + `BASA_CLOUD_KEY`, or `BASA_LAN_URL` + `BASA_LAN_KEY`, for LAN-only schools).

## Changes during implementation (2026-10-22/23, all decided by the owner)

- **D1:** `NlaReportViewModel`, `SrpViewModel` and `ReportSettingsViewModel` are in the tutor build: the tutor's `dashboard`, `reminders-tutor`, `trend-aral-activity` and `srp-classes` need them. Their admin methods are dropped by tree shaking and covered by markers; report text is not a marker. The import-walk list is the one in `tool/check_tutor_imports.dart` (it does not forbid these three).
- **Scan builds.** Shipped release builds call no ViewModel method yet (no console, placeholder home screen), so the compiler removed every admin method from both builds and the planned scan proved nothing (the admin self-test caught it). `build_release.ps1` now also builds two never-shipped arm64 APKs with `--dart-define=BASA_SCAN_BUILD=true`, which compiles the console (commands **and** overlay; without the overlay nothing calls `session.run` and the handler bodies were dropped too) into the build. `[admin]` markers are checked on the scan builds; the shipped builds are checked with `[admin-release]` (the 7 admin-only ViewModel names) and `[debug]`. The switch is `basaScanBuild` / `basaHasConsole` in `lib/app_shell.dart`.
- **Three more commands are admin only**, because their ViewModel methods refuse tutors (the brainstorm checked RLS but not these methods): `aral-export-roster` (`AralViewModel.rosterCsv`, found by the marker scan), `list-tutor-sections` (`TutorSectionAssignmentViewModel.loadForTutor`) and `aral-recommend-section` (`AralMaterialViewModel.sectionRecommendations`), both found by running every tutor command as a tutor. `aral_export_commands.dart` and `tutor_section_commands.dart` are wholly admin again (identical to their pre-split versions). Tutor console: **115** commands; admin console: 228.
- Final review (2026-10-23, fixed): `[debug]` markers are now also required to be PRESENT in the scan builds (they were only checked for absence, so a misspelled one proved nothing); scan builds run before the shipped builds, so Flutter's standard APK output path never holds a console build; `TutorSectionAssignmentViewModel` (every method refuses tutors) moved to the admin wiring; a command name registered twice now throws.
- `BasaApp` / `BasaHomeScreen` moved to `lib/app_shell.dart` (with a title) so `main_tutor.dart` doesn't import `main.dart`.
- Android app names come from `manifestPlaceholders["appName"]` (`resValue` is disabled by default in this Android Gradle version).
- Found by the T6 score-entry kit, outside this design: the cloud never got ARAL migration A1c (archived `20261015070000`): no section-cap function (server-side reactivation failed), no cap on insert, no `foundational`. Fixed by `supabase/migrations/20261023010000_aral_restore_a1c.sql` (app update required: no), committed separately.
