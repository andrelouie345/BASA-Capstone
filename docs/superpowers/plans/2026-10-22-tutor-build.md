# Tutor Build Variant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an admin build and a tutor build of BASA from one repo, on Android and Windows, where the tutor binaries carry no admin-only code.

**Architecture:** The duplicated wiring in both mains moves into pure-Dart `lib/core/wiring/` (`wireShared/wireTutor/wireAdmin` build ViewModels; `register*Commands` register console commands). Mixed command files are split so every admin command lives in an admin-only file. Two new entry points use only the shared and tutor wiring. An import walk (every piece) and a binary marker scan of the release builds (per release, with an admin self-test) prove the exclusion.

**Tech Stack:** Flutter 3.47 / Dart 3.13, sqflite_common_ffi (bundled SQLite via package:sqlite3 3.5.2 hooks), flutter_test, package:archive (already a dependency), Gradle Kotlin DSL, Windows PowerShell 5.1.

**Spec:** `docs/superpowers/specs/2026-10-21-tutor-build-design.md` (approved 2026-10-22). Read it with this plan.

## Decisions for the owner (answer before Task 1)

These came up while reading the code for this plan; they are not settled by the spec.

- **D1 (spec gap, needs your answer).** The tutor side cannot leave out `NlaReportViewModel`, `SrpViewModel` and `ReportSettingsViewModel`: `DashboardViewModel` (tutor `dashboard`) imports `nla_report_viewmodel` + `srp_viewmodel`, `ReminderViewModel` (`reminders-tutor`) and `TrendViewModel` (`trend-aral-activity`) import `nla_report_viewmodel`, `NlaReportViewModel` imports `report_settings_viewmodel`, and `srp-classes` needs `SrpViewModel`. `DashboardViewModel.summary` picks the school/region branch by role at run time, so the code that computes progress, the BOSY masterlist and SRP candidates stays reachable in the tutor binary (it still only sees RLS-limited data). Options:
  - **(a) Recommended:** accept it. These three ViewModels are shared; their *write/manage* methods (SRP class edits, report-settings writes) are still dropped by tree shaking and are covered by markers; report-computation code is not used as a marker. The spec's forbidden list is corrected in Task 6. No extra work.
  - (b) Split `DashboardViewModel`, `ReminderViewModel`, `TrendViewModel` and `SrpViewModel` into tutor and admin classes so the NLA/SRP report code leaves the tutor build. Adds about two tasks and changes the ViewModel API the UI will call.
- **D2.** `sync_apply` is called by the *uploader* (`SyncViewModel`, auto-approve / admin uploads), so it is **not** an admin marker; `sync_reject` is.
- **D3.** `AppContext` does not hold the SF1 column map (the spec listed it): `sf1_column_map.dart` is admin-only, so `wireAdmin` loads it.
- **D4.** Naming: admin halves are `<x>_admin_commands.dart` with `register<X>AdminCommands(...)`. Helper rule when splitting: a private helper used by both halves moves to `<x>_command_helpers.dart` (public names, no admin content); a helper used by one half moves with it.
- **D5.** Automated tests go in `test/` and run with `flutter test` (pure-Dart tests, no widgets): command-set tests, the data-folder move, the import walk, the marker scanner. Console runs and verify kits stay as the owner's check.
- **D6.** If the data-folder move fails, the Flutter app shows a one-screen error (`MaterialApp` with the message) instead of the home screen. This is the only UI touched, besides the title.
- **D7.** `--flavor` becomes required for `flutter run`/`build` on Android (`--flavor admin` or `--flavor tutor`). Windows ignores flavors; the entry point (`-t`) picks the variant there.

## Global Constraints

