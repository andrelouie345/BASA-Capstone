# ARAL Division Memorandum 180 s. 2026: ARAL rules as school settings, advisers, Forms 1, 2 and 4

Date: 2026-11-18. Owner decisions in this conversation (2026-11-18), marked
**owner**. My calls are marked **call** for the owner to check while reading.

## Why

The Schools Division of Valencia City issued Division Memorandum No. 180, s.
2026 (15 Nov 2026, effective at once, rest of SY 2026-2027), Supplemental
Guidelines on ARAL Reading and Mathematics. The reading coordinator's school is
under that Division (**owner**). Its ARAL rules differ from DepEd Memorandum
064 s. 2025, which BASA follows today: classes of 5 to 10 instead of up to 15,
weekday sessions of at most 1 hour, learners chosen from MoSY results,
advisers not tutoring their own learners, and ARAL Forms 1 to 6.

Two goals:

1. BASA follows the memo for that Division's schools, while other schools
   (other Divisions of the region) keep today's behaviour.
2. The next memo of this kind is a settings change, not a release. Every
   DepEd-given number at risk of changing becomes a school setting now.

## Goals, non-goals, anti-goals

Goals:

- G1. Class maximum and minimum as school settings; a class over the maximum
  is flagged with what to do (move learners), never blocked from other work.
- G2. Session rules as school settings: weekdays only, a maximum length that
  is refused (not only warned), a daily limit per internal tutor (sessions)
  and per external tutor (minutes), at least N sessions a week per class
  (reminder).
- G3. The basis round for choosing new ARAL learners as a school setting
  (BoSY as today, or the latest assessed round up to MoSY).
- G4. Check-in session numbers and the IRIP cycle length as school settings
  (**owner**, as recommended).
- G5. A section's class adviser and a tutor's type (internal/external), and
  the rule that an adviser does not tutor their own advisory learners (as a
  school setting).
- G6. ARAL Forms 1, 2 and 4 (Reading parts) as exports (**owner**).
- G7. A suggested class name in the memo's code format (ARAL-R-G4-01).
- G8. Docs: why Forms 3, 5 and 6 are not in BASA (tutor management is a
  separate system, **owner**), the new settings, and the audit below.

Non-goals:

- ARAL Mathematics (RMA): not a BASA instrument.
- Forms 3, 5, 6 (tutor HR details, printing and funds, overload pay): the
  separate tutor-management system and the school's own records hold them.
- A holiday calendar: holidays are not checked.
- The CRLA language per grade (G1 Mother Tongue, G2 Filipino, G3 English)
  stays in code: it drives story matching and the scoresheet (**owner**, as
  recommended). Flagged in the docs as a known risk.
