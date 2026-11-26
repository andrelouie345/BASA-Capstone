# SF1 import: continuing learners (short design)

Date: 2026-11-24. Found by the demo-data plan's Task 1 (`docs/superpowers/plans/2026-11-24-demo-data.md`).
Status: draft for the owner's approval.

## Why

Importing the new school year's SF1 turns every learner BASA already knows from that school into an
"LRN already exists" conflict (`sf1_importer.dart` `_existingLearnerRow`: a known LRN with no enrollment
that year at that school). A coordinator must then clear each one with `resolve-conflict <id> update`:
about 40 per section, every June. Learners who continue at the same school should simply be enrolled
in their new section by the import. The demo builder needs this too (2025-2026 -> 2026-2027).

## Goals / non-goals

- Goal: a known LRN that continues at the same school is enrolled by the import, with no conflict, and
  the trial says what will happen to each such learner.
- Non-goal: transfers from another school (stay a conflict; the superadmin's path, D15), ARAL rosters
  (per year; learners are proposed again from the new year's results), closing last year's enrollment.
- Anti-goal: enrolling a learner whose grade jump looks like a data error without a person looking.

## Rule (owner-approved 2026-11-24)

New trial outcome **`continuing`**, decided only when the learner has **no enrollment in the file's
school year** (today's moving / returning / enrolled cases are unchanged). Compare with the learner's
**latest enrollment in an earlier school year** (any status):

| Latest earlier enrollment | Outcome | Trial label |
|---|---|---|
| This school, one grade lower | continuing | `moving up from Grade 3 (2025-2026)` |
| This school, same grade | continuing | `repeating Grade 3` |
| This school, archived (transferred / dropped out), one grade lower or same | continuing | + `, back after leaving (dropped out, 2025-2026)` |
| This school, not the school year just before (gap) | continuing | + `, last here in 2024-2025` |
| This school, two or more grades lower, or a higher grade | conflict (as today) | reason names both grades |
| Another school, or none | conflict (as today) | unchanged |

Learner data on a continuing row:
- **Name** (last, first, middle) different from BASA's: **updated** from the SF1 (owner: likely a
  correction); the trial label adds `, name corrected: <old> -> <new>`.
- **Birth date**: filled only when BASA's is blank (today's "already enrolled" rule); never overwritten.

## Approaches

| Approach | |
|---|---|
| **A new `continuing` outcome in the importer** (trial decides, import enrolls) | **Chosen**: one place, the trial shows it before anything is written, no conflict rows |
| Import as today, then auto-resolve the conflicts with `update` | Rejected: logs conflict rows only to close them, `update` overwrites the birth date too, no trial preview |
| A separate "new school year" roll-over that copies last year's sections | Rejected: guesses sections; the SF1 is the source of truth |

## Shape of the change

- `StudentRepository.latestEnrollmentBefore(studentId, schoolYear)` (SQLite + Supabase): latest
  enrollment with `school_year < schoolYear`, any school, any status (school years compare as text).
- `Sf1Importer`: the `continuing` row (with `updatesName`, `fillsBirthDate`) in `_existingLearnerRow`;
  `import()` updates the name when flagged, fills a blank birth date, enrolls into the file's section,
  counts `continuing` in `Sf1ImportResult`, logs no conflict. Re-importing the same file gives
  "already enrolled" (no second enrollment).
- Console `import-trial` / `import-students`: the summary lines get `continuing: N` **at the end** (the
  command pass's `expect` lines match the existing prefix).
- `docs/handoff/screens/admin.md` (SF1 import): the new count and labels, for the frontend team (the
  screen itself is theirs).
- No migration, no SQLite version change, no RLS change (a coordinator already updates and enrolls
  their own school's learners: `resolve-conflict update` does both). `App update required: no`.

## Left to the plan

- Test names and fixtures (pattern: `test/core/services/sf1_importer_leavers_test.dart`).
- Whether any command-pass scenario depends on today's new-year conflict (grep first).
