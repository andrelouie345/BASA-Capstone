# ViewModel Completeness Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A screen can do everything the console can through ViewModels and models only, enforced by a tool, with a reviewed screen inventory per module.

**Architecture:** A direct-import checker with a shrink-only baseline lands first (passes on today's code). Then a docs-only screen inventory per module lists screens → ViewModel calls → gaps; the owner decides every gap. Fix batches then add ViewModel methods / model getters that call the same rule functions, rewire command files, and shrink the baseline to empty.

**Tech Stack:** Dart (pure, no Flutter in `core/` and `viewmodels/`), `flutter test`, command pass runner (`tool/command_pass/`).

**Spec:** `docs/superpowers/specs/2026-10-24-vm-completeness-design.md`

## Global Constraints

- Command files (`lib/core/console/commands/`) may import only `lib/viewmodels/`, `lib/core/models/`, `lib/core/console/`, Dart SDK (incl. `dart:io`).
- `lib/ui/**` may import only `lib/viewmodels/`, `lib/core/models/`, `lib/ui/`, Dart SDK, Flutter and UI packages; never `supabase`, `sqflite_common`, `sqflite_common_ffi`, `sqlite3`.
- Forbidden for both: `lib/core/services/`, `lib/core/data/`, `lib/core/wiring/`, `lib/core/viewmodels/`, `lib/core/release.dart`.
- Exempt by name: `test_data_commands.dart` (`db-*`), `debug_commands.dart` (`log-filter`, `list-viewmodels`), `text_commands.dart`; `lib/ui/debug/**` may also import `lib/core/console/` (it is the console overlay).
- Moves call the same rule function; no rule logic is copied; rule files stay where they are.
- Raw error text: no exception text (`$e`) in any message a ViewModel returns or stores; detail goes to the module's `ScopedLogger`. "Run pull-cloud" wording stays (handoff, F3).
- Testing: only new and touched code; command-pass batches of rewired commands on a new run (B0 once); one full run at the end.
- Owner rules: no git commands (give a commit message), stop after each task for owner verify, every decision presented before acting, backend only, never change code not seen.

## Review Focus

- A type defined in `core/services/` that appears in a ViewModel or model public signature (e.g. `PhilIriLevel` in `phil_iri_rules.dart`): a screen cannot name it → inventory gap class T; fix = `export ... show` from a `core/models/` file (owner decides per type). Pinned by the tool test "re-export through a model file is allowed" (Task 1) and by each batch's command files importing the type from the model file.
- A ViewModel method taking a file path: screens on Android get bytes from a picker → gap class P; Task 2 lists every such method; a batch test calls the bytes overload.
- A new method added to a ViewModel that the tutor build includes, for an admin-only capability → would ship admin code to tutors. Each batch runs `check_tutor_imports.dart`; a new admin-only method goes in an admin ViewModel or refuses tutors, with a VM test that a tutor gets `ViewModelException`.
- Live previews called on half-typed input (empty seconds, zero words, no miscues yet) must return null/empty, not throw. Every preview method gets a test with empty/zero input.
- Pass-through methods for things the console did directly (login logs, config, bootstrap) keep the same offline refusals as before (`requireOnlineSession` where the command had it). The batch-1 command-pass batches T1/A1 pin the refusal lines.

---

### Task 1: Boundary check tool + baseline

**Files:**
- Create: `tool/vm_boundary.dart` (pure function, testable)
- Create: `tool/check_vm_boundary.dart` (CLI)
- Create: `tool/vm_boundary_baseline.txt`
- Create: `test/tool/vm_boundary_test.dart`
- Modify: `tool/build_release.ps1:38` (add a step after the import walk)
- Modify: `CLAUDE.md` (*Layout* `tool/` line, *Commands*, *Builds* checks line), `lib/core/CLAUDE.md` (console section: the rule, one paragraph)

**Interfaces:**
- Produces:
  - `class BoundaryViolation { final String file; final String target; String get line => '$file -> $target'; }` (`file`, `target` relative to `lib/`, forward slashes; `target` for a package import = the `package:` URI without basa_capstone, e.g. `package:supabase/supabase.dart`)
  - `List<BoundaryViolation> findBoundaryViolations({required String packageRoot, required String packageName})`
  - `({List<String> added, List<String> gone}) compareToBaseline(List<BoundaryViolation> found, List<String> baseline)` (baseline lines: blank and `#` lines ignored)
  - CLI exit codes: 0 OK, 1 new or gone lines, 2 baseline file missing / listed exempt file missing.

- [ ] **Step 1: Write failing tests** in `test/tool/vm_boundary_test.dart`, fixture packages in a temp dir like `test/tool/import_walk_test.dart` (helper `lib(path, content)`, packageName `fx`):
  - `command file importing a service is a violation`: `core/console/commands/a_commands.dart` imports `'../../services/x_rules.dart'` → one violation, `line == 'core/console/commands/a_commands.dart -> core/services/x_rules.dart'`.
  - `viewmodels, models, console framework and dart:io are allowed` (relative and `package:fx/` forms) → empty.
  - `package import of a data package is a violation in commands`: `import 'package:supabase/supabase.dart';` → target `package:supabase/supabase.dart`.
  - `ui may import flutter but not sqflite`: `ui/x.dart` with `package:flutter/material.dart` + `package:sqflite_common/sqflite.dart` → one violation (sqflite).
  - `ui/debug may import the console framework`, `ui/other may not`.
  - `exempt command files are skipped`: violation in `test_data_commands.dart` → empty.
  - `re-export through a model file is allowed`: `core/models/m.dart` has `export '../services/x_rules.dart' show XLevel;`, command imports `../../models/m.dart` → empty (models are not scanned).
  - `export directives are checked too` (a command file `export`ing a service → violation).
  - `compareToBaseline`: found {a,b}, baseline {b,c,'# note',''} → added [a], gone [c].

- [ ] **Step 2: Run** `flutter test test/tool/vm_boundary_test.dart` → FAIL (file not found).

- [ ] **Step 3: Implement `tool/vm_boundary.dart`.** Scan files under `lib/core/console/commands/` and `lib/ui/` (recursive, `.dart`). Reuse the directive regex style of `tool/import_walk.dart` (`import|export`, not `part`). Resolve relative URIs against the file's directory, `package:<packageName>/` → `lib/`. Classify by the Global Constraints table; exempt names are a `const` list with a comment per entry. Sort violations by `line`.

- [ ] **Step 4: Run** the test → PASS.

- [ ] **Step 5: Implement `tool/check_vm_boundary.dart`** (header comment like `check_tutor_imports.dart`: what, how to run, how to add). Prints `OK: no new ViewModel-boundary imports (<n> baseline lines left)`; on failure prints `New forbidden imports:` / `Baseline lines no longer found (remove them):` with each line. Fails with exit 2 if an exempt file listed does not exist.

- [ ] **Step 6: Write the baseline.** Run the tool once with an empty baseline, paste its 26 lines (today's 32 minus the 6 in exempt files: 5 in `test_data_commands.dart`, 1 in `debug_commands.dart`) into `tool/vm_boundary_baseline.txt` under a header: `# Shrink-only. A fix batch removes its lines. Empty = remove this file and the baseline code (Task 9).` Run again → `OK ... (26 baseline lines left)`. If the count differs from 26, stop and show the owner the list.

- [ ] **Step 7: Wire it in.** `build_release.ps1`: `Invoke-Step 'ViewModel boundary (commands and ui import only ViewModels and models)' { dart run tool/check_vm_boundary.dart }` after the import walk. Docs lines as listed in Files.

- [ ] **Step 8: Verify.** `dart analyze` (0 errors), `flutter test` (all pass), `dart run tool/check_tutor_imports.dart` (OK), `dart run tool/check_vm_boundary.dart` (OK). Stop: owner verifies; commit message `feat(tool): ViewModel boundary check with shrink-only baseline`.

---

### Task 2: Screen inventory (docs only)

**Files:**
- Create: `docs/handoff/screens/` `common.md`, `auth.md`, `admin.md`, `crla.md`, `phil-iri.md`, `aral.md`, `reports.md`, `dashboard.md`, `sync.md`, `README.md` (what the folder is, the block format, gap classes, status legend)

**Interfaces:**
- Produces: numbered gaps `<MODULE>-G<n>` (`COMMON`, `AUTH`, `ADMIN`, `CRLA`, `PHILIRI`, `ARAL`, `REPORTS`, `DASH`, `SYNC`), each with class, proposed fix (exact new signature or getter), baseline lines removed, owner decision field `Decision: (open)`.

**Gap classes** (in `README.md`, used in every file):
- **I** forbidden import in a command file (every baseline line belongs to exactly one gap);
- **T** a service-defined type in a ViewModel/model public signature;
- **P** a ViewModel method that takes a file path;
- **N** names/labels/lookups only command code produces (ids → names, enum → label);
- **L** a live preview a screen needs that has no synchronous call;
- **E** raw exception text in a ViewModel message (the 8 spots + rethrow in the spec);
- **M** a screen need with no console capability → proposed `deferred` (spec *Out of scope*).

- [ ] **Step 1: Collect the facts** (read-only): public members of every file in `lib/viewmodels/` (`grep -nE "^  (Future|[A-Z]\w*[<?]?.*) [a-z]\w*\("`), the command list of both builds (`test/core/wiring/tutor_commands.txt` + admin list), the per-module specs in `docs/superpowers/specs/`, and the baseline. Save nothing outside the docs folder except scratch.

- [ ] **Step 2: Write `common.md` and `README.md`.** `common.md`: signed-in user/role/school/build, pickers (schools, sections, classes, school years, rounds, regions) with names, online/offline + pending upload + read-only state, version-check refusal, error display rule (`ViewModelException.message` shown as is).

- [ ] **Step 3: Write one module file at a time** in the order of the spec's batches (auth, admin, crla, phil-iri, aral, reports, dashboard, sync). Every command of both builds appears as the console equivalent of some screen, or is listed under `## Not a screen` with a reason (dev-only, console-only). Check: count of commands covered = 120 tutor ∪ 239 admin (no command missing; script in scratch comparing the docs against both command lists).

- [ ] **Step 4: Self-check:** every baseline line is in exactly one class-I gap; all spec E spots are gaps; no gap without a proposed fix; no layout/visual content.

- [ ] **Step 5: Stop.** Owner reviews all files and fills each `Decision:` (fix / deferred: reason / changed fix). Commit message `docs(handoff): screen inventory per module with ViewModel gaps`.

---

### Task 3: Batch plans from the approved gaps

**Files:**
- Modify: this plan, filling Tasks 4–9 sections `#### Approved gaps` with, per gap: exact signature/getter, file, test names + assertions, command files rewired, baseline lines removed, command-pass batches to rerun.

- [ ] **Step 1:** Write the sections from the owner's decisions only (a gap marked deferred is listed with its reason, nothing else).
- [ ] **Step 2:** Map each touched command to its command-pass batch (`tool/command_pass/scenarios/*.pass`, grep the command name) and list the batches per task.
- [ ] **Step 3: Stop.** Owner approves the filled plan. Commit message `docs(plan): VM completeness batch details from approved gaps`.

---

### Tasks 4–9: Fix batches (same steps each)

| Task | Batch | Known raw-error items (spec) |
|------|-------|------------------------------|
| 4 | common / auth / config / users / login logs | `auth_viewmodel.dart:281` `offlineWarning`; `user_viewmodel.dart:145`; `tutor_section_assignment_viewmodel.dart:109` |
| 5 | CRLA | `crla_threshold_viewmodel.dart:237` |
| 6 | Phil-IRI | `phil_iri_content_viewmodel.dart:682` |
| 7 | ARAL | `aral_material_viewmodel.dart:383`; `AralClassViewModel._write` rethrow (`aral_class_viewmodel.dart:377`) |
| 8 | reports, calendar, dashboard / trends / reminders | `round_calendar_viewmodel.dart:234`; `srp_viewmodel.dart:538` |
| 9 | sync + finish | none |

#### Approved gaps
(filled in Task 3, per task)

**Raw-error fix pattern (all E items):** the message keeps its sentence and wording, drops `($e)` / `: $e`; the exception text goes to the ViewModel's `ScopedLogger` (`_log('<what> failed: $e')`; it has only `call(String)`). For the rethrow: read the method first, bring the owner one option (known failure → `ViewModelException` with a plain sentence; unknown → `unexpectedErrorMessage`-style sentence), then build it.

Steps for each batch task:

- [ ] **Step 1: Failing tests** for each approved gap (names/assertions from `#### Approved gaps`); for each E item a test that the stored message does not contain the injected exception's text and the logger received it; for each L item an empty/zero-input test (Review Focus); for each new admin-only method on a shared ViewModel, a tutor-refusal test.
- [ ] **Step 2: Run** `flutter test <those files>` → FAIL for the stated reason.
- [ ] **Step 3: Implement** the ViewModel methods / model getters / re-exports (each calls the existing rule function).
- [ ] **Step 4: Rewire** the command files to the new calls; console output byte-identical (no command text changes in this piece).
- [ ] **Step 5: Shrink the baseline** by the gap's lines; `dart run tool/check_vm_boundary.dart` → OK with the new count.
- [ ] **Step 6: Verify:** `flutter test` (all), `dart analyze` (0 errors), `dart run tool/check_tutor_imports.dart` (OK).
- [ ] **Step 7: Command pass:** check for an open BASA console and ask the owner to close it; new run in Task 4 (`dart run tool/command_pass/run.dart` with only B0 + this batch's batches, recorded as `r<N>`), later tasks `--run r<N> <batches>`; every listed batch 0 failures.
- [ ] **Step 8: Stop.** Owner verifies; commit message per batch (`refactor(<module>): screens reach <...> through ViewModels`).

**Task 9 extra steps (finish):**
- [ ] Baseline empty → delete `tool/vm_boundary_baseline.txt`, remove `compareToBaseline` and its tests; the CLI fails on any violation; update its test and CLAUDE.md lines.
- [ ] Full command-pass run (new `r<N>`, no arguments) → clean, coverage 359/359.
- [ ] `docs/handoff/screens/*.md`: every gap shows ✅ fixed or `deferred: <reason>`; spec status line → built.
- [ ] Stop; commit message `feat(tool): ViewModel boundary absolute; VM completeness check done`.
