# D5 CRLA/ARAL Trends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three more dashboard charts: CRLA reading profiles per round, ARAL sessions + attendance per month, and ARAL exits per Phil-IRI round (the Division report's definition).

**Architecture:** Three methods on the existing `TrendViewModel`, same `TrendChart` output. No rule is computed twice: the CRLA learner profile is the ARAL implementation report's rule (extracted to a shared helper), attendance rate is `AralAttendanceSummary.rate`, exits are `NlaSectionReport.band(round, NlaBand.glr)`. Sessions come through `AralSessionViewModel.tutorSessions/schoolSessions` (their access checks). No table, no migration, no SQLite bump (stays 33), no RLS change.

**Tech Stack:** Dart (no Flutter in `core/` or `viewmodels/`).

**Spec:** `docs/superpowers/specs/2026-10-19-dashboard-design.md` (section D4–D5). Builds on D4: `lib/viewmodels/trend_viewmodel.dart`, `lib/core/models/trend_chart.dart`, `lib/core/console/commands/trend_commands.dart`.

## Global Constraints

- Output is `TrendChart` / `TrendSeries` (D4), `null` = gap. `asOf` always a parameter (default today); only data dated on or before it counts.
- CRLA = Grade 1–3 sections; Division ARAL exits = Phil-IRI Grade 4–10 (that report's scope).
- Profile names come from the data, not a hardcoded list (spec). Known profiles are only used for **ordering** (`aralCrlaProfileOrder`), unknown names follow alphabetically.
- No migration, no SQLite bump, no RLS change. Done = `dart analyze` (no new errors), console run on a scratch copy of the verify DB, kit `D:/0_CAPSTONE/verify/d5/`, fresh reviewer, commit message handed over.

## Decisions for the owner (spec silent or in conflict with the code)

1. **Attendance rate = present ÷ (present + absent); excused don't count.** The spec says "present ÷ marked", but the existing `AralAttendanceSummary.rate` (tutor summary) already excludes excused. Using the spec's wording would make the chart disagree with `aral-tutor-summary`. Plan: reuse the existing rate. Say so if you want excused to count.
2. **CRLA profile per learner per round = the ARAL implementation report's rule**: latest attempt per variant (with a profile), the weakest across variants. One learner counts once per round. Option `variant=mt|fil|eng` = only that variant's latest attempt (what the cloud `crla_section_summary` counts). Learners with a result in the round but no profile (no story match, e.g. outside region 13) form a `No profile` series, shown only when not 0, so the totals match the learners assessed.
3. **Exits = the Division report's count** (learners at grade level in MOSY1–3/EOSY, Phil-IRI only). Not the roster's exits (`aral_enrollments` exit reason) and no CRLA Grades 1–3. Chart: two series, `ARAL (3-LD + 2-LD)` and `Exited (grade level)`; BOSY has the ARAL value and a gap for Exited (the report has no BOSY exit column). Region = one regional-total chart (like D4 bands). Sex filter M/F/T like `trend-bands`.
4. **ARAL activity scope = tutor or school (spec: "per tutor or school"), plus region.** New `TutorScope` (`tutor:<user id>` or `tutor:me`). A tutor may see only `tutor:me`; admin/coordinator their school's tutors; superadmin anyone. `section:ID` is refused (sessions belong to tutors, not sections). School chart = one series per tutor with sessions (by name) + `School total`; region = one series per school + `Region total` (like D4 completion).
5. **ARAL activity returns two charts** (`sessions` counts, `attendance` percent 0–100), because the units differ. x-axis = every month `YYYY-MM` from the first to the last month with a session on or before `asOf` (gaps filled: 0 sessions, `null` attendance). The UI formats month names.
6. Every other trend (D4 bands/completion, CRLA profiles, exits) keeps refusing tutors and `TutorScope` (`Forbidden: tutor scope is only for ARAL activity.`).

## Review Focus

1. **CRLA outside region 13** — every profile null: chart shows only `No profile`, never an empty chart that hides the assessed learners. Pinned: kit `1_crla.txt` (one injected result with no story match).
2. **Learner assessed twice in a round / in two variants** — counted once (latest attempt per variant, weakest). Pinned: kit `1_crla.txt` (second attempt + English result injected; expected count unchanged, profile = weaker).
3. **Month with sessions but no marks / only excused** — sessions value counted, attendance `null` (not 0%). Pinned: kit `3_activity.txt`.
4. **Exits equal the NLA report** — `trend-aral-exits school:1` equals the `nla-report` ARAL exited / ARAL total columns for the same `asof`. Pinned: kit `2_exits.txt` shows both.
5. **Access** — tutor asking `tutor:<other id>` or `school:1` → Forbidden; coordinator asking another school's tutor → Forbidden; `section:ID` on activity → refused with a message. Pinned: kit `4_access.txt`.

---

### Task 1: Shared CRLA learner profile + `crlaProfiles` + console

**Files:**
- Modify: `lib/core/services/aral_rules.dart` (add helper), `lib/viewmodels/aral_report_viewmodel.dart` (`_crlaProfile` → call the helper; output unchanged), `lib/viewmodels/trend_viewmodel.dart`, `lib/core/console/commands/trend_commands.dart`, `lib/console/main.dart`, `lib/main.dart` (new constructor args)

**Interfaces:**
- `String? aralCrlaLearnerProfile(Iterable<CrlaResult> results, CrlaRound round, String asOf, {String? variant})` in `aral_rules.dart` — body = the current `AralReportViewModel._crlaProfile`, plus the optional variant filter. `results` = one learner's.
- `TrendViewModel` gets `required StudentRepository students, required CrlaResultRepository crlaResults` (Task 2 adds more).
- `Future<TrendChart> crlaProfiles(TrendScope scope, String schoolYear, {String? variant, DateTime? asOf})`. Sections = the scope's Grade 1–3 sections of that year (`_resolve` then filter by grade 1–3). Learners = `students.getBySection`. Results = `crlaResults.getBySection(id, schoolYear:)`, grouped by student. x = `CrlaRound.values` with at least one counted learner (label `round.label`). Series = profile names seen, ordered per Global Constraints, then `No profile`. Title `CRLA reading profiles — <scope name> — <year>` (+ ` (<variant>)`).
- `variant` not in `mt|fil|eng` → `ViewModelException`.

- [ ] **Step 1:** Extract the helper; `aral-report` output for the verify DB unchanged (diff before/after).
- [ ] **Step 2:** VM method. `TutorScope` handling in `_resolve` lands in Task 2; here only add the class if needed to keep the sealed switch compiling.
- [ ] **Step 3:** Console `trend-crla-profiles <section:ID|school:ID|region> <year> [asof=YYYY-MM-DD] [variant=mt|fil|eng]`: table as `trend-bands` with a `Total assessed` row; empty x → `No CRLA results yet.`
- [ ] **Step 4:** `dart analyze`; console run: `trend-crla-profiles section:6 2025-2026` counts equal the per-learner profiles `crla-results` lists for that section (latest attempt per variant, weakest), and the Grade 1–3 BOSY/MOSY columns of `aral-report` for its ARAL learners.

---

### Task 2: `TutorScope` + `aralActivity` + console

**Files:**
- Modify: `lib/core/models/trend_chart.dart`, `lib/viewmodels/trend_viewmodel.dart`, `lib/core/console/commands/trend_commands.dart`, both entry points

**Interfaces:**
- `class TutorScope extends TrendScope { final String? tutorId; }` (`null` = me). `TrendScope.parse` accepts `tutor:me` and `tutor:<id>` (id kept as typed, not lowercased — user ids are case-sensitive strings; trim only).
- `TrendViewModel` gets `required AralSessionViewModel aralSessions, required AralSessionRepository aralSessionRepo, required UserRepository users`.
- `Future<({TrendChart sessions, TrendChart attendance})> aralActivity(TrendScope scope, String schoolYear, {DateTime? asOf})`.
  - Tutor: `aralSessions.tutorSessions(tutorId:, schoolYear:)` (its access check). School: `aralSessions.schoolSessions(schoolId:, schoolYear:)` (manager check), grouped by `tutorId`, names from `users.getById` (`fullName`, fallback the id). Region: superadmin check, every school by name. Section → `ViewModelException('ARAL activity is per tutor or school, not per section.')`.
  - Per month: sessions = count; attendance = `AralAttendanceSummary.of(marks of those sessions).rate * 100`, null when rate is null. Marks via `aralSessionRepo.getAttendance(sessionId)`. Totals = the same over all sessions of the chart.
  - Titles `ARAL sessions per month — <name> — <year>`, `ARAL attendance per month — ...`.
- `_resolve` refuses `TutorScope` (Decision 6).

- [ ] **Step 1:** Scope class + parse.
- [ ] **Step 2:** VM method.
- [ ] **Step 3:** Console `trend-aral-activity <tutor:ID|tutor:me|school:ID|region> <year> [asof=YYYY-MM-DD]`: both tables, sessions as integers, attendance with 1 decimal; no session → `No ARAL sessions yet.`
- [ ] **Step 4:** `dart analyze`; console run: totals equal `aral-tutor-summary` (sessions count and attendance %) for the same tutor; the `asof` cut drops later sessions.

---

### Task 3: `aralExits` + console

**Files:**
- Modify: `lib/viewmodels/trend_viewmodel.dart`, `lib/core/console/commands/trend_commands.dart`

**Interfaces:**
- `Future<TrendChart> aralExits(TrendScope scope, String schoolYear, {NlaSex sex = NlaSex.total, DateTime? asOf})`. Same school loop as `bandDistribution` (reuse it: factor the summed `NlaSectionReport` into one private method both call). x = `conducted` rounds. Series `ARAL (3-LD + 2-LD)` = `nlaValue(NlaCounts.sum([ld3(r), ld2(r)]), sex)`, `Exited (grade level)` = `nlaValue(band(r, NlaBand.glr), sex)`, null at BOSY.

- [ ] **Step 1:** Factor the sum out of `bandDistribution`; `trend-bands` output unchanged.
- [ ] **Step 2:** VM method + console `trend-aral-exits <section:ID|school:ID|region> <year> [asof=YYYY-MM-DD] [sex=M|F|T]`; empty → `No Phil-IRI results yet.`
- [ ] **Step 3:** `dart analyze`; console run equals `nla-report school:1` ARAL columns.

---

### Task 4: Review, kit, docs

- [ ] **Step 1:** Fresh reviewer on the diff (access paths, double counting, month gaps, null vs 0).
- [ ] **Step 2:** Kit `D:/0_CAPSTONE/verify/d5/` per the verify-kits recipe: fresh copy of the verify DB, fixed `asof`, files `1_crla.txt`, `2_exits.txt`, `3_activity.txt`, `4_access.txt`, `5_region.txt`, each with expected output.
- [ ] **Step 3:** CLAUDE.md module checklist: D5 done; spec D5 lines note Decisions 1–5. Commit message handed over (`feat(dashboard): crla and aral trend charts ...`).
