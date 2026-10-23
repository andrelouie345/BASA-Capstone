# Command pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An automated runner that executes every console command of both builds from scenario files, checks the results and coverage, then the batches (B0, T1-T6, A1-A6, Z) that use it to find and fix failures.

**Architecture:** `tool/command_pass/` holds a pure-Dart runner (parser, checks, coverage, device manager, report) that wires a device exactly like `lib/console/main.dart` / `main_tutor.dart` and calls the registered command handlers in-process. Scenario files `tool/command_pass/scenarios/*.pass` describe each batch. Runs live in `D:\0_CAPSTONE\verify\pass\r<N>\`.

**Tech Stack:** Dart (no Flutter at runtime), sqflite_common_ffi, supabase, excel_plus (SF1 fixture), flutter_test for the runner's own tests.

**Spec:** `docs/superpowers/specs/2026-10-23-command-pass-design.md`

## Decisions for the owner (before Task 1)

Found while reading the code for this plan; each changes a detail of the approved design.

- **D1. Call handlers directly, not `ConsoleSession.run`.** `ConsoleRegistry.execute` catches every exception and returns `Error running <cmd>: <e>`. `ViewModelException.toString()` is only its message, so a normal refusal (a ViewModel saying "Forbidden: …") and a real crash (TypeError, PostgrestException, StateError) look the same. Recommendation: the runner looks the command up in `ctx.registry.all`, tokenizes with `ConsoleRegistry.tokenize`, and awaits `handler(args)` itself. A `ViewModelException` becomes the step's output (a refusal). **Any other exception fails the step as a crash**, with its type in the report. Log lines still arrive through `ctx.session` (the logger). Consequence: a raw database error reaching the user (e.g. RLS refusing what the ViewModel let through) shows up as a finding. That's intended: screens would otherwise show raw errors.
- **D2. One open device at a time.** `LocalDatabase` keeps a single static `Database` for the whole process (`local_database.dart:21`), so two devices can't be open together. Recommendation: `device <name>` closes the current device (`LocalDatabase.close()`) and opens or rewires the other one from its own folder. Sign-in lives in memory, so when the runner switches back to a device it **signs in again automatically** as that device's last account (shown in the report as a setup line, not a checked step).
- **D3. Passwords of the run's accounts.** The runner generates a random password per run account at first sign-in (replacing the temporary one) and keeps it in `r<N>\accounts.json`. That file is outside the repo, and every password is masked in the report.
- **D5. Literal numbers in privileged steps are written `{=10}`.** The spec allows plain numbers that aren't ids, but the runner can't tell a score from an old section id (school 6's sections are 6 and 28). Recommendation: as `zztest.super` or the coordinator, a bare integer is refused, and literals are written `{=10}` so they're visibly deliberate. Tutor steps are unaffected.
- **D4. Coverage counts only on a full run.** A partial run (`--run r7 T4`) reports its steps but skips the coverage check. Only a full run can print `343/343 covered`.

## Global Constraints

- Pure Dart under `tool/command_pass/`; never imported by `lib/` (the tutor/admin import walk stays clean). Tests in `test/tool/command_pass/`, run by `flutter test`, no network.
- Never use the owner's account. Accounts: `zztest.super@basa.test` (from `D:\0_CAPSTONE\verify\pass\accounts.json`), and per run `zztest.pass.r<N>.coord@basa.test`, `zztest.pass.r<N>.tutor1@basa.test`, `zztest.pass.r<N>.tutor2@basa.test`.
- Schools per run: `ZZTEST PASS r<N>` and `ZZTEST PASS r<N> B`, region 13. Nothing written outside them; school 6 only in `other-school` read-only steps.
- Run folder `D:\0_CAPSTONE\verify\pass\r<N>\` (counter file `D:\0_CAPSTONE\verify\pass\next_run.txt`). New devices copy `D:\0_CAPSTONE\verify\data\supabase_config.json`.
- Mask in all output: text after `Temporary password: ` up to whitespace, and every password the runner knows.
- Exit code 0 only when there are no failed steps and (on a full run) no uncovered commands.
- After each task: `dart analyze` (no new errors), `flutter test`, `dart run tool/check_tutor_imports.dart`.
- Git: the owner commits; each task ends with a commit message handed over, not a commit.

## Review Focus

1. **An expected text that also appears in the help or usage line.** `expect Started` would pass on a `Usage: …` answer that echoes the word. The step must fail when the output starts with `Usage:` unless the step is a `refuse`. Test in Task 2.
2. **A capture regex that matches nothing.** It must fail the capture step, not store an empty value that later turns into `crla-start  bosy`. Test in Task 2.
3. **Windows paths and quoted arguments in `run` lines** (`import-students "D:\…\r7\sf1 g2.xlsx"`). Substitution must keep the quotes so `tokenize` sees one argument. Test in Task 2.
4. **A scenario file with CRLF line endings** (git `autocrlf=true` on this machine). The parser must strip `\r`, or every `expect` silently gets a trailing `\r` and fails. Test in Task 1.
5. **A run killed halfway.** The next `--run r<N>` must reuse `captures.json` and `accounts.json` written so far: captures are saved after every capture step, not at the end. Test in Task 4.

---

### Task 1: Scenario parser

**Files:**
- Create: `tool/command_pass/scenario.dart`
- Test: `test/tool/command_pass/scenario_test.dart`

**Interfaces:**
- Produces:
  - `sealed class Step { int line; }` with subclasses `DeviceStep(name, String build /* 'tutor'|'admin' */)`, `AsStep(account)`, `RunStep(commandLine, {bool otherSchool})`, `ExpectStep(text)`, `ExpectRegexStep(RegExp)`, `RefuseStep(text)`, `CaptureStep(name, RegExp)`, `SqlStep(query, expected)`.
  - `class Scenario { String batch; List<Step> steps; }`.
  - `Scenario parseScenario(String batch, String source)`, which throws `FormatException('<batch>:<line>: <reason>')`.

- [ ] **Step 1: Write failing tests.**
  - `parses every step kind`: one line of each kind gives the matching type and fields. `other-school run school-list` gives `RunStep(otherSchool: true)`. `sql select 1 => 1` gives query `select 1`, expected `1`.
  - `skips comments and blank lines`.
  - `strips CR from CRLF input` (Review Focus 4): `'run whoami\r\nexpect Signed in\r\n'` gives expect text `Signed in` (no `\r`).
  - `rejects a check before any run`: `expect x` as the first step throws a FormatException naming line 1.
  - `rejects an unknown keyword and a device build other than tutor|admin`.
  - `rejects a bad regex` in `expect~` / `capture`, with the line number.
- [ ] **Step 2: Run** `flutter test test/tool/command_pass/scenario_test.dart`. Expected: FAIL (file missing).
- [ ] **Step 3: Implement `parseScenario`.** Line-based; the keyword is the first token and the rest of the line is the argument. Split `capture` on the first ` = ` and `sql` on the last ` => `.
- [ ] **Step 4: Run the test again.** Expected: PASS.
- [ ] **Step 5: Hand over a commit message** (`feat(pass): scenario parser`).

### Task 2: Step checks, substitution, masking, id guard

**Files:**
- Create: `tool/command_pass/checks.dart`
- Test: `test/tool/command_pass/checks_test.dart`

**Interfaces:**
- Consumes: Task 1 step types.
- Produces:
  - `class StepOutcome { bool passed; String message; }`.
  - `class CommandOutput { String text; bool refused /* ViewModelException */; String? crashType; }`.
  - `StepOutcome checkExpect(ExpectStep s, CommandOutput o)`, `checkExpectRegex`, `checkRefuse(RefuseStep s, CommandOutput o)`.
  - `String? capture(CaptureStep s, CommandOutput o)`, which returns null when nothing matches.
  - `String substitute(String line, Map<String, String> captures)`, which replaces `{name}` and `{=literal}` and throws `MissingCaptureException(name)`.
  - `String mask(String text, Iterable<String> secrets)`.
  - `String? guardIds(RunStep s, {required bool privileged, required Set<String> writeCommands})`, which returns the refusal reason or null.

- [ ] **Step 1: Write failing tests.**
  - **Crash rule:** any check on an output with `crashType != null` fails, even when the text matches.
  - **Expect on a usage answer** (Review Focus 1): `expect Started` on `Usage: crla-start …` fails ("usage answer").
  - **Expect on a refusal:** `expect` / `expect~` fail on a `refused` output. `refuse Forbidden` passes on `refused: true, text: 'Forbidden: …'`. It also passes on a non-exception answer containing the text (many commands return refusals as text). It fails when the text is absent.
  - **Empty capture** (Review Focus 2): a capture with no match returns null. The runner turns that into a failed step (asserted in Task 4).
  - **Substitution:** `substitute('crla-start {sec} {lrn} bosy', {'sec':'41','lrn':'999000070001'})` produces the filled line. A missing name throws `MissingCaptureException('lrn')`. Quoted Windows paths are kept intact (Review Focus 3): `import-students "{dir}\\sf1 g2.xlsx"` with `dir=D:\\x\\r7` gives `import-students "D:\x\r7\sf1 g2.xlsx"`, and `ConsoleRegistry.tokenize` of that gives 2 tokens.
  - **Masking:** `mask('Temporary password: Ab3$xyz (shown once)', ['secret1'])` gives `Temporary password: *** (shown once)`. Known secrets are replaced anywhere.
  - **Id guard (checked on the scenario text, before substitution):**
    - In a privileged step, **every bare integer token is refused**. Integers must come from a capture (`{sec_g7}`) or an explicit literal `{=10}`, which `substitute` turns into `10`. So `run section-delete 28` is refused, `run section-delete {sec_g7}` passes, and `run aral-idle-days-set {school} {=10}` passes.
    - Tokens that merely contain digits (dates `2026-10-23`, decimals `0.85`, LRN captures) aren't bare integers.
    - An `other-school` step whose command is in `writeCommands` is refused. On a read command it passes, and the integer rule is skipped (it names school 6 on purpose).
    - Non-privileged steps (tutors) aren't guarded; RLS already limits them, and a tutor touching another school is exactly what refusal steps test.
- [ ] **Step 2: Run** `flutter test test/tool/command_pass/checks_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** A "usage answer" is `text.trimLeft().startsWith('Usage:')`. A bare integer is a token matching `^\d+$` after tokenizing the unsubstituted line. Put `writeCommands` in `tool/command_pass/write_commands.txt`: every command whose name contains `create|delete|set|add|remove|update|import|assign|unassign|enroll|exit|reactivate|mark|start|finalize|approve|reject|move|build|clear|rate|edit|activate|promote|regenerate|reset|skip|link`. List the actual names from both command lists, one per line, sorted.
- [ ] **Step 4: Run the test again.** Expected: PASS.
- [ ] **Step 5: Hand over a commit message.**

