# Dashboard module — design

Status: approved by the owner 2026-10-19. Backend only (models, repos, ViewModels, console, SQL); the UI team draws everything.
Built piece by piece (D1 → D6); the owner runs `/clear` after every piece, so this file is the source of truth between pieces.

## Goal

A home screen per role made mostly of numbers (A), plus reminders (B: coordinators see assessments not done yet,
tutors see their unfinished work), plus trend charts over the school year (C). Each part reuses existing ViewModels;
no rule is computed twice.

## Structure (approach 1: small ViewModels, one per concern)

| ViewModel | Piece | Purpose |
|---|---|---|
| `RoundCalendarViewModel` | D1 | assessment round windows (default + school override), which rounds are scheduled/open/closed |
| `ReminderViewModel` | D2, D3 | coordinator reminders (D2), tutor reminders (D3) |
| `TrendViewModel` | D4, D5 | chart series |
| `DashboardViewModel` | D6 | per-role summary numbers; calls the others, owns no rules |

Each has its own `ScopedLogger`, its own console command file in `lib/core/console/commands/`, and is wired into both
`lib/console/main.dart` and `lib/main.dart`. They only call public methods of existing ViewModels/repos
(`NlaReportViewModel.report/progress/bosyMasterlist`, `SrpViewModel`, `AralReportViewModel`, ARAL session/IRIP/check-in
repos, `crla_results`).

Every piece: new migration (if any) newer than the last one (`20261019020000` at design time), SQLite mirror with a
`local_database.dart` version bump (30 at design time), RLS in the same piece, PG-harness RLS check, `dart analyze`,
console run on the verify DB, verify kit under `D:/0_CAPSTONE/verify/<piece>/` (fixed `today` dates), commit message.

## D1 — Round calendar

Table `assessment_calendar` (cloud migration + identical SQLite table):

| column | notes |
|---|---|
| `id` | bigint identity |
| `school_id` | null = default row (superadmin); set = that school's override |
| `school_year` | e.g. `2026-2027` (same format as `sections.school_year`) |
| `instrument` | text, check `in ('phil_iri','crla')` |
| `round` | text, check `in ('bosy','mosy','mosy1','mosy2','mosy3','eosy')` |
| `opens_on`, `closes_on` | date, nullable |
| `skipped` | boolean default false — a school override that removes a round the default schedules |
| `updated_by`, `updated_at` | as in `aral_settings` |

- Checks: `skipped` OR (`opens_on` and `closes_on` both set and `closes_on >= opens_on`). Skipped rows have no dates.
- Unique: `(coalesce(school_id, 0), school_year, instrument, round)`.
- Instrument ↔ round validity: `calendarRounds` (Phil-IRI: bosy, mosy1-3, eosy; CRLA: bosy, mosy, eosy) is built from
  the `PhilIriRound` / `CrlaRound` enums, and since 2026-10-19 (D2 fix) the cloud enforces the same pairing
  (`assessment_calendar_round_pairing`, migration 20261019050000). CRLA rules are not known yet (owner 2026-10-19): a
  change = the enum plus one migration swapping the assessment round check and the pairing (see `lib/core/CLAUDE.md`).
  The local mirror has no pairing check on purpose; rows the app doesn't know are ignored on read and shown as INVALID.
  A rounds change needs the app update on every device first: older apps can't pull data in unknown rounds.
- RLS (copy of `aral_settings`): select = `is_superadmin()` OR `school_id IS NULL` OR own school (tutors read too);
  write = superadmin, or admin/coordinator with `school_id IS NOT NULL AND school_id = current_user_school_id()`.
  Tutors cannot write.
- A round is **scheduled** for a school only when its effective row (school override wins over default) exists and is
  not skipped. No row = not scheduled = no reminders (e.g. a school running only one MOSY).

`RoundCalendarViewModel`:
- `setWindow(schoolId?, year, instrument, round, opens, closes)`, `skipRound(schoolId, ...)`, `clearWindow(...)`
  (clearing an override falls back to the default).
- `effectiveCalendar(schoolId, year)` — every window, marked default vs override.
- `scheduledRounds(schoolId, year, instrument)`.
- `status(window, today)` → `upcoming` / `open` (`opens_on <= today <= closes_on`) / `closed`. `today` is always a
  parameter (default now) so kits can test any date.

Console: `calendar-set`, `calendar-skip`, `calendar-clear`, `calendar-show <school> <year>`.

## D2 — Coordinator reminders (+ saved done threshold, + progress fix)

**`report_settings` table** (copy of the `aral_settings` pattern): `school_id` null = default, else school override;
`settings` jsonb with check `done_threshold` number between 0.01 and 1; same RLS as `aral_settings`. Progress
monitoring and reminders read the saved value (default 0.85 when no row); a passed parameter is still allowed as a
one-off override. Console `report-settings-set/show`. Separate from `aral_settings` because the threshold is not an
ARAL rule.

