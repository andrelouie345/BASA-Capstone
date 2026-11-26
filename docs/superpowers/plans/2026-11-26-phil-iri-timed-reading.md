# Phil-IRI Timed Reading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Time a Phil-IRI reading inside BASA (start, pause, resume, stop, restart) and keep every timer tap as an add-only timing log that the server checks at upload.

**Architecture:** Pure-Dart rules (`phil_iri_timer.dart`) decide the order of taps and the seconds; the same rules live in a SQLite insert trigger and a Postgres insert trigger, and the server re-checks seconds against the log at the end of an upload. The log is a new synced child table of `phil_iri_readings`, added the way `phil_iri_workbook_imports` was (migration `20261109010000`, SQLite v40). `PhilIriViewModel` gets the timer calls; console commands in both builds; the screen is handed to the frontend team.

**Tech Stack:** Dart (pure core), sqflite_common_ffi + bundled SQLite, Supabase Postgres (PG18 harness for tests), console command framework.

**Spec:** `docs/superpowers/specs/2026-11-26-phil-iri-timed-reading-design.md` (approved 2026-11-26).

## Global Constraints

- Table `phil_iri_reading_timer_events`: `id`, `reading_id` (FK `phil_iri_readings`, on delete cascade), `seq`, `kind` in (`start`, `pause`, `resume`, `stop`, `reset`), `at` timestamptz (device clock with offset; SQLite: ISO-8601 text with offset), `created_by`, `created_at`, `row_version`; unique (`reading_id`, `seq`). Insert-only for server rows.
- Order after the last `reset`: `start`, then `pause`/`resume` pairs, then `stop`; `reset` allowed any time after a `start`; times never go backwards within a reading. Same rule in Dart, SQLite trigger, Postgres trigger.
- Seconds = (stop − start) − Σ(resume − pause), whole seconds rounded down, from the events after the last `reset`.
- One minute: stop dated at start + 60 s + pauses before it (also when added later); `wordsRead` = tapped word index + 1, refused beyond `PhilIriPassage.words`.
- A reading is **timed** when it has a `start` after its last `reset` (or any `start` with no `reset`); then `saveTiming` is refused with exactly: `This reading is timed in BASA; restart the timer to time it again.`
- `complete` refuses a session with a timed reading whose timer is running or paused.
- Untitled imported readings can't be timed (existing `_requireOpenReading` refusal).
- Migration header + ledger: `App update required on all devices: yes`; grants per `20261025010000` (select/insert/update/delete to `authenticated, service_role`, nothing to `anon`); every view/function `search_path = public`.
- SQLite version 49. Messages follow the 2026-11-17 wording rule (no field/table/command names, `notSignedInMessage` when signed out).
- Labels: `Timed in BASA` / `Time typed in`.
- No git commands by the executor; give the owner commit messages (owner rule). Backend only on `excelsior`.

## Review Focus

1. A tutor taps Stop twice (double tap on a phone): the second `stop` must be refused with a plain message, not a raw trigger error. Test in Task 1 (`refuses a second stop`) and Task 4 (`stopTimer twice -> ViewModelException`).
2. The device clock jumps back between taps (time-zone change, manual clock fix): a later tap with an earlier time is refused, and the tutor can restart. Test in Task 1 (`refuses a tap earlier than the last`).
3. A one-minute reading reopened long after 60 s: the stop is dated at the 60-second mark, seconds exactly 60, `timer()` shows stopped and asks for the minute end. Test in Task 4 (`one-minute stop dated at the mark after reopen`).
4. An upload where the device's `reading_seconds` was edited outside the timer (old app, or a bug) while a log exists: the server refuses the upload, naming the learner. Test in Task 2 (PG step `mismatched seconds refused`).
5. The tutor restarts the timer and then completes the session without timing again: after a `reset` with no new `start` the reading is not timed and has no seconds, so `complete` must refuse with the existing "not timed yet" refusal (not accept a reading with no time). Test in Task 4 (`reset then complete refused`).

---

### Task 1: Timer rules (pure Dart)

**Files:**
- Create: `lib/core/models/phil_iri_timer_event.dart`, `lib/core/services/phil_iri_timer.dart`
- Test: `test/core/services/phil_iri_timer_test.dart`

