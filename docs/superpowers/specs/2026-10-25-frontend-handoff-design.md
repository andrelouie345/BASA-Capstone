# Frontend handoff — design

Status: design approved in brainstorming 2026-10-25 (owner). Plan: to be written (`docs/superpowers/plans/2026-10-25-frontend-handoff.md`).

## Goal

Hand the backend to the groupmates who build the screens, so that they (and their Claude Code) can build every screen through ViewModels alone, without asking the backend owner what a call does, and without console wording leaking into the app. Base: the screen inventory `docs/handoff/screens/` (VM completeness check, 2026-10-24).

## Decisions (owner, 2026-10-25)

| # | Decision |
|---|----------|
| Q1 | The backend owner is not the GitHub repo owner. UI work goes on a branch made from `excelsior`; it merges back into `excelsior` by pull requests that the backend owner reviews; `excelsior` then goes to `main` together. Groupmates may not know GitHub well, so the start-here guide has a short plain PR reminder at the point it is needed (a groupmate doc, not a git walkthrough for the owner). |
| Q2 | Write for "knows some Flutter, MVVM is new", with one worked example. (Nothing in the docs says anything about the groupmates' skill level.) |
| Q3 | The worked example is a real, runnable screen in `lib/ui/` marked "example, replace me": the base for groupmates and for their Claude Code. This is the owner's explicit exception to backend-only. |
| Q4 | The example screen is reachable **only in debug builds** (an entry in the debug overlay, under the `basaHasConsole` rule, never in a release build). The docs and `lib/ui/CLAUDE.md` say "debug build only". |
| Q5 | ViewModel messages written for the console ("run pull-cloud") are rewritten for both readers: a plain sentence with the command name in brackets, e.g. `Download the latest data first (pull-cloud).` |
| Reading path | C: the gap history (gap lists, decisions, statuses) moves to its own archive file; the screen files are cleaned for groupmates. |
| Checklist | `docs/handoff/checklist.md`, one row per screen, built in piece 2. |
| Hub | B: the admin build gets a "Reports & files" hub with every import and export (ma wants them in one place, required); imports are ALSO linked in their modules (SF1 from sections/learners, CRLA scoresheet import from CRLA). |
| Learner history | A: a read-only timeline ViewModel built from existing records, no new tables. Built AFTER the handoff; the checklist has a row "Learner history (pending backend)". |
| Screen list | Final: 47 screens + the hub + Learner history = 49 screens, + 2 menu items (Sign out, About/version: tagged "menu item", calls kept), + 5 shared parts. No splits (groupmates decide how to divide big screens). Home, navigation and role routing are not rows (groupmates' area). |
| Conventions | "Fix conventions before UI code" (which rules are backend-facing and fixed, which are the groupmates' own UI choices) is HELD to the end: decided at the start of piece 4, together with the example screen. |

## Pieces (in this order; stop after each: what to verify + commit message)

### 1. ViewModel messages for both readers

Every ViewModel message that tells the reader to run a console command is rewritten per Q5. Found by grep 2026-10-25 (the plan re-greps and lists every line):

- `lastMirrorWarning` texts ending "Run pull-cloud." / "run pull-cloud.": `aral_checkin_viewmodel`, `aral_material_viewmodel`, `crla_threshold_viewmodel`, `phil_iri_content_viewmodel`, `report_settings_viewmodel`, `round_calendar_viewmodel`, `srp_viewmodel`, `tutor_section_assignment_viewmodel`, `user_viewmodel`;
- "not on this device (run pull-cloud)" refusals: `aral_checkin_viewmodel` (2), `aral_material_viewmodel` (2), `phil_iri_viewmodel`, `srp_viewmodel` (2);
- "run aral-update" in `aral_material_viewmodel` (SHARP off);
- `sync_review_viewmodel` ("Run pull-cloud to see it on this device"), `sync_viewmodel` (3× "run sync-status").

Rules:
- the sentence says what to do in app terms ("Download the latest data", "Check the upload status when online"), then the command in brackets;
- one wording per kind of message (all mirror warnings alike, all "not on this device" alike), so a screen can show them as is;
- ids stay in refusals for now (console lines name learners by id on purpose; screens get names from the ViewModels).

Exact-text matches to update in the same piece: `tool/command_pass/scenarios/35_a5.pass:385` and the unit tests `test/viewmodels/mirror_warning_test.dart`, `aral_material_warning_test.dart`, `report_calendar_screen_calls_test.dart` (the plan re-greps).

Testing: `flutter test`, `dart analyze`, both import checks, command-pass batch `a5` (plus any batch whose output the re-grep shows) on a new run.

### 2. Screen docs for groupmates + checklist

- **Archive:** gap lists, the gap index, gap classes, decisions and ✅/⏸ statuses move to `docs/handoff/screens/gap-history.md` (history only, linked from the README).
- **Clean screen files:** each `screens/*.md` keeps only screen blocks (name, build, roles, purpose, calls, live previews, errors, console). A deferred call becomes a plain "Not available yet: …" line. The README becomes a short index + how to read a block.
- **New blocks:** the admin "Reports & files" hub (every import and export call, existing calls only) and "Learner history (pending backend)" (no calls yet, purpose only).
- **Checklist** `docs/handoff/checklist.md`: one row per screen of the final list (49 screens, 2 menu items, 5 shared parts): screen, build, file + block link, `Assigned` (blank), `Status` (blank). Rows for imports in modules note "also in the hub".

No code changes. Check: every screen block has exactly one checklist row and vice versa (counted in the plan).

### 3. Start-here guide

`docs/handoff/README.md`, for groupmates and their Claude Code:
- what BASA is in five lines; the two builds (admin / tutor) and which roles use which;
- MVVM in BASA: a screen gets ViewModels from `BasaScope` / `AdminScope`, calls methods, shows the returned models; never imports services, data, wiring (the boundary check refuses it); errors = `ViewModelException.message` shown as is (plus the COMMON-G1 rule for other exceptions);
- offline-first in user terms: sign in online, download (pull), work offline, upload, approver;
- the console as the reference: run the command named in a block to see real output;
- checks before every PR: `dart analyze`, `flutter test`, `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart`;
- **PR reminder** (plain, short): make your branch from `excelsior`, push it, open a PR into `excelsior` (not `main`), run the checks first, the backend owner reviews;
- where to go next: `checklist.md`, `screens/`, the example screen (piece 4).

Also in this piece: root `CLAUDE.md` wording "this repo's owner works on the backend only" → "the backend owner (not the GitHub repo owner) works on the backend only"; same check in `CLAUDE.local.md` and memory.

### 4. Conventions + example screen + `lib/ui/CLAUDE.md` (last)

Starts with the held conventions decision, presented to the owner before any code: which rules are fixed because the backend depends on them (ViewModels only through the scopes, no console strings, error display rule, admin code only in admin files, tutor build stays admin-free, `basaHasConsole` for debug-only code) and which are the groupmates' own (layout, widgets, state management inside screens, navigation, folder structure under `mobile/`/`windows/`).

Then:
- **example screen** in `lib/ui/` marked "example, replace me", reachable only from the debug overlay in debug builds (`basaHasConsole`; a `[debug]` marker so the marker scan proves it is absent from release builds). Content: one small real screen (which one: proposed in the plan, owner picks), showing scope lookup, a ViewModel call, loading/error/result states, and a refusal shown as is;
- **`lib/ui/CLAUDE.md`**: the fixed conventions, the example's path and "debug build only", the boundary rule, the checks; written for the groupmates' Claude Code;
- checks: `dart analyze`, `flutter test`, both import checks, a debug run that opens the example, and the marker scan (`build_release.ps1`) or at least the admin/tutor marker self-test.

## Done when

- no ViewModel message tells the reader to "run" a console command without app wording; tests and the command-pass batches pass;
- screen files hold only screen blocks; gap history archived; checklist rows = screen blocks;
- the start-here guide exists with the PR reminder; root `CLAUDE.md` wording fixed;
- conventions decided by the owner; the example screen runs in a debug build and is absent from release builds; `lib/ui/CLAUDE.md` written.

## Out of scope

- Learner history ViewModel (after the handoff, option A).
- Deferred gaps COMMON-G3, CRLA-G4, ARAL-G9, ADMIN-G3 bytes API.
- Screen layout and real UI code beyond the one example screen.
- Replacing ids with names in console/refusal text.