- `lib/core/**` never imports Flutter; `lib/core/wiring/` is pure Dart.
- Application ids `enn5.basa.admin` / `enn5.basa.tutor`; app names "BASA" / "BASA Tutor"; `MaterialApp.title` "BASA" / "BASA Tutor".
- Data folders: Flutter `<documents>/BASA/admin/` and `<documents>/BASA/tutor/`; admin console `./data` (unchanged); tutor console `./data_tutor`.
- Legacy move (admin build, desktop only): `basa_local.db`, `basa_local.db-journal`, `basa_local.db-wal`, `basa_local.db-shm`, `supabase_config.json`, `sf1_column_map.json` from `<documents>/` into `<documents>/BASA/admin/`.
- No console in release builds of either variant: command registration and `DebugConsoleShell` only under `kDebugMode`, written at the call site.
- Release builds need at least one server: `BASA_CLOUD_URL`+`BASA_CLOUD_KEY` or `BASA_LAN_URL`+`BASA_LAN_KEY`.
- No migration, no SQLite version bump, no ViewModel API change.
- `dart analyze`: no errors (existing lints accepted).
- Owner rules: no git commands run by the implementer; each task ends by handing the owner a conventional commit message. Any choice not settled here or in the spec is asked, not ruled. Backend only; UI touched only where named (D6, titles).

## Review Focus

1. **A desktop admin user with existing data in Documents** must find all of it (sessions, config) after updating — Task 3 test `moves legacy files into BASA/admin`.
2. **A move interrupted half-way** (crash or locked file) must complete on the next start, not leave the config behind — Task 3 test `retry after a failed move finishes it` (db moved last).
3. **Old and new data both present** must not overwrite either — Task 3 test `both present: nothing moved, one warning`.
4. **A command registered in the wrong half** (or in both) must be caught before release — Tasks 1/2/4 exact command-set tests for both builds.
5. **A marker that is mistyped or compiled away** must not let a leak pass silently — Task 5 scanner test `missing in admin binary fails`.

## File Structure

```
lib/core/wiring/app_context.dart     AppContext.open(): localDb, dataDir, config, session, registry, vmRegistry, authVm
lib/core/wiring/wire_shared.dart     SharedVms + wireShared + registerSharedCommands + registerDevCommands
lib/core/wiring/wire_tutor.dart      TutorVms + wireTutor + registerTutorCommands
lib/core/wiring/wire_admin.dart      AdminVms + wireAdmin + registerAdminCommands
lib/core/wiring/data_dir.dart        prepareDataDir + DataDirMoveException
lib/core/console/commands/*_admin_commands.dart   admin halves (Task 2)
lib/main.dart, lib/console/main.dart              admin entries (rewired)
lib/main_tutor.dart, lib/console/main_tutor.dart  tutor entries (Task 4)
tool/import_walk.dart                findForbiddenImports (library)
tool/check_tutor_imports.dart        CLI: forbidden list + exit code
tool/scan_markers.dart               marker scan library + CLI
tool/admin_markers.txt               [admin] / [debug] markers
tool/build_release.ps1               builds 4 artifacts, runs the scan
test/core/wiring/command_sets_test.dart, admin_commands.txt, tutor_commands.txt
test/core/wiring/data_dir_test.dart
test/tool/import_walk_test.dart, test/tool/scan_markers_test.dart
android/app/build.gradle.kts, android/app/src/main/AndroidManifest.xml
```

---

### Task 1: Move the wiring into `lib/core/wiring/` (behaviour unchanged)

**Files:**
- Create: `lib/core/wiring/app_context.dart`, `wire_shared.dart`, `wire_tutor.dart`, `wire_admin.dart`
- Modify: `lib/console/main.dart:140-528` (wiring body), `lib/main.dart:147-546` (same)
- Test: `test/core/wiring/command_sets_test.dart`, `test/core/wiring/admin_commands.txt`

