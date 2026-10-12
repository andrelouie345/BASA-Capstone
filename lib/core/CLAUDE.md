# lib/core — data layer conventions

Nothing in `core/` imports Flutter. Keep it that way.

## Models (`models/`)
- Plain Dart classes. Nullable `id`, `toMap()` with snake_case keys (omit `id` when null), `factory fromMap(Map<String, Object?>)`. Dates are ISO strings.
- Part tables (`CrlaPart1Standard`, `CrlaPart1English`, `CrlaPart2Fluency`) have **no `id`**: `assessmentId` is both primary key and FK to `crla_assessments.id`, and is always included in `toMap()`.
- **Postgres generated columns are read-only.** `total_score`, `reading_level` (both Part 1 tables) and `wpm` are `GENERATED ALWAYS`. They are read in `fromMap()` but never written in `toMap()`; writing them errors in Postgres.
- `numeric` columns (`wpm`, `pct_correct_words_read`) can arrive as int or double: read as `(m['x'] as num?)?.toDouble()`.
- `CrlaResult` maps the `crla_results` view: read-only, no `toMap()`. `pctCorrectWordsRead` is a 0–1 fraction rounded to 4 places, not a percentage.
- Language normalization: `crla_language.dart` → `normalizeCrlaLanguage()` maps "Filipino" (case/space-insensitive) to "Tagalog". `CrlaAssessment.toMap()` writes `normalizedLanguage` (variant `fil` always stores "Tagalog"; otherwise the normalized string). `CrlaStory.toMap()` normalizes too, because stories will be imported from source files that say "Filipino". Normalization happens only on writes through `toMap()`; a raw SQL load can bypass it. Callers should use the row returned by `insert()`, not the in-memory object they passed in.

## Repositories
- Interface in `repositories/`, SQLite impl in `data/local/`, Supabase impl in `data/remote/`.
- `upsertWithId(...)` is for local mirroring only (keeps the cloud-generated id). Supabase impls throw `UnimplementedError`.
- Supabase `update()` pattern: remove the key from the payload, filter on it, call `.select()`, and throw if the result is empty (that is how an RLS rejection looks from the client).
- Supabase `insert()` returns the stored row via `.select()` so DB-assigned and DB-computed values (`attempt_no`, totals, wpm) come back.
- Repos don't catch `PostgrestException`; ViewModels and console commands decide how to report it.
- `crla_assessments` has **no update** on purpose: a retake is a new row.

## CRLA semantics
- `crla_assessments` snapshots `school_id` and `section_id` (not `enrollment_id`) so a transfer or re-import never rewrites a past assessment.
- `attempt_no` is assigned by the database and resets to 1 per (student, school, section, subject_variant, school_year). Never send it on insert. Postgres: `BEFORE INSERT` trigger `set_crla_attempt_no`. SQLite: column default 0 plus an `AFTER INSERT` trigger that fires only when `attempt_no = 0`, so mirrored rows keep the cloud's number. Because sqflite's `insert` returns only the rowid, **the SQLite repo must re-read the row** to get the assigned `attempt_no`.
- `subject_variant` ∈ `mt`, `fil`, `eng`. Standard Part 1 requires `mt`/`fil`; English Part 1 requires `eng`. Enforced in the DB by a variant-check trigger (Postgres: insert and update; SQLite: insert and update of `assessment_id`).
- Part 1 CHECKs (identical on both sides): standard — `task2_low_score` only when `task1_score < 7`, `task2_high_score` only when `task1_score >= 7`; English — `task2_score` must be NULL when `task1_score = 0`.
- Part 1 level thresholds: standard (task1<7: total ≤10 Full, >10 Moderate; task1≥7: total=task1+10+task2_high, <27 Light, ≥27 Grade Ready); English (0 Full, 1–10 Moderate, 11–16 Light, 17–20 Grade Ready).
- Part 2 time caps (1/2/3 minutes by grade/variant) are intentionally not enforced. `observation_level` is stored even though no formula uses it (deliberate).
- `crla_results.reading_profile` replicates the Excel formula U11 exactly, including the quirk that Full/Moderate Refresher always yields "Low Emerging Reader". Do not "fix" it without asking.
- `crla_results` returns every attempt. Latest-only logic lives in `crla_latest_attempts` (and the two summary views built on it).

## SQLite (`data/local/local_database.dart`)
- Version-numbered schema (currently around v10 — check the file). `onCreate` builds everything; `onUpgrade` re-runs the CRLA creators unconditionally at the end (all `IF NOT EXISTS`), after the schools rebuild, so new CRLA objects appear on upgrade. **Do not put new-table creators inside `if (oldVersion < N)` blocks that existing installs skip.** Bump the version when adding anything.
- Order matters: regions → students/schools/sections/enrollments → users → CRLA tables (they reference schools, students, sections, users).
- SQLite can't do `BEFORE INSERT` row rewrites, hence the attempt_no pattern above. Generated columns are avoided (need SQLite ≥ 3.31, which older Android lacks): totals, reading levels and wpm are computed by `AFTER INSERT` / `AFTER UPDATE OF <score cols>` triggers that write only the computed columns, so they cannot loop.
- The fluency insert trigger runs only `WHEN NEW.wpm IS NULL`, so rows mirrored from the cloud keep the cloud's wpm. Postgres and SQLite can differ by 0.1 at rounding boundaries; the cloud value wins. Mirroring `upsertWithId` is intended to use `INSERT OR REPLACE` so ids, `attempt_no` and wpm are preserved (verify in the code).
- `crla_results` also exists as a SQLite view with the same column names as the Postgres one.
- Anything changed here must keep local and cloud behavior symmetric (offline and cloud attempt numbering, CHECKs and triggers must agree).

## Supabase specifics
- `crla_assessments.administered_by` is a `users.id` (uuid, handled as a String). ViewModels set it from the signed-in user; repos don't.
- Postgres `date` columns come back as ISO strings; `birth_date` and `assessed_at` are `String` in models.
- Soft rule: ask for the real schema/policy text (or a read-only query the owner can run) before assuming anything about columns, constraints, triggers, or RLS you haven't seen. The schema dump omits table-level CHECKs, view options and policies.