**Progress fix:** a round the school does not hold shows `NOT SCHEDULED` instead of `NO MOSY`/etc. With no calendar
for that year, progress behaves exactly as before (existing NLA/progress kits must still pass).

`ReminderViewModel.coordinatorReminders(schoolId, year, {today, doneThreshold})` — per instrument, per scheduled round:

| round status | reminder |
|---|---|
| upcoming, opens within 7 days | heads-up ("opens in 3 days") |
| open | in progress ("closes in 5 days: 3 of 8 sections below 85%" + section list with %) |
| closed, sections still below threshold | overdue ("closed 12 days ago" + section list) |
| closed, all done | none |

- Phil-IRI (G4-10): from `NlaReportViewModel.progress` — same definition of "done".
- CRLA (G1-3): share of learners with a `crla_results` row in that round per section — its own small private method.
- Order: overdue (oldest first), in progress (closing soonest), heads-up.
- School admin/coordinator: own school. Superadmin: every school, grouped by school.
- Console: `reminders-coordinator <school> <year> [today] [threshold]`.

## D3 — Tutor reminders

`ReminderViewModel.tutorReminders(tutorId, year, {today})`. Scope: the tutor's `tutor_section_assignments` sections
and their ARAL roster (`aral_enrollments.tutor_id`, active).

1. **Learners not assessed** — per scheduled round that is open or closed (overdue), per assigned section of the right
   grade (Phil-IRI 4-10, CRLA 1-3): learners with no result in that round (names + LRNs). The per-learner "assessed"
   test is extracted into one shared helper in `NlaReportViewModel` that progress also uses. CRLA again its own
   private method. Tutors are reminded about individual learners even if the section passed the threshold (approved).
2. **Check-in due** — the tutor has held ≥16 (or ≥32) sessions and an active learner whose key stage/track has a
   check-in tool at that checkpoint has no attempt at it. No tool → no reminder.
3. **No IRIP** — active ARAL learner with no `aral_irip_weeks` rows.
4. **No session lately** — tutor has active ARAL learners and the last `aral_sessions.held_on` is more than N days
   before `today`, or no session this school year. N = `aral_settings.settings.idle_session_days` (default 7; new check
   constraint like `checkin_pass_pct`, in D3's migration).

Order: overdue assessments, check-ins due, open-round assessments, no IRIP, no session lately.
RLS: nothing new; verify in the PG harness that a tutor cannot see learners outside their sections.
Console: `reminders-tutor <tutorId|me> <year> [today]`; set `idle_session_days` via the existing ARAL settings command
if it accepts the key, else add one.

## D4–D5 — Trends

Common shape `TrendChart { title, xLabels (rounds or months), series: [{name, values}], referenceLine? }` (pure Dart,
no chart library). Scope: section / school / region (superadmin: one series per school + regional total; region loops
schools through the existing per-school ViewModels).

- D4 `bandDistribution(scope, year)` — 7 Form 2b bands per Phil-IRI round, from `NlaReportViewModel.report`.
- D4 `completion(scope, year)` — % assessed per round from `progress`, saved threshold as reference line; unscheduled
  rounds left out.
- D5 `crlaProfiles(scope, year)` — counts per `reading_profile` per CRLA round; profile names come from the data,
  not a hardcoded list.
- D5 `aralActivity(scope, year)` — sessions held per month and attendance rate (present ÷ marked) per month, per tutor
  or school.
- D5 `aralExits(scope, year)` — exited-by-round using the NLA/Division report's definition (no second count).
- D5 as built (owner 2026-10-20): CRLA = one count per learner per round by the ARAL report's rule (latest attempt
  per variant, the weakest; `variant=` limits to one; `No profile` series); attendance = present ÷ (present + absent),
  the existing `AralAttendanceSummary.rate` (excused don't count), months `YYYY-MM` first to last session with gaps
  filled; activity scope tutor (`tutor:ID|me`) / school / region, not section, two charts (sessions, attendance);
  exits = ARAL (3-LD + 2-LD) and exited (GLR, none at BOSY), Phil-IRI only; tutors use only `tutor:me` activity.
  Plan: `docs/superpowers/plans/2026-10-20-d5-trends-crla-aral.md`.

Console: `trend-<name> <scope> <year>`.

## D6 — Dashboard summary (last)

`DashboardViewModel.summary(year, {today})` by signed-in role:
- Tutor: my sections + learners; my ARAL roster (active/exited); sessions this year + last session date; D3 reminders.
- School admin/coordinator: sections + learners per instrument; current/next round per instrument from the calendar
  with completion %; ARAL active/exited; BOSY masterlist count; SRP candidates + classes; D2 reminders.
- Superadmin: the school view per school + regional totals.

Charts are not inside `summary`; the UI calls `TrendViewModel` on demand. Console: `dashboard [year] [today]`.

## Out of scope

CRLA in SRP/NLA/progress; push/OS notifications (reminders are data the UI shows); caching of regional loops;
grade-based rule checks (tutor-capabilities phase).
