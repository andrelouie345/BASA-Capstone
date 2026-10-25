# Frontend Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hand the backend to the UI groupmates: ViewModel messages readable in the app, clean screen docs + a checklist, a start-here guide, and a debug-only example screen with `lib/ui/CLAUDE.md`.

**Architecture:** Task 1 changes message strings only (no behaviour). Tasks 2-3 are docs. Task 4 adds one Flutter screen under `lib/ui/example/`, reachable only from the debug console (compiled out of release builds through `basaHasConsole`), plus a `[debug]` marker proving that.

**Tech Stack:** Dart/Flutter, `flutter test` (pure-Dart tests), command pass (`tool/command_pass/run.dart`), marker scan (`tool/scan_markers.dart` via `tool/build_release.ps1`).

**Spec:** `docs/superpowers/specs/2026-10-25-frontend-handoff-design.md`

## Global Constraints

- Wording rule (Q5): a plain sentence with the command name in brackets, e.g. `Download the latest data first (pull-cloud).`; one wording per kind of message.
- Ids stay in refusals (console lines name learners by id on purpose).
- The example screen is reachable **only in debug builds** (debug overlay, `basaHasConsole`), never in a release build; docs and `lib/ui/CLAUDE.md` say "debug build only".
- Screens reach ViewModels only through `BasaScope.of(context)` / `AdminScope.of(context)`; `lib/ui/**` imports only `lib/viewmodels/`, `lib/core/models/`, Dart SDK, Flutter (`dart run tool/check_vm_boundary.dart`).
- Docs say nothing about the groupmates' skill level. PR target is `excelsior`, never `main`.
- After every task: `dart analyze` (no errors), `flutter test`, `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart`. Owner: before any console / command-pass run, ask the owner to close any open BASA console.
- Git: the owner commits. Each task ends with what to verify + a commit message; no git commands are run.

## Review Focus

1. A console-worded message added later slips back in → Task 1's guard test fails on any `run <command>` / `Run <command>` in a ViewModel string.
2. A command-pass `expect`/`refuse` line matches the old text by prefix → Task 1 keeps every old prefix up to "on this device" / "in the catalog on this device" and reruns the batches that print them.
3. A screen block still points at a gap id or a ⏸/🆕 marker after cleanup → Task 2's grep check returns nothing.
4. Checklist and screen blocks drift (a row with no block or a block with no row) → Task 2's count check (56 = 56).
5. The example screen leaks into a shipped build → Task 4's `[debug]` marker, checked by the marker scan on shipped builds.

---

### Task 1: ViewModel messages for both readers

**Files:**
- Create: `test/viewmodels/console_wording_test.dart`
- Modify: `lib/viewmodels/aral_checkin_viewmodel.dart:219,340,692`, `aral_material_viewmodel.dart:107,265,282,386`, `crla_threshold_viewmodel.dart:240`, `phil_iri_content_viewmodel.dart:685`, `phil_iri_viewmodel.dart:928`, `report_settings_viewmodel.dart:204-205`, `round_calendar_viewmodel.dart:236`, `srp_viewmodel.dart:370,505,543`, `sync_review_viewmodel.dart:71`, `sync_viewmodel.dart:204,262,352`, `tutor_section_assignment_viewmodel.dart:109`, `user_viewmodel.dart:145` (21 lines, 12 files; re-grep first)
- Modify (expectations): `test/viewmodels/mirror_warning_test.dart:123,134,153,168`, `test/viewmodels/aral_material_warning_test.dart:84`, `test/viewmodels/report_calendar_screen_calls_test.dart:118,135`, `tool/command_pass/scenarios/35_a5.pass:385`

**Interfaces:** none (strings only); no later task depends on the new wordings.

**New wordings (exact):**

| Kind | Old tail | New |
|------|----------|-----|
| Mirror warning (9 files) | `…, but the local copy was not updated. Run pull-cloud.` / `Saved online, but not copied onto this device; run pull-cloud.` | `<same subject> …, but the copy on this device was not updated. Download the latest data (pull-cloud).` — user/tutor-assignment: `Saved online, but the copy on this device was not updated. Download the latest data (pull-cloud).` |
| Not on this device | `… on this device; run pull-cloud.` / `… on this device (run pull-cloud).` / `… (run pull-cloud to get the latest passages).` | `<same start> on this device. Download the latest data (pull-cloud).` e.g. `Check-in tool 4 is not on this device. Download the latest data (pull-cloud).`, `No passage with id 9 on this device. Download the latest data (pull-cloud).`, `No user x@y on this device. Download the latest data (pull-cloud).` |
| Empty catalog note | `… in the catalog on this device (add some, or run pull-cloud).` | `… in the catalog on this device. Add some, or download the latest data (pull-cloud).` |
| SHARP off | `… for this school: run aral-update to move the learner to KS1.` | `… for this school: move the learner to KS1 (aral-update).` |
| Upload applied | `Upload N applied. Run pull-cloud to see it on this device.` | `Upload N applied. Download the latest data to see it on this device (pull-cloud).` |
| Withdraw failed reason | `…(${_plain(e)}); run sync-status again` | `…(${_plain(e)}); check the upload status again (sync-status)` |
| Upload state unknown (2) | `…stay locked; run sync-status when online.` | `…stay locked; check the upload status when online (sync-status).` |