### Task 3: Coverage

**Files:**
- Create: `tool/command_pass/coverage.dart`
- Test: `test/tool/command_pass/coverage_test.dart`

**Interfaces:**
- Consumes: Task 1 `Scenario`.
- Produces: `class CoverageResult { List<String> uncoveredTutor; List<String> uncoveredAdmin; int coveredTutor, totalTutor, coveredAdmin, totalAdmin; }` and `CoverageResult computeCoverage(List<Scenario> scenarios, {required List<String> tutorCommands, required List<String> adminCommands})`.

- [ ] **Step 1: Write failing tests.**
  - A command counts only for a `RunStep` **directly followed** by at least one check (`expect`, `expect~`, `refuse`, `sql`) before the next `run`, `as` or `device`.
  - It counts for the build of the `device` it ran on.
  - Tutor-list commands need a tutor device.
  - Admin-list commands count from either build when they're also in the tutor list, but only from an admin device when they're admin-only (spec *Coverage*).
  - An unchecked `run` doesn't count.
  - Totals come from the lists: with the real files the totals are 115 and 228. Read `test/core/wiring/*.txt` in the test.
- [ ] **Step 2: Run the test.** Expected: FAIL. **Step 3: Implement.** **Step 4: Run it again.** Expected: PASS.
- [ ] **Step 5: Hand over a commit message.**

