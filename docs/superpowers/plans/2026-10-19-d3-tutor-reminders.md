# D3 Tutor Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a tutor a list of unfinished work: learners not yet assessed in open/closed rounds, check-ins due, ARAL learners without an IRIP, and no session lately (with a saved `idle_session_days`).

**Architecture:** `ReminderViewModel.tutorReminders` reads only this device's copy, like D2. The per-learner "assessed" test is pulled out of `progress` into one public `NlaReportViewModel` helper, and the CRLA per-section count into one private helper both reminder kinds use. `tutor_section_assignments` is cloud-only today, so it gets a read-only SQLite mirror (v33) filled by `pull-cloud`. `idle_session_days` is a new `aral_settings` key with a cloud check (new migration).

**Tech Stack:** Dart (no Flutter in `core/` or `viewmodels/`), sqflite_common, supabase-dart, Postgres 18 harness.

**Spec:** `docs/superpowers/specs/2026-10-19-dashboard-design.md` (section D3). Patterns: D2 plan `docs/superpowers/plans/2026-10-19-d2-coordinator-reminders.md`.

## Global Constraints

- Migration `supabase/migrations/20261019060000_aral_idle_session_days.sql` (newer than `20261019050000`), idempotent, header `App update required on all devices: no` (a new optional key; older apps never write it), listed in README 2b. Never edit the baseline.
- SQLite `local_database.dart` version 32 → **33**, `IF NOT EXISTS`, runs on create and every upgrade.
- `idle_session_days`: whole number **1–60**, default **7**. Key absent = default.
- Phil-IRI = Grade 4–10 sections, CRLA = Grade 1–3. Checkpoints = `aralCheckinCheckpoints` (16, 32). `today` is always a parameter; nothing dated after `today` counts (sessions, results, check-ins).
- Tutors are reminded per learner even if the section passed the done threshold.
- No new cloud RLS (D3 reads existing tables); the PG harness proves a tutor sees no learner outside their sections.
- Done = `dart analyze` (no new errors), PG harness passes, D2 kit `D:/0_CAPSTONE/verify/d2` files give the same output (regression), console run on a scratch copy, kit `D:/0_CAPSTONE/verify/d3/`, commit message handed over.

## Review Focus

