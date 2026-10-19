# D1 Round Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store assessment round windows (a region default plus per-school overrides) and answer "which rounds does this school hold, and is each one upcoming, open or closed on a given day".

**Architecture:** New cloud table `assessment_calendar` (RLS copied from `aral_settings`), mirrored read-only into SQLite like `aral_settings`/`srp_classes`. Writes go online through the Supabase repo and are then mirrored locally (the `SrpViewModel._writer/_cloudWrite/_mirror` pattern); reads come from the local copy. A pure-Dart rules file holds `calendarRounds` and the status function, so later pieces (D2–D6) reuse them without the ViewModel.

**Tech Stack:** Dart (no Flutter in `core/` or `viewmodels/`), sqflite_common, supabase-dart, Postgres 18 harness for RLS.

**Spec:** `docs/superpowers/specs/2026-10-19-dashboard-design.md` (section D1).

## Global Constraints

- Migration file newer than `20261019020000`: use `supabase/migrations/20261019030000_assessment_calendar.sql`. Idempotent (`if not exists`, `drop ... if exists`), safe to run twice. Never edit the baseline.
- SQLite: `local_database.dart` version 30 → **31**, new creator in its own file, `IF NOT EXISTS`, runs on every create and upgrade.
- RLS in the same piece. Every SECURITY DEFINER function `SET search_path = public`. `revoke all ... from anon`.
- `core/` and `viewmodels/` never import Flutter. The app only uses the anon key.
- Rounds: Phil-IRI `bosy, mosy1, mosy2, mosy3, eosy`; CRLA `bosy, mosy, eosy`. Only the Dart map `calendarRounds` knows which instrument has which round; SQL only checks the union.
- Dates are `YYYY-MM-DD` strings in Dart and SQLite, `date` in Postgres. `today` is always a parameter (default now).
- Console: one action per command; no comment lines in kit files.
- Done = `dart analyze` (no new errors), PG harness checks pass, console run on a scratch copy of the verify DB, verify kit under `D:/0_CAPSTONE/verify/d1/`, commit message handed to the owner (no git commands).

## Review Focus

1. **Override vs default resolution** — a school row (dates or skipped) wins over the region row for the same `(year, instrument, round)`; clearing the school row brings the default back. Pinned in Task 3 kit file `3_override.txt`.
2. **Status boundaries** — `today == opens_on` and `today == closes_on` are both `open`; the day after `closes_on` is `closed`; the day before `opens_on` is `upcoming`. Pinned in Task 3 kit file `4_status.txt` (three `today` values).
3. **Wrong round for the instrument** — `calendar-set ... crla mosy1 ...` and `... phil_iri mosy ...` are refused by the ViewModel with a message listing the valid rounds; nothing is written. Kit file `5_refusals.txt`.
4. **Who may write** — a tutor is refused (VM and RLS); a school coordinator cannot write the region row or another school's row; the superadmin can write both. Task 1 PG matrix + `5_refusals.txt`.
5. **Skipping** — only a school row can be skipped (a region row cannot: SQL check + VM message); skipping a round the region doesn't schedule is allowed (it pins the school's choice if a default is added later). Task 1 check + `3_override.txt`.

---

### Task 1: Cloud migration + RLS check

**Files:**
- Create: `supabase/migrations/20261019030000_assessment_calendar.sql`
- Scratch: `<scratchpad>/d1pg/steps.sql` (not committed)

**Interfaces:**
- Produces table `public.assessment_calendar(id bigint identity pk, school_id bigint null references schools(id) on delete cascade, school_year text not null, instrument text not null, round text not null, opens_on date, closes_on date, skipped boolean not null default false, updated_by uuid references users(id), updated_at timestamptz not null default now())`.

- [ ] **Step 1: Write the migration**
  - `school_year` check copied from `srp_classes` (`^\d{4}-\d{4}$`, second year = first + 1).
  - `instrument in ('phil_iri','crla')`, `round in ('bosy','mosy','mosy1','mosy2','mosy3','eosy')`.
  - Named check `assessment_calendar_window`: `(skipped and school_id is not null and opens_on is null and closes_on is null) or (not skipped and opens_on is not null and closes_on is not null and closes_on >= opens_on)`.
  - Unique index `assessment_calendar_key on (coalesce(school_id, 0), school_year, instrument, round)`.
  - Stamp trigger reusing the existing `public.aral_settings_stamp()` function (sets `updated_at`, `updated_by = auth.uid()`); do not create a second identical function.
  - RLS enabled; policies `assessment_calendar_select` and `assessment_calendar_write` with the exact expressions of `aral_settings_select` / `aral_settings_write` (baseline lines 4336–4342), table name swapped. `revoke all ... from anon`. Header comment in the style of `20261019010000_srp_classes.sql` (what, rules, RLS).

