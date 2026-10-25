# Gap history (ViewModel completeness check)

History of the ViewModel completeness check, 2026-10-24 (spec `docs/superpowers/specs/2026-10-24-vm-completeness-design.md`). Not needed to build screens: the screen files show only what exists now. Kept for the record of what was fixed or deferred, and why.

## Gap classes

| Class | Meaning |
|-------|---------|
| **I** | A command file imports a service, repository, config or release file (a line of the former `tool/vm_boundary_baseline.txt`, emptied and removed 2026-10-24). Every baseline line belonged to exactly one gap. |
| **T** | A type defined in `core/services/` (or `supabase`) appears in a ViewModel or model a screen gets, so a screen cannot even name it. Usual fix: `export ... show` from a `core/models/` file. |
| **R** | A repository, service or Supabase client is reachable through a public ViewModel field or parameter, so a screen could bypass the ViewModel. |
| **G** | A sign-in or role check exists only in the console command; a screen calling the ViewModel skips it. |
| **P** | A ViewModel method takes a file path; a phone's file picker gives bytes. |
| **N** | A name, label, default value or figure that only command code produces. |
| **L** | A live preview a screen needs while typing, with no synchronous call. |
| **E** | Raw exception text (`$e`) in a ViewModel message (spec list). |
| **M** | A screen need with no console capability today: proposed `deferred` (spec *Out of scope*) unless the owner decides otherwise. |

Classes R and G were not in the spec; they came up during the walk (2026-10-24) and were accepted by the owner (2026-10-24).

## Gap format

```
**<MODULE>-G<n>** (class) — what is missing.
Fix: exact new method / getter / change.
Removes baseline: `file -> target` (class I only)
Decision: (open)
Status: ✅ fixed (Task n) | ⏸ deferred
```

The owner fills `Decision:` with `fix`, `deferred: <reason>`, or a changed fix. Only `fix` gaps go into the batch plan (plan Task 3).

## Gap index