1. **Tutor with no assigned sections / no ARAL learners** — prints `No reminders.`, never "0 learners". Pinned: Task 4 kit `3_tutor_none.txt`.
2. **Late joiner** — a learner entered after session 16 still owes the 16 check-in under the spec rule (tutor's session count). Flagged as an open question for the owner; kit shows the case either way.
3. **Sessions/results dated after `today`** — ignored: session 17 on `today+1` does not trigger the 16→ check, a result dated tomorrow leaves the learner "not assessed". Pinned: Task 4 kit `4_dates.txt`.
4. **Access** — a tutor asking for another tutor's id → `Forbidden`; school admin for a tutor of another school → `Forbidden`; `me` as admin → refused (admins have no tutor reminders). Pinned: Task 4 kit `5_access.txt`.
5. **Pull after a tutor sign-in leaves only the tutor's assignment rows; an admin pull holds the whole school's** — pinned: Task 2 step 3.

---

### Task 1: `idle_session_days` — migration, setting, console

**Files:**
- Create: `supabase/migrations/20261019060000_aral_idle_session_days.sql`
- Modify: `lib/core/services/aral_rules.dart`, `lib/core/models/aral_setting.dart` (keys comment), `lib/viewmodels/aral_checkin_viewmodel.dart`, `lib/core/console/commands/aral_checkin_commands.dart`, `README.md` (2b list)

**Interfaces:**
- Produces `class AralSessionSettings { static const idleSessionDaysKey = 'idle_session_days'; static const defaults = AralSessionSettings(idleSessionDays: 7); final int idleSessionDays; factory AralSessionSettings.fromMap(Map<String, Object?>) }` — bad/absent values fall back to 7 (as `AralCheckinSettings`).
- `AralCheckinViewModel.idleSessionDaysLayers(int? schoolId) → Future<({int? region, int? school, int effective})>` (online), `setIdleSessionDays(int? schoolId, int days) → Future<AralSetting>` (online, merges the map, refuses outside 1–60, mirrors), `localSessionSettings(int schoolId) → Future<AralSessionSettings>` (local).

- [ ] **Step 1:** Migration: `ALTER TABLE aral_settings DROP CONSTRAINT IF EXISTS aral_settings_idle_session_days; ADD CONSTRAINT ... CHECK (NOT (settings ? 'idle_session_days') OR (jsonb_typeof(...) = 'number' AND value between 1 and 60 AND value = trunc(value)))`. Header in the D2 style.
- [ ] **Step 2:** PG harness: SA region `{"idle_session_days": 10}` ok; 0, 61, 7.5, `"7"` → 23514; C1 school 1 row ok; T1 write refused; migration applied twice.
- [ ] **Step 3:** Owner applies; check `select conname from pg_constraint where conname = 'aral_settings_idle_session_days';` → 1 row.
- [ ] **Step 4:** Settings class + VM methods. `resetSchoolSettings` message now says it clears the cut-off, SHARP switch and idle days.
- [ ] **Step 5:** Console `aral-idle-days [schoolId]` (Default/Region/School/Applies, as `aral-checkin-cutoff`) and `aral-idle-days-set <region|schoolId> <1-60>`. Run: set region 10, school 14 → show prints `Applies: 14 days`; `aral-idle-days-set 1 0` → refused.

---

### Task 2: Local mirror of `tutor_section_assignments` (SQLite v33)

**Files:**
- Create: `lib/core/data/local/tutor_section_assignment_repository_sqlite.dart`
- Modify: `lib/core/repositories/tutor_section_assignment_repository.dart` (add `upsertWithId`), `lib/core/data/remote/tutor_section_assignment_repository_supabase.dart` (`upsertWithId` throws `UnimplementedError`), `lib/core/data/local/local_database.dart` (table + v33), `lib/core/console/commands/pull_commands.dart`, `lib/console/main.dart`, `lib/main.dart`

**Interfaces:**
- SQLite table `tutor_section_assignments (id INTEGER PRIMARY KEY, tutor_id TEXT NOT NULL, section_id INTEGER NOT NULL REFERENCES sections(id), assigned_by TEXT, assigned_at TEXT, UNIQUE (tutor_id, section_id))`.
- `TutorSectionAssignmentRepositorySqlite`: `getByTutor`, `getBySection`, `upsertWithId` read/mirror; `create`/`delete` throw (writes stay online in `TutorSectionAssignmentViewModel`). Local rows have no `tutorFullName`.

- [ ] **Step 1:** Table + version bump (comment line `v33: tutor_section_assignments mirror (D3)`).
- [ ] **Step 2:** Repo + `pull_commands.dart`: pulled after `sections`, cleared with the data tables, select columns without the joins.
- [ ] **Step 3:** Console run: `pull-cloud` as coordinator → row count = cloud `select count(*) from tutor_section_assignments` for school 1; as tutor → only the tutor's rows.

---

### Task 3: Shared "assessed" helpers (no behaviour change)

**Files:**
- Modify: `lib/viewmodels/nla_report_viewmodel.dart`, `lib/viewmodels/reminder_viewmodel.dart`

**Interfaces:**
- `static Set<PhilIriRound> NlaReportViewModel.assessedIn(PhilIriReportResults r)` — the one definition of "assessed in a round" (today `r.counted`, with the "her rule" comment moved onto it). `progress` calls it on the `reportResults` it already fetches (it still needs `res.gst` for GST takers, so no second call).
- `NlaReportViewModel.assessedPhilIriRounds({required int studentId, required int sectionId, required String schoolYear, required String asOf}) → Future<Set<PhilIriRound>>` = `assessedIn(await reportResults(...))`; no role check (callers check access). Used by tutor reminders.
- `ReminderViewModel._crlaAssessed(int sectionId, String year, CrlaRound round, String asOf, Set<int> learners) → Future<Set<int>>` (student ids); `_crlaCompletion` uses it.

- [ ] **Step 1:** Refactor. **Step 2:** `dart analyze`. **Step 3:** rerun D2 kit files and an NLA progress kit file → identical output except timestamps.

---

### Task 4: `tutorReminders` + console + PG check + kit

**Files:**
- Modify: `lib/viewmodels/reminder_viewmodel.dart` (new deps: `TutorSectionAssignmentRepository` local, `AralEnrollmentRepository`, `AralSessionRepository`, `AralIripRepository`, `AralCheckinRepository`, `AralSettingRepository` local), `lib/core/console/commands/reminder_commands.dart`, `lib/console/main.dart`, `lib/main.dart`

**Interfaces:**
- `enum TutorReminderKind { overdueAssessment, checkinDue, openAssessment, noIrip, noSessionLately }` (display order).
- `class ReminderLearner { final int studentId; final String lrn; final String name; final int? enrollmentId; }`
- `class TutorReminder { final TutorReminderKind kind; final String message; final Section? section; final CalendarInstrument? instrument; final CalendarWindow? window; final int? checkpoint; final int? days; final List<ReminderLearner> learners; }`
- `class TutorReminders { final String tutorId; final String schoolYear; final int sessionsHeld; final String? lastSession; final int idleSessionDays; final List<TutorReminder> reminders; }`
- `Future<TutorReminders> tutorReminders(String tutorId, String year, {DateTime? today})`.

Rules (spec D3, decided details):
1. **Access:** tutor → own id only; school admin/coordinator → a tutor whose `users.school_id` (local users table, else the school of their assigned sections) is theirs; superadmin → any. Unknown id → `No tutor <id> on this device.`
2. **Assessments:** sections = local assignments of the tutor ∩ `sections.school_year == year`. Per section's school, per `scheduledRounds` of the matching instrument with status open/closed: learners of the section (`getBySection`, sorted by last, first name) not assessed by `today` → one reminder per (section, round): closed → `overdueAssessment` ("Phil-IRI MOSY 1 closed 12 days ago: 3 of 30 learners in Grade 5 Rizal not assessed"), open → `openAssessment` ("… closes in 5 days: …"). Nobody missing → no reminder. Upcoming → nothing (heads-up is the coordinator's).
3. **Check-ins:** `sessionsHeld` = tutor's sessions of the year with `held_on <= today`. Per checkpoint ≤ sessionsHeld, per active roster learner (`aral_enrollments.tutor_id`, year) whose `toolFor(keyStage, track, checkpoint)` exists and who has no check-in at a tool of that checkpoint dated `<= today` → one `checkinDue` reminder per checkpoint listing them.
4. **No IRIP:** active roster learners with no `aral_irip_weeks` rows → one reminder listing them.
5. **No session lately:** active roster not empty and (no session `<= today` this year → "No ARAL session yet this school year", or `today − last held_on > idleSessionDays` → "Last ARAL session 9 days ago (2027-02-01)"). `idleSessionDays` from the school's local `aral_settings` (`localSessionSettings`).
6. **Order:** kind order above; within a kind: overdue by days since close (oldest first), open by closes soonest, then grade, section, instrument, round.