**Interfaces:**
- Produces:
  - `enum PhilIriTimerKind { start, pause, resume, stop, reset }` (`value` = the lowercase name; `fromString`).
  - `class PhilIriTimerEvent { int? id; int readingId; int seq; PhilIriTimerKind kind; DateTime at; String? createdBy; String? createdAt; Map<String, Object?> toMap(); factory fromMap(Map<String, Object?>); }` (`at` stored as ISO-8601 with offset; `toMap` omits null `id`, never sends `row_version`).
  - `enum PhilIriTimerStatus { none, running, paused, stopped }`.
  - `String? philIriTimerProblem(List<PhilIriTimerEvent> events, PhilIriTimerKind next, DateTime at)` → null when allowed, else the plain refusal.
  - `int? philIriTimedSeconds(List<PhilIriTimerEvent> events)` → null unless the current segment is stopped.
  - `PhilIriTimerStatus philIriTimerStatus(List<PhilIriTimerEvent> events)`; `Duration philIriElapsed(List<PhilIriTimerEvent> events, DateTime now)` (reading time so far, pauses excluded).
  - `DateTime philIriMinuteMark(List<PhilIriTimerEvent> events)` (start + 60 s + pauses before it; the one-minute stop time).
  - `bool philIriIsTimed(List<PhilIriTimerEvent> events)`.
  - Re-export the types from a `core/models/` file (`export ... show`) so commands may use them (VM boundary rule).

- [ ] **Step 1: Write the failing tests** — `seconds: start 0, pause 68, resume 99, stop 138 -> 107`; `seconds round down (stop at 10.9 s -> 10)`; `seconds null while running or paused`; `reset starts over: start, stop(30), reset, start, stop(+45) -> 45`; `refuses pause before start`, `refuses resume when not paused`, `refuses a second stop`, `refuses reset before any start`, `refuses a tap earlier than the last`; `status none/running/paused/stopped`; `elapsed excludes pauses`; `minute mark = start + 60 s + pauses before it`; `isTimed false after a reset with no new start`; `toMap/fromMap round trip keeps the offset`.
- [ ] **Step 2: Run** `flutter test test/core/services/phil_iri_timer_test.dart` — Expected: FAIL (files missing).
- [ ] **Step 3: Implement** the two files. Refusal texts (exact): `Start the timer first.`, `The timer is not paused.`, `The timer is already paused.`, `The timer is already stopped.`, `Start the timer before restarting it.`, `This time is earlier than the timer's last tap; check the device clock.`
- [ ] **Step 4: Run** the test — Expected: PASS. `dart analyze lib/core` — no errors.
- [ ] **Step 5: Commit message** to the owner: `feat(phil-iri): timer rules for a timed reading (pure Dart)`.

### Task 2: Server: table, rules, RLS, sync, evidence check

**Files:**
- Create: `supabase/migrations/20261126010000_phil_iri_timed_reading.sql`
- Modify: `lib/core/release.dart` (`'20261126010000': 'phil_iri_timed_reading'`), `README.md` (2b sentence; app update required: yes), `tool/command_pass/scenarios/21_t1.pass` (latest line)
- Test: `test/supabase/migration_grants_test.dart` (must stay green); PG harness steps in the verify kit `D:\0_CAPSTONE\verify\timed-reading\pg\` (owner-run)

**Interfaces:**
- Consumes: Task 1 rule texts (the SQL raises the same sentences).
- Produces: table + `public.check_phil_iri_timer_event()` BEFORE INSERT trigger (order, times, parent writable via `phil_iri_reading_writable`, `created_by` = `auth.uid()`, `seq` = previous + 1 required); policies `phil_iri_reading_timer_events_select` (`exists (select 1 from public.phil_iri_readings r where r.id = reading_id)`), `_insert` (`with check (public.phil_iri_reading_writable(reading_id))`), no update/delete policies; `sync_row_version` trigger; the table in `basa_private.sync_key_column` (`id`), `sync_ref_columns` (`reading_id`) and `sync_check_payload`'s allowed list and order (after `phil_iri_readings`) — copy the latest definitions (`20261112020000` for `sync_apply`/payload, `20261023040000` for key/ref) and add the table only; the D8 check `basa_private.phil_iri_timed_reading_problem(p_reading_id bigint) returns text` called from a DEFERRABLE INITIALLY IMMEDIATE constraint trigger on `phil_iri_readings` (update of `reading_seconds`, `words_read`) and on the events table, so `sync_apply` (which defers constraints) checks the final state; message `The reading of <last name>, <first name> (<passage title>) has a time that doesn't match its timer.`; ledger row `('20261126010000','phil_iri_timed_reading', true)` last; header line `App update required on all devices: yes`.