- [ ] **Step 2: Write the PG matrix** (`steps.sql`, harness from memory `pg-test-harness`: stubs + baseline + this migration twice; fixture schools 1–2, superadmin SA, coordinator C1 of school 1, tutor T1 of school 1)

Expected results, each as a `t()` row or a literal-id check (no `INSERT ... SELECT`, see the harness pitfall):

| as | action | want |
|---|---|---|
| SA | insert region row phil_iri bosy 2026-2027 2026-08-01..2026-08-15 | ok |
| SA | insert school 2 row | ok |
| C1 | insert school 1 row phil_iri bosy (override) | ok |
| C1 | insert region row | refused (42501) |
| C1 | insert school 2 row | refused |
| C1 | select | sees region + school 1 rows, not school 2 |
| T1 | select | sees region + school 1 rows |
| T1 | insert/update/delete school 1 row | refused / 0 rows changed |
| anon | select | permission denied |
| SA | insert region row with `skipped = true` | check violation (23514) |
| SA | insert closes_on < opens_on | 23514 |
| SA | insert second region row same key | 23505 |
| C1 | update own row | `updated_by` = C1, `updated_at` advanced |

- [ ] **Step 3: Run the harness**

Run: the recipe in memory `pg-test-harness` (export `PGCLIENTENCODING=UTF8`, migration applied twice).
Expected: both migration runs succeed; every row above matches; server stopped and `pgdata` removed.

