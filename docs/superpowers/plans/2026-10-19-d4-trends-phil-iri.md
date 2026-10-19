# D4 Phil-IRI Trends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chart data for the dashboard: the 7 Form 2b bands per Phil-IRI round, and the % of learners assessed per scheduled round against the saved done threshold, for a section, a school or the region.

**Architecture:** A new `TrendViewModel` that owns no rules: `bandDistribution` reads `NlaReportViewModel.report`, `completion` reads `NlaReportViewModel.progress`. The region scope loops schools through those same calls (no caching, spec "Out of scope"). Output is a pure-Dart `TrendChart` (no chart library); the UI team draws it. No table, no migration, no SQLite bump, no new RLS.

**Tech Stack:** Dart (no Flutter in `core/` or `viewmodels/`).

**Spec:** `docs/superpowers/specs/2026-10-19-dashboard-design.md` (section D4–D5). Patterns: `lib/viewmodels/reminder_viewmodel.dart` (superadmin school loop), `lib/core/console/commands/reminder_commands.dart` (option parsing).

## Global Constraints

- `TrendChart { title, xLabels, series: [{name, values}], referenceLine? }`, pure Dart, in `lib/core/models/trend_chart.dart`.
- Scope = section / school / region. Region = superadmin only; section/school = admin/coordinator of that school or the superadmin (the access of `NlaReportViewModel.reportSections`). Tutors: refused (no tutor charts in the spec; D6 tutor summary has none).
- Phil-IRI only (Grade 4–10 sections). `asOf` is always a parameter (default today).
- Completion: unscheduled rounds left out; reference line = the saved done threshold. Bands: counts, not percents.
- No migration, no SQLite version bump (stays 33), no RLS change (reads existing data through existing VMs).
- Done = `dart analyze` (no new errors), console run on a scratch copy of the verify DB, kit `D:/0_CAPSTONE/verify/d4/`, fresh reviewer, commit message handed over.

## Decisions for the owner (spec is silent or ambiguous)

1. **Region bands = one chart of regional totals**, not one series per school: 7 bands × N schools does not fit one chart. A per-school band chart = call the school scope. Region completion does follow the spec: one series per school + `Region total`.
2. **School completion = one series (the school total)**, not one per section (the progress report already has the per-section table).
3. **Band x-axis = rounds someone in the scope took** (NLA `conducted`); untaken rounds would be flat zeros.
4. **Region reference line** = the threshold when every school in the chart has the same effective one, else none (null) — schools can override it, so a single regional line would lie.
5. **Values:** bands = learner counts (sex filter M/F/T, default T, as the NLA report); completion = percent 0–100 (not rounded; console prints 1 decimal), `null` = gap (round not scheduled at that school, or nobody enrolled).

## Review Focus

