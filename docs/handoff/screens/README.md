# Screen inventory

What each screen of BASA can do, and which ViewModel calls serve it. Written 2026-10-24 for the ViewModel completeness check (spec `docs/superpowers/specs/2026-10-24-vm-completeness-design.md`); the frontend handoff docs grow from it. Layout, visuals and navigation are the UI team's and are not in here.

Status: **gaps decided by the owner 2026-10-24 (all as recommended).**

## Files

| File | Covers |
|------|--------|
| `common.md` | what every screen needs: who is signed in, pickers, online/offline, errors |
| `auth.md` | sign-in (online/offline), password change, server settings, version check |
| `admin.md` | users, schools, sections, learners, tutor assignments, SF1 import, login logs, first admin |
| `crla.md` | CRLA assessment, results, stories, thresholds, scoresheet import/export |
| `phil-iri.md` | GST, Phil-IRI sessions, readings, miscues, answers, rubric, results, content, thresholds |
| `aral.md` | ARAL roster, classes, sessions/attendance, IRIP, check-ins, materials, readability, reports, settings |
| `reports.md` | NLA report, progress monitoring, BOSY masterlist, SRP, report settings |
| `dashboard.md` | dashboard summary, round calendar, reminders, trends |
| `sync.md` | pull, upload, status, conflicts, approver review |

## Screen block

```
### <Screen name>
Build: tutor | admin | both    Roles: tutor / coordinator / admin / superadmin
Purpose: one line.
Calls:
- ✅ `Vm.method(args)` → `ReturnType` — what for
- 🆕 `Vm.newMethod(args)` → `Type` — gap <ID>
Live previews: synchronous calls used while typing (or "none").
Errors: refusals the ViewModel raises (`ViewModelException.message`, shown as is).
Console: the command(s) that show the real output.
```

✅ = exists today. 🆕 = does not exist; the gap with that id proposes it.

## Gap classes

| Class | Meaning |
|-------|---------|
| **I** | A command file imports a service, repository, config or release file (a line of `tool/vm_boundary_baseline.txt`). Every baseline line belongs to exactly one gap. |
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
| ARAL-G9 | M | `aral.md` | No Flesch preview of a typed text before saving a readability entry. | deferred |
| REPORTS-G1 | I, T | `reports.md` | `NlaBand`, `NlaCounts`, `NlaGstBand` (`nla_form2b.dart`), `PhilIriLevel` (`phil_iri_rules.dart`) and … | fix |
| REPORTS-G2 | I, N | `reports.md` | `srp-build` / `srp-list` read `srpDefaultPerSection` and `srpDefaultClassSize` from `srp_rules.dart`. | fix |
| REPORTS-G3 | E | `reports.md` | `srp_viewmodel.dart:538` puts `$e` in `lastMirrorWarning`. | fix |
| DASH-G1 | I, T, N | `dashboard.md` | `calendar-show` calls `roundStatus` and `roundLabel` from `calendar_rules.dart` directly (the ViewModel … | fix |
| DASH-G2 | I | `dashboard.md` | Five console helpers check that a typed date is real with `calendarDate(d) != raw` … | fix |
| DASH-G3 | I | `dashboard.md` | `reminders-tutor me` reads `notSignedInMessage` from `auth_messages.dart`. | fix |
| DASH-G4 | E | `dashboard.md` | `round_calendar_viewmodel.dart:234` puts `$e` in `lastMirrorWarning`. | fix |