- [ ] **Step 1:** Implement + `dart analyze`.
- [ ] **Step 2:** Console `reminders-tutor <tutorId|me> <year> [today=YYYY-MM-DD]`: header `Tutor <name or id> — <n> sessions held, last <date|none>, idle after <N> days`, then `[OVERDUE] / [CHECK-IN] / [IN PROGRESS] / [NO IRIP] / [NO SESSION]` lines, learners indented `LRN  Last, First`. `No reminders.` when empty.
- [ ] **Step 3:** PG harness (no migration change): as T1, `select` on `students`, `enrollments`, `aral_enrollments`, `tutor_section_assignments` returns only rows of T1's sections/roster; a student of an unassigned section → 0 rows.
- [ ] **Step 4:** Fresh reviewer (most capable model) on the whole D3 diff.
- [ ] **Step 5:** Kit `D:/0_CAPSTONE/verify/d3/` with fixed `today` dates: `1_settings.txt` (idle days), `2_tutor.txt` (each reminder kind), `3_tutor_none.txt`, `4_dates.txt` (day boundaries, after-today rows), `5_access.txt`, plus expected files and README.
- [ ] **Step 6:** Commit message; update `todos` memory (NEXT = D4).

## Owner decisions (2026-10-19)

1. **Check-in due for late joiners:** keep the spec rule — the *tutor's* session count; a learner who joined at session 20 is still due the after-16 check-in.
2. **Who may call `reminders-tutor`:** the tutor, the school's admin/coordinator, and the superadmin.
