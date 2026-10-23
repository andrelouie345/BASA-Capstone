# ARAL classes — design

Date: 2026-10-23. Status: design approved in conversation 2026-10-23 (sections 1-5); spec awaiting owner review.

## Goal

Give ARAL-Reading the groups tutors actually teach. DepEd Memorandum 064 s. 2025 caps a class at 15 learners (Encl. 2 item 7) and groups learners by reading profile rather than grade or section (Encl. 3 item 15); at VNHS a tutor teaches several sets of 15 (the special intervention sections plus learners other teachers ask to join). BASA today caps a **section** at 15 active ARAL learners and gives each learner a tutor directly; neither matches.

Success:
- Every active ARAL learner sits in at most one class; no class ever holds more than 15 active learners.
- A class keeps one program and one grade band; learners come from any section of the school.
- A tutor teaches any number of classes; the coordinator places and moves learners freely and their records stay with them.
- A class tutor reads and assesses the learners of their classes, whatever the learner's section.
- The 15-per-section rule is gone; teacher referrals are a way into ARAL.

Out of scope: UI (groupmates); any change to how Phil-IRI/CRLA are scored; ALS and ESC learners (no section in the school); LAN-specific work.

## Decisions (owner, 2026-10-23)

1. **15 active learners per class, hard stop** (cloud and device). Exited learners stay linked to the class but don't count.
2. **One program per class** (`foundational`, `ks1`, `ks2_basic`, `ks2_plus`, `ks3_basic`, `ks3_plus`) **and one grade band** (`1-3`, `4-6`, `7-10`, by the learner's grade). A Grade 6 may sit with Grade 4s; a Grade 7 is not put with Grade 2s.
3. A class belongs to a school and a school year, **not to a section**; a learner keeps their SF1 section and has **at most one class**.
4. A class has **one tutor, possibly blank** for a while; a tutor may teach several classes. A learner's tutor **is** their class's tutor (`aral_enrollments.tutor_id` is removed).
5. **Enrolling and placing are two steps.** A learner may be on the roster "waiting for a class"; such learners are listed and are in no session. A full class never blocks an enrolment.
6. **A session is one class's meeting**: attendance list = that class; one session per class per date; session numbers and check-ins (after sessions 16 and 32) count per class. The per-tutor "several sessions a day" setting is removed.
7. When `aral-update` changes a learner's program, **the learner stays in the class** and is flagged ("now KS2 Plus: move to a KS2 Plus class"). New placements and moves must match the class's program and band.
8. After a move, the **new tutor reads** (not edits) the learner's attendance in the old class's sessions (and those sessions' date/lesson/number); the old class's other learners stay hidden. IRIP, check-ins and readability follow the roster entry.
9. **Referrals:** a new basis `referral`, with `referred_by` and `referral_reason` required and the program picked by hand; the learner need not qualify by results. A referred learner is never exited with classroom support (only grade-level ready).
10. **Class tutors assess their class learners** (CRLA, Phil-IRI, GST) regardless of section, in addition to section tutors.
11. **Existing data:** existing ARAL learners become unplaced; existing sessions keep no class.
12. **Approach B: `aral_classes` is offline-first and synced** like the roster (owner's choice over an online-only class table).

## 1. Data model

### `aral_classes` (new; Postgres and SQLite; synced)

| column | notes |
|---|---|
| `id` | identity; negative device id when made offline |
| `school_id`, `school_year` | school-year format check as elsewhere |
| `class_name` | not blank; unique per school and year, ignoring case |
| `program` | one of the six programs above |
| `grade_band` | `1-3`, `4-6`, `7-10` |
| `tutor_id` | nullable; must be an active tutor of the school (checked when set) |
| `room`, `schedule`, `notes` | optional text |
| `created_by`, `created_at`, `updated_at` | stamped by trigger |
| `row_version` | sync |

Program and band may change only while the class has no learners (active or exited). A class is deleted only when no roster entry and no session points at it.

### `aral_enrollments`

- **Add** `class_id` (nullable, references `aral_classes`; null = waiting for a class).
- **Add** `referred_by`, `referral_reason` (text). `basis_source` gains `referral`; a check requires both texts exactly when the basis is `referral`.
- **Drop** `tutor_id` (and its tutor checks in the triggers).
- **Placement check** (cloud trigger; device trigger for local rows) whenever a row gets a class, changes class, or becomes active in one: same school and year as the class; the learner's program equals the class's program; the learner's grade (their section's `grade_level`) is in the band; fewer than 15 other active learners in that class (transaction advisory lock per class). A program change by `aral-update` that leaves the learner in their class is **not** re-checked (decision 7).
- **Remove** the 15-per-section cap (`aral_check_section_cap` and its calls, device and cloud).

### `aral_sessions`

- **Add** `class_id` (references `aral_classes`). Required for new sessions; sessions from before stay null and readable.
- `tutor_id` stays: who held the session (normally the class tutor; a coordinator may log one for a substitute).
- One session per class per date (replaces one per tutor per date). `session_no` numbers per class.

### `aral_attendance`

Unchanged (session × roster entry, present/absent/excused). Default list for a session = the class's learners active on that date.

### `aral_tutor_settings`

Dropped (its only setting, several sessions per day, is replaced by per-class sessions). Removed from the synced tables.

## 2. Sync

- `aral_classes` becomes the 19th synced table. **Server:** `row_version` + `basa_bump_row_version` trigger; added to the synced list in `basa_private.sync_check_payload`; `sync_apply` handles it through the existing generic paths. **Device:** added to `syncedTables` (`lib/core/data/pull_tables.dart`), so `createSyncLocalSchema` generates its journal, lock and new-id triggers; new classes get negative ids from `nextLocalId`.
- **References to new rows:** `aral_enrollments.class_id` and `aral_sessions.class_id` join `basa_private.sync_ref_columns` and the device's equivalent, so an upload may hold a new class and placements/sessions pointing at it; `sync_apply` remaps the negative id. Inserts: classes before roster entries and sessions (pull order); deletes: children first.
- **Who uploads classes:** only admins/coordinators may write classes (RLS), and their uploads apply at once, so class records never wait for an approver. A tutor's upload may hold sessions for their existing classes, never a class.
- **Conflicts and refusals** use the existing mechanisms: an edited-on-both-sides class is a normal conflict (`sync-resolve aral_classes <id> mine|server`); a duplicate class name or a class already full on the server refuses the upload at apply with a readable message; a new class waiting in a pending upload can't be referenced by new rows (existing lock).
- **Pull:** coordinators get the school's classes, tutors their own; classes are pulled before roster and sessions; the existing merge rules apply.
- **Wording:** `sync-preview` / `sync-show` describe classes (`ARAL class "7-Rose KS1" (G7-10, KS1, tutor …): new`) and placements (`… placed in class …`).
- `aral_tutor_settings` leaves the synced lists (server and device).

## 3. Access (RLS)

New SECURITY DEFINER helpers (`SET search_path = public`):
- `aral_tutor_has_class(class_id)`: the caller is a tutor and teaches that class.
- `aral_tutor_has_student(student_id)`: the caller is a tutor and the learner is **currently placed** in a class they teach (any status).

Policies:
- **`aral_classes`**: read — superadmin; admin/coordinator of the school; tutor where `tutor_id = auth.uid()`. Write (insert/update/delete) — superadmin; admin/coordinator of their own school. Tutors never write.
- **`aral_enrollments`**: tutor read = learner in a class I teach **or** `tutor_has_section(section_id)` (replaces `tutor_id = auth.uid()`). Writes unchanged (admin/coordinator), placements included. `aral_enrollment_readable` changes the same way (IRIP, check-ins and readability follow it).
- **Assessing (decision 10):** CRLA, Phil-IRI and GST insert policies and `crla_assessment_writable` / `phil_iri_assessment_writable` accept a tutor when `tutor_has_section(section)` **or** `aral_tutor_has_student(student)`. Assessments still record the learner's own section and school.
- **Reads for class learners:** `tutor_has_student` also returns true for `aral_tutor_has_student` (names; CRLA, Phil-IRI and GST reads). A tutor also reads such a learner's own `enrollments` row and their section's `sections` row (needed to assess and to pull), not the rest of that section.
- **`aral_sessions`**: insert — tutor for a class they teach with `tutor_id = auth.uid()`; admin/coordinator for any class of their school. Read — tutor: sessions they held or of their classes, plus the header of an older session in which one of their current learners has a mark (decision 8). Update/delete — as today through `aral_session_writable` (held by me or of my class; admin/coordinator of the school).
- **`aral_attendance`**: read — marks of sessions the tutor can write, plus their current learners' own marks in older sessions. Write — unchanged (the session's writer).
- `aral_tutor_settings` and its policies are dropped. No new views.
- Before trusting results, check for leftover wide-open policies.

## 4. ViewModels and commands

- **`AralClassViewModel`** (new, `lib/viewmodels/aral_class_viewmodel.dart`): `createClass`, `editClass`, `deleteClass`, `place(enrollmentId, classId)` (also moves), `unplace` — admin build; `classes(schoolId, year)` (tutors: their own), `classRoster(classId)` — both builds. Device checks mirror the triggers so the device refuses first with a readable message.
- **`AralViewModel`**: `enroll` takes an optional class; `enrollProposed`'s tutor becomes a class (fills it weakest first up to 15, the rest unplaced and named in the warning); `assignTutor` removed; new `refer(…)` (referred by, reason, program); `reactivate` puts the learner back unplaced (with a warning) when their class is full; `applyResults` adds informational lines (program mismatch with the class, waiting for a class, now in another section, left the school) and never moves anyone; `moveToSection` (F9b) follows an SF1 section move inside the school — the class stays unless the new grade leaves its band (then unplaced and flagged); a school move is an `aral-exit … transferred_out`. Roster CSV export and import use the class (import column `Class`; a full or mismatched class leaves the row unplaced, flagged in the preview).
- **`AralSessionViewModel`**: `logSession` takes a class (tutors: their own classes; admin/coordinator: any class of the school); default list, one-per-date, numbering and check-in timing per class; the several-sessions-a-day methods are removed; `learnerAttendance` includes marks from earlier classes; tutor summary per class.
- **Reminders / dashboard**: tutor reminders per class (no session lately, check-ins due, learners not assessed); coordinator reminders add unplaced learners, program mismatches and classes without a tutor.
- **CRLA / Phil-IRI ViewModels**: no device-side section check exists; class learners become assessable once RLS and pull provide their rows.
- **Console** (one action per command): new admin `aral-class-add`, `aral-class-edit`, `aral-class-delete`, `aral-class-place`, `aral-class-unplace`, `aral-refer`, `aral-move`; new in both builds `aral-classes`, `aral-class-show`; `aral-log` / `aral-sheet` take a class; roster lines show the class; removed `aral-tutor`, `aral-tutor-multi`. Command lists, the tutor-build split (`tool/check_tutor_imports.dart`), the read-only list and the session-guard test are updated.

## 5. Build, release, testing

**Release:** one migration, `App update required on all devices: yes` (columns removed, rules changed). The server SQL is written and tested first but **applied last**, together with the finished app (the version check refuses older apps). Before applying: every device synced, every upload decided (README *Keeping BASA up to date*).

**Pieces** (each: build, test, owner check, commit message):
1. **C1 server SQL** — migration (table, helpers, RLS, roster/session changes, drops, referral, sync lists, ledger row); PG18: chain loads, runs twice, RLS matrix. Not applied.
2. **C2 device schema** — SQLite v36: `aral_classes` + triggers, rebuilds of `aral_enrollments` / `aral_sessions` copying every column (incl. `row_version`), drop `aral_tutor_settings`, device sync lists; tests: upgrade from v35, real database copy.
3. **C3 models and repositories** — class model, SQLite repository, pull.
4. **C4 classes** — `AralClassViewModel` + class commands.
5. **C5 roster** — enroll/refer/proposal/update flags, F9b transfers, import/export.
6. **C6 sessions and dependants** — attendance, check-in timing, reminders, dashboard.
7. **C7 wording, lists, docs** — sync texts, command lists, CLAUDE.md files, README 2b, `release.dart`, memory.
8. **C8 go live** — owner applies the migration; command-pass A4 (classes, referrals, transfers), T5/T6 updates; B0 creates a class, so the full pass runs on a new run (r6).

**Testing:** pure-Dart tests for placement rules (same cases as the triggers); SQLite trigger and upgrade tests; PG18 RLS matrix with superadmin, coordinators of two schools, two tutors, a learner joining from another section and a learner moved between classes (reads, writes, assessing, history); session-guard entries for every new public method; live command-pass batches with hand-worked figures where computed.

**Risks:** the two table rebuilds must keep `row_version` (else synced rows look new) — the v35 rebuild pattern and its test; pull order (classes before roster/sessions); the per-class cap under two coordinators placing at once — per-class advisory lock.