Every new text keeps the old text's start up to and including "on this device" (command-pass prefix matches in `25_t5.pass:43,45`, `34b_a4b.pass:247,256,258,260` stay valid).

- [ ] **Step 1: Write the failing guard test** `test/viewmodels/console_wording_test.dart`

Test `no ViewModel message tells the reader to run a console command`: for every `.dart` file under `lib/viewmodels/` and `lib/core/viewmodels/`, skip lines whose trimmed text starts with `//`, collect matches of `RegExp(r"\b[Rr]un [a-z]+(-[a-z]+)+")`, and `expect(hits, isEmpty, reason: hits.join('\n'))` where each hit is `file:line: text`.

- [ ] **Step 2: Update the 7 test expectations and `35_a5.pass:385`** to the new wordings (scenario: `refuse No user nobody@basa.test on this device. Download the latest data (pull-cloud).`).

- [ ] **Step 3: Run tests, verify they fail**

Run: `flutter test test/viewmodels/console_wording_test.dart test/viewmodels/mirror_warning_test.dart test/viewmodels/aral_material_warning_test.dart test/viewmodels/report_calendar_screen_calls_test.dart`
Expected: FAIL — guard lists 21 hits; the 7 expectations mismatch.

- [ ] **Step 4: Rewrite the 21 messages** per the table. Comments next to them stay.

- [ ] **Step 5: Run the checks**

Run: `flutter test` → all pass; `dart analyze` → no errors; `dart run tool/check_tutor_imports.dart` and `dart run tool/check_vm_boundary.dart` → OK.

- [ ] **Step 6: Command pass (owner closes any open console first)**

Run: `dart run tool/command_pass/run.dart b0 t3 t4 t5 t6 a4 a4b a5 a6`, then `dart run tool/command_pass/run.dart --run r<N> z` with the new run id.
Expected: report `verify\pass\r<N>\report.md` shows 0 failures. A failure that only reports a variable set by a skipped batch → add that batch to a new run, don't edit the scenario.

- [ ] **Step 7: Stop — verify list + commit message to owner**

Owner verifies: guard test, a mirror warning in the console (e.g. any `lastMirrorWarning` test), run report. Commit message:
```
refactor(viewmodels): messages read in the app, command name in brackets

- 21 messages in 12 ViewModels no longer say "run pull-cloud" / "run sync-status" / "run aral-update"
- one wording per kind (mirror warnings, "not on this device", upload status)
- guard test: no ViewModel string tells the reader to run a console command
- tests and the a5 scenario updated; command pass r<N> clean
```

---

### Task 2: Screen docs for groupmates + checklist

**Files:**
- Create: `docs/handoff/screens/gap-history.md`, `docs/handoff/checklist.md`
- Modify: `docs/handoff/screens/README.md`, `common.md`, `auth.md`, `admin.md`, `crla.md`, `phil-iri.md`, `aral.md`, `reports.md`, `dashboard.md`, `sync.md`

**Interfaces:**
- Produces: `docs/handoff/checklist.md` and the clean `screens/` files that Task 3's guide links to; screen block headings stay `### <Screen name>`.

- [ ] **Step 1: Archive.** `gap-history.md` = a short header ("History of the ViewModel completeness check, 2026-10-24; not needed to build screens") + the README's *Gap classes*, *Gap format*, *Gap index* sections + each file's `## Gaps` section under `## <file>.md`, all verbatim. Remove those sections from the source files.

- [ ] **Step 2: Clean blocks.** In every screen block: drop the ✅ marks; drop inline gap references (`— gap AUTH-G3`, `(type T: gap AUTH-G3)`); a ⏸ deferred call becomes `Not available yet: <what>` (COMMON-G3, CRLA-G4, ARAL-G9, ADMIN-G3 bytes API). `common.md` *Error display*: replace "→ gap COMMON-G1" with the rule as built: anything other than `ViewModelException` → show `unexpectedErrorMessage` (from `core/models/messages.dart`) and log the detail. `## Not a screen` sections stay.