### Task 4: Devices, executor, report, CLI, self-test scenario

**Files:**
- Create: `tool/command_pass/device.dart`, `tool/command_pass/runner.dart`, `tool/command_pass/report.dart`, `tool/command_pass/run.dart` (main), `tool/command_pass/scenarios/00_selftest.pass`
- Test: `test/tool/command_pass/runner_test.dart`

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces:
  - `class Device { String name; String build; Directory dir; AppContext ctx; String? lastAccount; }`.
  - `class DeviceManager { Future<Device> switchTo(String name, String build); }`, which closes the open device (`LocalDatabase.close()`), opens `AppContext.open(dataDir: <run>/devices/<name>)` and wires it like `lib/console/main_tutor.dart` (tutor) or `lib/console/main.dart` (admin) (D2). The config is copied on first creation.
  - `class RunState { Map<String,String> captures; Map<String,String> passwords; }`, with `load(Directory run)` and `save()` writing `captures.json` / `accounts.json` after every capture or password change.
  - `class StepResult { Step step; StepOutcome outcome; String output; }`.
  - `Future<List<StepResult>> runScenario(Scenario s, DeviceManager d, RunState st, Accounts a)`.
  - `String renderReport(List<StepResult> all, CoverageResult? cov, Iterable<String> secrets)`.
  - CLI: `dart run tool/command_pass/run.dart [--run r<N>] [batch...]`. No `--run` takes the next N from `next_run.txt`. No batches runs every scenario in file-name order. Writes `report.md` and prints the summary line `<covered>/<total> covered, <steps> steps, <failed> failed` (coverage only on a full run, D4). Exits 1 on any failure.
