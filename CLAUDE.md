# BASA (ARAL-Read) — project guide

Flutter/Dart reading-assessment app for tutors (DepEd ARAL-Reading program, Phil-IRI / CRLA instruments; CRLA is administered to Grades 1–3 only). Capstone project, team of several; **this repo's owner works on the backend only** (models, repositories, ViewModels, console, SQL). Groupmates own UI — do not build or restyle UI unless explicitly asked.

> These guides were assembled from working notes, not generated from the code. If anything here disagrees with the repo, the repo wins: tell the user about the mismatch and fix the doc.

## Stack
- Flutter/Dart, MVVM. Offline-first: **SQLite** (sqflite on mobile, sqflite_common_ffi on desktop/console) mirrored from **Supabase** (cloud, plus an optional self-hosted LAN Supabase/Postgres using the same client with a different URL).
- Supabase URL/anon key (cloud + LAN) are runtime-editable via console `config-*` commands and persisted to disk (`<data dir>/supabase_config.json`). Nothing is hardcoded: when no config file exists, defaults come from build-time defines `BASA_CLOUD_URL`, `BASA_CLOUD_KEY`, `BASA_LAN_URL`, `BASA_LAN_KEY` (`flutter run/build --dart-define=...`, `dart run -D...`), else empty.
- The app only ever uses the anon key. Never put a `service_role` key in the app or console. Admin account creation goes through a server-side Edge Function.
- Tests are done through the developer console (`lib/console/main.dart`, plain `dart run`, no Flutter engine), plus `dart analyze`.

## Layout (lib/)
```
console/main.dart                  console entry point
main.dart                          Flutter entry point
core/                              pure Dart — NEVER imports Flutter
  console/                         command framework + commands/ (one file per module)
  data/local/                      SQLite repos + local_database.dart (schema, triggers, views, migrations)
  data/remote/                     Supabase repos, supabase_config, auth_session_store
  models/                          plain Dart models
  repositories/                    abstract interfaces
  services/                        sf1_importer, sf1_column_map, roster_exporter, xls_to_xlsx_converter, ...
  viewmodels/viewmodel_registry.dart
viewmodels/                        ViewModels (also never import Flutter)
ui/                                debug overlay, mobile/, windows/  (not the owner's area)
```

## Module workflow (follow this order)
pure-Dart model → abstract repository interface → SQLite implementation (+ Supabase implementation) → ViewModel with a per-module `ScopedLogger` → console commands (one action per command, files in `core/console/commands/`) → wire into **both** `console/main.dart` and `main.dart` → test through the console → only then does UI call the **ViewModel directly** (never the console command strings).

