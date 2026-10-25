# Learner history — design

Status: built 2026-10-25 (plan `docs/superpowers/plans/2026-10-25-learner-history.md`). Changes made while building are listed at the end.

## Goal

One learner's progress across school years on one screen, so a coordinator (or ma) can see whether the learner is improving and whether the intervention worked before placing, moving or discussing the learner. Built from the records BASA already keeps: no new tables, no migration. Replaces the handoff's "Learner history (pending backend)" row (`docs/handoff/screens/admin.md`, `docs/handoff/checklist.md` row 17).

## Decisions (owner, 2026-10-25)

| # | Decision |
|---|----------|
| Q1 | A progress summary grouped by school year (results per round, ARAL program/class/attendance/exit), for coordinator decisions. Not an audit log: rows keep only their last editor, so a who-did-what list would be incomplete and misleading. Tutors don't need it: **admin build only** (admin / coordinator / superadmin). |
| Q2 | The viewer sees only what RLS already gives them: a school-bound admin/coordinator sees their own school's records, a superadmin every school. School records stay within the school. Reading a transferred-in learner's past results from another school is NOT built (see *Planned features*). |
| Q3 | Per year: section enrollment, CRLA profile per round and language, Phil-IRI GST/rounds/end result, and a summary per ARAL entry (program, class and tutor, entered/exited + reason, placement basis, attendance rate, 16th/32nd check-in passed/failed/not taken). IRIP weeks and the readability log are not repeated: the screen links to their existing screens. One line per year for the Summer Remediation class (owner: keep it). |
| Approach | 1: a new `LearnerHistoryViewModel` (admin build) that assembles the history from the existing ViewModels and services. No scoring is copied, so a threshold change shows in the history too. (Rejected: a SQL view, which would rewrite the scoring rules in SQL; the screen calling each module itself, which breaks the "one ViewModel per screen need" rule from the completeness check.) |
| Scope note | It cannot be detected on the device that a learner has records at another school (RLS hides those rows; detecting it would need the cross-school read Q2 rules out). So the note is fixed text: a school-bound viewer always sees "Only your school's records are shown."; a superadmin sees none. |

## Data shape

```
LearnerHistory
  student      Student (name, LRN)
  years        List<LearnerHistoryYear>, latest school year first
  scopeNote    String? — "Only your school's records are shown." for a school-bound viewer, null for a superadmin

LearnerHistoryYear
  schoolYear   "2026-2027"
  enrollments  List<LearnerHistoryEnrollment>: section name, grade, school name, status
               (at most one: enrollments is UNIQUE per learner and year; a move updates the row)
  crla         Map<CrlaRound, Map<String test, String? profile>>: latest attempt per round per
               test (subject variant), labelled "MT (<language>)" / "Filipino" / "English" in that
               order; every test given (not only the one ARAL counts); empty when none
  philIri      List<PhilIriLearnerResults>: PhilIriViewModel.learnerResults per section the learner
               has Phil-IRI rows in that year (usually one; round snapshots, as the Phil-IRI screen
               shows it); empty when the year has no Phil-IRI rows
  aral         List<LearnerHistoryAral>, 0 or 1 (one ARAL entry per learner per year)
  srp          the year's Summer Remediation class (class name, tutor name, room), or null
  isEmpty      true when the year has no CRLA, Phil-IRI, ARAL or SRP, only the enrollment (screen: "No assessments recorded")

LearnerHistoryAral
  enrollment   AralEnrollment (program, entered/exited + reason, basis, referral)
  className    String? (null = waiting for a class)
  tutorName    String?
  attendance   AralAttendanceSummary (rate + label; excused don't count)
  checkin16    LearnerHistoryCheckin: passed / failed / notTaken / unavailable (latest attempt as
               the check-in report picks it: latest date, then attempt; today's cut-off)
  checkin32    same
  unavailable  String? — "Not available on this device: ..." when the check-ins can't be read
```

Names (school, section, class, tutor) are resolved in the ViewModel; the screen never looks up ids. Exact class and field names may be refined in the plan; the content above is fixed.

## Reads, access and errors

- **Calls:** `LearnerHistoryViewModel.history(int studentId)` → `Future<LearnerHistory>`; `historyByLrn(String lrn)` → same (search box). The screen gets the student id from the Learners screen.
- **Source:** the device copy only (works offline). `pull-cloud` copies every school year the user can read, already scoped by RLS.
- **New repository reads (SQLite only; the ViewModel reads local, so no Supabase versions):**
  - `StudentRepository.enrollmentsForStudent(int studentId)`: every `enrollments` row of the learner joined to its section (school year, grade, section name, school).
  - `AralEnrollmentRepository.getByStudent(int studentId)`: every ARAL entry of the learner, all years.