**Interfaces:**
- Produces:
  - `class AppContext { final Database localDb; final String dataDir; final SupabaseConfigStore config; final ConsoleSession session; final ConsoleRegistry registry; final ViewModelRegistry vmRegistry; final AuthViewModel authVm; static Future<AppContext> open({required String dataDir}); }` — opens `LocalDatabase.instance(dataDir)`, loads the config, builds registry/session/vmRegistry and `AuthViewModel` exactly as the mains do today. The caller sets `databaseFactory` first.
  - `SharedVms wireShared(AppContext ctx)` — fields: `textVm, testDataVm, syncVm, schoolVm, sectionVm, studentVm, tutorSectionVm, tutorSectionRepo, exporter, sectionRepo, studentRepo`.
  - `TutorVms wireTutor(AppContext ctx, SharedVms s)` — fields: `crlaVm, crlaExportVm, crlaThresholdVm, philIriContentVm, philIriVm, aralVm, aralSessionVm, aralIripVm, aralCheckinVm, aralMaterialVm, aralReadabilityVm, calendarVm, reportSettingsVm, nlaReportVm, reminderVm, trendVm, srpVm, dashboardVm`.
  - `Future<AdminVms> wireAdmin(AppContext ctx, SharedVms s, TutorVms t)` — loads `Sf1ColumnMap.load(ctx.dataDir)`; fields: `userVm, importVm, syncReviewVm, loginLogVm, crlaImportVm, aralReportVm, aralRosterImportVm`.
  - `void registerSharedCommands(AppContext, SharedVms)`: config, auth, version, pull, sync, school, section, student, tutor_section.
  - `void registerTutorCommands(AppContext, SharedVms, TutorVms)`: crla, crla export, crla_threshold, phil_iri_content, phil_iri, aral, aral_session, aral_irip, aral_checkin, aral_material, aral_readability, aral_export (whole, until Task 2), calendar, reminder, trend, srp, dashboard.
  - `void registerAdminCommands(AppContext, SharedVms, TutorVms, AdminVms)`: admin_bootstrap, user, import, sync review, login, crla import, nla_report, report_settings, aral_report, aral roster import.
  - `void registerDevCommands(AppContext, SharedVms)`: text, test_data, debug (call it last so `list-viewmodels` sees every ViewModel).
  - Every ViewModel keeps its current `vmRegistry` name and constructor arguments.

- [ ] **Step 1: Capture the baseline command list.** From a scratch folder, pipe `help` + `exit` into the current admin console (launcher recipe in memory `console-test-harness`), take each line's text before ` — `, sort, write `test/core/wiring/admin_commands.txt`. Expected: 228 lines (227 commands + `help`).
- [ ] **Step 2: Write the failing test** `test/core/wiring/command_sets_test.dart`: `setUpAll` → `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` and a temp dir. Test `'admin build registers exactly the baseline commands'`: open `AppContext`, run `wireShared`, `wireTutor`, `wireAdmin`, then all four `register*` functions; `expect(ctx.registry.all.map((c) => c.name).toList()..sort(), File('test/core/wiring/admin_commands.txt').readAsLinesSync())`.
- [ ] **Step 3: Run it.** `flutter test test/core/wiring/command_sets_test.dart` → FAIL (wiring files missing).
- [ ] **Step 4: Implement the four wiring files** by moving the bodies out of `lib/console/main.dart` (same order, same arguments; reuse one repository instance where the mains already do, e.g. `tutorSectionRepo`).
- [ ] **Step 5: Rewire both admin mains**: entry keeps factory init, data folder (`./data` / `docsDir` for now) and REPL/`runApp`; the middle becomes `AppContext.open` + the wire and register calls. `BasaApp` gets `textVm` from `SharedVms`.
- [ ] **Step 6: Run** `flutter test test/core/wiring/command_sets_test.dart` → PASS; `dart analyze` → no errors.
- [ ] **Step 7: Regression kit.** Rerun the existing kit `D:/0_CAPSTONE/verify/d6` on a scratch copy and diff against its expected files: only timestamps differ. Hand the owner the same kit command.
- [ ] **Step 8: Commit message** (owner commits): `refactor(wiring): move app/console wiring into core/wiring`.

### Task 2: Split the mixed command files

**Files:**
- Create: `lib/core/console/commands/{sync,school,section,tutor_section,crla_import,crla_threshold,phil_iri,phil_iri_content,aral,aral_session,aral_checkin,aral_material,aral_export,calendar,reminder,trend,srp}_admin_commands.dart` (for `section-commands.dart` the admin file is `section_admin_commands.dart`), plus `<x>_command_helpers.dart` where D4 needs one
- Modify: the 17 matching command files, `lib/core/wiring/wire_tutor.dart`, `wire_shared.dart`, `wire_admin.dart`

**Interfaces:**
- Consumes: Task 1 register functions.
- Produces: `register<X>AdminCommands(ConsoleRegistry registry, ...)` per file (arguments = the ViewModels its commands use); `registerAralExportCommands(registry, aralVm)` keeps only `aral-export-roster`; `registerAralExportAdminCommands(registry, aralReportVm, aralCheckinVm)`; `registerSyncReviewCommands` moves to `sync_admin_commands.dart`; `registerCrlaImportCommands` moves to `crla_import_admin_commands.dart`; `registerAralRosterImportCommands` moves to `aral_export_admin_commands.dart`. The command ↔ file split is the spec's *Command split* table, exactly.

