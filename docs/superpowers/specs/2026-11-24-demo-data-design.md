# Demo data: the Night City world (design)

Date: 2026-11-24. Consultation log item **M1-05**. Status: draft for the owner's approval.

## 1. Why

At the 2026-11-24 consultation the advisor could not see what BASA already does. The dashboard showed
"ARAL 0 active", the lists held "ZZ test" sections and "121 schools" (leftovers of about 55 command-pass
runs), and features she asked about were already built but had no data to show. Before the next
consultation (next week) BASA needs a **demo world**: readable, believable records that put something on
every built screen, so the team can walk her through the system. "Really complete" is the bar: every
feature listed in section 6 shows real-looking data, and that is **double-checked** (a coverage report
from the builder, then the owner's click-through).

## 2. Goals, non-goals, anti-goals

Goals
- Every built feature of the admin and tutor builds has demo data that shows it (section 6).
- The data tells small, followable stories (section 5), so a learner can be traced from CRLA through
  ARAL to Phil-IRI and across two school years.
- Every record is made through the app's own ViewModels and the normal upload/approval flow, so the demo
  shows only what BASA really produces (rules, triggers and RLS all apply).
- One command builds it; the same command can build it again on another server later (the fresh project
  planned before the defense).

Non-goals
- No new app feature, screen, migration or rule change. If a feature can't be shown without one, it is
  listed as a gap in the report, not built here.
- Not a test suite: the command pass stays the test. The builder only checks that the demo data is there.
- No teardown tool inside the app.

Anti-goals (a failure even if it runs)
- Data the app would never produce (inserted past the rules).
- Anything that looks like a real school, real learner or real person.
- Passwords or keys in the repo.
- Writing to the wrong server (the builder must never touch a server it wasn't pointed at).

## 3. Constraints (found in the code)

- **No future dates.** ARAL sessions, check-ins, IRIP weeks and readability logs refuse dates after
  today (`aral_session_viewmodel.dart:614` and three others); reminders, open rounds and the dashboard
  measure against today. So the world uses real school years **2025-2026** (complete) and **2026-2027**
  (up to the day the builder runs), not 2077-2078 (owner chose this, option A).
- CRLA and Phil-IRI sessions take a past date (`assessedAt`), so 2025-2026 can be filled properly.
- CRLA stories exist only for **Region X** (region 13), Grades 1-3: both schools are in Region X.
- Learners exist only through an **SF1 import** (as in the command pass).
- One upload holds at most 6 MB (`maxPackageBytes`): the builder uploads in batches (per section and round).
- `LocalDatabase` is a process-wide singleton: one device open at a time (`tool/command_pass/device.dart`).
- The materials catalog is not seeded and BASA stores no files: demo materials get placeholder links.
- Builder code is backend/tooling: branch `excelsior`, never mixed with UI commits.

## 4. Approaches (decided)

| Approach | Trade-off | |
|---|---|---|
| **1. Dart builder through the ViewModels** (`tool/demo_data/`) | Real rules and RLS; repeatable from a fixed seed; slower run, most code | **Chosen (owner)** |
| 2. Hand-written `.pass` scenario | Hundreds of lines per learner; runner naming tied to ZZTEST | Rejected |
| 3. SQL seed file | Fast, but skips every app rule; needs a DB password the app never uses | Rejected |

Server: the **dev cloud** for now (owner: the schema still changes; ZZTEST data is harmless). A fresh
Supabase project comes later, before the defense, set up by following the README as a test of the
guide; the builder then runs once on it. To avoid the ZZTEST clutter in the demo, the walkthrough uses a
**Night City coordinator** account (school-bound: sees only their school); the superadmin only for the
regional view.

## 5. The world

### Schools (Region X)
| School | Grades | School ID | Division (text) |
|---|---|---|---|
| Night City Elementary School | 1-6 | `NCES-DEMO` | Night City Division |
| Night City High School | 7-10 | `NCHS-DEMO` | Night City Division |

### Sections
One section per grade per school year (2 x 10 sections). 2025-2026 and 2026-2027 use the same section
names (e.g. Grade 4 - Sampaguita); a learner moves up one grade between the years. Every section has an
adviser (`section-adviser`). Grade 6 (ES) and Grade 10 (HS) learners of 2025-2026 leave the world (they
finish); Grade 1 and Grade 7 of 2026-2027 are new learners. *(My call: moving a Grade 6 learner to the
HS is a cross-school transfer, and the same-server transfer (`sf1_transfer_in`, D15) keeps the grade,
so it doesn't fit moving up a grade.)*

### People (all fictional; emails on the reserved `.test` domain)
| Account | Role | School | Notes |
|---|---|---|---|
| `demo.super@nightcity.test` | admin, no school (superadmin) | - | regional view |
| `coord.es@nightcity.test`, `coord.hs@nightcity.test` | coordinator | ES / HS | the demo accounts |
| `admin.es@nightcity.test` | admin | ES | a school admin |
| 3 tutors per school | tutor | ES / HS | at least one internal (adviser) and one external tutor (`user-tutor-type`) |

Passwords are set by the builder and written only to `D:\0_CAPSTONE\verify\demo\accounts.json` (outside
the repo), with the server config in `D:\0_CAPSTONE\verify\demo\supabase_config.json`.

### Learners
About **12 per section** (about 120 a year), with readable fictional Filipino-style names from fixed
name lists (first name, middle initial, surname), sexes balanced, birth dates fitting the grade. LRNs use
a demo prefix that no real LRN or command-pass LRN uses (`9991` + 8 digits). The same learners continue
into 2026-2027 (one grade up), minus the leavers, plus a few new ones.

### Results (generated from a fixed seed)
Each learner gets a **reading level** for the year (drawn so the bands look like a real school: most
grade-level ready, some Frustration/Struggling, a few Non-Readers) and a **trend** (improves, stays,
slips). The builder turns these into raw records the app scores itself:
- **CRLA** (Grades 1-3): BOSY and EOSY in 2025-2026; BOSY in 2026-2027 (MOSY where the calendar holds it).
  Part 1 scores and Part 2 story, miscues, time and comprehension, consistent with the target profile.
- **Phil-IRI** (Grades 4-10): GST for each learner; oral readings with **miscues placed on real passage
  words** (types mixed, some self-corrections), timing, comprehension answers per question, rubric
  scores; BOSY, MOSY #1 and EOSY in 2025-2026; BOSY and MOSY #1 in 2026-2027. Some silent readings
  (with the follow-up the rules ask for). Rounds finalized where the year is over.
- **ARAL**: learners proposed from the basis round, enrolled and placed into **classes** (both years;
  KS1, KS2 Basic/Plus, KS3; at least one mixed-program class), sessions on school days with attendance
  (present / absent / excused), IRIP targets and weekly ratings, both check-ins after sessions 16 and 32
  where reached, materials recommended, a readability log at the school with SHARP on, exits at EOSY,
  one teacher referral.
- **Settings**: round calendar windows for both years (school overrides; 2026-2027 BOSY closed, MOSY #1
  open on the build date), report settings (done threshold, auto-approve off at the HS), ARAL settings
  from Memo 180 at one school, offline days, Phil-IRI value sources (one list on carried).

### Stories (named learners the walkthrough can follow)
1. **Moves up through ARAL**: Grade 3 in 2025-2026, CRLA Low Emerging -> ARAL KS1 -> EOSY Developing ->
   Grade 4 in 2026-2027, Phil-IRI Instructional (learner history shows the whole path).
2. **No improvement**: an ARAL learner whose MOSY ranks no higher than BOSY (shows under "No improvement"
   in ARAL Form 2 and in the reports).
3. **Non-Reader in the high school**: Grade 7, Phil-IRI Non-Reader, in ARAL KS3 and on the SRP list.
4. **Exits to grade level ready** at EOSY.
5. **Leavers**: one transferred out (archived), one dropped out (archived), one moved to another section,
   one returning learner. Shown by a **same-year re-import**: the 2026-2027 SF1s are imported for June,
   then re-imported for October without the leavers, so `sf1-missing` lists them. *(A new year's section
   has no earlier SF1, so leavers only show within one year.)*
6. **Sync**: one tutor upload approved, one **left pending** (Review uploads and the coordinator's
   reminders show it), one rejected with a reason.

## 6. Coverage list (the double check)

Each line is a feature and the demo data that shows it. The builder's report ticks every line with a
count read back from the device (e.g. "CRLA attempts 2025-2026: 72"); the owner then clicks through the
app with the same list (kit in `D:\0_CAPSTONE\verify\demo\`). A line that can't be shown is reported as
a gap, not skipped.

| Area | Feature / screen | Shown by |
|---|---|---|
| Accounts | Users, tutor types, login logs, offline sign-in | section 5 accounts; each signs in at least once |
| Admin | Schools, sections + advisers, tutor assignments | 2 schools, 20 sections, tutors assigned |
| Admin | Learners, roster CSV, SF1 import + trial | SF1 files for both years |
| Admin | Learner history | stories 1-5 |
| Leavers | Not on SF1, archive, move, restore, anonymize preview | story 5 (anonymize: preview only) |
| CRLA | Section list, attempts, Part 1/2, profiles, thresholds, scoresheet export | Grades 1-3, both years |
| Phil-IRI | GST, sessions, miscues on words, answers, rubric, learner results, finalize round, thresholds | Grades 4-10 |
| Phil-IRI | Content (collections, passages) | the seeded passages (no new content) |
| Phil-IRI | Value sources, ranking list | one carried list; ranking per section |
| ARAL | Roster (proposed, enrolled, waiting, placed, exited, referral) | both years |
| ARAL | Classes, sessions, attendance, idle-class reminder | 6+ classes; one idle class |
| ARAL | IRIP, check-ins + check-in report | placed learners |
| ARAL | Settings (memo keys, KS1 extended, SHARP, cut-off) | one memo school |
| ARAL | Materials, recommendations, readability log | 6+ demo materials |
| ARAL | Implementation report, Forms 1, 2, 4, roster/check-in CSV | both schools |
| Reports | NLA Form 2b + Division ARAL, progress monitoring, BOSY masterlist, SRP (candidates + classes) | HS Phil-IRI data |
| Dashboard | Summary per role, years, round calendar, coordinator + tutor reminders, trends (bands, completion, CRLA profiles, ARAL exits, activity) | both years |
| Sync | Pull, upload, approve, pending, reject, auto-approve | story 6 |
| Settings | Report settings, offline days, FLT switch | one school each |

## 7. How it runs

- `dart run tool/demo_data/build.dart --config D:\0_CAPSTONE\verify\demo\supabase_config.json` (the
  config path is required; there is no default, so it can't hit the dev cloud by accident). It prints
  the server URL and the school codes and asks for `yes` before writing.
- It reuses `tool/command_pass/device.dart`: one device folder per account under
  `D:\0_CAPSTONE\verify\demo\devices\`, the admin or tutor build per role, and works through the
  ViewModels of each device's wiring (console commands only where no ViewModel call is simpler).
- **Bootstrap account**: creating `demo.super` (an admin with no school) needs a superadmin already on
  that server. The builder signs in once with the command pass's test superadmin
  (`D:\0_CAPSTONE\verify\pass\accounts.json`) to create it, then works only as the demo accounts. On a
  fresh server, the README's bootstrap step (5) creates that first superadmin.
- **First task of the plan = a short check** that the two-year path works as assumed: a 2026-2027 SF1
  holding the same LRNs one grade up gives each learner a new enrollment (not a conflict), and learner
  history then shows both years. If it doesn't, the plan stops and the owner decides.
- Order: superadmin (schools, coordinators, calendar defaults) -> coordinators (tutors, SF1 imports,
  sections, assignments, settings) -> tutors (assessments, ARAL work, uploads) -> coordinators
  (approvals, finalize rounds, reports) -> 2026-2027 the same way -> the leftovers (pending and
  rejected uploads) -> the coverage report.
- **Resumable**: every step checks what exists before creating it (by school code, email, LRN, date and
  round), so a run that stops halfway continues where it stopped. Running it twice changes nothing.
- The fixed seed makes the world the same every time; the build date only moves the "today" end of
  2026-2027.
- Output: `D:\0_CAPSTONE\verify\demo\report.md` (coverage list with counts, gaps, the accounts list
  without passwords) and the walkthrough kit `walkthrough.md` (which account to use for each screen).

## 8. Decided by the owner

- Approach 1; dev cloud now, a fresh project later (before the defense).
- Real years 2025-2026 and 2026-2027; Night City names.
- The demo is led by the team with a Night City coordinator account.

## 9. My calls (correct any)

- Two schools (ES Grades 1-6, HS Grades 7-10), Region X, one section per grade, about 12 learners each.
- Account emails on `nightcity.test`; passwords only in `D:\0_CAPSTONE\verify\demo\`.
- Demo LRN prefix `9991`.
- Demo materials link to `https://example.org/basa-demo/...` (clearly not real files).
- Teardown on the dev cloud is not built; if needed, a SQL script for the owner to run by hand comes later.
- The builder lives in `tool/demo_data/` (not shipped in any app build; the import walk covers `lib/`
  only).

## 10. Left to the plan

- The name lists, the level/trend draws and how each target level becomes raw records (miscue counts,
  times, answers) per instrument.
- Batch sizes per upload.
- Which ViewModel calls cover each step, and where a command is simpler.
- The exact counts each coverage line expects.