- **Years** = the union of the years in the learner's section enrollments, CRLA results, Phil-IRI assessments/GST, ARAL entries and SRP memberships, so a year is not lost when its enrollment row is missing.
- **Reuse:** Phil-IRI via `PhilIriViewModel.learnerResults` (per year, the year's section; a year with Phil-IRI rows in two sections is read for each section the learner was in); CRLA via the CRLA result repository (`getByStudent`) and the profile rule in `aral_rules.dart`/the results view; attendance via `AralAttendanceSummary.of` over `getAttendanceForEnrollment`; check-ins via `AralCheckinViewModel.learnerCheckins` (today's cut-off for the learner's school); SRP via the SRP class repository.
- **Access:** signed in; a tutor is refused like other admin-only ViewModels (`ViewModelException`); a school-bound admin/coordinator is refused for a learner of another school (even when a stale row is on the device); a superadmin reads any learner on the device.
- **Errors** (wording for both readers, per the handoff Q5 rule): learner not on the device → "Learner not found on this device. Download the latest data first (pull-cloud)."; unknown LRN → same style naming the LRN; blank LRN → "Enter an LRN.". A part that can't be read on the device (a Phil-IRI section missing or no longer Grade 4-10, a check-in tool missing) does not fail the history: that part gets a "Not available on this device: <reason>" note and the rest shows.
- **Logging:** a per-module `ScopedLogger`, like the other ViewModels.
- **Wiring:** built in `core/wiring/wire_admin.dart`, exposed as `AdminViewModels.learnerHistory`.

## Console

New wholly admin command file `lib/core/console/commands/learner_history_admin_commands.dart` (added to the admin file list in `tool/check_tutor_imports.dart`), registered in the admin `register*Commands`:

- `learner-history <studentId>`
- `learner-history-lrn <lrn>`

Output: the scope note, then one block per school year: enrollment line(s), CRLA per round and language, Phil-IRI GST/rounds/end, each ARAL entry (program, class, tutor, in/out + reason, basis, attendance label, check-ins), SRP class. The command files stay thin (ViewModel boundary rule). Admin console: 239 → 241 commands; the tutor command list does not change.

## Testing

- `test/viewmodels/learner_history_test.dart` (pure Dart, local SQLite fixture like the existing `*_screen_calls_test.dart`):
  - a two-year learner: Grade 3 CRLA (two languages); Grade 4 GST + Phil-IRI rounds, an ARAL entry in a class with attendance and a 16th check-in, an SRP class; years latest first, every field filled as expected;
  - a tutor is refused; a school-bound coordinator is refused for another school's learner; a superadmin gets no scope note, a coordinator gets it;
  - unknown student id and unknown LRN messages;
  - a year with only an ARAL entry (no enrollment row) is still listed; an enrollment-only year is `isEmpty`.
- Command pass: both commands added to an admin scenario that already has a learner with CRLA, Phil-IRI and ARAL history (chosen in the plan, likely `35_a5.pass` or `36_a6.pass`); rerun that batch + `z` on a new run, then one full run before the commit.
- Checks: `dart analyze`, `flutter test`, `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart`; verify kit under `D:/0_CAPSTONE/verify/learner-history/`.

## Docs

- `docs/handoff/screens/admin.md`: the "Learner history (pending backend)" block becomes "Learner history" with `Build: admin`, the calls above and the console commands.
- `docs/handoff/checklist.md` row 17: same title and build changes.
- `CLAUDE.md`: module checklist line (learner history done), admin console count 241.

## Planned features (not built)

1. **Cross-school history (Q2-B):** let a school read a transferred-in learner's past assessment results from their old school (results only, not ARAL details). Needs new read policies, pull/sync changes, and a data-sharing decision by ma / the division.
2. **Academic history:** age, elementary school graduated from, address (deferred to the next version on 2026-10-19). Needs new columns, so a migration.

## Changes made while building (2026-10-25)

- The new reads live in their own `LearnerHistoryRepository` (interface + SQLite: student by id/LRN, section enrollments, ARAL entries, SRP classes) instead of new methods on `StudentRepository` / `AralEnrollmentRepository`, which have Supabase versions and test fakes that would never use them.
- The console file needs no entry in `tool/check_tutor_imports.dart`: a `*_admin_commands.dart` file is admin by name.
- `philIri` is a list of `LearnerHistoryPhilIri` (`sectionId`, `sectionName`, `results`): `PhilIriLearnerResults` does not say which section it is for. `learnerResults` counts the GST for the whole year (Phil-IRI's rule), so a learner moved between sections shows the same GST under each.

## Changes after the final review (2026-10-25)

- CRLA is grouped by test (subject variant), not by language: a fil result is stored as "Tagalog", so an MT (Tagalog) and a Filipino result in the same round merged into one entry. Labels "MT (<language>)" / "Filipino" / "English".
- The 16th/32nd check-in is picked like the check-in report (latest date, then attempt) through the shared `aralLatestCheckin` / `AralLearnerCheckins.latestAt`: attempt numbers count per tool, so after a program change the highest attempt is not the latest.
- One unreadable part no longer fails the whole history: `LearnerHistoryPhilIri.results` is null with `unavailable` set, `LearnerHistoryAral.unavailable` is set and its check-ins are `unavailable`.
- An enrollment whose school is not on the device is kept (`schoolName` null) instead of dropped.
- Blank LRN refused ("Enter an LRN."); the console prints the placement basis and referral.
- Follow-up, not done: CRLA attempt numbers restart per section, so for a learner moved mid-year the "latest attempt" can be the old section's. `aralCrlaLearnerProfile` (ARAL report, dashboard trend) has the same weakness; fix both together (order by date, then attempt) so the history and the ARAL report stay consistent.
