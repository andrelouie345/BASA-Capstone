# Command pass (run every command) — design

Date: 2026-10-23. Status: **built** (2026-10-24). Last full run r10 (after the final review): `359/359 covered` (tutor 120/120, admin 239/239), 3036 steps, 0 failed. Where this text and *Changes during implementation* (end of file) disagree, the latter wins.

## Goal

Run every console command of both builds (228 admin, 115 tutor; lists in `test/core/wiring/`) against the dev cloud project, check each one, and fix what fails, **before the frontend handoff**. Every ViewModel path a screen will call should be known to work, so bugs are found here and not through a groupmate's screen.

The pass is **automated** (owner: running kits by hand risks missing tests): a runner in the repo executes scenario files and checks their results. It also checks coverage, so no command can be skipped without the run failing. The runner stays in the repo as a regression check to rerun before releases.

Success:
- Every command in `tutor_commands.txt` is checked on a tutor-build device, and every command in `admin_commands.txt` on a device of either build (see *Coverage*).
- One command runs the whole pass and ends with `343/343 covered, N steps, 0 failed`.
- Every failure found was decided by the owner and either fixed (batch rerun passes) or recorded as a known follow-up.

Out of scope: UI; LAN server runs (cloud dev project only); adding the pass to `build_release.ps1` (possible later, the exit code allows it); cleaning old runs' rows off the dev project.

## Decisions (owner, 2026-10-23)