| Gap | Class | File | What | Recommended |
|-----|-------|------|------|-------------|
| COMMON-G1 | E | `common.md` | Exceptions other than `ViewModelException` (a `PostgrestException`, a socket error) reach the screen raw. … | fix (screen rule + export) |
| COMMON-G2 | N | `common.md` | Settings shown as layers (default / region / school / applies: CRLA and Phil-IRI thresholds, check-in … | fix |
| COMMON-G3 | M | `common.md` | A screen cannot ask whether a record is locked by a pending upload before the user edits it; it only … | deferred |
| AUTH-G1 | I, N | `auth.md` | `offline-status` computes the window end and reads `offlineMaxFailedAttempts` from … | fix |
| AUTH-G2 | I, R | `auth.md` | `config-*` commands use `SupabaseConfigStore` (`core/data/remote/supabase_config.dart`) directly; there is … | fix |
| AUTH-G3 | I, T, N | `auth.md` | `version-app` reads `basaMigrations` (`core/release.dart`); `version-check` formats with … | fix |
| AUTH-G4 | R, T | `auth.md` | `AuthViewModel.client` (a `SupabaseClient`) is public "so user-create etc. can reuse the session", and … | fix (doc line + tool check) |
| AUTH-G5 | E | `auth.md` | `auth_viewmodel.dart:281` puts `$e` in `offlineWarning` ("Offline sign-in was not saved on this device: $e"). | fix |
| ADMIN-G1 | I, R, G | `admin.md` | `login-recent`/`login-history` build `LoginLogRepositorySupabase(authVm.client!)` in the command, and the … | fix |
| ADMIN-G2 | I, R | `admin.md` | `bootstrap-admin` picks the cloud/LAN profile from the config store, builds a `SupabaseClient` and an … | fix |
| ADMIN-G3 | P, T | `admin.md` | SF1 import takes a file path all the way down (`.xls` files are converted on disk by … | (b): defer bytes, add export |
| ADMIN-G4 | E | `admin.md` | `user_viewmodel.dart:145` and `tutor_section_assignment_viewmodel.dart:109` put `$e` in `lastMirrorWarning`. | fix |
| CRLA-G1 | N | `crla.md` | The variants (`mt`, `fil`, `eng`) and their default language (fil → Tagalog, eng → English, mt must be … | fix |
| CRLA-G2 | I, N | `crla.md` | `crla-thresholds` reads `CrlaThresholds.defaults` from `crla_rules.dart` to show each key's default. | fix |
| CRLA-G3 | T | `crla.md` | `CrlaThresholds` (`crla_rules.dart`), `CrlaScoresheetFile`, `CrlaScoresheetRow` (`crla_scoresheet.dart`) … | fix |
| CRLA-G4 | M | `crla.md` | No preview of wpm / reading profile while Part 2 is typed (the profile comes from the results view after … | deferred |
| CRLA-G5 | E | `crla.md` | `crla_threshold_viewmodel.dart:237` puts `$e` in `lastMirrorWarning`. | fix |
| PHILIRI-G1 | I, N | `phil-iri.md` | `phil-iri-gst` decides "passed / below the cut-off" itself: it guesses the grade group from the max score … | fix |
| PHILIRI-G2 | I, T, N | `phil-iri.md` | `PhilIriPassageResult`, `PhilIriRoundResult` (`phil_iri_results.dart`), `PhilIriLevel`, … | fix |
| PHILIRI-G3 | N | `phil-iri.md` | Whether a reading is timed yet (`_timed`: one-minute needs words read, the others need seconds) and the … | fix |
| PHILIRI-G4 | I, N | `phil-iri.md` | `phil-iri-thresholds` reads `PhilIriThresholds.defaults` from `phil_iri_rules.dart`. | fix |
| PHILIRI-G5 | E | `phil-iri.md` | `phil_iri_content_viewmodel.dart:682` puts `$e` in `lastMirrorWarning`. | fix |
| ARAL-G1 | I, N | `aral.md` | "n/15 active" reads `aralClassCap` from `aral_rules.dart` in `aral_command_helpers.dart`. | fix |
| ARAL-G2 | I, N | `aral.md` | Met / Not met (`AralCheckinScore.passes(passPct)`) and the percent text are made in … | fix |
| ARAL-G3 | N | `aral.md` | The implementation report's grade subtotals (when a grade has more than one section) and the school total … | fix |
| ARAL-G4 | I, N | `aral.md` | Setting defaults: the check-in cut-off and idle days come from `AralCheckinSettings.defaults` / … | fix |
| ARAL-G5 | T | `aral.md` | Service types in results: `AralCheckinScore`, `AralCheckinScoring`, `AralCheckinSettings` … | fix |
| ARAL-G6 | N | `aral.md` | `AralViewModel.tutors` returns a positional record `(User, int, int)`; a screen has to know which int is … | fix |
| ARAL-G7 | E | `aral.md` | `aral_material_viewmodel.dart:383` puts `$e` in `lastMirrorWarning`. | fix |
| ARAL-G8 | E | `aral.md` | `AralClassViewModel._write` rethrows unknown database errors as they are (after turning known ones into … | no change (with COMMON-G1) + log line |
| ARAL-G10 | E | `aral.md` | The database's CHECK text was put in a `ViewModelException` (found in Task 7). | fix |
| ARAL-G9 | M | `aral.md` | No Flesch preview of a typed text before saving a readability entry. | deferred |
| REPORTS-G1 | I, T | `reports.md` | `NlaBand`, `NlaCounts`, `NlaGstBand` (`nla_form2b.dart`), `PhilIriLevel` (`phil_iri_rules.dart`) and … | fix |
| REPORTS-G2 | I, N | `reports.md` | `srp-build` / `srp-list` read `srpDefaultPerSection` and `srpDefaultClassSize` from `srp_rules.dart`. | fix |
| REPORTS-G3 | E | `reports.md` | `srp_viewmodel.dart:538` puts `$e` in `lastMirrorWarning`. | fix |
| DASH-G1 | I, T, N | `dashboard.md` | `calendar-show` calls `roundStatus` and `roundLabel` from `calendar_rules.dart` directly (the ViewModel … | fix |
| DASH-G2 | I | `dashboard.md` | Five console helpers check that a typed date is real with `calendarDate(d) != raw` … | fix |
| DASH-G3 | I | `dashboard.md` | `reminders-tutor me` reads `notSignedInMessage` from `auth_messages.dart`. | fix |
| DASH-G4 | E | `dashboard.md` | `round_calendar_viewmodel.dart:234` puts `$e` in `lastMirrorWarning`. | fix |

## common.md

**COMMON-G1** (E) — Exceptions other than `ViewModelException` (a `PostgrestException`, a socket error) reach the screen raw. The console prints them; a screen would show SQL or server text.
Fix: no ViewModel change. `common.md` and the handoff docs fix the rule: a screen shows `ViewModelException.message`; anything else gets one fixed sentence (`unexpectedErrorMessage` from `core/services/auth_messages.dart`, reached through the model export below) and is logged. Class T export: `core/models/messages.dart` with `export '../services/auth_messages.dart' show unexpectedErrorMessage, notSignedInMessage;`.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 4).

**COMMON-G2** (N) — Settings shown as layers (default / region / school / applies: CRLA and Phil-IRI thresholds, check-in cut-off, idle-session days, SHARP, KS1 extended) do not carry their default; the console reads it from the rule file (`CrlaThresholds.defaults`, `PhilIriThresholds.defaults`, `AralCheckinSettings.defaults`, `AralSessionSettings.defaults`) or writes it as fixed text ("Default: off"). Report settings and offline days don't show a default today.
Fix: each of those `...Layers` results gets a `defaults` field (same type as `effective`), filled by the ViewModel from the same rule constant; the commands read it from there. Covered per module: CRLA-G2, PHILIRI-G4, ARAL-G4 (this gap is the shared rule, decided once).
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 4).

**COMMON-G3** (M) — A screen cannot ask whether a record is locked by a pending upload before the user edits it; it only learns from the refusal.
Fix: deferred (no console capability; the refusal message is enough for now).
Decision: deferred: no console capability; the refusal message is enough for now (owner 2026-10-24).
Status: ⏸ deferred (see Decision).

## auth.md

**AUTH-G1** (I, N) — `offline-status` computes the window end and reads `offlineMaxFailedAttempts` from `offline_signin_rules.dart`.
Fix: `AuthViewModel.offlineStatus()` → `OfflineStatus?` (new model `core/models/offline_status.dart`: `email`, `lastOnlineAt`, `windowDays`, `until`, `failedAttempts`, `maxFailedAttempts`); null when not set up. Command prints from it.
Removes baseline: `core/console/commands/auth_commands.dart -> core/services/offline_signin_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 4).

**AUTH-G2** (I, R) — `config-*` commands use `SupabaseConfigStore` (`core/data/remote/supabase_config.dart`) directly; there is no ViewModel, and key masking is command code.
Fix: new `ServerConfigViewModel` (`lib/viewmodels/server_config_viewmodel.dart`, both builds, wired in `wire_tutor.dart` (shared)) with `show()` → `ServerConfigView` (`cloudUrl`, `cloudKeyMasked`, `lanUrl`, `lanKeyMasked`; mask rule moves here unchanged), `setCloud({url, anonKey})`, `setLan({url, anonKey})`. `registerConfigCommands` takes the ViewModel.
Removes baseline: `core/console/commands/config_commands.dart -> core/data/remote/supabase_config.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 4).

**AUTH-G3** (I, T, N) — `version-app` reads `basaMigrations` (`core/release.dart`); `version-check` formats with `versionLabel`/`versionMessage`/`fetchFailedMessage` (`version_check.dart`); `VersionCheck` is a service type.
Fix: `AuthViewModel.appRelease()` → `List<String>` (`<id>_<name>`, oldest first); `AuthViewModel.versionReport()` → `({String label, String message})` (calls `checkVersion`, the same label/message functions, and `fetchFailedMessage` on a fetch failure); `export '../services/version_check.dart' show VersionCheck, VersionVerdict;` from `core/models/version.dart`.
Removes baseline: `core/console/commands/version_commands.dart -> core/release.dart`, `core/console/commands/version_commands.dart -> core/services/version_check.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 4).

**AUTH-G4** (R, T) — `AuthViewModel.client` (a `SupabaseClient`) is public "so user-create etc. can reuse the session", and `checkVersion([SupabaseClient? client])` takes one. A screen holding the client could query the server around every ViewModel.
Found: 16 ViewModels read `_auth.client` to build their cloud repositories, so it cannot become private without a wiring redesign. And a screen does not need to import `supabase` to call methods on it, so the import check alone does not stop it.
Fix: (a) keep it public, with a doc line "ViewModels only, never a screen"; (b) `tool/vm_boundary.dart` also refuses the text `.client` (as a member access, `\.client\b`) in `lib/ui/` files, with a fixture test; (c) `checkVersion` loses its `SupabaseClient` parameter if nothing passes one (checked in the batch; else it stays, wiring-only). After ADMIN-G1 no command file uses `.client` either.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 4).

**AUTH-G5** (E) — `auth_viewmodel.dart:281` puts `$e` in `offlineWarning` ("Offline sign-in was not saved on this device: $e").
Fix: spec rule (sentence kept without the exception text, exception to the logger).
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 4).

## admin.md

**ADMIN-G1** (I, R, G) — `login-recent`/`login-history` build `LoginLogRepositorySupabase(authVm.client!)` in the command, and the sign-in + admin/coordinator checks are only in the command. `LoginLogViewModel` takes repositories (`useRepository`, `cloud:`) and checks nothing.
Fix: `LoginLogViewModel` gets the `AuthViewModel` and a cloud-repository factory in its constructor (wiring, like the other ViewModels); `loadRecent({int limit = 50})` and `loadForUser(String userId)` call `requireOnlineSession()` and refuse non-admin/coordinator with `ViewModelException('Forbidden: admin or coordinator only.')`; `record(...)` checks `requireActiveSession()` + the same role. `useRepository` and the `cloud:` parameter go away. Console output unchanged.
Removes baseline: `core/console/commands/login_commands.dart -> core/data/remote/login_log_repository_supabase.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 4).

**ADMIN-G2** (I, R) — `bootstrap-admin` picks the cloud/LAN profile from the config store, builds a `SupabaseClient` and an `AdminBootstrapService`, then a ViewModel, all in the command.
Fix: `AdminBootstrapViewModel` is built once in `wire_admin.dart` with the config store and a client factory; `bootstrap(String target, String email, String fullName)` → `String?` does the profile choice ("<target>.url not set" refusal as `ViewModelException`) and builds the client. Command only parses arguments.
Removes baseline: `core/console/commands/admin_bootstrap_commands.dart -> core/data/remote/supabase_config.dart`, `... -> core/services/admin_bootstrap_service.dart`, `... -> package:supabase/supabase.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 4).

**ADMIN-G3** (P, T) — SF1 import takes a file path all the way down (`.xls` files are converted on disk by `xls_to_xlsx_converter`); `Sf1ColumnMap`, `Sf1TrialResult`, `Sf1ImportResult` are service types.
Fix options: (a) bytes overloads `previewRowBytes(bytes, fileName, rowIndex)`, `trialBytes(bytes, fileName)`, `importBytes(bytes, fileName)` that write a temp file inside the ViewModel and call the path versions; (b) defer: SF1 import is a desktop admin task (the `.xls` converter needs a desktop tool anyway), and a desktop file picker gives a path. Plus the T export either way: `core/models/sf1.dart` with `export '../services/sf1_importer.dart' show Sf1TrialResult, Sf1ImportResult;` and `export '../services/sf1_column_map.dart' show Sf1ColumnMap;`. Recommend (b) + the export.
Decision: (b) (owner 2026-10-24): the path API stays (desktop admin task); add the type export only.
Status: ✅ export done (`core/models/sf1.dart`, Task 4); ⏸ bytes API deferred (desktop admin task).

**ADMIN-G4** (E) — `user_viewmodel.dart:145` and `tutor_section_assignment_viewmodel.dart:109` put `$e` in `lastMirrorWarning`.
Fix: spec rule (sentence kept without `($e)`, exception to the logger).
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 4).

## crla.md

**CRLA-G1** (N) — The variants (`mt`, `fil`, `eng`) and their default language (fil → Tagalog, eng → English, mt must be named) are only in `crla-start`'s argument code. A screen's form needs both, and the rule would otherwise be rebuilt in a widget.
Fix: `core/models/crla_variant.dart`: `const crlaSubjectVariants = ['mt', 'fil', 'eng'];` and `String? crlaDefaultLanguage(String variant)` (same mapping); `startAssessment`'s `language` becomes optional and the ViewModel fills the default (ViewModelException "The mt variant needs a language (e.g. Cebuano)." when missing); the command uses both. No console text changes.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 5).

**CRLA-G2** (I, N) — `crla-thresholds` reads `CrlaThresholds.defaults` from `crla_rules.dart` to show each key's default.
Fix: `CrlaThresholdLayers.defaults` (`CrlaThresholds`, = `CrlaThresholds.defaults`), per COMMON-G2.
Removes baseline: `core/console/commands/crla_threshold_commands.dart -> core/services/crla_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 5).

**CRLA-G3** (T) — `CrlaThresholds` (`crla_rules.dart`), `CrlaScoresheetFile`, `CrlaScoresheetRow` (`crla_scoresheet.dart`) are service types in ViewModel results.
Fix: `core/models/crla_types.dart` with `export '../services/crla_rules.dart' show CrlaThresholds;` and `export '../services/crla_scoresheet.dart' show CrlaScoresheetFile, CrlaScoresheetRow;`.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 5).

