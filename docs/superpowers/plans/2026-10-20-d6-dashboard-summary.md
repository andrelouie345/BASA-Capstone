# D6 Dashboard Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One call, `DashboardViewModel.summary(year, {today})`, gives the signed-in user's home-screen numbers: tutor, school admin/coordinator, or superadmin (every school + regional totals).

**Architecture:** A new `DashboardViewModel` that owns no rules. It only calls existing public methods: `ReminderViewModel` (D2/D3), `RoundCalendarViewModel`, `NlaReportViewModel.progress/bosyMasterlist`, `SrpViewModel.candidates/classes`, `AralViewModel.schoolRoster/tutorRoster`, plus section/student/assignment repositories for plain counts. Two rules it needs that are private today get shared: the "active ARAL learner on a day" test (a helper in `aral_rules.dart`) and CRLA round completion (`ReminderViewModel.crlaCompletion`, made public). No table, no migration, no SQLite bump (stays 33), no RLS change.

**Tech Stack:** Dart (no Flutter in `core/` or `viewmodels/`).

**Spec:** `docs/superpowers/specs/2026-10-19-dashboard-design.md` (section D6). Builds on D1–D5.

## Global Constraints

- `today` is always a parameter (default now). Only data dated on or before it counts, as in progress, reminders and trends.
- CRLA = Grade 1–3 sections (`crlaGradeOf`), Phil-IRI = Grade 4–10 (`philIriGradeOf`). Progress, masterlist and SRP are Phil-IRI only (their existing scope).
- No number is computed twice: every figure is either a call to an existing ViewModel or a plain count of rows (sections, learners).
- Charts are not in `summary` (spec). The UI calls `TrendViewModel` itself.
- No migration, no SQLite bump, no RLS change. Done = `dart analyze` (no new errors), a console run on a scratch copy of the verify DB, kit `D:/0_CAPSTONE/verify/d6/`, a fresh reviewer, and a commit message handed over.

## Decisions for the owner (the spec is silent or vague here)

1. **School year is required, plus a list of years (owner chose option B, 2026-10-20).** `summary` always takes the year (BASA has no rule for which school year a date falls in; DepEd start dates move). `DashboardViewModel.schoolYears()` lists the school years that have sections on this device, latest first, so the UI can preselect the first. Console: `dashboard <year> [today=YYYY-MM-DD]` and `dashboard-years`.
2. **"ARAL active/exited" = the roster (`aral_enrollments`) on `today`.** Active = entered on or before `today` and not exited by then. Exited = exited on or before `today`, with a count per exit reason. A learner entered after `today` is not counted. This is a different number from the D5 exits chart, which uses the Division report's definition (Phil-IRI grade level). The dashboard shows the roster count because the spec says "roster".
3. **Current/next round per instrument** (school calendar, scheduled rounds only):
   - current = every round open on `today`; when none is open, the most recently closed round (marked closed);
   - next = the earliest upcoming round.

   Each round shows assessed/enrolled learners, the share, and sections done/sections at the saved threshold. Phil-IRI numbers come from `progress` (school total); CRLA numbers come from `crlaCompletion`. An instrument with no scheduled round lists no rounds, so the UI shows "no calendar".
4. **Regional totals = sums** of section/learner counts, ARAL roster, BOSY masterlist, SRP, and reminders per kind. No regional round row: each school can override the dates, so a "current round" for the region is undefined. Rounds stay per school.
5. **BOSY masterlist count** = learners listed, and separately how many of them were not assessed (the masterlist lists them too, flagged).
6. **SRP** = candidates, recommended (default 15 per section, as `srp-list`), classes, and learners in classes.
7. **Tutor learners** = learners of the tutor's assigned sections for that year. The ARAL roster count is separate, because it can include learners whose regular section is not theirs. Sessions held and last session come from `TutorReminders` (no second count).

## Review Focus