- [ ] **Step 3: README** = what the folder is (one paragraph, no history), the file table, the block format without ✅/🆕/⏸ lines, a link to `gap-history.md` as "history".

- [ ] **Step 4: New blocks.**
  - `reports.md`: `### Reports & files (hub)` — Build: admin; Roles: coordinator / admin / superadmin; Purpose: every import and export in one place (ma's request). Calls: the existing calls of *Learners and roster CSV*, *SF1 import* (admin.md), *Scoresheet export*, *Scoresheet import* (crla.md), *Implementation report and roster files* (aral.md), and every export call in reports.md, each line ending `(also in <block>)` for imports. No new calls.
  - `admin.md`: `### Learner history (pending backend)` — Build: both (planned); Purpose: one learner's timeline built from existing records (assessments, ARAL enrollment/classes, sessions, check-ins); Calls: `Not available yet: built after the handoff.`

- [ ] **Step 5: Checklist** `docs/handoff/checklist.md`: one-line intro (fill `Assigned` with a name, `Status` with `not started` / `in progress` / `PR open` / `merged`), then a table `| # | Screen | Kind | Build | Doc | Assigned | Status |` with one row per `### ` heading in the module files (Kind = `screen`, or `menu item` for *Sign out* and *About / version*) and per `### ` heading in `common.md` (Kind = `shared part`). Doc = relative link `screens/<file>.md#<anchor>`. Import rows in modules get `also in the hub` in Screen.

- [ ] **Step 6: Checks**

Run: `grep -nE "G[0-9]+|🆕|⏸|baseline|✅" docs/handoff/screens/*.md | grep -v gap-history.md` → no output.
Run: `cat docs/handoff/screens/{common,auth,admin,crla,phil-iri,aral,reports,dashboard,sync}.md | grep -c "^### "` → `56`; `grep -cE "^\| [0-9]+ \|" docs/handoff/checklist.md` → `56` (49 screens + 2 menu items + 5 shared parts).

- [ ] **Step 7: Stop — verify list + commit message**
```
docs(handoff): screen docs for groupmates, gap history archived, checklist

- gap lists, index and statuses moved to screens/gap-history.md (history only)
- screen files hold only screen blocks; deferred calls read "Not available yet"
- new blocks: Reports & files hub (admin), Learner history (pending backend)
- checklist.md: 49 screens + 2 menu items + 5 shared parts, Assigned/Status blank
```

---

### Task 3: Start-here guide + CLAUDE.md wording

**Files:**
- Create: `docs/handoff/README.md`
- Modify: `CLAUDE.md:3` (and any match in `CLAUDE.local.md` and memory files)

**Interfaces:**
- Consumes: `docs/handoff/checklist.md`, `docs/handoff/screens/` (Task 2).
- Produces: the guide links `lib/ui/example/example_screen.dart` and `lib/ui/CLAUDE.md` (written in Task 4; link them now with "(added with the example screen)").

- [ ] **Step 1: Write `docs/handoff/README.md`** with the sections, in order: *What BASA is* (≤5 lines: tutors' reading assessments, CRLA G1-3, Phil-IRI G4-10, ARAL-Reading; offline-first); *Two apps* (admin build `lib/main.dart` for admins/coordinators, tutor build `lib/main_tutor.dart`; tutor build never imports admin files); *How a screen talks to the backend* (BasaScope / AdminScope → ViewModel method → model; request/response, screen owns loading/error state; error rule from `common.md`; forbidden imports); *Offline in user terms* (sign in online → download → work offline → upload → approver decides); *See the real output* (debug console: `dart run lib/console/main.dart` / `main_tutor.dart`, or the in-app console in debug builds; the `Console:` line of each block); *Checks before every PR* (the 4 commands); *Opening a PR* (make your branch from `excelsior`; push it; on GitHub open a pull request into `excelsior`, not `main`; run the checks first; the backend owner reviews); *Next* (checklist, screens, example screen, `lib/ui/CLAUDE.md`). Reader: knows some Flutter, MVVM new. No git command walkthrough beyond those five plain lines.

- [ ] **Step 2: Wording.** `CLAUDE.md:3`: "**this repo's owner works on the backend only**" → "**the backend owner (not the GitHub repo owner) works on the backend only**". Run `grep -rn "repo's owner\|repo owner" CLAUDE.md CLAUDE.local.md lib/core/CLAUDE.md "C:/Users/Ethan Campomanes/.claude/projects/d--0-CAPSTONE-Code-BASA-Capstone/memory/"`; show each other hit to the owner before changing it.

- [ ] **Step 3: Check** every relative link in `docs/handoff/README.md` resolves (Task 4 paths excepted, marked as such).

- [ ] **Step 4: Stop — verify list + commit message**
```
docs(handoff): start-here guide for the UI team

- docs/handoff/README.md: builds, screens -> ViewModels, offline flow, console as reference, checks, PR into excelsior
- CLAUDE.md: "backend owner (not the GitHub repo owner)"
```

---

### Task 4: Conventions + debug-only example screen + `lib/ui/CLAUDE.md`

**Files:**
- Create: `lib/ui/example/example_screen.dart`, `lib/ui/CLAUDE.md`
- Modify: `lib/ui/debug/debug_overlay.dart` (header row near line 133), `tool/admin_markers.txt` (`[debug]` section), `docs/handoff/README.md` (drop "(added with the example screen)"), root `CLAUDE.md` *Layout* (`ui/example/`)

**Interfaces:**
- Consumes: `BasaScope.of(context)` → `AppViewModels` (`lib/ui/basa_scope.dart`); `unexpectedErrorMessage` (`lib/core/models/messages.dart`); `ViewModelException`.
- Produces: `class ExampleScreen extends StatefulWidget` (`const ExampleScreen({super.key})`); marker string `Example screen (replace me)`.

- [ ] **Step 1: Owner decision — conventions.** Present, and wait for the answer:
  - Fixed (backend depends on them): ViewModels only through the scopes; no console command strings in screens; error rule (`ViewModelException.message` as is, else `unexpectedErrorMessage` + log); admin screens only under `lib/ui/admin/`; tutor build admin-free; debug-only code behind `basaHasConsole`; the 4 checks before a PR.
  - Groupmates' own: layout, widgets, theming, navigation and routing, state handling inside a screen, folders under `lib/ui/mobile/` and `lib/ui/windows/`.
  - Ask which items move between the two lists.

- [ ] **Step 2: Owner decision — which screen.** (a) Dashboard home — recommended: both builds, a year picker (`dashboard.schoolYears()`), a result (`dashboard.summary(year)`), a real refusal when not signed in; (b) About / version (`auth.versionReport()`): smallest, needs online sign-in; (c) Section CRLA list: needs a section picker first. The steps below assume (a); for (b)/(c) swap the calls only.

- [ ] **Step 3: Write `lib/ui/example/example_screen.dart`.** Top comment: "Example, replace me. Debug build only: opened from the debug console; never in a release build." `ExampleScreen` loads `schoolYears()` in `initState`, shows a dropdown of years, calls `summary(year)` on change; states: loading (progress indicator), error (`ViewModelException` → `e.message`; anything else → `unexpectedErrorMessage`, detail via `debugPrint`), empty (no years: "No school years on this device yet."), result (a few `DashboardSummary` fields as list tiles). AppBar title: `Example screen (replace me)`. Imports: Flutter, `../basa_scope.dart`, `lib/viewmodels/` and `lib/core/models/` files only.

- [ ] **Step 4: Debug overlay entry.** In the console header row of `debug_overlay.dart`, an `IconButton` (tooltip `Example screen (debug build only)`) that does `Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExampleScreen()))`. No other file references `ExampleScreen`.

- [ ] **Step 5: Marker.** Add `Example screen (replace me)` to the `[debug]` section of `tool/admin_markers.txt`.

- [ ] **Step 6: Write `lib/ui/CLAUDE.md`** for the groupmates' Claude Code: the fixed conventions from Step 1 (as the owner decided them), the example's path + "debug build only, replace me", the import rule, where screen needs are documented (`docs/handoff/screens/`, `checklist.md`), the 4 checks, PR into `excelsior`. Update the guide link and root `CLAUDE.md` *Layout*.

- [ ] **Step 7: Checks**

Run: `dart analyze` → no errors; `flutter test` → pass; `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart` → OK.
Run (owner, debug): `flutter run --flavor admin -t lib/main.dart` → console header shows the new button; it opens *Example screen (replace me)*; signed out it shows the not-signed-in refusal; after `sign-in` + `pull-cloud` in the console it shows years and a summary. Same with `--flavor tutor -t lib/main_tutor.dart`.
Run (owner): `powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -CloudUrl <url> -CloudKey <key>` → marker scan passes (the new `[debug]` marker in neither shipped build).

- [ ] **Step 8: Stop — verify list + commit message**
```
feat(ui): debug-only example screen and lib/ui/CLAUDE.md for the UI team

- lib/ui/example/example_screen.dart: Dashboard home through BasaScope, loading/error/empty/result states, refusal shown as is ("example, replace me")
- opened only from the debug console (basaHasConsole); [debug] marker proves it is absent from shipped builds
- lib/ui/CLAUDE.md: fixed conventions (owner decision), import rule, checks, PR into excelsior

Known follow-ups not included here:
- learner history ViewModel (after the handoff)
```
