# ARAL class tutors: MOSY/EOSY reminders by class, and each learner's progress

Status: approved for planning (owner, 2026-11-27). Consultation agenda "Next things" #2; feeds M1-13 (ARAL
effectiveness alerts) later.

## Intent

ARAL class tutors give MOSY and EOSY to their own class learners; the section's tutors give BOSY (GST and readings).
This is decided (the reading coordinator, 2026-11-27), not an open question. BASA already lets a class tutor assess
their class learners in any section (`aral_tutor_assesses`), but its reminders still follow sections only: a class
tutor is never reminded about their class learners, and the section tutors are reminded about learners who are no
longer theirs to assess. This piece makes the reminders follow the decision, and gives each class a list of how each
learner has moved since they entered ARAL ("has ARAL helped so far?"), which M1-13's no-improvement alerts will read.

## Goals

- At MOSY and EOSY, a learner active in an ARAL class that has a tutor is reminded to that class tutor, grouped by
  class, and no longer to the section's tutors.
- Per class, each learner's change from their ARAL starting round to their latest assessed round: up / same / down by
  reading profile, with the numbers behind it.
- Fix the parked CRLA "latest attempt" bug on the way (a learner moved mid-year could get the old section's attempt).

## Non-goals

- No change to who may assess (RLS, server, device triggers): section tutors can still assess a class learner.
- No alerts yet (M1-13), no new report, no screen (the frontend team builds it from the handoff).
- Coordinator reminders are unchanged (they count by section and school).
- Not a year-end ARAL status (parked separately: an unexited learner keeps an active row in last year's roster).

## Anti-goals

- A tutor's view must never say "carried" or "actual" (owner, 2026-11-15; as tutor learner pages).
- A learner with no own reading in the later round must not show a change computed from the Phil-IRI "not assessed"
  stand-in (that would be a fake "down").
- Two people chased for the same learner at MOSY/EOSY.

## Constraints

- No new tables, no migration, no SQLite version change: everything is computed on the device from stored results.
- Both builds (tutors and coordinators). Message wording rule of 2026-11-17 (plain words, no fields, ids, commands).
- Repo is public: no names of people beyond roles.

## Approaches

1. **Computed on the device from stored results** (chosen): the roster row already records its starting round
   (`aral_enrollments.basis_round`); profiles and numbers come from the existing CRLA and Phil-IRI results. Nothing new
   to keep in step.
2. Stored change per learner (a table filled when results change): faster to read, but a second copy of the scores
   that can drift from the readings it comes from, plus a migration and sync. Rejected.

## Decisions

**D1. Hand-over (owner, A).** In `ReminderViewModel.tutorReminders`:
- For MOSY rounds (CRLA `mosy`; Phil-IRI `mosy1`-`mosy3`) and EOSY, a section's "not assessed" line leaves out learners
  active (on the reminder day, `aralActiveOn`) in an ARAL class of that year whose class has a tutor. BOSY lines are
  unchanged. A learner waiting for a class, or in a class without a tutor, stays on the section line (nobody else has
  them).
- The class tutor gets new lines, one per class x instrument x scheduled round that is open or closed: the class's
  active learners not assessed in that round, e.g. "Phil-IRI MOSY #1 closes in 5 days: 4 of 9 learners of ARAL class
  ARAL-R-G7-01 not assessed." Same kinds as today (`openAssessment` / `overdueAssessment`) with `aralClass` set. A
  mixed-grade class can get a CRLA line and a Phil-IRI line. The calendar is the class's school's.
- "Assessed" is today's definition per instrument (Phil-IRI `NlaReportViewModel.assessedIn`; CRLA the round's attempt),
  read for the learner's own section, as the section lines do.
- Every assigned tutor of a section still sees the same shared section line (unchanged).
- Known limit (final review I1, accepted by the owner 2026-11-27): a tutor's device holds only that tutor's own
  classes, so a class with no tutor is not on it and its learners look handed over there: until the class gets a
  tutor, they have no MOSY/EOSY line on tutors' devices. The coordinator's "class has no tutor" notice is the safety
  net; a coordinator's device (all classes) keeps them on the section line. The same holds for a deactivated class
  tutor. No migration to widen what tutors read.

**D2. Progress per learner (owner: profile decides, numbers shown).** `AralClassViewModel.classProgress(classId,
{asOf})` -> one row per learner placed in the class this school year (active, and exited ones marked with their exit):
- Instrument by the learner's grade: CRLA for Grades 1-3 (the grade's CRLA language, `aralCrlaBasisVariant`: G1 Mother
  Tongue, G2 Filipino, G3 English; other-language attempts ignored), Phil-IRI for Grades 4-10.
- From: the roster row's starting round (`basis_round`; Grade 1 CRLA starts at MOSY). To: the latest round assessed
  on or before `asOf` (owner: starting point to latest, not round to round).
- Change: up / same / down by the profile's place on the grade's scale (CRLA `aralCrlaProfileOrder`: Low Emerging ->
  High Emerging -> Developing -> Transitioning -> At Grade Level; Phil-IRI: Struggling / Non-Reader -> Frustration ->
  Instructional -> Independent). "Not assessed yet" when there is no own reading after the starting round; "no
  starting result" when the starting round has none (shown, not guessed).
- Numbers before -> after: CRLA correct words %, wpm, comprehension; Phil-IRI word recognition %, wpm, comprehension %.
- Values follow the school's `values_aral` switch (as the ARAL report and proposals). For a tutor the row never says
  carried/actual (anti-goal).

**D3. CRLA latest attempt (parked bug, owner: fix it here).** `crla_assessments.attempt_no` restarts per section, so
"highest attempt number" picks an old section's attempt for a learner moved mid-year. One shared rule: the latest
attempt = latest `assessed_at`, then highest `attempt_no`, then the later-made row. Used by `aralCrlaLearnerProfile`
(ARAL implementation report, dashboard CRLA trend), learner history (`_crlaByRound`) and D2. The server views group by
section and stay as they are.

**D4. Console and handoff.** `aral-class-progress <classId> [asof=YYYY-MM-DD]` (both builds); `reminders-tutor` shows
the new class lines with no change of its own. Screen handoff in `docs/handoff/screens/aral.md` (class progress list;
reminders by class). A walkthrough row in the demo report (the demo already has class tutors giving MOSY).

## Tests (written first)

- Hand-over: at MOSY a placed learner leaves the section line and appears on the class line; BOSY unchanged; a class
  without a tutor keeps its learners on the section line; a learner who exited ARAL goes back to the section line
  (D1: only learners active in a class leave it).
- Progress: up, same, down, not assessed yet, no starting result; Grade 1 starting at MOSY; a Phil-IRI learner with no
  MOSY reading under `actual` shows "not assessed yet" (not the stand-in); a tutor's row has no carried/actual words.
- D3: a learner moved mid-year with attempt 2 in the old section (earlier date) and attempt 1 in the new one (later
  date) -> the new one, in all three places.
- The command pass gets steps for `aral-class-progress` and the class reminder line.

## Left to the builder

The exact model names and fields; message wording within the rule; how the progress row carries the numbers; which
ARAL ViewModel helper reads the results (reuse the report's).