Module checklist: Login/user management (done), Learner Management (covered by student/enrollment code), Import-export (SF1 import/export; CRLA scoresheet import + export into the DepEd CRLA2 template; ARAL implementation report export in the template layout, roster/check-in/report CSV, roster import — all done; templates are passed by path for now), **CRLA (backend, ViewModel and console done)**, **Phil-IRI (backend, both ViewModels and console done; passages seeded from `supabase/seeds/`)**, **ARAL (backend, ViewModels and console done: roster, sessions/attendance, IRIP, automatic updates, implementation report, check-in assessments with an adjustable cut-off and a per-section report)**, **Learning material recommendations (ARAL only, done: catalog with file names + Google Drive links (no files in Supabase), per-school links, recommendations by ARAL program, SHARP switch; readability log (Flesch ease/grade) kept only while SHARP is on)**, Dashboard (in progress, spec `docs/superpowers/specs/2026-10-19-dashboard-design.md`; D1 round calendar done: `assessment_calendar` region windows + school overrides/skips, `RoundCalendarViewModel`, `calendar-*` commands; D2 coordinator reminders done: `report_settings` saved done threshold (`ReportSettingsViewModel`, `report-settings-*`), progress shows NOT SCHEDULED for rounds the calendar does not hold, `ReminderViewModel.coordinatorReminders` + `reminders-coordinator`), Statistics/Report (built last; 2026-10-19: NLA portal report = Phil-IRI for JHS Form 2b + the Division's ARAL report, with sex/round/block/section filters; progress monitoring with an adjustable done threshold; BOSY masterlist of learners not grade level ready; Summer Remediation Program: ranked candidates + classes with tutor/room/schedule (`srp_classes`, `srp_class_members`; an SRP tutor reads only the learner rows of their classes)). Build order is fixed: CRLA → Phil-IRI → ARAL (ARAL depends on both).

## Data model (Postgres, snake_case; SQLite uses identical table names)
- Schema files: `supabase/migrations/20261018040000_baseline.sql` is the whole schema (squashed from the live project, 2026-10-18). Every later change is a NEW migration file newer than it; never edit the baseline. **Hard requirement (owner 2026-10-19):** the database and every device run the same BASA release (README *Keeping BASA up to date*); every new migration's header says `App update required on all devices: yes/no` (yes when it changes rules: rounds, required values, renamed/removed columns; no for pure additions) and README 2b lists it. `supabase/migrations_archive/` holds the 29 old migrations as history only (they can't build a fresh DB). Content comes from `supabase/seeds/`.
- Core: `regions` (18 PH regions, ids 1-18 in a fixed order, e.g. 7 = NCR, 13 = Region X; rows from `supabase/seeds/regions.sql`), `schools` (region_id FK), `sections` (school_id, school_year, grade_level, section_name), `students` (keyed by `lrn`, school_id), `enrollments` (student-section-year, status), `import_conflicts`, `users`, `login_logs`, `tutor_section_assignments` (many-to-many: a tutor can have many sections, a section many tutors).
- Dashboard: `assessment_calendar` (round windows per school year/instrument/round; `school_id` null = region default, else school override or `skipped`; rounds per instrument = the `PhilIriRound`/`CrlaRound` enums (`calendarRounds` is built from them) and the cloud check `assessment_calendar_round_pairing`; change them together, see `lib/core/CLAUDE.md`; rows the app doesn't know are ignored on read and shown as INVALID), `report_settings` (jsonb per region/school like `aral_settings`; `done_threshold` 0.01-1, default 0.85, read by progress monitoring and reminders).
- CRLA: `crla_stories`, `crla_assessments`, `crla_part1_standard`, `crla_part1_english`, `crla_part2_fluency`, plus views `crla_results`, `crla_latest_attempts`, `crla_section_summary`, `crla_school_summary`, `crla_school_summary_weighted`. Details and gotchas are in `lib/core/CLAUDE.md`.
- Phil-IRI (English, Grades 4–10): content `phil_iri_collections`, `phil_iri_rubric_criteria`, `phil_iri_passages`, `phil_iri_questions`, `phil_iri_thresholds`; assessments `phil_iri_gst_results`, `phil_iri_assessments` (rounds bosy/mosy1–3/eosy), `phil_iri_readings`, `phil_iri_miscues`, `phil_iri_answers`, `phil_iri_rubric_scores`. Scoring rules live in `lib/core/services/phil_iri_rules.dart` / `phil_iri_results.dart` with adjustable thresholds.
- Multi-school by design: one regional database, many schools. Identical section names across schools must not collide.
- `sections.grade_level` is always a bare numeric string ("7", not "Grade 7") — normalized by `normalizeGradeLevel()` (SF1 importer, section-create). It throws on non-numeric input on purpose (no Kindergarten in BASA).

## Roles and access
- Roles: `admin`, `coordinator`, `tutor`. Admin and coordinator have identical permissions (the two names are kept distinct, nothing more).
- Superadmin = admin with `school_id` null (regional). Admin/coordinator with `school_id` set are school-bound. Coordinators are always school-bound.
- Tutors only see/edit their assigned sections and those sections' students (RLS via `tutor_has_section` / `tutor_has_student`).
- Login: first login requires being online (Supabase Auth); sessions do **not** persist across app restarts; login attempts are logged to local SQLite **and** Supabase; `is_active` is enforced as part of user management; admin-created accounts get a temp password and `must_change_password`.

## RLS rules (important)
- Whenever a table or view is added or touched, raise its RLS policies in the same piece of work.
- Before trusting a test result, check for leftover wide-open placeholder policies ("allow all", "authenticated users can read X"). They have caused false passes twice (schools, students).
- Every view must be `security_invoker = true`, otherwise it bypasses RLS. All five `crla_*` views were verified.
- Policy pattern: `is_superadmin()` OR own-school-only for admin/coordinator; tutors via the section/student helper functions. All SECURITY DEFINER functions use `SET search_path = public`.

## Offline and sync (design intent; sync is PARKED)
- Intended flow: login (online) pulls the cloud data scoped to that user into the local DB; modules work offline from the local copy; offline edits sync back later after a review step. A different user logging in on the same device replaces the local cache (warn first).
- DB switching (`db-use local|cloud|lan`) only works on `testTable`, and its clients are anonymous. Real repos will need the signed-in client. Deliberately not designed yet.
- `lib/core/console/commands/pull_commands.dart` (`pull-cloud`) is a **temporary one-way** cloud→local copy. It **replaces** the local data with everything the signed-in user can read: it downloads first, then clears and rewrites the data tables in one transaction (regions and login_logs kept). So an admin's pull holds everything, and a tutor's later pull leaves only the tutor's scope. It refuses while un-uploaded CRLA assessments exist (`crla_assessments.origin = 'local'`) unless run as `pull-cloud yes discard-local`. `sync_meta` records who pulled last. The owner wants to reuse it as part of the eventual sync mechanism; its logic still lives in the console command, not a ViewModel.
- Sync gets designed after the remaining modules, but before real field data lives only on devices.

## Parked / known follow-ups
- Sync + DB-switching redesign (above).
- Grade-based rule checks (e.g. English only for Grade 3) are intentionally NOT in the ViewModel until the tutor-capabilities phase.
- A build variant that physically excludes admin-only modules from the tutor build (not just hides them in UI) is a high-priority future requirement.
- `crla_stories` is seeded only for region 13 (Northern Mindanao), grades 1–3. A section in another region gets no story match, so the view returns NULL for `pct_correct_words_read` and `reading_profile`. This is expected, not a bug. CRLA assessments for sections outside Grades 1–3 are refused by the cloud insert policy (M4).
- Story import from source workbooks is planned (see the language normalization note in `lib/core/CLAUDE.md`).
- `config-set-*-url` commands don't validate the URL.

## Commands
- `dart analyze` — run after every piece. Existing lint warnings (unused imports, underscore names) are accepted; errors are not.
- Console: `dart run lib/console/main.dart` (confirm the exact invocation; the console must work without Flutter).