- Changing who qualifies for Grades 4-10. The memo's "Frustration or
  Instructional" is the ARAL template's own groups (3 Level Down, 2 Level
  Down), i.e. every learner below grade level, which BASA already proposes
  (**owner**, confirmed with the reading coordinator's earlier input). No
  qualification change.
- Scoring (CRLA, Phil-IRI) is untouched; no result shifts.

Anti-goals (a failure even if it works):

- A school outside the Division sees any behaviour change without changing a
  setting. Every new setting's default is today's behaviour.
- A lowered maximum blocks exits, attendance or edits in an existing class.
  Only taking a new place is refused.
- Any learner record is lost when a class is over the maximum. Moving
  learners (unplace / place) keeps every record: enrollment, attendance,
  IRIP, check-ins and readability hang off the enrollment, not the class
  (checked 2026-11-18; a class with learners can't be deleted, `on delete
  restrict`).

## Audit of fixed DepEd numbers (2026-11-18)

Already settings: CRLA and Phil-IRI cut-offs, check-in cut-off
(`checkin_pass_pct`), SHARP (`foundational_program`), `ks1_extended`,
`idle_session_days`, done threshold, FLT, value sources, offline days,
archive period.

| Fixed today | Where | Source | Risk | This piece |
|---|---|---|---|---|
| Class max 15 | `aralClassCap` (aral_rules.dart), SQLite trigger `_classCap`, server `aral_check_class_placement` + `aral_enrollments_class_cap` | DM 064 | changing now | setting |
| Weekday 60 min (warned), 120 max, weekend setup allowed | `aral_session.dart`, `aral_sessions_minutes_check` 1-120, setup check | DM 064 | changing now | settings |
| Basis round: CRLA G1 MoSY, G2-3 BoSY; Phil-IRI BoSY | `aralCrlaBasisRound`, `aral_viewmodel.dart` | DM 064 / reading coordinator | changing now | setting |
| Check-ins after sessions 16 and 32 | `aralCheckinCheckpoints`, `aralCheckInAfter` | DepEd ARAL tools | medium | setting |
| IRIP cycle 8 weeks | `aralIripWeeks`, `aral_irip_weeks_week_no_check` 1-8 | DepEd IRIP format | medium | setting |
| CRLA language per grade | crla rules / ARAL basis variant | DM 064 | medium | stays, documented |
| Scoresheet facts (comprehension maximums, time caps, Table 8, GST items), rounds, placement bands, "not assessed = 3 down" | rules files | the instruments / reading coordinator | low | stay |

## Approaches considered

1. **Change the numbers in code to the memo's** (cap 10, no weekends). Smallest
   change, but it imposes Valencia City's rules on every other school in the
   region, and the next memo is another release. Rejected.
2. **School settings with today's behaviour as the default** (chosen,
   **owner** "as recommended"). Same pattern as `ks1_extended` and
   `foundational_program`: an `aral_settings` key, school row over the
   default row (`school_id` null), read by the device rules and by the
   server checks. One release now; later memos change settings.
3. **A "Division profile"** (one switch "Valencia City memo" that sets
   everything). Simpler to turn on, but it bakes this memo into code again
   and can't follow a partial change. Rejected.

## Design

### 1. Settings (aral_settings keys)

Read like `foundational_program`: the school's row, else the default row
(`school_id` null), else the built-in default. Each key gets a database CHECK
on `aral_settings` (type and range), like `aral_settings_pass_pct`.

| Key | Type, range | Default (= today) | Valencia City value |
|---|---|---|---|
| `class_max_learners` | integer 1-50 | 15 | 10 |
| `class_min_learners` | integer 0-50, 0 = none; must be <= max (device check) | 0 | 5 |
| `session_max_minutes` | integer 1-240 | 120 (and today's warning above 60 on weekdays) | 60 |
| `sessions_weekdays_only` | boolean | false | true |
| `internal_tutor_max_sessions_per_day` | integer 1-10, absent = none | none | 2 |
| `external_tutor_max_minutes_per_day` | integer 1-600, absent = none | none | 120 |
| `class_min_sessions_per_week` | integer 0-7, 0 = none | 0 | 3 |
| `basis_round` | text `bosy` / `mosy` | `bosy` | `mosy` |
| `checkin_after_sessions` | array of 2 increasing integers, each 1-200 | [16, 32] | unchanged |
| `irip_weeks` | integer 1-26 | 8 | unchanged |
| `adviser_tutors_own_class` | boolean | true (allowed) | false |

**call:** `session_max_minutes` replaces both 60/120 constants. When the key
is absent, today's behaviour stays exactly (warn above 60 on weekdays, refuse
above 120, weekends up to 120). When set, sessions above it are refused on
any day.

**call:** the weekend setup (`AralSetup.weekend`) stays a valid value (old
sessions keep it); with `sessions_weekdays_only` on, a new or edited session
on a Saturday or Sunday, or with the weekend setup, is refused.

Console (admin build, `*_admin_commands.dart`), following `aral-ks1-extended`
/ `-set`: one show + one set command per key, or one pair
`aral-setting <key> [schoolId]` / `aral-setting-set <key> <region|schoolId> <value|->`
(**call:** the generic pair, plus keeping the existing specific commands; `-`
removes the school's value so the default applies). Settings screen is UI
work (on `don`, later).

### 2. Class size

- Device: `aralClassCap` becomes the default; `aralPlacementProblem` takes
  the school's maximum. The SQLite trigger reads the maximum from the local
  `aral_settings` copy (json_extract, as the readability trigger does for
  SHARP), default 15.
- Server: `aral_check_class_placement` and `aral_enrollments_class_cap` read
  `aral_setting_int(school_id, 'class_max_learners', 15)` (a new SECURITY
  DEFINER helper, `search_path = public`, generalizing
  `aral_foundational_program_on`). The cap trigger already returns early
  when a learner keeps their place, so exits and edits in an over-cap class
  still work (checked 2026-11-18).
- Over the maximum (**owner**): a class whose active learners exceed the
  school's maximum is flagged, never blocked:
  - `AralClassViewModel` class lines and summary show
    "12 of 10: over the maximum, move learners to another class"
    (unplace, or place straight into another class);
  - coordinator reminders get a new kind (`aralClassOverMax`);
  - placing into it is refused (already the case: count >= max).
- Below the minimum: a class with fewer active learners than
  `class_min_learners` is flagged ("allowed only when no other learners of
  that grade can be combined", memo item 9d), never refused.
- Error messages name the setting's number, not "15".

### 3. Sessions

Device (`AralSessionViewModel`, add and edit) and server (BEFORE INSERT/UPDATE
trigger on `aral_sessions`, reading the settings):

- `sessions_weekdays_only`: refuse Saturday/Sunday `held_on` and the weekend
  setup.
- `session_max_minutes`: refuse above it (when set).
- `internal_tutor_max_sessions_per_day`: refuse a session that would give an
  internal tutor more than N sessions on that date (school-wide).
- `external_tutor_max_minutes_per_day`: refuse a session that would give an
  external tutor more than N minutes on that date.
- A tutor without a type: no daily check (**call**), shown blank in Form 2.
- The two daily checks count rows, so on the server they are end-state
  checks like the class cap: a deferrable constraint trigger, serialized per
  tutor and date (advisory lock), so `sync_apply` can apply offline swaps
  (pattern of `20261024050000`).
- `class_min_sessions_per_week`: a tutor and coordinator reminder for a class
  with fewer sessions than N in the current Monday-Friday week, from the
  week's Wednesday on (**call**, so Monday doesn't flag every class).
  `idle_session_days` stays as it is.

### 4. Basis round

`basis_round = mosy`: a new proposal for Grades 2-10 uses the latest
assessed round up to MoSY (CRLA `mosy`; Phil-IRI the latest of
`mosy1`..`mosy3` that counts, by the school's ARAL value source), falling back
to BoSY when there is none. Grade 1 already uses CRLA MoSY. The proposal's
`basisRound` records the round used. `bosy` (default) is today's behaviour.
Learners already in ARAL are unchanged (`applyResults` already follows later
results).

### 5. Check-in sessions and IRIP length

- `checkin_after_sessions` [a, b]: the first and second check-ins are due
  after the class's sessions a and b (reminders, session warnings). The
  check-in tools and saved check-ins keep their identifiers 16 and 32, which
  mean "first" and "second" check-in (the seeded tools and
  `aral_checkin_tools_checkpoint_check` are unchanged). Docs say so.
- `irip_weeks` N: a cycle has N weeks. The `aral_irip_weeks_week_no_check`
  (1-8) is widened to 1-26 and a trigger refuses week_no above the school's
  N; the SQLite mirror the same. Lowering N never deletes weeks already
  saved; the next cycle uses the new length (**call**).

### 6. Advisers and tutor type

- `sections.adviser_name` (text, optional) and `sections.adviser_user_id`
  (uuid, optional, a user of the section's school) (**call**: both, because
  an adviser is often not a BASA user, but the "own learners" check needs
  the link). Set with `section-update` arguments or a new
  `section-adviser <sectionId> <name|-> [userId]` command (**call**: the new
  command). Mirrored in SQLite (v46) by the pull. RLS unchanged (sections'
  existing write policy: admin/coordinator of the school, superadmin).
- `users.tutor_type` text null, `internal` / `external`. Set by
  admin/coordinator of the school (existing `users_update_scoped`) with a new
  `user-tutor-type <userId> <internal|external|->` command.
- `adviser_tutors_own_class = false`: refuse (device and server) placing a
  learner into a class whose tutor is the adviser (`adviser_user_id`) of the
  learner's home section, and setting a class's tutor to the adviser of any
  active learner's home section. Message names the learner and section.
- The tutor's advisory class (Form 2 column) = the section(s) where the
  tutor is `adviser_user_id` in that school year.

### 7. Class code suggestion

`AralClassViewModel.suggestClassName(schoolId, year, grade)` returns
`ARAL-R-G<grade>-<nn>` with the next free two-digit number for that school
and year (names compared ignoring case). Console `aral-class-add` uses it
when no name is given (**call**). Names stay free text.

### 8. ARAL Forms 1, 2 and 4 (Reading)

Admin build, read-only from the device copy, `.xlsx` with BASA's own layout
copying the form's columns and header fields (only the PDF exists, no
template file). New `AralFormsViewModel` (or methods on
`AralReportViewModel`, **call**: a new ViewModel), console
`aral-form1 <classId|all> <schoolId> <year> <file.xlsx>`,
`aral-form2 <schoolId> <year> <file.xlsx>`,
`aral-form4 <schoolId> <year> <asOf YYYY-MM-DD> <file.xlsx>`.
Fields BASA doesn't hold are left blank for hand entry; each form's footer
note lists them.

- Form 1, one sheet per class: school name, school ID, class code (class
  name), grade, learning area Reading, tutor, tutor type, session type
  (`aral_classes.session_type`, see below), days and time (`schedule`),
  venue (`room`), number of learners M/F/total. Rows (active learners, by
  last name): LRN, name (Last, First, MI), sex, home grade and section, class
  adviser (`adviser_name`), MoSY tool (CRLA for Grades 1-3, Phil-IRI 4-10),
  MoSY result (CRLA profile; Phil-IRI "Frustration" for 3+ levels down and
  non-readers, "Instructional" for 1-2 down, as the implementation report
  groups them), workbook issued (blank), remarks (blank). Blank: district,
  workbook issued, signatures.
- Form 2: one row per class: code, grade, area R, M/F/total, MoSY result of
  the class (the one result all its learners share, else "mixed"), tutor,
  type I/E, tutor's advisory class, days and time, session type, venue.
  Footer counts: reading classes, reading learners, internal and external
  tutors. Mathematics columns and counts blank.
- Form 4, Part I per grade 1-10 (Reading columns; Mathematics blank), as of
  a date:
  - Identified at BoSY: ARAL learners of the year whose basis round is BoSY.
  - Served in ARAL classes: ARAL learners placed in a class who were marked
    present at least once by the date (**call**).
  - Reached grade level (exited): exited as grade-level ready by the date.
  - Improved, still below (continue): still in ARAL, MoSY result better than
    BoSY (CRLA profile order; Phil-IRI adjusted level higher).
  - No improvement (referred): still in ARAL, MoSY result not better (or no
    MoSY result).
  - ARAL learners at MoSY: still in ARAL on the date.
  - Results follow the school's ARAL value source (carried / actual).
  - Part II: organized ARAL classes; tutors internal / external; sessions
    conducted and hours rendered (sum of session minutes / 60) by the date.
    Narrative rows blank.
- `aral_classes.session_type` text null, `pull_out` / `before_after`
  (memo item 14, one per class), set with `aral-class-edit`. Mirrored.

**call:** the Form 4 definitions above are mine; the owner (and the reading
coordinator) check them before the plan.

### 9. Docs

- README: 2b line for the new migration (app update required: **yes**, rules
  change: class cap, session checks, advisers); 7 the new commands.
- `tool/installer/guide/admin/Functions/ARAL-Reading.txt`: the settings, the
  over-maximum notice and how to move learners, the forms, and a short
  "Forms 3, 5 and 6" note: tutor details, printing and overload pay are kept
  in the separate tutor-management system, so BASA leaves them out; BASA
  gives each tutor's ARAL hours (sessions) for them.
- `docs/handoff/screens/`: a block for the settings screen fields and the
  forms export (UI owner builds them on `don`).
- CLAUDE.md module checklist line; `lib/core/CLAUDE.md` placement rules note
  (the cap is a setting now, read in three places).
- `docs/guides/BASA_ARAL` (html + pdf): class size and session rules are
  school settings; re-export the PDF.

## Constraints

- One migration (app update required: yes), ending with its
  `basa_migrations` row and listed in `lib/core/release.dart`; grants for any
  new table/view (none planned); RLS raised for every touched table
  (`aral_settings`, `sections`, `users`, `aral_sessions`, `aral_classes`,
  `aral_irip_weeks`).
- SQLite v46: new columns (sections adviser x2, users tutor_type,
  aral_classes session_type), triggers reading settings.
- Placement rules stay checked in the three documented places (ViewModel,
  SQLite trigger, server); all three read the same setting.
- Tutor build: settings reads and session/placement checks are shared;
  setting writes, adviser/tutor-type writes and the forms are admin
  (`*_admin_commands.dart`, `check_tutor_imports`).
- `dart analyze`, `flutter test`, the two tool checks, a PG test of the
  migration (placement, cap trigger with an over-cap class, session checks,
  sync_apply swaps), the command pass (both command lists change; new
  commands need pass scenarios).

## Left to the builder

- Order of work (suggested: settings plumbing + class size → sessions →
  basis round → check-ins/IRIP → advisers/tutor type → forms → docs).
- Exact message wording (plain, names the number and the setting).
- How the generic setting commands print values and sources (school /
  default / built-in), like `value-sources`.