- [ ] **Step 4: Checkpoint — owner applies the migration** in the Supabase SQL Editor of the dev project (Task 3's console run needs the cloud table). Give the owner the read-only check: `select policyname, cmd from pg_policies where tablename = 'assessment_calendar';` → 2 rows.

---

### Task 2: Model, rules, repositories, SQLite mirror, pull-cloud

**Files:**
- Create: `lib/core/models/assessment_calendar.dart`
- Create: `lib/core/services/calendar_rules.dart`
- Create: `lib/core/repositories/assessment_calendar_repository.dart`
- Create: `lib/core/data/local/calendar_local_schema.dart`
- Create: `lib/core/data/local/assessment_calendar_repository_sqlite.dart`
- Create: `lib/core/data/remote/assessment_calendar_repository_supabase.dart`
- Modify: `lib/core/data/local/local_database.dart` (v31 comment + `version: 31`, call `createCalendarLocalSchema` in `onCreate` and `onUpgrade`)
- Modify: `lib/core/console/commands/pull_commands.dart` (`'assessment_calendar': 'id'` in `_pullOrder` after `schools`/`users`; `'assessment_calendar'` in `_clearedTables` before `users`; not in `_originTables` — mirror-only)

**Interfaces:**
- Produces (model file):
  - `enum CalendarInstrument { philIri('phil_iri', 'Phil-IRI'), crla('crla', 'CRLA') }` with `dbValue`, `label`, `static CalendarInstrument parse(String)` (accepts `phil_iri`, `philiri`, `crla`, any case; throws `ArgumentError` otherwise).
  - `class CalendarWindow { int? id; int? schoolId; String schoolYear; CalendarInstrument instrument; String round; String? opensOn; String? closesOn; bool skipped; String? updatedBy; String? updatedAt; toMap(); factory fromMap(Map) }` — `toMap` omits `updated_*` (stamped by the DB) as `AralSetting.toMap` does; `fromMap` accepts SQLite `0/1` and Postgres `bool` for `skipped`, and trims Postgres dates to `YYYY-MM-DD`.
- Produces (rules file, pure):
  - `const Map<CalendarInstrument, List<String>> calendarRounds = {philIri: ['bosy','mosy1','mosy2','mosy3','eosy'], crla: ['bosy','mosy','eosy']};`
  - `enum RoundStatus { upcoming, open, closed }`
  - `RoundStatus roundStatus(CalendarWindow w, DateTime today)` — compares `YYYY-MM-DD` of local `today` with `opensOn`/`closesOn`; throws `StateError` for a skipped window.
  - `String roundLabel(CalendarInstrument i, String round)` — `BOSY`, `MOSY #1`…, CRLA `MOSY`.
- Produces (repository interface, `AssessmentCalendarRepository`):
  - `Future<List<CalendarWindow>> regionWindows(String schoolYear)` / `Future<List<CalendarWindow>> schoolWindows(int schoolId, String schoolYear)`
  - `Future<CalendarWindow?> find(int? schoolId, String schoolYear, CalendarInstrument instrument, String round)`
  - `Future<CalendarWindow> save(CalendarWindow w)` — cloud: find by key then insert or update (as `AralSettingRepositorySupabase.save`; no `onConflict`, the unique index is on an expression); throws when an update returns no row.
  - `Future<void> delete(int id)` — cloud; throws when nothing was deleted.
  - `Future<CalendarWindow> upsertWithId(CalendarWindow w)` / `Future<void> removeMirrored(int id)` — local only; Supabase impl throws `UnimplementedError`. SQLite impl throws `UnsupportedError` for `save`/`delete` (as `AralSettingRepositorySqlite._online`).
- SQLite table: same columns, `id INTEGER PRIMARY KEY`, `skipped INTEGER NOT NULL DEFAULT 0`, same CHECKs (school_year GLOB check as in `aral_local_schema.dart`), unique index on `(IFNULL(school_id, 0), school_year, instrument, round)`, no triggers.

- [ ] **Step 1: Write the six new files and the two modifications** per the interfaces above.
- [ ] **Step 2: Run `dart analyze`** — Expected: no errors (existing warnings accepted).
- [ ] **Step 3: Upgrade check** — open a scratch copy of `D:/0_CAPSTONE/verify/data` with the console (`exit` only), then `python -I` read-only: `PRAGMA user_version` = 31 and `assessment_calendar` exists with the unique index. Then run `pull-cloud` on that copy as `zztest.coord@basa.test` and confirm it completes (table empty or holding the school's rows).

---

### Task 3: ViewModel, console commands, wiring, verify kit

**Files:**
- Create: `lib/viewmodels/round_calendar_viewmodel.dart`
- Create: `lib/core/console/commands/calendar_commands.dart`
- Modify: `lib/console/main.dart`, `lib/main.dart` (construct, `vmRegistry.register('RoundCalendarViewModel', ...)`, `registerCalendarCommands(registry, vm)` next to the SRP block)
- Kit: `D:/0_CAPSTONE/verify/d1/` (recipe in memory `verify-kits`)

**Interfaces:**
- Consumes: Task 2 model, rules, repository; `AuthViewModel` (`requireActiveSession()`, `client`, signed-in user), `ScopedLogger`, `ViewModelException`.
- Produces (`RoundCalendarViewModel({required AuthViewModel auth, required AssessmentCalendarRepository local, required AssessmentCalendarRepository Function(SupabaseClient) cloud, Logger? logger})`):
  - `class CalendarEntry { final CalendarWindow window; final bool isOverride; bool get skipped; }`
  - `Future<CalendarWindow> setWindow(int? schoolId, String year, CalendarInstrument instrument, String round, DateTime opens, DateTime closes)`
  - `Future<CalendarWindow> skipRound(int schoolId, String year, CalendarInstrument instrument, String round)`
  - `Future<void> clearWindow(int? schoolId, String year, CalendarInstrument instrument, String round)` — throws `ViewModelException` when there is no such row.
  - `Future<List<CalendarEntry>> effectiveCalendar(int? schoolId, String year)` — region rows, each replaced by the school's row for the same instrument+round (`isOverride = true`), plus school-only rows; skipped overrides included (the UI shows them); ordered by instrument then the order in `calendarRounds`. `schoolId == null` = region rows only.
  - `Future<List<CalendarEntry>> scheduledRounds(int? schoolId, String year, CalendarInstrument instrument)` — effective entries of that instrument, not skipped.
  - `RoundStatus status(CalendarWindow w, {DateTime? today})` — delegates to `roundStatus(w, today ?? DateTime.now())`.
  - `String? lastMirrorWarning`.
- Rules in the VM: writes need an online session; role check as `SrpViewModel._manages` (superadmin for `schoolId == null` and any school; admin/coordinator only their own school; tutor never) → `Forbidden: ...`; round must be in `calendarRounds[instrument]` (message lists the valid ones); `closes >= opens`; year via the existing school-year check used by sections (or the same regex as the migration). Map Postgres `42501` → Forbidden, `23514`/`P0001` → "The database refused it: …", `23505` → retry not needed (find-then-write), rethrow others.
- Console (`calendar_commands.dart`, `<region|schoolId>` as in `aral-checkin-cutoff-set`):
  - `calendar-set <region|schoolId> <year> <phil_iri|crla> <round> <opens YYYY-MM-DD> <closes YYYY-MM-DD>`
  - `calendar-skip <schoolId> <year> <phil_iri|crla> <round>`
  - `calendar-clear <region|schoolId> <year> <phil_iri|crla> <round>`
  - `calendar-show <region|schoolId> <year> [today=YYYY-MM-DD]` — one line per entry: `Phil-IRI MOSY #1  2026-11-10 .. 2026-11-21  OPEN  (school override)`; skipped rows print `SKIPPED (school override)`; empty calendar prints `No rounds scheduled for <school> <year>.`

- [ ] **Step 1: Write the ViewModel and command file; wire both mains.**
- [ ] **Step 2: Run `dart analyze`** — Expected: no errors.
- [ ] **Step 3: Console run on a scratch copy** (memory `console-test-harness`), signed in as the test superadmin and `zztest.coord@basa.test`, using school 2026-2027. Command files, each ending in `exit`:
  - `1_region.txt` (superadmin): set region phil_iri bosy 2026-08-01..2026-08-15, mosy1 2026-11-10..2026-11-21, eosy 2027-03-15..2027-03-26; crla bosy 2026-08-01..2026-08-15; `calendar-show region 2026-2027`.
  - `2_school.txt` (coordinator of school S): `calendar-show S 2026-2027` → 4 region entries, none marked override.
  - `3_override.txt` (coordinator): set S phil_iri mosy1 2026-11-17..2026-11-28; skip S phil_iri eosy; skip S crla mosy (region doesn't schedule it — allowed); show → mosy1 override dates, eosy SKIPPED, crla mosy SKIPPED; clear S phil_iri mosy1; show → mosy1 back to region dates.
  - `4_status.txt`: `calendar-show S 2026-2027 today=2026-11-09` (mosy1 UPCOMING), `today=2026-11-10` (OPEN), `today=2026-11-21` (OPEN), `today=2026-11-22` (CLOSED).
  - `5_refusals.txt`: crla mosy1 → refused listing `bosy, mosy, eosy`; phil_iri mosy → refused; closes before opens → refused; coordinator sets region → Forbidden; coordinator sets another school → Forbidden; `calendar-skip region ...` → usage/Forbidden; tutor `calendar-set` → Forbidden; `calendar-clear` of a row that doesn't exist → "no such window".
  - `6_offline.txt`: `pull-cloud`, sign out, `calendar-show S 2026-2027` still prints from the local copy.
  Expected: every line as described; cloud rows cleaned up at the end of `5_refusals.txt` is NOT required (dev project is recycled), but the kit's README says which rows the run leaves behind.
- [ ] **Step 4: Build the verify kit** under `D:/0_CAPSTONE/verify/d1/` (fresh `data/` + `data_fresh/`, `launch.dart`, the six files with real ids, `expected_n.txt` via `annotate.py`, README). Kit files 1 and 3 overwrite cloud rows, so the README says to run them in order and that rerunning is safe (set = replace).
- [ ] **Step 5: Docs + handover** — update `CLAUDE.md` module checklist (Dashboard: D1 round calendar done), memory `todos.md` NEXT → D2; give the owner the commit message:

```
feat(dashboard): assessment round calendar with school overrides

- assessment_calendar (cloud migration 20261019030000 + SQLite v31 mirror):
  region default windows per school year/instrument/round, school overrides
  (other dates or skipped); RLS as aral_settings, tutors read only
- calendarRounds map (Phil-IRI bosy/mosy1-3/eosy, CRLA bosy/mosy/eosy) is the
  only place that pairs instruments with rounds; SQL checks the union only
- RoundCalendarViewModel: set/skip/clear windows online (mirrored locally),
  effective calendar (override wins), scheduled rounds, upcoming/open/closed
  status with today as a parameter
- console: calendar-set, calendar-skip, calendar-clear, calendar-show
- pull-cloud copies assessment_calendar

Known follow-ups not included here:
- CRLA round rules are still unknown; changes stay in calendarRounds plus at
  most a constraint swap in a new migration
- windows are not checked against each other (overlaps) or the school year
```

(plus the `Co-Authored-By` line from the session's attribution reminder)
