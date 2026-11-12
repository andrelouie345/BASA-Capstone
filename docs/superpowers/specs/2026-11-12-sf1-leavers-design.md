# Learners who leave a section (SF1 re-import: archive, move, return, anonymize) — design

Date: 2026-11-12. Status: approved in conversation (owner, section by section); this file awaits the owner's review.

## Why

ma (reading coordinator) asked on 2026-11-12: when a section's SF1 is imported again, BASA should notice learners it has enrolled who are no longer on the file, and ask per learner whether they **transferred out** to another school, **dropped out**, or **moved to another section** of the same school (which one?).

- Transferred out and dropped out: the learner is **archived**, never deleted. They may come back, and their data may be asked for. ma: keep archived learners 6 months; owner: the duration is a setting (default 6 months).
- Moved: the learner goes to the other section **with their data**.

Today an SF1 re-import only adds learners ("Already enrolled" for the rest) and never flags missing ones. `enrollments.status` (text, default `active`, no CHECK) is never changed by anything. A learner already enrolled in another section of the same school shows up on that section's SF1 as a generic conflict, "LRN already exists" (`sf1_importer.dart`, `_parseSheet`).

## Facts the design relies on

- `enrollments` has **one row per learner per school year** (`UNIQUE (student_id, school_year)`); a section move changes that row's `section_id`.
- Every learner list (`student_repository_*`) and the CRLA / Phil-IRI / GST insert triggers require `enrollments.status = 'active'`: a non-active enrollment drops off the lists and cannot be newly assessed, with no other change.
- `students.id` (not the LRN) is what every learner record points to: `enrollments`, `crla_assessments`, `phil_iri_assessments`, `phil_iri_gst_results`, `aral_enrollments`, `import_conflicts`.
- CRLA, Phil-IRI and GST rows carry `section_id`. `crla_assessments_unique_attempt` is `UNIQUE (student_id, school_id, section_id, subject_variant, school_year, attempt_no)`.
- A finalized Phil-IRI assessment cannot be changed at all (baseline trigger: "a finalized Phil-IRI assessment cannot be changed").
- `tutor_has_student` reads enrollments without checking status: a section's tutor can still read an archived learner.
- ARAL already has `aral-exit` (`transferred_out` / `dropped_out` / `other`, record kept read-only) and a section-move rule (record kept, new tutor) (memory/ARAL transfers; `aral-update` flags moved/left learners).
- SF1 import writes straight to the server (online) and mirrors to the device; it is never unsent work.

## Decisions (owner, 2026-11-12)