1. **Depth = smoke + refusals, plus checked results where numbers matter.** Every command: a normal case runs without a crash or unexpected error, plus its important refusals (wrong role or other school's data, bad argument, no online session where one is required). Commands that compute numbers or write data that sync depends on also get their results checked independently (see *Checked results*).
2. **Failures: log, then fix per batch.** Findings are collected per batch; at the end of a batch the owner decides each one; agreed fixes are one small piece with a batch rerun. A failure that blocks the rest of a batch (e.g. sign-in) is raised immediately.
3. **Fresh test school per run** (not the existing school 6 data).
4. **A dedicated test superadmin** `zztest.super@basa.test`, created once by the owner with `user-create zztest.super@basa.test admin - <name>`. Its password lives only in `D:\0_CAPSTONE\verify\pass\accounts.json` (outside the repo). The owner's own account is never used.
5. **Approach: in-process Dart runner + plain-text scenario files** in `tool/command_pass/` (not a stdout-piping script, not `dart test` against ViewModels: the point is to run the real commands of each build).
6. **Coverage rule:** a command in both lists counts once on either build; admin-only commands must run on an admin device; role-dependent commands get admin steps by scenario judgment.
7. **No pending uploads at the end of a run**, and a **guard on privileged steps' ids** (below).
8. Order: setup, then tutor batches, then admin batches, then teardown.

## Runner

`dart run tool/command_pass/run.dart [--run r<N>] [batch...]`, pure Dart (no Flutter), like the consoles.

- **Run folder:** `D:\0_CAPSTONE\verify\pass\r<N>\` (N from a counter file in `verify\pass\`). A new run takes the next N; `--run r<N>` reuses an existing run's setup and captures to rerun some batches. Holds device data folders, `captures.json`, `report.md`, `findings.md`.
- **Devices:** `device <name> tutor|admin` switches to (or creates) a device: its own data folder in the run folder, wired exactly like `lib/console/main_tutor.dart` (tutor: shared + tutor commands + dev commands) or `lib/console/main.dart` (admin: all). A device keeps its database across switches, so multi-device flows (tutor uploads, coordinator approves, tutor takes the result in) are one scenario. New devices get the dev cloud config copied from `verify\data\supabase_config.json`.
- **Executes commands in-process** through `ConsoleSession.run`, reading each result and log entry separately (no stdout parsing).

### Scenario format

`tool/command_pass/scenarios/<NN>_<batch>.pass`, one batch per file, steps in order:

| Step | Meaning |
|---|---|
| `device <name> tutor\|admin` | switch device (create on first use) |
| `as <account>` | sign out, then `sign-in cloud` as that account (password from `accounts.json` or the run's captured accounts); first sign-in of a new account also changes its temporary password |
| `run <command line>` | execute; `{name}` is replaced by a captured value |
| `expect <text>` | output of the last `run` must contain the text |
| `expect~ <regex>` | output must match the regex |
| `refuse <text>` | output must contain the text and must not look like a success |
| `capture <name> = <regex>` | store group 1 of the regex match in the output |
| `sql <query> => <value>` | read-only query on the current device's SQLite; first column of first row must equal the value |
| `other-school` (prefix on a `run`) | marks a deliberate read-only step against another school (school 6) |
| `# ...` | comment |

Rules the runner enforces:
- Output containing `Error running <cmd>:` (an uncaught exception) fails the step, even if the expected text is present. `Unknown command` fails.
- A `{name}` that was never captured fails the step (never sends the literal text).
- **Id guard:** a `run` step as `zztest.super` or the run's coordinator may only use ids from captures; numbers that are not ids (scores, rounds, counts) are allowed as literals. A step that is meant to touch school 6 must carry `other-school`, and the runner refuses `other-school` on any command in its write list.
- Temporary passwords (`Temporary password: ...`) and every password from `accounts.json` are masked in the report and findings.

### Report

`report.md`: every step with PASS/FAIL; a failure shows the command, expected text and actual output. Summary line: commands covered per build, steps, failures, and the UNCOVERED list if any. Exit code non-zero on any failure or coverage gap.

## Test data per run

Fake school years were considered and rejected: ARAL refuses session dates in the future, so data must sit in the real current school year. Instead every run builds its own school:

- **Once, by the owner:** `zztest.super` (decision 4).
- **Per run (batch B0, as `zztest.super`):** school `ZZTEST PASS r<N>` in region 13 (the only region with CRLA stories) and `ZZTEST PASS r<N> B` (cross-school refusals and the `school-delete` test); accounts `zztest.pass.r<N>.coord@basa.test`, `.tutor1` (assigned) and `.tutor2` (unassigned) via `user-create`, their temporary passwords captured and changed on first sign-in; sections G2 (CRLA) and G7 (Phil-IRI, ARAL) in the current school year; about eight students imported from an **SF1 workbook the runner generates per run** (run-unique LRNs; `sample-files/` is gitignored, so no checked-in sample is used); calendar windows around today; report/ARAL settings; ARAL enrolment of a few learners.
- **Other school:** school 6 for read-only refusal checks only. Nothing outside the run's two schools is written.
- **End of run (batch Z):** the run's accounts are deactivated (`user-set-active`, checked), and the runner checks that the run left no undecided sync upload.
- **What stays on the dev project:** each run's two schools (one deleted by the test, if that test passes), three inactive accounts and their rows. The owner's superadmin views (school lists, regional reports, dashboard, pull-cloud) will include them; superadmin checks therefore match this run's lines, never regional totals.

## Batches

| Batch | Build / accounts | Commands |
|---|---|---|
| B0 Setup | admin; `zztest.super`, coordinator | user-create, school-create, section-create, SF1 import, assign-section, calendar-set, report settings, ARAL enrol; change-password on first sign-in |
| T1 Session & dev | tutor | sign-in, sign-in-offline, sign-out, whoami, change-password, version-app/-check, config-* (on a throwaway device, restored), offline-status, help, text commands, db-*, log-filter, list-viewmodels |
| T2 Reads & pull | tutor | pull-cloud, school/section/student lists, calendar-show, dashboard(+years), reminders-tutor, trend-aral-activity, aral-tutors, aral-tutor-summary, srp-classes |
| T3 CRLA | tutor | crla-start/part1/part2/results/stories/thresholds, crla-export, export-section |
| T4 Phil-IRI | tutor | every tutor phil-iri command (GST, reading, miscues, answers, rubric, complete/discard/reopen) |
| T5 ARAL | tutor | sessions, attendance, IRIP, check-ins, materials, readability, recommend, roster, sheet, sharp/idle/cutoff reads |
| T6 Sync | tutor + coordinator devices | sync-preview/-upload/-status/-withdraw/-resolve; approve/reject from the coordinator |
| A1 | admin | users, schools, sections, assignments, student imports, conflicts, column map, login logs |
| A2 | admin | CRLA admin (import, regenerate, thresholds set/reset) |
| A3 | admin | Phil-IRI content (collections, passages, questions, criteria), thresholds, finalize, finalize-round |
| A4 | admin | ARAL admin (enrol/propose/import/update/exit/reactivate/remove, tutor assignment, cutoff/sharp/idle set, materials catalog, reports and exports, check-in report) |
| A5 | admin | calendar, report settings, reminders-coordinator, trends, dashboard, NLA, progress, BOSY masterlist, SRP |
| A6 | admin | approver side, offline days, auto-approve, pull-cloud as coordinator/superadmin |
| Z Teardown | admin | deactivate the run's accounts; no-pending-uploads check |

Each batch creates what it needs beyond B0, so `--run r<N> <batch>` can rerun one batch after a fix.

## Coverage

- Tutor build: every command in `tutor_commands.txt` must appear in a checked `run` step (followed by `expect`, `expect~`, `refuse` or `sql`) on a tutor device.
- Admin build: every command in `admin_commands.txt` must appear in a checked step; one also in the tutor list may count from a tutor device; admin-only commands must run on an admin device.
- The runner reads both lists from `test/core/wiring/`, so a new command fails the pass until a scenario covers it.

## Checked results

Independently confirmed (an `sql` check on the device, or a figure worked out by hand in the scenario comment): crla-results, phil-iri-results/-score, aral-report, aral-checkin-report, nla-report, progress-report, bosy-masterlist, srp-list/-classes, trend-*, dashboard, and the sync uploads (rows and real ids after approval). All other commands: normal case plus refusals.

## Workflow per batch

1. Write the batch's scenario; run it.
2. Scenario mistakes (wrong expected text, wrong id) are fixed directly (mechanical). Product failures go to `findings.md`: command, step, actual output, suspected cause, recommended fix.
3. End of batch: the owner decides each finding. Agreed fixes = one piece: code change, `dart analyze`, `dart run tool/check_tutor_imports.dart`, batch rerun until it passes. Then a commit message (scenario + fixes) and the next batch.
4. The owner reruns the batch with the runner and compares with my report (replaces hand-made verify kits for this piece).

The first piece is the runner itself (no batch yet) with its tests; B0 follows once `zztest.super` exists.

## Testing the runner

Pure-Dart tests in `test/tool/command_pass/` (run by `flutter test`, no cloud): scenario parser, `{name}` substitution and missing-capture failure, `expect`/`refuse`/`Error running` rules, id guard, coverage count against both lists, password masking.

## Risks

- `zztest.super` has superadmin powers on the dev project; the id guard and the run-only writes limit what a scenario mistake can reach.
- Several devices in one process: `AppContext.open` per data folder must not share state (e.g. a database instance cache). The plan checks this first; fallback is one process per device switch.
- Rows of every run accumulate on the dev project (accepted while it is recycled).
- The pass depends on the dev cloud being reachable and on the deployed `create-user` Edge Function.

## Changes during implementation

Plan decisions (owner, 2026-10-23, plan `docs/superpowers/plans/2026-10-23-command-pass.md`):
- **D1. Handlers are called directly**, not through `ConsoleSession.run`: the runner looks the command up in `ctx.registry.all`, tokenizes with `ConsoleRegistry.tokenize` and awaits the handler. A `ViewModelException` is the step's output (a refusal); any other exception fails the step as a crash, with its type. A raw database error reaching the user is therefore a finding.
- **D2. One open device at a time** (`LocalDatabase` holds one static database). `device <name>` closes the current device and opens the other from its folder; switching back signs in again as that device's last account (a setup line, not a checked step). A successful `sign-out` step clears the last account, so a device signed out by the scenario stays signed out (R2, 2026-10-24); a failed automatic re-sign-in counts as a failed step (R1).
- **D3. Run accounts' passwords** are generated at first sign-in and kept in `r<N>\accounts.json`; masked in the report.
- **D4. Coverage is checked only on a full run** (no batch arguments). The command lists grew with later work: 343 at design time, 359 at r8 (120 tutor, 239 admin).
- **D5. Literal numbers in privileged steps are written `{=n}`**; a bare integer in a step run as `zztest.super` or the coordinator is refused by the id guard.

Runner additions found necessary while writing the batches:
- Steps: `device <name> tutor|admin fresh` (empty folder each time: makes a batch rerunnable), `make-sf1 <capture> a|b <grade> <section> <count> [from=<n>]` (generated SF1 workbook for school A or B), `write-file <capture> <text...>` (a file in the run folder, `{..}` filled in, path stored in the capture).
- Built-in values (win over captures): `{run}`, `{year}`, `{code_a}`/`{code_b}`, `{name_a}`/`{name_b}`, `{today}`, `{yesterday}`, `{ago2}`, `{ago3}`, `{past}` (-30 days), `{future}` (+30 days), `{rundir}`, `{stamp}` (unique per execution, for rerunnable names), `{email_<account>}`, `{pw_<account>}`.
- `other-school` is allowed only on commands in `tool/command_pass/readonly_commands.txt`.
- The test superadmin's password is written back to `accounts.json` when a scenario changes it.
- A printed catch-all (`... failed: <SomeException|Error>` on a non-log line) fails the step unless the step names that type (F21): console catch-alls would otherwise hide crashes from D1.
- Values are substituted in `expect`, `expect~`, `refuse` and `capture`, not in an `sql` step's expected value (fold captures into the query instead). Regex `^`/`$` anchor the whole output; use `(\n|$)` for a line end.
- Batch A4 grew a second file, `34b_a4b.pass` (the 17 ARAL admin commands no batch had reached).

Rules this pass established (also in `lib/core/CLAUDE.md`): every public ViewModel method checks sign-in and says `notSignedInMessage` (F5, F6, F7, F18, F19; `test/viewmodels/session_guard_test.dart`); console date arguments are strict (F17, F22); screens never get raw Supabase, RLS, SQL or file-system text (F2, F4, F8, F15, F20, F24).

Findings (all decided by the owner; fixes are in the commits of each batch):

| # | Batch | Finding | Outcome |
|---|---|---|---|
| F1 | B0 | `user-create` did not mirror the new user locally | fixed (local mirror) |
| F2 | T1 | raw Supabase auth exception text | fixed (`auth_messages.dart`) |
| F3 | T1 | ViewModel messages name console commands ("run pull-cloud") | session messages fixed; the rest left to the frontend handoff |
| F4 | T3 | list/export commands bypassed ViewModels; raw file errors | fixed (ViewModel methods, `file_output.dart`) |
| F5, F6, F7 | T4-T6 | Phil-IRI, CRLA, ARAL and sync ViewModels worked signed out | fixed (`_requireSignIn`) |
| F8 | A1 | admin bootstrap showed raw Edge Function text | fixed |
| F9 | A1 | ARAL roster did not follow a section move | became the KS1 memo piece and ARAL classes (own spec) |
| F10 | A2 | CRLA words read typed freely vs the DepEd sheet formula | fixed (story words - miscues; migration `20261023020000`) |
| F11 | A3 | deleting a synced read passage said "sync them" | fixed |
| F12, F13 | A4 | `aral-propose` % words correct divided by 100; settings refusal said "cut-off" | fixed |
| F14 | classes T6 | `aral_sessions` SELECT policy broke `sync_apply ... RETURNING` | fixed (migration `20261024020000`; RLS rule in CLAUDE.md) |
| F15, F16 | A4 | duplicate class name gave a raw constraint error; coordinator notice showed ids only | fixed (migration `20261024030000`; names in notices) |
| F17 | A5 | lenient `asof=` dates | fixed (`date_args.dart`) |
| F18, F19 | A5 | settings/calendar reads worked signed out; inconsistent "Not signed in." | fixed |
| F20 | A6 | settings mirror clashed on a new server id | fixed (delete old key row, then upsert) |
| F21 | A6 | catch-alls hid crashes from the pass | runner check added; full rerun found nothing hidden |
| F22 | A4b | ARAL console parsers took impossible dates | fixed |
| F23 | A4b | recommendations named learners "student N" | fixed there; other id-only console lines kept on purpose (screens get names from ViewModels) |
| F24 | r7 | coordinator importing another school's SF1 got a raw RLS error | fixed (own-school check before writes) |

Final review (2026-10-24, two reviewers): the crash check now also catches errors that print no type name (`Bad state:`, casts, null checks, `ArgumentError`, plain `Exception`) and runs on `capture`/`sql` steps; the exit code uses the report's failure rule (R1 included); `refuse` fails on a usage answer unless the step expects `Usage:`; the id guard also refuses `key=<n>` / `key:<n>`; captured values are escaped in regex steps; a `run sign-in` step updates the guard's account; a crash during the automatic sign-in fails the step instead of stopping without a report. Sign-in after authenticating no longer shows raw database text and signs the unused client out. Full run r10: 359/359, 3036 steps, 0 failed.

Known leftovers: raw exception text in the local-mirror warnings of six ViewModels (users, materials, CRLA thresholds, Phil-IRI content, calendar, SRP; console only) goes to the ViewModel completeness check before the frontend handoff. Old runs r2-r8 stay on the dev project with inactive accounts (no delete commands exist for users/students).