- [ ] **Step 1: Split one file at a time** (move each admin command's registration + its helpers per D4); after each file, `flutter test test/core/wiring/command_sets_test.dart` → PASS (admin set unchanged).
- [ ] **Step 2: Move the admin register calls** into `registerAdminCommands`; `registerTutorCommands`/`registerSharedCommands` call only non-admin files.
- [ ] **Step 3: Check no tutor/shared command file names an admin command.** For each name in the spec's admin column, grep `'<name>'` under `lib/core/console/commands/` → found only in `*_admin_commands.dart` or the seven wholly-admin files. (Task 4's tutor set test pins this permanently.)
- [ ] **Step 4:** `dart analyze` → no errors; command-set test PASS; rerun kit d6 → unchanged.
- [ ] **Step 5: Commit message:** `refactor(console): split admin commands into *_admin_commands files`.

### Task 3: Per-variant data folder and debug-only console in the admin app

**Files:**
- Create: `lib/core/wiring/data_dir.dart`
- Modify: `lib/main.dart` (data folder, `kDebugMode` guards, error screen per D6)
- Test: `test/core/wiring/data_dir_test.dart`

**Interfaces:**
- Produces:
  - `Future<String> prepareDataDir({required String documentsPath, required String variant, required bool moveLegacy, void Function(String message)? warn, Future<void> Function(File from, String toPath)? mover})` — returns `<documentsPath>/BASA/<variant>` (created). When `moveLegacy`: if `<documentsPath>/basa_local.db` exists and the target `basa_local.db` does **not**, move each legacy file (Global Constraints list) that exists and whose target does not, **`basa_local.db` last**. If both db files exist: move nothing, call `warn` once with a message naming both paths. `mover` defaults to `File.rename`.
  - `class DataDirMoveException implements Exception { final String message; }` — thrown when a move fails; message names the file and both folders.

- [ ] **Step 1: Write failing tests** in `data_dir_test.dart` (temp dirs, files with known contents):
  - `moves legacy files into BASA/admin`: legacy db + both json → returned path ends `BASA/admin`; the three files exist there with the same contents; none left in documents.
  - `retry after a failed move finishes it`: `mover` throws for `basa_local.db` → `DataDirMoveException`; json files already moved; db still in documents. Call again with the default mover → db moved.
  - `both present: nothing moved, one warning`: legacy db and target db with different contents → both unchanged; `warn` called once.
  - `moveLegacy false leaves documents alone`.
  - `tutor variant creates BASA/tutor only`.
- [ ] **Step 2:** `flutter test test/core/wiring/data_dir_test.dart` → FAIL.
- [ ] **Step 3: Implement `data_dir.dart`.**
- [ ] **Step 4:** tests → PASS.
- [ ] **Step 5: Wire it into `lib/main.dart`:** `prepareDataDir(documentsPath: docs.path, variant: 'admin', moveLegacy: Platform.isWindows || Platform.isLinux || Platform.isMacOS, warn: debugPrint)`; on `DataDirMoveException` → `runApp` of the D6 error screen and return. Register commands inside `if (kDebugMode) { ... }` at the call site; `home: kDebugMode ? DebugConsoleShell(...) : BasaHomeScreen(...)`.
- [ ] **Step 6: Check on Windows:** with the old `Documents/basa_local.db` present, `flutter run -d windows` → console `whoami`/`config-show` show the old config; files now in `Documents/BASA/admin/`. `flutter run -d windows --release` → app starts, 5 corner taps / tilde do nothing.
- [ ] **Step 7:** `dart analyze` → no errors. **Commit message:** `feat(build): per-variant data folder with one-time move; console only in debug builds`.

### Task 4: Tutor entry points and the import walk

