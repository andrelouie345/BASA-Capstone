# D2 Coordinator Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Save the progress "done" threshold per region/school, make progress monitoring show `NOT SCHEDULED` for rounds a school does not hold, and give coordinators reminders (heads-up / in progress / overdue) per scheduled Phil-IRI and CRLA round.

**Architecture:** New cloud table `report_settings` (copy of the `aral_settings` pattern, RLS included), mirrored into SQLite v32. A small `ReportSettingsViewModel` owns the effective threshold (default 0.85 ← region ← school). `NlaReportViewModel.progress` reads that threshold and the D1 calendar. A new `ReminderViewModel` combines the calendar, `NlaReportViewModel.progress` (Phil-IRI) and a private CRLA count from `crla_results`; it owns no other rule.

**Tech Stack:** Dart (no Flutter in `core/` or `viewmodels/`), sqflite_common, supabase-dart, Postgres 18 harness for RLS.

**Spec:** `docs/superpowers/specs/2026-10-19-dashboard-design.md` (section D2). D1 plan for patterns: `docs/superpowers/plans/2026-10-19-d1-round-calendar.md`.

## Global Constraints

- Migration `supabase/migrations/20261019040000_report_settings.sql` (newer than `20261019030000`). Idempotent, safe to run twice. Never edit the baseline.
- SQLite: `local_database.dart` version 31 → **32**, new creator in its own file, `IF NOT EXISTS`, runs on create and every upgrade.
- RLS in the same piece; `revoke all ... from anon`; reuse `public.aral_settings_stamp()` for the stamp trigger.
- `core/` and `viewmodels/` never import Flutter. Anon key only.
- Threshold is stored as a fraction (`done_threshold`, 0.01–1, default **0.85**); console takes a percent (`85` → 0.85). A passed threshold is a one-off override and is never saved.
- `today` is always a parameter (default now); heads-up window = **7 days** (`reminderHeadsUpDays`).
- Phil-IRI = Grade 4–10 sections; CRLA = Grade 1–3 sections. Calendar round string ↔ enum by name (`'mosy1'` ↔ `PhilIriRound.mosy1`, `'mosy'` ↔ `CrlaRound.mosy`).
- Done = `dart analyze` (no new errors), PG harness passes, console run on a scratch copy of the verify DB, verify kit `D:/0_CAPSTONE/verify/d2/`, commit message handed over (no git commands).

## Review Focus

