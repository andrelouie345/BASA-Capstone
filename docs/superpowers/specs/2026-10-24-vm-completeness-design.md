# ViewModel completeness check — design

Status: approved in brainstorm 2026-10-24, spec awaiting owner review.

## Goal

Before the frontend handoff, make sure a screen can do everything the console can, through ViewModels and models alone. The groupmates' screens (and their Claude) must never need a rule file, a repository, the config store or console command code. "Complete" = both:

- **Strict import rule** (mechanical, enforced by a tool): command files and `lib/ui/` import only ViewModels, models and their framework.
- **Screen walk** (per module): a written inventory of the screens each build needs, checked against the ViewModels; every gap is fixed or explicitly deferred by the owner.

## Decisions (owner, 2026-10-24)

| # | Decision |
|---|----------|
| Q1 | Bar = C: strict import rule + per-module screen walk. |
| Q2 | Raw error text (`$e` in warnings, raw rethrow) is fixed in this piece. Console wording ("run pull-cloud") stays for the handoff (F3), settled with the groupmates. |
| Q3 | The screen list is written by Claude from commands, specs and DepEd forms (no groupmate designs exist yet); owner reviews it. |
| Q4 | Screens and command files may NOT import `core/services/` (not even pure helpers). A rule a screen needs is reached through a ViewModel method or a model getter that calls the same rule function. Live previews = synchronous ViewModel methods / model getters. |
| Approach | 1: tool + baseline first, then inventory, then fixes per module. |
| Testing | Only new and touched code: unit tests for new methods/getters, command-pass batches of rewired commands, one full run at the very end. Untouched, already-tested functions are not retested. |

## 1. Boundary rule and check tool

**Allowed imports**

| Files | May import |
|-------|-----------|
| `lib/core/console/commands/*.dart` | `lib/viewmodels/`, `lib/core/models/`, the console framework (`lib/core/console/`), Dart SDK (`dart:io` included) |
| `lib/ui/**` | `lib/viewmodels/`, `lib/core/models/`, Dart SDK, Flutter and UI packages |

Forbidden: `lib/core/services/`, `lib/core/data/`, `lib/core/wiring/`, `lib/core/viewmodels/viewmodel_registry.dart` (registry is wiring).

**Exempt by name** (listed in the tool, reason next to each):
- the `register*Commands` wiring files (they build ViewModels);
- dev-only commands: `db-*` (test repositories), text commands, `log-filter`, `list-viewmodels`.

**`dart:io` in command files** stays allowed: reading a path into bytes/strings is console plumbing; screens use a file picker. Consequence checked in the inventory: no ViewModel method takes a file path, only bytes or strings.

**Models importing services** is allowed (e.g. `phil_iri_reading.dart` already does): models are where screen-safe getters live.

**Tool:** `tool/check_vm_boundary.dart`
- scans direct `import`/`export` lines of the files above (not transitive: ViewModels may import services);
- reads `tool/vm_boundary_baseline.txt` (one `file -> import` per line, today's violations);
- fails on a violation not in the baseline, and on a baseline line that no longer occurs (the baseline only shrinks);
- has a pure-Dart test in `test/` like the import walk's;
- is added to CLAUDE.md *Commands* and to `tool/build_release.ps1` beside `check_tutor_imports.dart`.

When the baseline is empty, the baseline file and its code path are removed and the rule is absolute.

## 2. Screen inventory

**Where:** `docs/handoff/screens/` (the handoff docs grow from it):
`common.md`, `auth.md`, `admin.md` (users, schools, sections, assignments, settings, login logs), `crla.md`, `phil-iri.md`, `aral.md`, `reports.md` (NLA, progress, BOSY masterlist, SRP), `dashboard.md` (calendar, reminders, trends, summary), `sync.md`.

**Per screen block:**
- name, build (tutor / admin / both), roles;
- purpose (one line);
- ViewModel calls: `method` → returned model, marked ✅ exists or 🆕 gap;
- live previews (synchronous calls while typing), if any;
- errors to show (which refusals the ViewModel raises);
- console equivalent (command a groupmate can run to see the real output).

**`common.md`** covers cross-cutting needs: signed-in user, role, school, build; pickers (schools, sections, classes, school years, rounds) with names, not ids; online/offline state, pending uploads, read-only records; the version-check refusal.

**Gap list** at the end of each file, numbered per module (`CRLA-G1`, …), each with a proposed fix (new method / model getter / move out of a command file) and the baseline lines it removes. Owner decides each gap (fix / defer with reason), like the command-pass findings.

**Not in it:** layout, visuals, navigation (groupmates' area).

**Review:** all inventory files are written in Phase 2 and reviewed together, with gap decisions, before any Phase 3 code.

## 3. Fixes, error text, testing

**Phases**
1. Tool + baseline (passes on today's code).
2. Inventory (docs only) → owner review and gap decisions.
3. Fix batches, in order:
   1. common / auth / config / users / login logs (`LoginLogRepositorySupabase` and `supabase_config` use in `login_commands`/`config_commands` move behind ViewModels);
   2. CRLA;
   3. Phil-IRI;
   4. ARAL (roster, classes, sessions, IRIP, check-ins, materials, readability, report);
   5. reports, calendar, dashboard / trends / reminders;
   6. sync.

   Each batch implements only the gaps approved for it, rewires its command files, removes its baseline lines. Stop after each batch: what to verify + commit message.

**How moves are done:** the ViewModel method or model getter calls the *same* rule function; no logic is copied, rule files stay where they are. Console-only layout (line formats, text→enum parsing) stays in command files, unless the inventory shows a screen needs the same label; then it becomes a model `.label`-style getter the command also uses.

**Raw error text** (fixed in the batch owning each ViewModel). Found by grep 2026-10-24, the inventory confirms the full list:
- `lastMirrorWarning` with `$e`: `aral_material_viewmodel.dart`, `crla_threshold_viewmodel.dart`, `phil_iri_content_viewmodel.dart`, `round_calendar_viewmodel.dart`, `srp_viewmodel.dart`, `tutor_section_assignment_viewmodel.dart`, `user_viewmodel.dart`;
- `offlineWarning` with `$e`: `auth_viewmodel.dart`;
- raw `rethrow` in `AralClassViewModel._write`.

Rule: a known failure gets a plain sentence; an unknown one gets a fixed sentence in the style of `unexpectedErrorMessage` (`core/services/auth_messages.dart`), and the detail goes only to the module's `ScopedLogger`. The "run pull-cloud" wording in these messages stays until the handoff (Q2).

**Testing per batch**
- test-first unit tests for each new method / getter (`flutter test`);
- `dart analyze` (no errors), `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart`;
- command-pass batches that use the rewired commands, on a new run `r<N>` (B0 once, then only the affected batches);
- one full command-pass run at the very end.

## Done when

- the baseline is empty and removed (rule absolute, tool still runs);
- every inventory gap is fixed or marked `deferred: <reason>` by the owner;
- the final full command-pass run is clean;
- root `CLAUDE.md` and `lib/core/CLAUDE.md` state the rule (and the tool in *Commands*).

## Out of scope

- Console wording in ViewModel messages (handoff, F3).
- Screen layout / UI code.
- New features found during the walk that are not needed for an existing console capability: they go to the gap list as `deferred` unless the owner decides otherwise.