| # | Decision |
|---|----------|
| D1 | Transferred out / dropped out = **archive**: the enrollment's status changes; nothing is deleted. |
| D2 | After the archive period a learner is **anonymized, never deleted** (option B): personal fields cleared, records and **sex** kept (NLA filter); grade comes from the section. LRN becomes `ANON-<id>` (NOT NULL, unique). An anonymized learner can't be matched again: a returner comes in as a new learner. |
| D3 | Anonymizing is **never automatic**: an admin/coordinator runs it (preview + confirm code). Only learners whose every enrollment is archived, the newest archived more than `archive_keep_months` ago, **and** whose school year has ended (so EOSY and year reports are not shifted). |
| D4 | Who may archive, move, restore, anonymize: the **superadmin**, or the learner's school's **admin/coordinator** (option A). Admin build only; tutors refused. |
| D5 | A section move takes **this school year's** CRLA, Phil-IRI and GST records with it (new `section_id`); earlier years stay with their own sections. |
| D6 | A move is detected **from both files**: re-importing X lists the learner as missing ("moved to section …"); importing Y shows the row as "moving from X" instead of the generic conflict. One shared move action; whichever comes first, the move happens once. |
| D7 | Moves are **same grade only**; another grade is refused (CRLA is Grades 1–3 with per-grade stories, Phil-IRI passages are grade-level). |
| D8 | An archived learner on an SF1 of the same year shows as **returning** (archived on <date>, reason); the coordinator confirms; the enrollment becomes active again in that file's section, moved if it differs (same grade). ARAL is not restored automatically. |
| D9 | Missing learners the coordinator doesn't decide on **stay active**, are listed again ("not on the latest SF1 – undecided") on every re-import of the section, and in a school-wide list. The import never waits for these decisions. |
| D10 | Architecture: **one Postgres function per action**, online, one transaction each (option A). Rejected: app-side writes (not atomic, blocked by the finalize trigger); offline sync journal (heavy new sync machinery for an action done next to an online SF1 import). |
| D11 | Work in flight for a moved/archived learner: archive/move refuse while a **pending upload** holds the learner's records; on upload of unsent device work, `sync_apply` **re-points** this school year's records of a moved learner to the current section (same school, same grade) and notes it; an **archived** learner's records stop the upload with a named message. |
| D12 | Archive duration `archive_keep_months`: a `report_settings` key, school then region then 6, whole number 1–120. |
| D14 | (Added 2026-11-12 while planning, owner.) `sync_apply` runs as the uploader, and a tutor's insert policies only cover their own sections and ARAL class learners, so re-pointing alone (D11) would still be refused by RLS. A tutor may therefore still write **this school year's** CRLA, Phil-IRI and GST records of a learner who **moved away from one of their sections** (an `enrollment_moves` row from that section): new helper `tutor_had_moved_learner(student, school_year)` in the three insert policies and in `crla_assessment_writable` / `phil_iri_assessment_writable`. Their device stops listing the learner after the next pull, so in practice it only carries work done before the move. An **edit** of an already-uploaded record of a moved learner stays a normal sync conflict (resolved with `sync-resolve … server`). Rejected: refusing the moved learner's records (work lost); a time limit after the move. |
| D13 | Cross-server transfers (a learner who moves to a school on another BASA server: another division or a LAN server) are **out of scope**: v2 follow-up "learner transfer file" (export the archived learner's records, import them on the other server). Until then a coordinator answers a request by hand from `learner-history-lrn`. |

## 1. Statuses and data

**`enrollments`** (Postgres and SQLite mirror):
- `status` gets a CHECK: `active`, `transferred_out`, `dropped_out`. Archived = `transferred_out` or `dropped_out`.
- New columns `left_on` (date), `left_by` (uuid, the user who archived), `left_note` (text, optional). CHECK: `left_on` and `left_by` are set exactly when `status <> 'active'` (pattern of `aral_enrollments_exit`); `left_note` only then.

**New table `enrollment_moves`** (history, insert-only by the functions): `id`, `enrollment_id`, `student_id`, `school_id`, `school_year`, `from_section_id`, `to_section_id`, `moved_on` (date), `moved_by` (uuid), `source` (`sf1_missing` = decided from X's re-import, `sf1_incoming` = confirmed from Y's import, `return` = a restore into another section). It is the only record that the learner was in X once `section_id` is rewritten; learner history shows it. Mirrored to SQLite by pull (read-only on the device).

**`students`**: new column `anonymized_at` (timestamptz). When set: `lrn = 'ANON-' || id`, `last_name = 'Anonymized'`, `first_name = '—'`, `middle_name`, `birth_date`, `mother_tongue`, `ip_group`, `religion`, address fields, parents', guardian and contact fields, `learning_modality`, `remarks` null; `sex` kept.

**Setting** `archive_keep_months` in `report_settings` (D12), type- and range-checked by a CHECK like `no_comprehension_counts_FLT`.

**Migrations.** One Postgres migration: the CHECKs, columns, table, grants, RLS, the four functions, the finalize-trigger exception and the `sync_apply` change. Header: **`App update required on all devices: yes`** (the status CHECK and the rules change what older apps may write); README 2b lists it; ends with its `basa_migrations` row; id added to `lib/core/release.dart`. SQLite v44 (columns, table, CHECKs where SQLite can hold them).

## 2. The SF1 import flow

**Preview** (`import-sf1-trial`). Besides the existing row outcomes (insert, enrolled, conflict, skip), a row can be:
- **moving from X**: the LRN is actively enrolled this year in another section X of the same school with the same grade. Another grade → *other grade, can't move*, kept as today's conflict.
- **returning**: the LRN has an archived enrollment this year at this school (not anonymized): *archived on <date>, dropped out / transferred out*.

After the rows, a block **not on this SF1**: learners actively enrolled in this section this year who aren't in the file.

**Import** runs as today (new learners added, enrolled rows skipped). *Moving from* and *returning* rows are **not** applied by the import: they wait for a decision like the missing learners. They are not logged to `import_conflicts`.

**Decisions** (one console command per action, each calling its function; amended 2026-11-12 while planning, owner: only `learner-anonymize` takes a preview confirm code; archive, move and restore name one learner each, like `aral-exit`, and take none. The undecided list comes from a server table `sf1_last_imports` holding each section's last imported LRN set, so every admin device sees the same list):
- `sf1-archive <enrollmentId> transferred|dropped [note]`
- `sf1-move <enrollmentId> <sectionId>` (a missing learner, or confirming a *moving from X* row)
- `sf1-restore <enrollmentId> [sectionId]` (a returning learner; into the file's section)
- `sf1-missing [sectionId]` (undecided learners of the school, or of one section)

## 3. The actions (server functions)

All are `SECURITY DEFINER`, `SET search_path = public`; each first checks the caller (superadmin, or admin/coordinator of the learner's school; tutors refused), runs in one transaction and returns what it changed so the device copy is updated.

**`sf1_archive_learner(p_enrollment_id, p_reason, p_note)`**: an active enrollment only; `p_reason` `transferred_out` | `dropped_out`. Sets status, `left_on = current_date`, `left_by = auth.uid()`, `left_note`. An active ARAL enrollment of the learner in that school year is **exited** in the same transaction with the same reason (existing exit rules; record kept read-only). Refused while a pending upload holds the learner's records (D11).

**`sf1_move_learner(p_enrollment_id, p_to_section_id, p_source)`**: active enrollment; target section in the same school and school year, same grade, not the current one. Sets the enrollment's `section_id`; moves this school year's `crla_assessments`, `phil_iri_assessments`, `phil_iri_gst_results` of the learner to the new section:
- a finalized Phil-IRI assessment may get a new `section_id`, nothing else, and only from this function (narrow exception in the finalize trigger, e.g. a transaction-local flag the function sets);
- CRLA attempts that would collide with the learner's attempts already in the new section are renumbered after them, in their order;
- ARAL follows the existing section-move rule (record kept; the new section's tutor where that applies);
- writes one `enrollment_moves` row.
Refused while a pending upload holds the learner's records (D11).

**`sf1_restore_learner(p_enrollment_id, p_to_section_id)`**: an archived, not anonymized enrollment. Status back to `active`, `left_*` cleared; when `p_to_section_id` differs, then moves it as above (`source = 'return'`, same grade only). ARAL not restored (D8).

**`learner_anonymize(p_student_id)`**: allowed only under D3 for the caller's school (the superadmin: any). Clears the fields (section 1), sets `anonymized_at`. Console: `learner-anonymize-preview` (eligible learners + confirm code), `learner-anonymize <code>` (all of them).

## 4. ARAL, tutors and sync

- **Tutors**: an archived learner stays readable to the section's tutor (history) but leaves every active list and can't be newly assessed. A moved learner leaves the old section's tutor and appears for the new section's tutor with this year's records. ARAL class tutors keep their access rules.
- **Devices** take the changes in on the next `pull-cloud`: enrollments and the moved records are server rows the tutor didn't edit, so the merge replaces them.
- **Pending uploads** (D11): archive and move refuse, naming the upload; the coordinator approves or rejects it first.
- **Unsent device work** (D11): on upload, `sync_apply`
  - **moved learner**: re-points an incoming CRLA / Phil-IRI / GST record of this school year whose section is no longer the learner's to the learner's current section (same school, same grade), and notes it on the upload ("N records followed a section move");
  - **archived learner**: refuses the upload with a named message ("<name> was archived on <date> (<reason>): ask the coordinator to restore them, or delete these records with `sync-resolve`").
  This is a small change to the approved sync design (spec 2026-10-20); the only alternative is refusing moved learners too, which would fail a tutor's whole upload after any routine move.

## 5. Settings, RLS, code, testing

**Settings**: `archive-keep-months [n]` through `ReportSettingsViewModel` (admin build).

**RLS** (raised in the same migration):
- `enrollments`: insert/update WITH CHECK only allows clients to write `status = 'active'` (archive/move/restore only through the functions).
- `enrollment_moves`: select for the superadmin, the school's admin/coordinator, and tutors who can read the learner, checked on the row's own columns first (F14); no client insert/update/delete. Grants: select/insert/update/delete to `authenticated, service_role`, nothing to `anon` (`migration_grants_test`).
- `students`: anonymizing only through its function. Check for leftover wide-open placeholder policies before trusting any test.

**Code**: `LearnerLeaversViewModel` (admin build, `wire_admin`, `AdminViewModels`); the importer's trial gains the two row kinds and the missing block; console in `sf1_leaver_admin_commands.dart` (admin list in `tool/check_tutor_imports.dart`; admin count 257 → about 264, tutor stays 126); `[admin]` markers for the refusals; learner history shows archive and move entries.

**Testing**:
- PG18: each function's refusals (other school, other grade, tutor, pending upload, not eligible for anonymizing), finalized-round re-pointing, CRLA renumbering, ARAL exit, `sync_apply` re-pointing and refusal; insert policies tested with `RETURNING`.
- Pure Dart: the trial's new row kinds and missing block.
- Command pass: new scenario (archive → returning → restore; move from both files; anonymize refused before the window).
- `dart analyze`, `check_tutor_imports`, `check_vm_boundary`, `flutter test`; verify kit under `D:\0_CAPSTONE\verify\sf1-leavers\`.

**Screens**: the SF1 import preview and the missing/returning decisions need UI (admin build); listed in `docs/handoff/screens/` when the backend is done; who builds them is agreed with the owner then.

## Follow-ups (not in this piece)

- **v2: learner transfer file** (D13): export an archived learner's records; import them on another BASA server (matching by LRN, sections/rounds, conflicts, finalized rounds).
- Separate piece next (owner 2026-11-12): five school-wide `report_settings` switches, carried vs actual Phil-IRI results, for the ARAL list, BOSY masterlist, NLA Form 2b, SRP candidates, and progress/reminders/dashboard; plus ma's ranking list (lowest N by accuracy, words per minute or comprehension, per round and scope, actual values).