**CRLA-G4** (M) — No preview of wpm / reading profile while Part 2 is typed (the profile comes from the results view after saving).
Fix: deferred (no console capability; the screen shows `getResult` after saving).
Decision: deferred: no console capability; the screen shows getResult after saving (owner 2026-10-24).
Status: ⏸ deferred (see Decision).

**CRLA-G5** (E) — `crla_threshold_viewmodel.dart:237` puts `$e` in `lastMirrorWarning`.
Fix: spec rule.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 5).

## phil-iri.md

**PHILIRI-G1** (I, N) — `phil-iri-gst` decides "passed / below the cut-off" itself: it guesses the grade group from the max score (40 → 7, else 4), calls `philIriGstPassed` with the school's thresholds, and rounds with `philIriWholePercent`. `philIriGstPassed` throws a raw `ArgumentError` on bad input. A screen can't show the verdict.
Fix: `PhilIriViewModel.gstPassed(PhilIriGstResult g)` → `Future<bool>` (same grade-group rule, school thresholds, same function); `PhilIriGstResult.wholePercent` getter (`int`, same rounding). `gst-list` can stay as it is (no verdict today).
Removes baseline: `core/console/commands/phil_iri_commands.dart -> core/services/phil_iri_rules.dart` (with PHILIRI-G2, G3)
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 6).