- Executor rules:
  - **`run` (D1):**
    1. the id guard on the unsubstituted line, where privileged means the device's account is `super` or `coord`;
    2. substitute;
    3. look up the command; an unknown one fails the step;
    4. `await handler(args)`;
    5. a `ViewModelException` gives `CommandOutput(refused: true)`; any other exception gives `crashType = e.runtimeType`;
    6. log entries added during the call are appended to the output.
  - **`as <account>`:**
    1. `sign-out` if signed in, then `sign-in cloud <email> <password>`;
    2. when the output contains `(must change password)`, run `change-password <generated>` and store the password (D3);
    3. a failing sign-in fails the step and **stops the scenario**.
  - **`capture`:** a null result fails the step (Review Focus 2).
  - **A failed `run`:** its check steps are reported as skipped. The scenario continues.

- [ ] **Step 1: Write failing tests (offline: they use only `set-text`, `get-text`, `append-text`, `clear-text`, `help`, `whoami` and the `sql` step).**
  - `00_selftest.pass` runs on devices `a` (tutor) and `b` (admin):
    - `set-text` on `a`, then `sql` on `a` finds it;
    - on `b` the same `sql` finds nothing (separate folders);
    - back on `a` the value is still there (D2).
  - **Unknown command:** a step `run no-such-cmd` fails.
  - **Crash detection:** a test-only command registered on the device that throws `StateError` gives a step failing with `StateError` in the message. One that throws `ViewModelException('Forbidden: x')` passes a `refuse Forbidden`.
  - **Resume** (Review Focus 5): a run whose `captures.json` holds `x=5` resolves `{x}` in a second invocation with the same run folder.
  - **Report:** contains `PASS` / `FAIL` per step, masks a known secret, and the summary line format.
