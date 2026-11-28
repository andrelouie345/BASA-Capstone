# ARAL effectiveness: no-improvement alerts and the progress trend

Status: draft for owner approval (2026-11-27). Consultation item M1-13; objectives iii and iv. Builds on
`AralClassViewModel.classProgress` (spec `2026-11-27-aral-class-tutor-design.md` D2).

## Intent

The advisor asked BASA to show whether ARAL works, and to flag learners who are not improving. BASA records the
readings, the check-ins and each class learner's change since their ARAL starting round, but nothing tells anyone
"this learner is stuck" or "ARAL is (not) moving learners up this year". This piece adds both:

- **Alerts**: a learner who is not improving is flagged to their ARAL class tutor (who adjusts the IRIP) and to the
  school's coordinator (who keeps an eye on it).
- **Trend**: at each round of the year, the share of ARAL learners who are up / same / down since their start.

## Goals

- Tutor reminders: one line per ARAL class of the tutor with flagged learners, the learners under it, each with
  their reason.
- Coordinator reminders: the same, for every class of the school, grouped by class.
- A trend chart per instrument (CRLA, Phil-IRI) for a school or the region: per round, the up / same / down shares.
- One rule, used by the alerts and the trend's counting, so the reminders and the chart never disagree.

## Non-goals

- No check of whether the IRIP was changed after an alert (a second rule to argue about).
- No by-class or by-tutor comparison chart (it amounts to ranking tutors).
- No IRIP weekly ratings as a signal (the tutor's own judgement; noise).
- No alert for "not assessed yet" / "no starting result" learners (the tutor reminders already chase missing
  assessments).
- No stored flags, no "dismiss" or "acknowledged" state, no notifications outside the reminders.
- No screen (the frontend team builds it from the handoff doc), no report export (M1-07).
- Not the moving-up rule (M1-11, next piece).

## Anti-goals

- A learner flagged after a handful of sessions (Same right after placement is normal).
- The reminders saying N learners are stuck while the chart, for the same class and round, counts differently.
- "Carried" / "actual" wording in anything a tutor reads (owner, 2026-11-15).
- An alert computed from the Phil-IRI "not assessed" stand-in (a fake "down"; already excluded by `classProgress`).

## Constraints

- Computed on the device from stored records: no table, no migration, no SQLite version change, both builds.
- Pure Dart in ViewModels/services (no Flutter). Message wording rule of 2026-11-17 (plain words, no ids, fields or
  commands). Repo is public: roles only, no names of people.

## Approaches

1. **One shared rule, read by reminders and trends** (chosen by the owner): a pure-Dart rule decides "no
   improvement" from `classProgress`, attendance and the latest check-in; `AralClassViewModel` exposes the flagged
   learners; `ReminderViewModel` and `TrendViewModel` read it. Same counting everywhere, nothing new to keep in step.
2. Each place writes its own rule (reminders compute alerts, the trend computes shares): slightly quicker, but two
   copies of "the same" rule that can drift (tutor sees 3 stuck, chart says 2). Rejected.
3. Stored alert flags (a synced table refreshed when results change): fast reads, but a second copy of the scores, a
   migration and sync work. Rejected, as for `classProgress`.

## Decisions

**D1. Who sees it (owner).** The ARAL class tutor (adjusts the IRIP) and the school's coordinator/admin. Tutors see
their own classes only (as for the class-tutor reminders: a tutor's device holds only their classes). Coordinators
see every class of their school; the superadmin, every school on the device.

**D2. Signals (owner: A + B).** A learner placed in an ARAL class this school year and **active** on the reminder
day (`aralActiveOn`; exited learners never alert) is flagged when either holds:

- **A. Round:** their `classProgress` row has change **Same** or **Down**, and they **attended** (mark `present`;
  absent and excused do not count) at least the school's `checkin_after_sessions` sessions (first checkpoint, 16 by
  default) of their ARAL enrollment dated on or before that latest round's assessment date. My call: attended rather
  than held, because a learner who keeps missing sessions is a different problem (attendance), not "ARAL not
  working".
- **B. Check-in:** their latest **complete** check-in (`aralLatestCheckin` over both checkpoints, latest date then
  attempt) is below the school's pass mark (`passPct`, today's cut-off as the check-in report scores it). Programs
  with no check-in tool (KS1, Foundational) simply never trigger B.

A learner can carry both reasons; each is listed.

**D3. Reasons (wording).** Each flagged learner carries one or two plain reasons, e.g.:
- "Same since BOSY: Frustration -> Frustration (MOSY #1)"; "Down since BOSY: Developing -> High Emerging (MOSY)".
- "Check-in after session 16: 45%, pass mark 60%".

**D4. Clearing (my call, owner agreed).** Nothing is stored; the flag is recomputed on every read, so it goes away
when a newer round shows Up, a newer check-in passes, or the learner exits.

**D5. The trend (owner: per round over the year).** `TrendViewModel.aralProgress(scope, schoolYear, instrument)`:
- One chart per instrument (CRLA rounds BOSY / MOSY / EOSY; Phil-IRI BOSY / MOSY #1-#3 / EOSY): x = the rounds,
  series = Up / Same / Down as % of the learners counted at that round.
- Counted at round R: learners placed in an ARAL class this year (one per roster row, whichever class), whose
  starting round is before R, with a starting result and an own result in R; the change is start -> R (not start ->
  latest). Learners with no result in R are left out of R (my call: the chart shows the learners counted at each
  round, e.g. in the x label "MOSY #1 (n = 24)").
- Scopes: section, school, region (superadmin), as the other trends; `TutorScope` refused (no tutor comparison).
- My call: the trend does **not** apply D2's attendance minimum (it pictures the outcome of everyone ARAL reached);
  it uses the same change computation as `classProgress`, so a class's Same/Down learners at their latest round are
  the alert's A candidates before the attendance check.

**D6. Shape.** `classProgress` gets an "at this round" option (`atRound`) so the trend can ask the change at each
round with the same code; `AralClassViewModel.noImprovement(classId, {asOf})` returns the flagged learners with
reasons; the rule itself is a pure function (in `lib/core/services/`), unit-tested on its own.

## Left to the builder

- Names of the new types and where the pure rule lives; the console commands (likely `aral-no-improvement
  <classId>` and `trend-aral-progress <scope> <year> crla|phil-iri`) and their test lists.
- How reminders carry the reason (e.g. an optional `note` on `ReminderLearner`), the tutor reminder kind's place in
  the display order (proposal: right after check-ins due), the coordinator side as an `AralClassNoticeKind` with the
  class and learners.
- Efficiency (reuse the class rosters and results the reminders already load).
- Screen handoff doc (`docs/handoff/screens/`), command pass steps, guides' lines, consultation log update.