**PHILIRI-G2** (I, T, N) — `PhilIriPassageResult`, `PhilIriRoundResult` (`phil_iri_results.dart`), `PhilIriLevel`, `PhilIriThresholds` (`phil_iri_rules.dart`) are service types in results. The console makes their percents with `philIriWholePercent` and the adjusted-level / levels-down text with `philIriAdjustedLevelLabel` / `philIriLevelsDownLabel`.
Fix: `core/models/phil_iri_types.dart` exports those four types; getters on the result classes (in their own files, calling the same functions): `PhilIriPassageResult.wordReadingPercent`, `.comprehensionPercent` (`int?`), `PhilIriRoundResult.wordReadingPercent`, `.comprehensionPercent`, `.adjustedLevelLabel` (`String?`), `.levelsDownLabel` (`String?`). The commands use them.
Removes baseline: `core/console/commands/phil_iri_commands.dart -> core/services/phil_iri_results.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 6).

**PHILIRI-G3** (N) — Whether a reading is timed yet (`_timed`: one-minute needs words read, the others need seconds) and the observation labels (`_observationText`) are command code.
Fix: `PhilIriReading.isTimed` getter; `PhilIriObservation.labels` → `List<String>` (same wording). The miscue position text ("before word 3") stays console layout.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 6).

**PHILIRI-G4** (I, N) — `phil-iri-thresholds` reads `PhilIriThresholds.defaults` from `phil_iri_rules.dart`.
Fix: `PhilIriThresholdLayers.defaults`, per COMMON-G2.
Removes baseline: `core/console/commands/phil_iri_content_commands.dart -> core/services/phil_iri_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 6).