1. **School with no calendar or no Grade 4–10 sections**: zeros and empty round lists, never an exception. Pinned: kit `2_school.txt` runs on a school with only Grade 1–3 sections (or an empty one).
2. **Two rounds open at once** (overlapping windows, e.g. a school override): both are listed as current. Pinned: kit `2_school.txt` injects an overlapping window.
3. **ARAL learner entered or exited after `today`**: entered later is not counted; exited later is still active. Pinned: kit `1_tutor.txt` and `2_school.txt` use two `today=` values around an exit date.
4. **Figures equal their source commands for the same `today`**: Phil-IRI round % = `progress`; masterlist = `bosy-masterlist`; SRP = `srp-list` / `srp-classes`; reminders = `reminders-coordinator` / `reminders-tutor`. Pinned: every kit file prints the source command next to `dashboard`.
5. **Superadmin**: every school on the device is listed (also schools with no sections), totals equal the sum of the lines, and a school admin never sees another school. Pinned: kit `3_region.txt`, `4_access.txt`.

---

### Task 1: Shared rules (no behaviour change)

**Files:**
- Modify: `lib/core/services/aral_rules.dart`, `lib/viewmodels/reminder_viewmodel.dart`, `lib/core/console/commands/reminder_commands.dart`

**Interfaces:**
- `bool aralActiveOn(AralEnrollment e, String day)` and `bool aralExitedBy(AralEnrollment e, String day)` in `aral_rules.dart` (`day` = YYYY-MM-DD; compare the first 10 characters). This is the same test `tutorReminders` uses inline today; `tutorReminders` switches to the helper.
- `Future<List<SectionCompletion>> crlaCompletion(int schoolId, String year, CrlaRound round, {DateTime? today, double? doneThreshold})` on `ReminderViewModel`: public, with the same access check as `coordinatorReminders` for one school. It defaults to the saved threshold and wraps the existing private `_crlaCompletion`, which internal callers keep using.
- `String coordinatorRemindersText(List<SchoolReminders>)` and `String tutorRemindersText(TutorReminders)`: the current private `_text` / `_tutorText`, made public so `dashboard` prints reminders the same way.

- [ ] **Step 1:** Make the three changes.
- [ ] **Step 2:** `dart analyze`. On a scratch copy of the verify DB, the output of `reminders-coordinator` and `reminders-tutor` (kit d3 commands, same `today=`) is byte-identical before and after.

---

### Task 2: `DashboardViewModel` + wiring

**Files:**
- Create: `lib/viewmodels/dashboard_viewmodel.dart` (classes and the ViewModel, as in `reminder_viewmodel.dart`)
- Modify: `lib/console/main.dart`, `lib/main.dart` (construct + `vmRegistry.register('DashboardViewModel', ...)`)

**Interfaces (all in `dashboard_viewmodel.dart`):**
- `class SectionLearnerCount { final int sections; final int learners; }`
- `class AralRosterCount { final int active; final int exited; final Map<AralExitReason, int> exitedBy; }`, built from a roster list with `aralActiveOn` / `aralExitedBy`.
- `class RoundSnapshot { final CalendarInstrument instrument; final CalendarWindow window; final RoundStatus status; final int assessed; final int enrolled; final int sectionsDone; final int sectionCount; double? get share; }` (`share` is null when `enrolled == 0`).
- `class SchoolSummary { final School school; final double doneThreshold; final Map<CalendarInstrument, SectionLearnerCount> counts; final SectionLearnerCount otherGrades; final List<RoundSnapshot> current; final List<RoundSnapshot> next; final AralRosterCount aral; final int masterlistLearners; final int masterlistNotAssessed; final int srpCandidates; final int srpRecommended; final int srpClasses; final int srpClassLearners; final SchoolReminders reminders; }`. `otherGrades` holds sections that are neither CRLA nor Phil-IRI grades, so the totals still add up.
- `sealed class DashboardSummary { String get schoolYear; String get today; }`, with:
  - `TutorDashboard { final String tutorId; final String? tutorName; final List<(Section, int)> sections /* by grade, name; learner count */; final AralRosterCount aral; final TutorReminders reminders; }` (sessions held and last session are read from `reminders`);
  - `SchoolDashboard { final SchoolSummary school; }`;
  - `RegionDashboard { final List<SchoolSummary> schools /* by name */; final Map<CalendarInstrument, SectionLearnerCount> counts; final SectionLearnerCount otherGrades; final AralRosterCount aral; final int masterlistLearners, masterlistNotAssessed, srpCandidates, srpRecommended, srpClasses, srpClassLearners; final Map<ReminderKind, int> reminders; }`.