- [ ] **Step 1: Write the PG harness steps first** (`pg/timed_steps.sql`): as tutor (section tutor) insert a reading's events start/pause/resume/stop with `returning id` (accepted, F14); a second `stop` (refused, rule text); update/delete an event (refused: no policy); other school's coordinator `select` (0 rows); `sync_apply` of a package with a timed reading whose `reading_seconds` = log (applied) and one with seconds + 5 (refused with the D8 message, upload stays pending); rerun the migration (idempotent).
- [ ] **Step 2: Run** the harness without the migration — Expected: the steps fail (table missing).
- [ ] **Step 3: Write the migration** (idempotent: `create table if not exists`, `drop ... if exists` before each create).
- [ ] **Step 4: Run** the harness with it (twice) and `flutter test test/supabase/migration_grants_test.dart` — Expected: every step as listed; grants test PASS.
- [ ] **Step 5:** Owner applies on dev, pastes `select id, app_update_required from basa_migrations where id = '20261126010000';` → `true`. Commit message: `feat(phil-iri,sql): timing log table, rules, RLS and upload evidence check`.

### Task 3: Device: SQLite v49, repository, sync plumbing

**Files:**
- Modify: `lib/core/data/local/phil_iri_local_schema.dart` (table + insert trigger mirroring Task 2's order/time rules for `origin`-less local rows; pulled rows untouched), `lib/core/data/local/local_database.dart` (version 49, comment), `lib/core/data/pull_tables.dart` (all four maps, after `phil_iri_readings`; parent `('phil_iri_readings', 'reading_id')`), `lib/core/data/local/sync_local_schema.dart` (`_noServerUpdate` and the no-delete list), `lib/core/data/local/sync_local_repository_sqlite.dart` (table list; owner text "Phil-IRI reading timer"), `lib/core/services/sync_review_lines.dart` (fold under the reading), `lib/core/repositories/phil_iri_assessment_repository.dart` + `lib/core/data/local/phil_iri_assessment_repository_sqlite.dart` (`Future<PhilIriTimerEvent> insertTimerEvent(PhilIriTimerEvent e)` with `nextLocalId`; `Future<List<PhilIriTimerEvent>> timerEvents(int readingId)` by `seq`); the Supabase repository throws `UnimplementedError` for both (device-only, as other session writes).
- Test: `test/core/data/phil_iri_timer_v49_test.dart`, existing sync package tests

**Interfaces:**
- Consumes: Task 1 model; Task 2 column names.
- Produces: the two repository methods; the table pulled after `phil_iri_readings`, uploaded after it (inserts parents first), its local rows deleted with their reading (`deleteReading` cascades in SQL: add `ON DELETE CASCADE` and delete children explicitly in `deleteReading`, since local foreign keys are off).

- [ ] **Step 1: Write the failing tests:** `v48 -> v49 upgrade creates the table and keeps readings`; `a fresh v49 database has it`; `local insert out of order refused by the trigger`; `a pulled event can't be updated or deleted` (sync triggers); `deleteReading removes its events`; `the upload package lists events after their reading with negative ids followed` (extend the existing package test); `pull mirrors events of a pulled reading`.
- [ ] **Step 2: Run** them — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/core/data` and the sync tests — Expected: PASS. `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart` — clean.
- [ ] **Step 5: Commit message:** `feat(phil-iri,sqlite): timing log on the device (v49) and its sync`.

### Task 4: ViewModel

**Files:**
- Modify: `lib/viewmodels/phil_iri_viewmodel.dart`
- Test: `test/viewmodels/phil_iri_timer_test.dart`, `test/viewmodels/session_guard_test.dart` (add the new methods), `test/viewmodels/phil_iri_screen_calls_test.dart` (if it lists screen calls)

**Interfaces:**
- Consumes: Tasks 1 and 3.
- Produces on `PhilIriViewModel`: `Future<PhilIriTimerState> startTimer(int readingId, {DateTime? at})`, `pauseTimer`, `resumeTimer`, `stopTimer` (same shape; whole text/silent: saves `readingSeconds`; one minute: refused before the mark: `The one-minute timer stops by itself at 60 seconds.`), `resetTimer`, `Future<PhilIriTimerState> timer(int readingId)` (adds the one-minute stop at the mark when due), `Future<PhilIriReading> setMinuteEnd(int readingId, int wordIndex)` (one minute only, after its stop; `wordsRead = wordIndex + 1`). `class PhilIriTimerState { List<PhilIriTimerEvent> events; PhilIriTimerStatus status; Duration elapsed; bool timedInBasa; bool minuteEndNeeded; }` (in a `core/models/` file). `at` defaults to `DateTime.now()`.

- [ ] **Step 1: Write the failing tests:** `timed whole-text flow saves 107 s and scores`; `typed flow unchanged`; `saveTiming refused when timed` (exact text); `stopTimer twice -> ViewModelException`; `complete refused while running` and `while paused`; `reset then complete refused` (existing untimed refusal); `one-minute stop dated at the mark after reopen` (new ViewModel over the same database, `timer()` at 5 min → stopped, 60 s, `minuteEndNeeded`); `setMinuteEnd beyond the passage refused`; `Untitled reading can't be timed`; `a tutor without the section can't time` (existing writable check); session guard lists the 7 methods.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** (`_requireSignIn()` first; `_requireOpenReading`; refusals through Task 1's `philIriTimerProblem`). **Step 4: Run** `flutter test test/viewmodels/phil_iri_timer_test.dart test/viewmodels/session_guard_test.dart` — PASS; full `flutter test` once (not alongside analyze; slow machine).
- [ ] **Step 5: Commit message:** `feat(phil-iri): timer calls on the Phil-IRI ViewModel`.

### Task 5: Console, handoff, docs, command pass

**Files:**
- Modify: `lib/core/console/commands/phil_iri_commands.dart` (both builds): `phil-iri-timer-start|pause|resume|stop|reset <readingId> [at]` (`at` via `strictDateArg`-style date-time parsing; refuse a bad value with the existing date message), `phil-iri-minute-end <readingId> <wordIndex>`, `phil-iri-timer <readingId>` (prints status, elapsed, events, `Timed in BASA`/`Time typed in`); `test/core/wiring/tutor_commands.txt` and `admin_commands.txt` (+7 each); `tool/command_pass/scenarios/24_t4.pass` (a timed whole-text reading with a pause, a one-minute reading with minute end, a refused `phil-iri-time` on the timed reading, a second stop refused, upload approved); `docs/handoff/screens/phil-iri.md` (the spec's screen section + calls + labels); `CLAUDE.md` (Phil-IRI line: timing log, v49, migration; tutor/admin command counts) and `lib/core/CLAUDE.md` (the three-places rule for timer order).
- Test: command-set tests in `test/core/wiring/`; command pass.

- [ ] **Step 1:** Add the command-list lines first; run `flutter test test/core/wiring` — FAIL (commands missing).
- [ ] **Step 2: Implement** the commands. **Step 3: Run** `flutter test test/core/wiring`, `dart analyze`, both check tools — PASS/clean.
- [ ] **Step 4:** Command pass after the owner applied Task 2: `dart run tool/command_pass/run.dart` — Expected: 415/415 covered, 0 failed (**DO NOT PLAY RESOURCE INTENSIVE GAMES**; 30-minute updates if over an hour).
- [ ] **Step 5:** Verify kit `D:\0_CAPSTONE\verify\timed-reading\` (ids filled, expected outputs), consultation log M1-01 note (built; screen pending on `don`), commit message: `feat(phil-iri): timer console commands, handoff and docs`.