**PHILIRI-G5** (E) — `phil_iri_content_viewmodel.dart:682` puts `$e` in `lastMirrorWarning`.
Fix: spec rule.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 6).

## aral.md

**ARAL-G1** (I, N) — "n/15 active" reads `aralClassCap` from `aral_rules.dart` in `aral_command_helpers.dart`.
Fix: `AralClassViewModel.classCap` getter (`int`, = `aralClassCap`).
Removes baseline: `core/console/commands/aral_command_helpers.dart -> core/services/aral_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 7).

**ARAL-G2** (I, N) — Met / Not met (`AralCheckinScore.passes(passPct)`) and the percent text are made in `aral_checkin_command_helpers.dart`.
Fix: `AralCheckinResult.met` (`bool`, = `score.passes(passPct)`) and `AralCheckinScore.wholePercent` (`int`, same rounding as `toStringAsFixed(0)`). The report rows get the same if they carry a score (checked in the batch).
Removes baseline: `core/console/commands/aral_checkin_command_helpers.dart -> core/services/aral_checkin_rules.dart`
Decision: fix (owner 2026-10-24, as recommended). Changed in Task 7 (owner 2026-10-24): no `met` getter, because `AralCheckinResult.passed` already exists and the per-part lines are plain `AralCheckinScore`s; a screen calls `score.passes(passPct)` (the type comes from `aral_types.dart`, ARAL-G5). Only `wholePercent` was added.
Status: ✅ fixed (VM completeness Task 7).

**ARAL-G3** (N) — The implementation report's grade subtotals (when a grade has more than one section) and the school total are summed in `aral-report`. The DepEd layout shows them, so a screen needs them too.
Fix: `AralImplementationReport.gradeTotals` → `Map<int, AralReportTotals>` and `.schoolTotal` → `AralReportTotals` (new small class in `aral_report_viewmodel.dart`: `enrolment`, `bosy`/`mosy` per column, `bosyTotal`, `mosyTotal`, `exitedGradeLevelReady`, `exitedOther`, `exited`, `bosyMinusMosy`), same sums as the command; the command prints from them.
Decision: fix (owner 2026-10-24, as recommended). Task 7 (owner 2026-10-24): `bosyTotal` / `mosyTotal` are stored fields, because the school total has no columns (Phil-IRI and CRLA columns differ) but still has totals.
Status: ✅ fixed (VM completeness Task 7).

**ARAL-G4** (I, N) — Setting defaults: the check-in cut-off and idle days come from `AralCheckinSettings.defaults` / `AralSessionSettings.defaults`; SHARP and KS1-extended defaults ("off") are fixed text in the command.
Fix: per COMMON-G2: `AralCheckinSettingLayers.defaults`; the three record results gain a `defaults` field (`bool` / `int`), from the same constants.
Removes baseline: `core/console/commands/aral_checkin_commands.dart -> core/services/aral_checkin_rules.dart`, `core/console/commands/aral_checkin_commands.dart -> core/services/aral_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 7).