**Files:**
- Create: `lib/main_tutor.dart`, `lib/console/main_tutor.dart`, `tool/import_walk.dart`, `tool/check_tutor_imports.dart`, `test/core/wiring/tutor_commands.txt`, `test/tool/import_walk_test.dart`
- Modify: `test/core/wiring/command_sets_test.dart`

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces:
  - `lib/main_tutor.dart`: as `lib/main.dart` without `wireAdmin`/`registerAdminCommands`, `variant: 'tutor'`, `moveLegacy: false`, title "BASA Tutor". `lib/console/main_tutor.dart`: as the admin console with `./data_tutor`. Both must not import anything admin (checked below).
  - `class ImportViolation { final String forbidden; final List<String> chain; }`
  - `List<ImportViolation> findForbiddenImports({required String packageRoot, required String packageName, required List<String> entries, required bool Function(String libPath) isForbidden})` — `libPath` is relative to `lib/` with `/`. Follows `import`/`export`/`part` with `package:<packageName>/…` or relative URIs; ignores `dart:` and other packages; visits each file once; one violation per forbidden file reached, with the first chain found.
  - `tool/check_tutor_imports.dart`: entries `lib/main_tutor.dart`, `lib/console/main_tutor.dart`; forbidden = `main.dart`, `console/main.dart`, `core/wiring/wire_admin.dart`, `core/console/commands/*_admin_commands.dart`, the seven wholly-admin command files (spec), `viewmodels/{sync_review,user,import,login_log,crla_import,aral_report,aral_roster_import}_viewmodel.dart`, `core/data/local/sync_review_local_sqlite.dart`, `core/services/{admin_bootstrap_service,sf1_importer,sf1_column_map}.dart`, `core/data/*/import_conflict_repository_*.dart`. Prints each chain; exit 1 on any violation, else prints `OK: no admin file reachable from the tutor entries` and exits 0.

- [ ] **Step 1: Write failing tests** in `import_walk_test.dart` (fixture package written to a temp dir):
  - `finds a forbidden file through a chain`: `lib/entry.dart` → `lib/a.dart` (relative) → `package:fx/b_admin_commands.dart` → one violation, `chain == ['entry.dart', 'a.dart', 'b_admin_commands.dart']`.
  - `clean tree has no violations`.
  - `cycles terminate` (a ↔ b).
  - `dart: and other packages are ignored`.
- [ ] **Step 2: Add the tutor set test** to `command_sets_test.dart`: `'tutor build registers exactly the tutor commands'` (shared + tutor + dev register functions only) vs `tutor_commands.txt` = the 107 tutor names (plan appendix) + 10 dev (`append-text clear-text db-add db-delete db-list db-use get-text list-viewmodels log-filter set-text`) + `help` = 118 lines, sorted.
- [ ] **Step 3:** `flutter test test/tool test/core/wiring` → FAIL.
- [ ] **Step 4: Implement** `tool/import_walk.dart`, `tool/check_tutor_imports.dart`, the two tutor entries.
- [ ] **Step 5:** tests → PASS. `dart run tool/check_tutor_imports.dart` → `OK…`. If it reports a forbidden file reached through a tutor path not listed in D1, **stop and report it to the owner** (do not widen the list on your own).
- [ ] **Step 6: Negative check:** temporarily add `import '../core/console/commands/user_commands.dart';` to `lib/console/main_tutor.dart` → the tool exits 1 showing that chain; remove it.
- [ ] **Step 7: Verify kit `D:/0_CAPSTONE/verify/tb4/`** (recipe: memory `verify-kits`; launcher imports `package:basa_capstone/console/main_tutor.dart`; data folder `data_tutor/` = copy of the verify data): `1_tutor_commands.txt` signs in as the tutor test account, runs `help`, `crla-results section 6`, `phil-iri-finalize 1`, `aral-enroll 1`, `sync-approve 1`, `user-list` → the last four print `Unknown command: …`.
- [ ] **Step 8:** `dart analyze` → no errors. **Commit message:** `feat(build): tutor entry points and import walk check`.

### Task 5: Android flavors, release script and binary marker scan

**Files:**
- Modify: `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml` (label → `@string/app_name`)
- Create: `tool/scan_markers.dart`, `tool/admin_markers.txt`, `tool/build_release.ps1`, `test/tool/scan_markers_test.dart`