1. **No results / no sections yet** — empty x-axis, console prints `No Phil-IRI results for <scope> in <year>.` (bands) / `No Grade 4-10 sections ...` (completion), never a crash or a chart of zeros. Pinned: kit `3_empty.txt`.
2. **Mixed calendars in the region** — school A holds MOSY2, school B skips it: x-axis has MOSY2, B's value is null, `Region total` for MOSY2 counts only A's learners. Pinned: kit `4_region.txt`.
3. **School with no Phil-IRI calendar** — every round counts (progress's existing rule); all 5 rounds on the axis. Pinned: kit `2_school.txt`.
4. **Access** — coordinator asking `region` or another school's section → `Forbidden`; tutor → `Forbidden`. Pinned: kit `5_access.txt`.
5. **Consistency** — the chart numbers equal the existing `nla-report` / `progress` outputs for the same school and date (no second count). Pinned: kit `2_school.txt` shows both.

---

### Task 1: `TrendChart` + `TrendViewModel.bandDistribution` + console + wiring

**Files:**
- Create: `lib/core/models/trend_chart.dart`, `lib/viewmodels/trend_viewmodel.dart`, `lib/core/console/commands/trend_commands.dart`
- Modify: `lib/console/main.dart`, `lib/main.dart` (construct, register `'TrendViewModel'`, `registerTrendCommands`)

**Interfaces:**
- `class TrendSeries { final String name; final List<num?> values; }` (one value per x label).
- `class TrendChart { final String title; final List<String> xLabels; final List<TrendSeries> series; final double? referenceLine; }`.
- `sealed class TrendScope` with `TrendScope.section(int sectionId)`, `TrendScope.school(int schoolId)`, `TrendScope.region()`; `static TrendScope parse(String)` for `section:ID`, `school:ID`, `region` (throws `FormatException`).
- `TrendViewModel({required AuthViewModel auth, required SchoolRepository schools, required SectionRepository sections, required NlaReportViewModel nla, Logger? logger})`, `ScopedLogger` name `'TrendViewModel'`.
- `Future<TrendChart> bandDistribution(TrendScope scope, String schoolYear, {NlaSex sex = NlaSex.total, DateTime? asOf})`.
- Section scope: `nla.report(schoolId: section.schoolId, sectionIds: {id})`; school: `nla.report(schoolId)` → `total`; region: superadmin check, then every school from `schools.getAll()` (by name) that has Grade 4–10 sections that year, summed with `NlaSectionReport.addAll`. Series = `NlaBand.values` in order, name = `band.label`; x = `PhilIriRound.values` in `conducted`, label = `round.label`.

- [ ] **Step 1:** Model + scope + VM method.
- [ ] **Step 2:** Console `trend-bands <section:ID|school:ID|region> <year> [asOf=YYYY-MM-DD] [sex=M|F|T]`, printing a table: one row per band, one column per round, plus a `Total assessed` row. Reuse the reminder commands' date check (`calendarDate`).
- [ ] **Step 3:** Wire both entry points. `dart analyze` → no new errors.
- [ ] **Step 4:** Console run on a scratch copy: `trend-bands school:1 2025-2026` numbers equal the `nla-report` totals (T columns) for the same `asOf`.

---

### Task 2: `TrendViewModel.completion` + console

**Files:**
- Modify: `lib/viewmodels/trend_viewmodel.dart`, `lib/core/console/commands/trend_commands.dart`, wiring (add `ReportSettingsViewModel` only if `ProgressReport.doneThreshold` is not enough — it should be).

**Interfaces:**
- `Future<TrendChart> completion(TrendScope scope, String schoolYear, {DateTime? asOf})`.
- Per school: `nla.progress(schoolId, sectionIds?)`. x = `PhilIriRound.values` where at least one school in the chart `isScheduled(r)`. Value = `share(r) * 100`, null if not scheduled there or `enrolment.total == 0`. Section/school: one series (section name / `School total`), `referenceLine = doneThreshold * 100`. Region: one series per school (`schoolName`) + `Region total` = Σ assessed / Σ enrolled over the schools that schedule that round; reference line per Decision 4.

- [ ] **Step 1:** VM method.
- [ ] **Step 2:** Console `trend-completion <scope> <year> [asOf=YYYY-MM-DD]`: one row per series, one column per round (`.` for null), last line `Done threshold: 85.0%` or `Done threshold: differs per school`.
- [ ] **Step 3:** `dart analyze`; console run: `trend-completion school:1 2025-2026` equals the `progress` SCHOOL TOTAL `%` columns; a `calendar-skip` for MOSY2 removes that column.

---

### Task 3: Review, kit, docs

- [ ] **Step 1:** Fresh reviewer on the diff (access paths, null handling, region sums).
- [ ] **Step 2:** Kit `D:/0_CAPSTONE/verify/d4/` per [verify-kits]: fresh copy of the verify DB, fixed `asOf`, files `1_bands_section.txt`, `2_school.txt`, `3_empty.txt`, `4_region.txt` (second school + calendar override injected), `5_access.txt`, each with expected output.
- [ ] **Step 3:** CLAUDE.md module checklist: D4 done. Commit message handed over (`feat(dashboard): phil-iri trend charts ...`).
