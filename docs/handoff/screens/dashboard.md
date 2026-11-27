# Dashboard: summary, round calendar, reminders, trends

### Dashboard home
Build: both    Roles: tutor (own work) / school admin or coordinator (school) / superadmin (every school + regional sums)
Purpose: one screen per role with the year's figures and reminders.
Calls:
- `DashboardViewModel.schoolYears()` → `List<String>` (latest first; the year is always passed)
- `DashboardViewModel.summary(schoolYear, today:)` → `DashboardSummary` (owns no rules; every figure comes from another ViewModel)
- `progressPercent(share)`, `thresholdPercent(share)` → `String`
Console: `dashboard`, `dashboard-years`

### Round calendar
Build: both (view) / admin (set)    Roles: view all; set admin / coordinator (superadmin: region defaults)
Purpose: each instrument's round windows for a year (region default, school override or skipped) and whether each is upcoming / open / closed.
Calls:
- `RoundCalendarViewModel.effectiveCalendar(schoolId, year)` → `List<CalendarEntry>`; `scheduledRounds(...)`; `invalidWindows(...)` → `List<CalendarWindow>`
- `status(window, today:)` → `RoundStatus` (`.label`; type from `core/models/calendar_types.dart`)
- `CalendarWindow.roundLabel` ("MOSY #1"); `status(...).label`
- admin: `setWindow(...)`, `skipRound(...)`, `clearWindow(...)`; `lastMirrorWarning` → `String?`
- instruments: `CalendarInstrument.values` (`label`, model)
Console: `calendar-show`, `calendar-set`, `calendar-skip`, `calendar-clear`

### Reminders
Build: tutor reminders both; coordinator reminders admin    Roles: tutor / coordinator / admin
Calls:
- `ReminderViewModel.tutorReminders(tutorId, year, today:)` → `TutorReminders` (a tutor passes `currentUser.id`)
- Since 2026-11-27 (the reading coordinator's rule: ARAL class tutors give MOSY and EOSY): "not assessed" lines come
  per section (`section` set) and per ARAL class (`aralClass` set, `section` null). At MOSY/EOSY a learner in a class
  with a tutor is on the class tutor's class line only; BOSY stays on the section line. Group the class lines under
  the class name. Known limit: while an ARAL class has no tutor, its learners get no MOSY/EOSY line on tutors' phones
  (the phone can't see a class that isn't the tutor's); the coordinator's "class has no tutor" notice covers it.
- No improvement (2026-11-28): a tutor gets one `TutorReminderKind.noImprovement` line per own ARAL class with flagged
  learners (`Class "<name>": 2 learners show no improvement.`, right after the check-ins due); each
  `ReminderLearner.reasons` holds the reasons to show under the name (other reminders' learners have none). The
  coordinator gets one `AralClassNoticeKind.noImprovement` notice per class, also for a class without a tutor. Tapping
  it opens the class's no-improvement list (`aral.md`).
- `coordinatorReminders(schoolId, year, ...)` → `List<SchoolReminders>`; `crlaCompletion(...)` → `List<SectionCompletion>`
- reminder text functions (`tutorRemindersText` etc.) are in the command helpers; a screen builds its own list from the models.
Console: `reminders-tutor`, `reminders-coordinator`

### Trends
Build: tutor activity both; the others admin    Roles: tutor (own activity) / admin / coordinator
Calls:
- `TrendViewModel.bandDistribution(scope, year, ...)`, `completion(...)`, `crlaProfiles(...)`, `aralExits(...)`, `aralProgress(scope, year, instrument:, asOf:)` → `TrendChart`; `aralActivity(...)` → `({TrendChart sessions, TrendChart attendance})`
- `TrendScope`, `TrendChart` (model `core/models/trend_chart.dart`); sexes `NlaSex`
- ARAL progress (2026-11-28): per round after BOSY, the % of ARAL class learners Up / Same / Down since their ARAL
  start (series `Up`, `Same`, `Down`, one decimal; x label `MOSY #1 (n = 5)`: show n, the shares are small numbers).
  `instrument` is `AralLearnerProgress.crla` or `.philIri` (one chart each; a mixed class splits). Scopes school,
  section (learners of that section), region (superadmin); tutor scope refused. A round nobody has is left out; no rows
  = "No ARAL class learner has a result after their start yet."
Console: `trend-bands`, `trend-completion`, `trend-crla-profiles`, `trend-aral-exits`, `trend-aral-activity`, `trend-aral-progress`