**Interfaces:**
- Produces:
  - Gradle: `flavorDimensions += "variant"`; `productFlavors { create("admin") { dimension = "variant"; applicationId = "enn5.basa.admin"; resValue("string", "app_name", "BASA") }; create("tutor") { …"enn5.basa.tutor"…"BASA Tutor" } }`; `applicationId` removed from `defaultConfig`; `namespace` unchanged.
  - `admin_markers.txt`: lines under `[admin]` and `[debug]`; `#` comments and blank lines ignored.
  - `class ScanResult { final List<String> leaks; final List<String> missingInAdmin; bool get ok; }`
  - `ScanResult scanMarkers({required List<String> adminMarkers, required List<String> debugMarkers, required List<List<int>> tutorBinaries, required List<List<int>> adminBinaries})` — `leaks`: each `[admin]` marker found in any tutor binary and each `[debug]` marker found in any binary (prefixed with the binary's label); `missingInAdmin`: each `[admin]` marker absent from an admin binary. Byte search of the UTF-8 encoding.
  - CLI `dart run tool/scan_markers.dart --markers tool/admin_markers.txt --tutor <file>… --admin <file>…`: `.apk` → reads `lib/arm64-v8a/libapp.so` via package:archive; other files read as is. Prints leaks/missing; exit 1 unless ok.
  - `build_release.ps1 [-CloudUrl] [-CloudKey] [-LanUrl] [-LanKey]` (defaults from env vars of the same `BASA_*` names): refuses unless one complete server pair is given; builds `flutter build apk --release --flavor admin -t lib/main.dart`, `--flavor tutor -t lib/main_tutor.dart`, `flutter build windows --release -t lib/main.dart`, then `-t lib/main_tutor.dart`, copying each output to `build/dist/` (`basa-admin.apk`, `basa-tutor.apk`, `windows-admin/`, `windows-tutor/`) right after its build; runs `check_tutor_imports.dart` first and the scan last; prints the APK sizes; exits non-zero on any failure.

- [ ] **Step 1: Write failing tests** `scan_markers_test.dart` with byte fixtures:
  - `clean tutor and complete admin pass`.
  - `admin marker in tutor binary is a leak`.
  - `debug marker in any binary is a leak`.
  - `missing in admin binary fails` (Review Focus 5).
- [ ] **Step 2:** `flutter test test/tool/scan_markers_test.dart` → FAIL; implement `scan_markers.dart`; → PASS.
- [ ] **Step 3: Write `admin_markers.txt`.** `[admin]`: `create-user`, `bootstrap-admin`, `sync_reject`, `crla_regenerate_results`, and these exact messages: `Forbidden: only an admin or coordinator reviews uploads.`, `Forbidden: you can only create users for your own school.`, `Forbidden: only an admin or coordinator can import an ARAL roster.`, `Forbidden: only an admin or coordinator can generate ARAL reports.`, `Forbidden: only an admin or coordinator can finalize Phil-IRI sessions.`, `Forbidden: only an admin or coordinator can change the ARAL roster.`, `Forbidden: only an admin or coordinator sets the assessment calendar.`, `Forbidden: only an admin or coordinator sets the report settings.`, `Forbidden: you can only manage the CRLA thresholds of your own school.`, `Forbidden: only the superadmin marks a collection as prescribed.`, `Forbidden: only the superadmin manages region-wide materials.`, `Forbidden: you can only set the cut-off of your own school.`, `Forbidden: only an admin or coordinator of the school manages its SRP classes.`, `Forbidden: can only manage sections for your own school.`; plus one distinctive literal (≥ 20 chars) from each of `import_viewmodel.dart`, `sf1_importer.dart`, `crla_import_viewmodel.dart`, `login_log_viewmodel.dart` that grep shows only in that file. `[debug]`: `BASA Debug Console`, `mark a session done (needs the timed reading)`. Grep each line in `lib/` → it exists.
- [ ] **Step 4: Gradle + manifest.** `flutter build apk --debug --flavor tutor -t lib/main_tutor.dart` → builds.
- [ ] **Step 5: Write `build_release.ps1`**; run it with no server → refuses with a message; run it with the dev cloud defines → all four artifacts, import walk OK, scan OK.
- [ ] **Step 6: If the scan reports a leak or a marker missing in admin: stop and report it to the owner** with the marker and the method it comes from (choices: drop the marker as legitimately shared, or split that ViewModel — owner decides).
- [ ] **Step 7: Phone:** uninstall `com.example.basa_capstone`; install both `build/dist/*.apk` on the LYA L29 → two icons "BASA" and "BASA Tutor"; each signs in; a `pull-cloud` in one does not appear in the other (debug flavour builds for the console check: `flutter run --flavor tutor -t lib/main_tutor.dart`).
- [ ] **Step 8: Commit message:** `feat(build): android flavors, release script and admin marker scan`.

### Task 6: Tutor score-entry kit and docs

**Files:**
- Modify: `CLAUDE.md`, `lib/core/CLAUDE.md`, `README.md`, `docs/superpowers/specs/2026-10-21-tutor-build-design.md` (forbidden list and D1 outcome)

- [ ] **Step 1: Verify kit `D:/0_CAPSTONE/verify/tb6/`** (tutor console, tutor test account, ids filled from the verify DB): `1_crla.txt` crla-start → part1 → part2 → crla-results; `2_phil_iri.txt` start → read → time → miscue → answer → complete; `3_aral.txt` aral-log → aral-mark → aral-irip-rate → aral-checkin-start → aral-checkin-answers → aral-readability-add; `4_sync.txt` sync-preview → sync-upload → sync-status. Run each on a scratch copy; all succeed; write expected files and README.
- [ ] **Step 2: Docs.** `CLAUDE.md`: Layout (`core/wiring/`, the tutor entries, `tool/`), Commands (`flutter run --flavor admin|tutor -t …`, `dart run lib/console/main_tutor.dart`, `dart run tool/check_tutor_imports.dart`, `tool/build_release.ps1`), module workflow "wire into both mains" → "build the ViewModel in `wire_tutor`/`wire_admin` and register its commands in the matching `register*` function", remove the tutor-build item from *Parked*. `lib/core/CLAUDE.md`: a new command goes in the tutor file or the `*_admin_commands.dart` file by the RLS rule; a new admin-only file goes in the import-walk list; a new admin method gets a marker. `README.md`: building/installing both variants, `--flavor`, the data-folder move, uninstalling the old `com.example` app. Spec: forbidden list matches Task 4, D1 outcome recorded.
- [ ] **Step 3:** `dart analyze` → no errors; `flutter test` → all PASS; `dart run tool/check_tutor_imports.dart` → OK.
- [ ] **Step 4: Commit message:** `docs(build): tutor build docs, tutor score-entry kit`.

## Appendix: the 107 tutor and shared command names

`aral-attendance aral-checkin aral-checkin-answers aral-checkin-clear aral-checkin-cutoff aral-checkin-delete aral-checkin-edit aral-checkin-items aral-checkin-mark aral-checkin-start aral-checkin-tools aral-checkins aral-export-roster aral-idle-days aral-irip aral-irip-delete aral-irip-next aral-irip-notes aral-irip-rate aral-irip-start aral-irip-target aral-irip-targets aral-irip-unrate aral-log aral-mark aral-mark-rest aral-materials aral-readability aral-readability-add aral-readability-delete aral-readability-set aral-recommend aral-recommend-section aral-roster aral-session-delete aral-session-edit aral-sessions aral-sharp aral-sheet aral-tutor-summary aral-tutors aral-unmark calendar-show change-password config-set-cloud-key config-set-cloud-url config-set-lan-key config-set-lan-url config-show crla-export crla-part1 crla-part2 crla-results crla-start crla-stories crla-thresholds dashboard dashboard-years export-section list-sections list-students list-tutor-sections offline-status phil-iri-answer phil-iri-collections phil-iri-complete phil-iri-criteria phil-iri-discard phil-iri-gst phil-iri-gst-list phil-iri-miscue phil-iri-miscue-remove phil-iri-miscue-update phil-iri-observe phil-iri-passage-show phil-iri-passages phil-iri-passages-for phil-iri-read phil-iri-reading-delete phil-iri-reopen phil-iri-results phil-iri-rubric phil-iri-score phil-iri-session phil-iri-sessions phil-iri-start phil-iri-thresholds phil-iri-time pull-cloud reminders-tutor school-list section-list sign-in sign-in-offline sign-out srp-classes student-list student-list-section sync-preview sync-resolve sync-status sync-upload sync-withdraw trend-aral-activity version-app version-check whoami`

Admin console: 228 names (unchanged). Tutor console: 107 + 10 dev + `help` = 118.