- Constructor takes (`required`): `AuthViewModel auth, RoundCalendarViewModel calendar, ReminderViewModel reminders, NlaReportViewModel reports, SrpViewModel srp, AralViewModel aral, ReportSettingsViewModel reportSettings, SchoolRepository schools, SectionRepository sections, StudentRepository students, TutorSectionAssignmentRepository assignments`, plus `Logger? logger` and `ScopedLogger(logger, 'DashboardViewModel')`.
- `Future<DashboardSummary> summary(String schoolYear, {DateTime? today})`:
  - not signed in → `ViewModelException('Not signed in.')`; the year is normalised (`FormatException` → `ViewModelException`);
  - tutor → `TutorDashboard` for `me.id`;
  - admin/coordinator with a school → `SchoolDashboard`;
  - superadmin → `RegionDashboard` over `schools.getAll()`.
- `Future<List<String>> schoolYears()`: distinct `sections.school_year` on this device (what the signed-in user's pull could read), latest first (sort by the first 4 digits, descending); signed in required. Empty list when there are no sections.
- Per school: Phil-IRI current/next rounds come from one `progress(..., asOf: today)` call (round status from `calendar.status`; sections done = rows whose `status == 'DONE'`). CRLA rounds come from `reminders.crlaCompletion`. The masterlist, SRP candidates/classes and `coordinatorReminders(schoolId, ...)` all get the same `today`.

- [ ] **Step 1:** Classes + `summary` for the school role.
- [ ] **Step 2:** Tutor and region branches.
- [ ] **Step 3:** Wire both entry points; `dart analyze` shows no new errors.

---

### Task 3: Console `dashboard` + kit + docs

**Files:**
- Create: `lib/core/console/commands/dashboard_commands.dart` (`registerDashboardCommands(registry, vm)`)
- Modify: both entry points (register), `CLAUDE.md` (module checklist: Dashboard done), spec D6 (note the Decisions as built)

- [ ] **Step 1:** `dashboard-years` (one year per line, latest first; `No school years on this device.` when empty) and `dashboard <year> [today=YYYY-MM-DD]`, with the `today=` parsing of `reminder_commands.dart` (a real date, no roll-over). Output:
  - tutor: sections with learner counts, ARAL active/exited (per reason), sessions held + last, then `tutorRemindersText`;
  - school: counts per instrument (+ other grades), a `Rounds` block (`[OPEN] Phil-IRI MOSY #1 2026-..–..: 120/150 (80.0%), 3/5 sections done at 85%`, then `[NEXT] ...`; `No calendar` when empty), ARAL, masterlist, SRP, then `coordinatorRemindersText`;
  - region: one compact block per school, then `REGION TOTAL`.
- [ ] **Step 2:** `dart analyze`; console run on a scratch copy of the verify DB as superadmin, coordinator and tutor (test accounts). Check every Review Focus line by hand against the source commands.
- [ ] **Step 3:** Fresh reviewer on the diff (access, double counting, `today` passed everywhere, empty schools).
- [ ] **Step 4:** Kit `D:/0_CAPSTONE/verify/d6/` per the verify-kits recipe: a fresh copy of the verify DB, fixed `today`, files `1_tutor.txt`, `2_school.txt`, `3_region.txt`, `4_access.txt`, each with the expected output and the source commands to compare against.
- [ ] **Step 5:** Docs; hand over the commit message (`feat(dashboard): per-role summary ...`).