**ARAL-G5** (T) — Service types in results: `AralCheckinScore`, `AralCheckinScoring`, `AralCheckinSettings` (`aral_checkin_rules.dart`); `AralPlacement`, `AralProgramSettings`, `AralRankKey`, `AralSessionSettings` (`aral_rules.dart`); `AralReadability` (`aral_readability.dart`).
Fix: `core/models/aral_types.dart` exports them.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 7).

**ARAL-G6** (N) — `AralViewModel.tutors` returns a positional record `(User, int, int)`; a screen has to know which int is which.
Fix: named record `({User tutor, int classes, int activeLearners})`; its one caller (`aral-tutors`) updated.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 7).

**ARAL-G7** (E) — `aral_material_viewmodel.dart:383` puts `$e` in `lastMirrorWarning`.
Fix: spec rule.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 7).

**ARAL-G8** (E) — `AralClassViewModel._write` rethrows unknown database errors as they are (after turning known ones into `ViewModelException`).
Found: rethrowing the original exception is what every other ViewModel does; with COMMON-G1 a screen shows one fixed sentence for any non-`ViewModelException`, so the raw text never reaches the user.
Fix: no code change if COMMON-G1 is accepted (log the error before rethrowing, one line); otherwise wrap it in `ViewModelException(unexpectedErrorMessage)`.
Decision: no code change beyond logging the error before the rethrow, since COMMON-G1 is accepted (owner 2026-10-24).
Status: ✅ fixed (VM completeness Task 7).