1. **No calendar for the year** — progress is byte-for-byte as before (`NO IRA` / `NO MOSY` / `NO EOSY`, threshold 85% when no `report_settings` row) and reminders print `No reminders`. Pinned: Task 3 step 3 reruns an existing progress kit file; Task 4 kit `6_no_calendar.txt`.
2. **Day boundaries** — opens in 7 days → heads-up, in 8 → nothing; `today == closes_on` → in progress "closes today"; day after → overdue "closed 1 day ago". Pinned: Task 4 kit `4_dates.txt`.
3. **Threshold edge** — 17 of 20 at 0.85 is done (counts, not the rounded share, via `ProgressReport.status`); a section with nobody enrolled is neither below nor counted in "of N sections". Pinned: Task 4 unit check in step 3.
4. **Instrument without matching sections** — a school with no Grade 1–3 sections gets no CRLA reminders (not "0 of 0 sections"); same for Phil-IRI without Grade 4–10. Pinned: Task 4 kit `3_reminders.txt` (CRLA line absent or present per the verify DB's grades).
5. **Skipped / unscheduled round** — a school-skipped round gives no reminder and shows `NOT SCHEDULED` in progress, while a round with ≥ threshold assessed stays `DONE` even if unscheduled. Pinned: Task 3 kit `2_progress.txt`, Task 4 `3_reminders.txt`.

---

### Task 1: Cloud migration + RLS check

**Files:**
- Create: `supabase/migrations/20261019040000_report_settings.sql`
- Scratch: `<scratchpad>/d2pg/steps.sql` (not committed)

**Interfaces:**
- Produces `public.report_settings(id bigint identity pk, school_id bigint null references schools(id) on delete cascade, settings jsonb not null, updated_by uuid references users(id), updated_at timestamptz not null default now())`.

- [ ] **Step 1: Write the migration** — copy of `aral_settings` (baseline lines 1739–1748, 3988, 4064–4065, 4336–4342) with the table name swapped: `settings` object check; named check `report_settings_done_threshold`: key absent OR (`number` and between 0.01 and 1); unique index `report_settings_school_key on (coalesce(school_id, 0))`; trigger `report_settings_stamp` → `aral_settings_stamp()`; policies `report_settings_select` / `report_settings_write` with the `aral_settings` expressions; header comment in the D1 migration's style (what, rules, RLS; "separate from aral_settings: the threshold is not an ARAL rule").
- [ ] **Step 2: Write the PG matrix** (memory `pg-test-harness`; schools 1–2, superadmin SA, coordinator C1 of school 1, tutor T1 of school 1; literal ids, no `INSERT ... SELECT`):

| as | action | want |
|---|---|---|
| SA | insert region row `{"done_threshold": 0.9}` | ok |
| SA | insert school 2 row | ok |
| C1 | insert school 1 row `{"done_threshold": 0.8}` | ok |
| C1 | insert region row / school 2 row | refused (42501) |
| C1, T1 | select | region + school 1 rows only |
| T1 | insert/update/delete school 1 row | refused / 0 rows |
| anon | select | permission denied |
| SA | `done_threshold` 0, 1.5, `"0.8"` (string) | 23514 each |
| SA | second region row | 23505 |
| C1 | update own row | `updated_by` = C1, `updated_at` advanced |

- [ ] **Step 3: Run the harness** (migration applied twice). Expected: every row matches; server stopped, `pgdata` removed.
- [ ] **Step 4: Checkpoint — owner applies the migration** in the dev project SQL Editor. Check: `select policyname, cmd from pg_policies where tablename = 'report_settings';` → 2 rows.

---

### Task 2: Saved threshold — model, repos, SQLite v32, ViewModel, console

**Files:**
- Create: `lib/core/models/report_setting.dart`, `lib/core/repositories/report_setting_repository.dart`, `lib/core/data/local/report_local_schema.dart`, `lib/core/data/local/report_setting_repository_sqlite.dart`, `lib/core/data/remote/report_setting_repository_supabase.dart`, `lib/viewmodels/report_settings_viewmodel.dart`, `lib/core/console/commands/report_settings_commands.dart`
- Modify: `lib/core/data/local/local_database.dart` (v32 comment + `version: 32`, `createReportLocalSchema` in `onCreate` and `onUpgrade`), `lib/core/console/commands/pull_commands.dart` (`'report_settings': 'id'` next to `aral_settings` in the pull order and the cleared tables), `lib/console/main.dart`, `lib/main.dart`

**Interfaces:**
- `ReportSetting` and `ReportSettingRepository`: same shape as `AralSetting` / `AralSettingRepository` (`getRegion`, `getForSchool`, `save(int? schoolId, Map settings)`, `deleteForSchool`, `upsertWithId`, `removeMirroredForSchool`), table `report_settings`. SQLite repo is read + mirror only (`_online()` throws), Supabase repo throws `UnimplementedError` for the mirror methods — as the ARAL pair. SQLite table: copy of the `aral_settings` local table + its unique index.
- `class ReportSettings { static const doneThresholdKey = 'done_threshold'; static const defaultDoneThreshold = 0.85; final double doneThreshold; factory ReportSettings.fromMap(Map<String, Object?>) }` (in the model file; `num` → `double`).
- `ReportSettingsViewModel({required AuthViewModel auth, required ReportSettingRepository local, required ReportSettingRepository Function(SupabaseClient) cloud, Logger? logger})`:
  - `Future<ReportSettings> effective(int schoolId)` — local: defaults ← region ← school.
  - `Future<({double? region, double? school, double effective})> doneThresholdLayers(int? schoolId)` — local copy.
  - `Future<ReportSetting> setDoneThreshold(int? schoolId, double share)` — online, merges into the stored map (as `AralCheckinViewModel.setPassPct`), refuses outside 0.01–1, mirrors.
  - `Future<void> resetSchool(int schoolId)` — online; "School N has no report settings override." when none.
  - Writer/role check, `_cloudWrite` error mapping and `_mirror` + `lastMirrorWarning` as `RoundCalendarViewModel`.
- Console: `report-settings-show <region|schoolId>` → `Done threshold: region 90% · school 80% · applies 80%` (`not set` for missing layers); `report-settings-set <region|schoolId> <percent 1-100>`; `report-settings-reset <schoolId>`.

- [ ] **Step 1: Write the files and modifications;** register `ReportSettingsViewModel` in `vmRegistry` in both mains, constructed **before** `NlaReportViewModel`.
- [ ] **Step 2: `dart analyze`** — no errors.
- [ ] **Step 3: Upgrade + round trip** on a scratch copy of `D:/0_CAPSTONE/verify/data`: console `exit` → `PRAGMA user_version` = 32 and `report_settings` exists; then as `zztest.coord@basa.test`: `report-settings-show <S>` (all `not set`, applies 85%), `report-settings-set <S> 80`, show (school 80%), `report-settings-set region 90` → Forbidden, `report-settings-reset <S>`, show (85%), `pull-cloud` completes.

---

### Task 3: Progress reads the saved threshold and the calendar

**Files:**
- Modify: `lib/viewmodels/nla_report_viewmodel.dart`, `lib/core/console/commands/nla_report_commands.dart`, `lib/console/main.dart`, `lib/main.dart` (construct `RoundCalendarViewModel` before `NlaReportViewModel` and pass both new dependencies)

**Interfaces:**
- Consumes: `ReportSettingsViewModel.effective` (Task 2), `RoundCalendarViewModel.effectiveCalendar` (D1).
- Produces:
  - `NlaReportViewModel({..., required ReportSettingsViewModel reportSettings, required RoundCalendarViewModel calendar})`.
  - `progress({required int schoolId, required String schoolYear, Set<int>? sectionIds, double? doneThreshold, DateTime? asOf})` — null threshold = `(await _reportSettings.effective(schoolId)).doneThreshold`; a passed value is still range-checked.
  - `ProgressReport` gains `final Set<PhilIriRound>? scheduledRounds;` — null when the school's effective calendar for the year has **no Phil-IRI entry at all** (skipped ones count as entries); else the non-skipped Phil-IRI rounds.
  - `ProgressReport.status(row, r)`: unchanged when `DONE`; otherwise `'NOT SCHEDULED'` when `scheduledRounds != null && !scheduledRounds!.contains(r)`, else the old `NO IRA`/`NO MOSY`/`NO EOSY`.
- Console: `progress-report[-csv]` `done=` becomes optional; with none given the header shows the saved threshold. Usage text: `[done=<percent, default: saved setting>]`.

- [ ] **Step 1: Make the changes.**
- [ ] **Step 2: `dart analyze`** — no errors.
- [ ] **Step 3: Regression** — rerun the existing reports kit's progress file(s) (`D:/0_CAPSTONE/verify/` reports/progress kit; find it by `progress-report` in its command files) on a scratch copy and diff against its `expected_*.txt`: only timestamps differ. First confirm (`python -I`, read-only) that the verify DB has no `assessment_calendar`/`report_settings` rows for that year; if it does, say so instead of claiming a pass.
- [ ] **Step 4: NOT SCHEDULED check** — on a scratch copy as the coordinator: set a school calendar (Phil-IRI bosy, mosy1, eosy; skip mosy2, mosy3) for the year with data, `pull-cloud` not needed (writes mirror), `progress-report <S> <year>` → MOSY #2/#3 `NOT SCHEDULED`, other rounds as before.

---

### Task 4: ReminderViewModel, console, wiring, verify kit, docs

**Files:**
- Create: `lib/viewmodels/reminder_viewmodel.dart`, `lib/core/console/commands/reminder_commands.dart`
- Modify: `lib/console/main.dart`, `lib/main.dart` (register `ReminderViewModel`, `registerReminderCommands`), `CLAUDE.md` (Dashboard: D2 done), memory `todos.md` (NEXT → D3)
- Kit: `D:/0_CAPSTONE/verify/d2/`

**Interfaces:**
- Consumes: `RoundCalendarViewModel.scheduledRounds/status`, `NlaReportViewModel.progress` (once per school, `asOf: today`, threshold passed through), `ReportSettingsViewModel.effective`, `CrlaResultRepository.getBySection(sectionId, schoolYear:)`, `SectionRepository`, `StudentRepository`, `SchoolRepository` (local, for the superadmin's school list and names), `AuthViewModel`.
- Produces:
  - `const reminderHeadsUpDays = 7;`
  - `enum ReminderKind { overdue, inProgress, headsUp }`
  - `class SectionCompletion { final Section section; final int assessed; final int enrolled; double get share; }` (sections with `enrolled == 0` are never built)
  - `class CoordinatorReminder { final int schoolId; final CalendarInstrument instrument; final CalendarWindow window; final ReminderKind kind; final int days; final int sectionCount; final List<SectionCompletion> below; final double doneThreshold; String get message; }` — `days` = days until `opens_on` (heads-up), until `closes_on` (in progress, 0 = today), since `closes_on` (overdue).
  - `class SchoolReminders { final int schoolId; final String schoolName; final double doneThreshold; final List<CoordinatorReminder> reminders; }`
  - `Future<List<SchoolReminders>> coordinatorReminders(int? schoolId, String year, {DateTime? today, double? doneThreshold})` — `schoolId` null = every school (superadmin only; school-bound admin/coordinator → Forbidden unless it is their school; tutor → Forbidden). Schools ordered by name; schools with no reminders are kept with an empty list.
- Rules:
  - Per scheduled round (`scheduledRounds`), by `status(today)`: upcoming and opens within `reminderHeadsUpDays` → heads-up; open → in progress (always, even with all sections done); closed with ≥1 section below → overdue; else nothing.
  - Phil-IRI below = sections whose `ProgressReport.status(row, round) != 'DONE'` and enrolment > 0; `sectionCount` = sections with enrolment > 0.
  - CRLA (private `_crlaCompletion`): Grade 1–3 sections of the school/year; assessed = distinct `studentId`s of the section's learners with a `crla_results` row of that round and section; done when `assessed >= threshold * enrolled - 1e-9` (same comparison as progress).
  - An instrument with `sectionCount == 0` gives no reminders.
  - Order inside a school: overdue (largest `days` first), in progress (smallest `days` first), heads-up (smallest `days` first); ties by instrument then round order.
  - Messages (exact): `Phil-IRI MOSY #1 opens in 3 days (2026-11-10).` · `Phil-IRI MOSY #1 closes in 5 days: 3 of 8 sections below 85%.` / `closes today: …` / `all 8 sections done.` · `CRLA BOSY closed 12 days ago: 2 of 4 sections below 85%.` ("1 day", not "1 days"; percent without decimals unless fractional, e.g. `87.5%`).
- Console: `reminders-coordinator <schoolId|all> <year> [today=YYYY-MM-DD] [done=<percent>]` — per school a header `School <name> (#id) — done at 85%`, then one line per reminder, then indented `<grade>-<section>  12/20 (60.0%)` lines for its `below` sections; `No reminders.` for an empty school.

- [ ] **Step 1: Write the ViewModel and commands; wire both mains.**
- [ ] **Step 2: `dart analyze`** — no errors.
- [ ] **Step 3: Threshold edge check** — a scratch console probe (not committed) or kit step that shows a section at exactly the threshold counted as done (pick or set the threshold so `assessed / enrolled` of a real verify-DB section equals it, e.g. 17/20 → `done=85`).
- [ ] **Step 4: Verify kit** `D:/0_CAPSTONE/verify/d2/` (recipe in memory `verify-kits`; inspect the verify DB first for the coordinator's school, a year with Phil-IRI and, if any, CRLA data, and section enrolments). Files, all ids filled:
  - `1_settings.txt` — show / set 80 / show / region refused / reset / show.
  - `2_progress.txt` — calendar with a skipped Phil-IRI round; `progress-report` shows `NOT SCHEDULED`, saved threshold in the header; `done=` override changes the header only for that call.
  - `3_reminders.txt` — windows chosen so one `today` gives one overdue, one in progress and one heads-up round; `reminders-coordinator <S> <year> today=...`; skipped round absent.
  - `4_dates.txt` — the Review Focus #2 boundaries (opens in 7 / 8 days, closes today, closed 1 day ago).
  - `5_refusals.txt` — `reminders-coordinator all ...` as coordinator → Forbidden; another school → Forbidden; tutor → Forbidden; bad `done=0`/`done=150` → refused.
  - `6_no_calendar.txt` — a year with no windows → `No reminders.`; progress shows the old labels.
  The superadmin `all` path is run by me on the scratch copy (expected output kept in the kit as `expected_superadmin.txt`); the README says the kit's cloud rows (calendar, report settings) stay behind and rerunning is safe.
- [ ] **Step 5: Docs + handover** — `CLAUDE.md` (Dashboard: D2 reminders + `report_settings` done; Data model line for `report_settings`), memory `todos.md` NEXT → D3; commit message:

```
feat(dashboard): coordinator reminders and a saved done threshold

- report_settings (cloud migration 20261019040000 + SQLite v32 mirror):
  done_threshold (0.01-1, default 0.85) per region with school overrides;
  RLS as aral_settings, tutors read only
- ReportSettingsViewModel + report-settings-show/set/reset
- progress monitoring reads the saved threshold (done= stays a one-off
  override) and shows NOT SCHEDULED for rounds the school's calendar does
  not hold; without a calendar for the year it is unchanged
- ReminderViewModel.coordinatorReminders: per scheduled Phil-IRI/CRLA round,
  heads-up (opens within 7 days), in progress, overdue with the sections
  below the threshold; superadmin gets every school
- console: reminders-coordinator

Known follow-ups not included here:
- tutor reminders (D3)
- CRLA "assessed" = any crla_results row in the round, finished or not
```

(plus the `Co-Authored-By` line from the session's attribution reminder)
