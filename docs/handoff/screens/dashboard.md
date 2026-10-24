# Dashboard: summary, round calendar, reminders, trends

### Dashboard home
Build: both    Roles: tutor (own work) / school admin or coordinator (school) / superadmin (every school + regional sums)
Purpose: one screen per role with the year's figures and reminders.
Calls:
- ✅ `DashboardViewModel.schoolYears()` → `List<String>` (latest first; the year is always passed)
- ✅ `DashboardViewModel.summary(schoolYear, today:)` → `DashboardSummary` (owns no rules; every figure comes from another ViewModel)
- ✅ `progressPercent(share)`, `thresholdPercent(share)` → `String`
Console: `dashboard`, `dashboard-years`

### Round calendar
Build: both (view) / admin (set)    Roles: view all; set admin / coordinator (superadmin: region defaults)
Purpose: each instrument's round windows for a year (region default, school override or skipped) and whether each is upcoming / open / closed.
Calls:
- ✅ `RoundCalendarViewModel.effectiveCalendar(schoolId, year)` → `List<CalendarEntry>`; `scheduledRounds(...)`; `invalidWindows(...)` → `List<CalendarWindow>`
- ✅ `status(window, today:)` → `RoundStatus` (class T: DASH-G1; the console calls the rule function directly instead: DASH-G1)
- ✅ `CalendarWindow.roundLabel` ("MOSY #1"); `status(...).label` — DASH-G1
- ✅ admin: `setWindow(...)`, `skipRound(...)`, `clearWindow(...)`; `lastMirrorWarning` (class E: DASH-G4)
- ✅ instruments: `CalendarInstrument.values` (`label`, model)
Console: `calendar-show`, `calendar-set`, `calendar-skip`, `calendar-clear`

### Reminders
Build: tutor reminders both; coordinator reminders admin    Roles: tutor / coordinator / admin
Calls:
- ✅ `ReminderViewModel.tutorReminders(tutorId, year, today:)` → `TutorReminders` (a tutor passes `currentUser.id`)
- ✅ `coordinatorReminders(schoolId, year, ...)` → `List<SchoolReminders>`; `crlaCompletion(...)` → `List<SectionCompletion>`
- ✅ reminder text functions (`tutorRemindersText` etc.) are in the command helpers; a screen builds its own list from the models. Not a gap.
Console: `reminders-tutor`, `reminders-coordinator`

### Trends
Build: tutor activity both; the others admin    Roles: tutor (own activity) / admin / coordinator
Calls:
- ✅ `TrendViewModel.bandDistribution(scope, year, ...)`, `completion(...)`, `crlaProfiles(...)`, `aralExits(...)` → `TrendChart`; `aralActivity(...)` → `({TrendChart sessions, TrendChart attendance})`
- ✅ `TrendScope`, `TrendChart` (model `core/models/trend_chart.dart`); sexes `NlaSex`
Console: `trend-bands`, `trend-completion`, `trend-crla-profiles`, `trend-aral-exits`, `trend-aral-activity`

## Gaps

**DASH-G1** (I, T, N) — `calendar-show` calls `roundStatus` and `roundLabel` from `calendar_rules.dart` directly (the ViewModel already has `status`); `RoundStatus` is a service type.
Fix: commands call `RoundCalendarViewModel.status`; `CalendarWindow.roundLabel` getter (model, same function); `core/models/calendar_types.dart` exports `RoundStatus`.
Removes baseline: `core/console/commands/calendar_commands.dart -> core/services/calendar_rules.dart`, `core/console/commands/calendar_admin_commands.dart -> core/services/calendar_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

**DASH-G2** (I) — Five console helpers check that a typed date is real with `calendarDate(d) != raw` (`calendar_rules.dart`): `calendar_command_helpers`, `dashboard_commands`, `reminder_command_helpers`, `trend_command_helpers`, and `calendar_commands` for the header date. Console-only parsing; screens use a date picker.
Fix: use the console's own `strictDateArg` (`core/console/date_args.dart`, same rollover check) with each command's existing message text, and a local YYYY-MM-DD formatter for the header line (`date_args.dart`). Console output unchanged.
Removes baseline: `core/console/commands/calendar_command_helpers.dart -> core/services/calendar_rules.dart`, `core/console/commands/dashboard_commands.dart -> core/services/calendar_rules.dart`, `core/console/commands/reminder_command_helpers.dart -> core/services/calendar_rules.dart`, `core/console/commands/trend_command_helpers.dart -> core/services/calendar_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

**DASH-G3** (I) — `reminders-tutor me` reads `notSignedInMessage` from `auth_messages.dart`.
Fix: import it from `core/models/messages.dart` (COMMON-G1's export).
Removes baseline: `core/console/commands/reminder_commands.dart -> core/services/auth_messages.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

**DASH-G4** (E) — `round_calendar_viewmodel.dart:234` puts `$e` in `lastMirrorWarning`.
Fix: spec rule.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).