**ARAL-G10** (E, found in Task 7) — `aral_material_viewmodel.dart` put the database's CHECK text in a `ViewModelException` (`'The database refused the values (${e.message}).'`).
Fix: `'The database refused the values.'`; the text goes to the log.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 7).

**ARAL-G9** (M) — No Flesch preview of a typed text before saving a readability entry.
Fix: deferred (no console capability; the entry shows its scores after saving).
Decision: deferred: no console capability; the entry shows its scores after saving (owner 2026-10-24).
Status: ⏸ deferred (see Decision).

## reports.md

**REPORTS-G1** (I, T) — `NlaBand`, `NlaCounts`, `NlaGstBand` (`nla_form2b.dart`), `PhilIriLevel` (`phil_iri_rules.dart`) and `SrpRankKey` (`srp_rules.dart`) are service types in report results; `nla_report_commands.dart` imports both rule files for them.
Fix: `core/models/report_types.dart` exports `NlaBand, NlaCounts, NlaGstBand` and `SrpRankKey`; `PhilIriLevel` comes from `phil_iri_types.dart` (PHILIRI-G2).
Removes baseline: `core/console/commands/nla_report_commands.dart -> core/services/nla_form2b.dart`, `core/console/commands/nla_report_commands.dart -> core/services/phil_iri_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

**REPORTS-G2** (I, N) — `srp-build` / `srp-list` read `srpDefaultPerSection` and `srpDefaultClassSize` from `srp_rules.dart`.
Fix: `SrpViewModel.defaultPerSection` and `.defaultClassSize` getters (same constants).
Removes baseline: `core/console/commands/srp_admin_commands.dart -> core/services/srp_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

**REPORTS-G3** (E) — `srp_viewmodel.dart:538` puts `$e` in `lastMirrorWarning`.
Fix: spec rule.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

## dashboard.md

**DASH-G1** (I, T, N) — `calendar-show` calls `roundStatus` and `roundLabel` from `calendar_rules.dart` directly (the ViewModel already has `status`); `RoundStatus` is a service type.
Fix: commands call `RoundCalendarViewModel.status`; `CalendarWindow.roundLabel` getter (model, same function); `core/models/calendar_types.dart` exports `RoundStatus`.
Removes baseline: `core/console/commands/calendar_commands.dart -> core/services/calendar_rules.dart`, `core/console/commands/calendar_admin_commands.dart -> core/services/calendar_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

**DASH-G2** (I) — Five console helpers check that a typed date is real with `calendarDate(d) != raw` (`calendar_rules.dart`): `calendar_command_helpers`, `dashboard_commands`, `reminder_command_helpers`, `trend_command_helpers`, and `calendar_commands` for the header date. Console-only parsing; screens use a date picker.
Fix: use the console's own `strictDateArg` (`core/console/date_args.dart`, same rollover check) with each command's existing message text, and a local YYYY-MM-DD formatter for the header line (`date_args.dart`). Console output unchanged.
Removes baseline: `core/console/commands/calendar_command_helpers.dart -> core/services/calendar_rules.dart`, `core/console/commands/dashboard_commands.dart -> core/services/calendar_rules.dart`, `core/console/commands/reminder_command_helpers.dart -> core/services/calendar_rules.dart`, `core/console/commands/trend_command_helpers.dart -> core/services/calendar_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

**DASH-G3** (I) — `reminders-tutor me` reads `notSignedInMessage` from `auth_messages.dart`.
Fix: import it from `core/models/messages.dart` (COMMON-G1's export).
Removes baseline: `core/console/commands/reminder_commands.dart -> core/services/auth_messages.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

**DASH-G4** (E) — `round_calendar_viewmodel.dart:234` puts `$e` in `lastMirrorWarning`.
Fix: spec rule.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

## sync.md

None found. (`lockedCounts()` gives per-upload counts, not per record; the per-record question is COMMON-G3.)