- [ ] **Step 2: Run** `flutter test test/tool/command_pass/runner_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Look the wiring order up in `lib/console/main.dart:23-30` and `lib/console/main_tutor.dart:20-25`; don't change them. `exit()` at the end of `run.dart`, as the consoles do, because the Supabase client keeps the process alive.
- [ ] **Step 4: Run the test again.** Expected: PASS. Then run `dart run tool/command_pass/run.dart selftest` from the repo root. Expected: the summary shows 0 failed and `D:\0_CAPSTONE\verify\pass\r1\report.md` exists. (The counter starts at 1; a self-test run uses up a number, which is acceptable.)
- [ ] **Step 5: Hand over a commit message** (`feat(pass): command pass runner`), with `.gitignore` unchanged (runs live outside the repo).

### Task 5: SF1 fixture generator

**Files:**
- Create: `tool/command_pass/sf1_fixture.dart`
- Test: `test/tool/command_pass/sf1_fixture_test.dart`
- Modify: `tool/command_pass/runner.dart` (step `make-sf1`)

**Interfaces:**
- Produces:
  - `void writeSf1(String path, {required String schoolCode, required String schoolName, required String regionLabel, required String schoolYear, required String grade, required String section, required List<Sf1Learner> learners})`, with `class Sf1Learner { String lrn, last, first, sex /* M|F */; String? birthDate; }`.
  - New scenario step `make-sf1 <capture name> <grade> <section> <count>`, which writes `<run>/sf1_g<grade>.xlsx` and stores its path under the capture name.
- Values:
  - school code `ZZPASS<N padded to 4>` (and `…B` for school B);
  - region label as `Region.resolve` accepts for region 13 (check `Region.resolve` for the accepted spelling, e.g. `Region X`);
  - school year = the current school year (`normalizeSchoolYear` format: June onward is `Y-(Y+1)`);
  - LRN `9990` + N(4) + grade(1) + index(3) = 12 digits;
  - sexes alternate, starting with M;
  - names `ZZTEST<letter>` / `Learner<index>`.
- Cells at the default `Sf1ColumnMap` positions (`lib/core/services/sf1_column_map.dart`); data from row `dataStartRow` (6).

- [ ] **Step 1: Write a failing test.** Write a file with 3 learners to a temp dir, read it back with `excel_plus` at the `Sf1ColumnMap()` defaults, and assert that the header cells (school code, name, region, year, grade, section), 3 LRNs and the sexes match.
- [ ] **Step 2: Run the test.** Expected: FAIL. **Step 3: Implement.** **Step 4: Run it again.** Expected: PASS.
- [ ] **Step 5: Hand over a commit message.** Batch B0's `import-trial` step is the real proof that the importer accepts the file.

### Tasks 6-19: Batches

One task per batch, in this order: **B0, T1, T2, T3, T4, T5, T6, A1, A2, A3, A4, A5, A6, Z.** The commands for each are in the spec's *Batches* table; refusals and checked results are in *Decisions* 1 and *Checked results*. Each batch file is `tool/command_pass/scenarios/<NN>_<batch>.pass`: `10_b0`, `21_t1` … `26_t6`, `31_a1` … `36_a6`, `90_z`.

Procedure per batch (the same each time):

- [ ] **Step 1: Write the scenario.**
  - Every command in the batch gets a normal case with a check. Add the refusals the spec asks for: wrong role, another school (`other-school` read or tutor2), bad argument, and no online session where one is required.
  - Commands in *Checked results* also get a `sql` step or a hand-worked figure in a comment.
  - Read each command's usage line (`help`) before writing its step. Never guess an argument.
- [ ] **Step 2: Check for an open BASA console** (open-console-check), then run `dart run tool/command_pass/run.dart --run r<N> <batch>`. B0 runs without `--run` (it starts a new run).
- [ ] **Step 3: Sort the failures.**
  - A scenario mistake (wrong expected text, wrong argument) gets fixed in the scenario, then rerun.
  - A product failure goes to `r<N>\findings.md`: command, step, output, suspected cause, recommended fix.
  - A failure that blocks the rest of the batch: stop and tell the owner at once.
- [ ] **Step 4: Stop. Walk the owner through `findings.md`** and get a decision per finding (decisions-before-acting).
- [ ] **Step 5: Make the agreed fixes as one piece.** Code change (raise RLS in the same step if a policy is involved; a new migration if the schema changes, following the CLAUDE.md migration rules), `dart analyze`, `flutter test`, `dart run tool/check_tutor_imports.dart`, then rerun the batch until it passes.
- [ ] **Step 6: Hand over a commit message** (scenario + fixes, with any finding deferred by the owner listed under "Known follow-ups"), and the rerun command for the owner.

Batch-specific notes:

- **B0** needs `zztest.super` in `D:\0_CAPSTONE\verify\pass\accounts.json` (`{"super": {"email": "zztest.super@basa.test", "password": "…"}}`). If it's missing, stop and ask the owner. B0 captures:
  - the school ids `school`, `schoolB` and the section ids `sec_g2`, `sec_g7`;
  - the user ids `coord`, `tutor1`, `tutor2`;
  - the learner LRNs `lrn_g2_1..4`, `lrn_g7_1..4`;
  - the temporary passwords, taken from `user-create` output by a capture step. `as` then replaces them with generated passwords (D3).
- **T1** puts `config-set-*` on a throwaway device `t1-config` only, and restores the values it changed before the batch ends (the `config-show` output is checked after the restore).
- **T6 and A6** must end with every upload decided. `Z` asserts it: `sync-pending` as the coordinator shows none for the run's school.
- **Z** deactivates the coordinator and both tutors (`user-set-active … false`, then `as tutor1` must be refused), as `zztest.super`.
- **After A6/Z:** a full run, `dart run tool/command_pass/run.dart`, must end with `343/343 covered`. Any UNCOVERED command goes back into the batch it belongs to.

### Task 20: Docs

- [ ] **Step 1: Update docs.**
  - `CLAUDE.md` *Commands*: add `dart run tool/command_pass/run.dart [--run r<N>] [batch...]` (needs `D:\…\verify\pass\accounts.json`; the dev cloud only).
  - `CLAUDE.md` layout `tool/` line: add `command_pass/`.
  - Spec status line: built, with a "Changes during implementation" section for D1-D4 and any later deviations.
- [ ] **Step 2: Hand over a commit message.**
