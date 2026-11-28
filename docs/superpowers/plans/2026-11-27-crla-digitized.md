# Digitized CRLA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give CRLA inside BASA: Part 1 items marked one by one, the Part 2 story marked word by word with an in-app timer that stops at the grade's limit, comprehension marked per question, and the existing totals, levels and profile computed from those marks, which the server checks at upload.

**Architecture:** Content (Part 1 items, story text, questions) for the 19 Region X forms is typed into a JSON source in the repo, checked by a repo tool and turned into a seed. Four synced evidence tables under `crla_assessments` (item marks, word marks, answers, timer taps) feed the existing `crla_part1_*` / `crla_part2_fluency` rows, written by `CrlaViewModel` after every mark. The Phil-IRI timer rules become a shared, instrument-free rule file; the same order/time rules live in Dart, a SQLite trigger and a Postgres trigger, and a deferred server check refuses digitized attempts whose totals don't match their marks (as `phil_iri_timed_reading_check`).

**Tech Stack:** Dart (pure core), sqflite_common_ffi + bundled SQLite, Supabase Postgres (PG18 harness), console command framework, the demo builder.

**Spec:** `docs/superpowers/specs/2026-11-27-crla-digitized-design.md` (approved 2026-11-27). Pattern source: `docs/superpowers/plans/2026-11-26-phil-iri-timed-reading.md` and its migrations `20261126010000` / `20261126030000`.

## Global Constraints

- Migration `20261127010000_crla_digitized.sql`: header `App update required on all devices: yes`; ledger row last; grants per `20261025010000` (select/insert/update/delete to `authenticated, service_role`, nothing to `anon`; content tables too); every function `set search_path = public`; `lib/core/release.dart` and README 2b list it; `21_t1.pass` latest line.
- SQLite version **51** (now 50).
- Content tables (read: every signed-in user; write: superadmin only): `crla_stories.body text` (one sentence per line, null = no digitized text), `crla_part1_items` (`id`, `region_id`, `language`, `grade`, `task` in `task1`,`task2_low`,`task2_high`,`task2`, `item_no` 1.., `text`, `sentence_no` null for word lists; unique (region, language, grade, task, item_no)), `crla_story_questions` (`id`, `story_id` FK `crla_stories`, `question_no` 1.., `after_sentence`, `question`, `accepted_answers`; unique (story_id, question_no)).
- Evidence tables (synced children of `crla_assessments`, on delete cascade, `row_version`, `created_by`): `crla_part1_marks` (`assessment_id`, `task`, `item_no`, `correct` bool, `self_corrected` bool default false; unique (assessment_id, task, item_no)); `crla_part2_word_marks` (`assessment_id`, `story_no`, `word_index` 0-based, `kind` in `miscue`,`self_corrected`; unique (assessment_id, word_index)); `crla_part2_answers` (`assessment_id`, `story_no`, `question_no`, `mark` in `correct`,`incorrect`,`not_asked`; unique (assessment_id, question_no)); `crla_timer_events` (`assessment_id`, `story_no`, `seq`, `kind` start/pause/resume/stop/reset, `at` timestamptz; unique (assessment_id, seq); insert-only for server rows).
- `crla_part2_fluency.last_word_reached smallint` (0-based word index; null = whole story).
- An attempt is **digitized** when it has any evidence row. Then typed saves are refused with exactly: `This attempt is marked in BASA; change its marks instead of typing totals.` Typed attempts behave exactly as today.
- Part 2 evidence of one attempt uses one story (`story_no` the same on every row; the trigger refuses another).
- Words read (digitized) = `(last_word_reached ?? lastIndex) + 1 − miscues among words ≤ last_word_reached`; a miscue mark after `last_word_reached` is refused: `That word is after the last word reached.` Typed: `crlaWordsRead` as today. Three places: Dart `crla_rules.dart` + `crla_digitized.dart`, SQLite trigger, `check_crla_part2_limits`.
- Timer limit = `crlaTimeCapSeconds(grade, variant)` (60/120/180). At the limit the stop is dated start + limit + pauses (as `philIriMinuteMark`, generalized). After an automatic stop the Part 2 row is not written until `last_word_reached` is set (`Tap the last word the learner reached.`).
- Part 1: Task 2 allowed only as the Task 1 score leads (standard: < 7 → `task2_low`, else `task2_high`; English: Task 1 = 0 → no Task 2, refusal `Task 1 is 0: the test ends here.`). A Task 1 change that switches the Task 2 needs `confirm: true` and then deletes the other Task 2's marks; without it: `This changes which Task 2 is given; confirm to clear its marks.` `closeTask` marks every unmarked item of the task wrong.
- Comprehension correct = count of `correct`; `not_asked` counts as not correct.
- Digitizing is refused when no form matches: `No digitized CRLA form for this school's region, language and grade: enter the totals instead.`
- Content is committed (owner 2026-11-27: "keep content inside the repo, it's public data"): source `supabase/seeds/crla_content/region10.json`, generated seed `supabase/seeds/crla_content_region10.sql` (idempotent; loaded by the owner in the SQL editor after the migration).
- Messages follow the 2026-11-17 wording rule; labels `Marked in BASA` / `Totals typed in`.
- No git commands by the executor; commit messages to the owner. Backend on `excelsior`. Every report and commit message carries an `Objective:` line (ii).

## Review Focus

1. The tutor taps a word twice quickly (double tap on a phone): it must end unmarked or marked, never two rows or a raw unique-key error. Test in Task 5 (`double tap on a word is one toggle`).
2. The timer hits the limit while the app is closed; reopened later, the stop is dated at the limit, the Part 2 row waits for the last word, and the seconds are exactly the limit. Test in Task 5 (`auto-stop dated at the limit after reopen`).
3. A tutor marks miscues past where the learner stopped, then sets the last word reached earlier: the later miscues must be refused at the last-word step (`That word is after the last word reached.` → the tutor removes them first). Test in Task 5 (`last word before a marked miscue refused`).
4. Task 1 is re-marked so the other Task 2 applies, after Task 2 was marked: without confirm nothing changes; with confirm the old Task 2 marks are gone and the totals follow. Test in Task 5 (`task 1 change switching task 2 needs confirm`).
5. An upload where a device's Part 2 totals were edited outside the marks (an old app): the server refuses it, naming the learner. Test in Task 3 (PG step `mismatched totals refused`).

---

### Task 1: Shared timer rules and CRLA rules (pure Dart)

**Files:**
- Create: `lib/core/services/reading_timer.dart`, `lib/core/services/crla_digitized.dart`, `lib/core/models/crla_marks.dart`
- Modify: `lib/core/services/phil_iri_timer.dart` (thin wrappers over `reading_timer.dart`, same names and texts)
- Test: `test/core/services/reading_timer_test.dart`, `test/core/services/crla_digitized_test.dart`; `test/core/services/phil_iri_timer_test.dart` must stay 20/20

**Interfaces:**
- Produces:
  - `reading_timer.dart`: `enum TimerTapKind { start, pause, resume, stop, reset }`; `typedef TimerTap = ({TimerTapKind kind, DateTime at})`; `enum TimerStatus { none, running, paused, stopped }`; `String? timerProblem(List<TimerTap> taps, TimerTapKind next, DateTime at)`; `TimerStatus timerStatus(List<TimerTap>)`; `int? timedSeconds(List<TimerTap>)`; `Duration timerElapsed(List<TimerTap>, DateTime now)`; `DateTime limitMark(List<TimerTap>, Duration limit)`; `bool isTimed(List<TimerTap>)`. Texts = the Phil-IRI ones.
  - `crla_marks.dart`: `enum CrlaTask { task1, task2Low, task2High, task2 }` (`value` = `task1`, `task2_low`, `task2_high`, `task2`); `enum CrlaWordMarkKind { miscue, selfCorrected }` (`miscue`, `self_corrected`); `enum CrlaAnswerMark { correct, incorrect, notAsked }` (`correct`, `incorrect`, `not_asked`); `CrlaPart1Mark`, `CrlaWordMark`, `CrlaAnswer`, `CrlaTimerEvent` (fields per Global Constraints; `toMap`/`fromMap`, ISO time with offset as `PhilIriTimerEvent`); `CrlaPart1Item`, `CrlaStoryQuestion`.
  - `crla_digitized.dart`: `List<List<String>> crlaStorySentences(String body)` (lines → words split on whitespace, punctuation kept); `List<String> crlaStoryWords(String body)`; `CrlaTask? crlaTask2For(String variant, int task1Score)`; `int crlaTaskScore(List<CrlaPart1Mark> marks, CrlaTask task)` (correct or self-corrected); `int crlaDigitizedMiscues(List<CrlaWordMark>, int? lastWordReached)`; `int crlaDigitizedWordsRead({required int wordCount, int? lastWordReached, required List<CrlaWordMark> marks})`; `int crlaComprehensionFromAnswers(List<CrlaAnswer>)`.

- [ ] **Step 1: Write the failing tests** — reading_timer: the Phil-IRI cases ported (`start 0, pause 68, resume 99, stop 138 -> 107`, the six refusals, `limitMark = start + limit + pauses before it`); crla_digitized: `sentences of "Para flies away.\nIt is dark." -> [[Para, flies, away.], [It, is, dark.]]`, `Iba't and Puting-puti are one word each`; `task2For mt 6 -> task2Low, 7 -> task2High, eng 0 -> null, eng 1 -> task2`; `taskScore counts correct and self-corrected`; `words read: 100 words, no last word, 3 miscues -> 97`; `last word 59, miscues at 10 and 70 -> 59` (70 ignored for the count, refused elsewhere); `comprehension counts correct only (not_asked = 0)`.
- [ ] **Step 2: Run** `flutter test test/core/services/reading_timer_test.dart test/core/services/crla_digitized_test.dart` — Expected: FAIL (files missing).
- [ ] **Step 3: Implement**; rewrite `phil_iri_timer.dart` as wrappers (convert `PhilIriTimerEvent` → `TimerTap`; `philIriMinuteMark(e) = limitMark(e, 60 s)`).
- [ ] **Step 4: Run** the two new tests + `test/core/services/phil_iri_timer_test.dart` — Expected: PASS (Phil-IRI 20/20 unchanged). `dart analyze lib/core` clean.
- [ ] **Step 5: Commit message** `refactor(timer): shared reading-timer rules; feat(crla): digitized CRLA rules (pure Dart)`.

### Task 2: Content format, checker and seed builder + the 19 forms

**Files:**
- Create: `tool/crla_content/content.dart` (load/validate), `tool/crla_content/check.dart` (`dart run tool/crla_content/check.dart <region10.json>` prints per-form OK / problems), `tool/crla_content/build_seed.dart` (writes the idempotent SQL: `update crla_stories set body`, upsert items and questions), `tool/crla_content/README.md` (the JSON format)
- Create: `supabase/seeds/crla_content/region10.json`, generated `supabase/seeds/crla_content_region10.sql`
- Test: `test/tool/crla_content_test.dart` (a 2-form fixture in the test, not real content)

**Interfaces:**
- Consumes: `crlaStorySentences`, `crlaComprehensionMax`, `CrlaTask` (Task 1).
- Produces: JSON format: `{ "region_id": 13, "forms": [ { "language", "grade", "variant", "tasks": { "<task>": [ {"text", "sentence_no"?} ] }, "stories": [ { "story_no", "title", "word_count", "sentences": [ {"text", "words"} ], "questions": [ {"after_sentence", "question", "accepted_answers"} ] } ] } ] }`. `List<String> checkCrlaContent(CrlaContent c, Map<(String language, int grade, int storyNo), ({String title, int wordCount})> stored)` → problems (empty = OK).

- [ ] **Step 1: Failing tests** — `a sentence whose words differ from its printed count is a problem`; `a story total differing from crla_stories.word_count is a problem` (stored map from the 38 known rows: the test holds the English G3 pair `Para the Parrot 100`, `A Day in the Fields 100`); `a task with other than its printed maximum of items is a problem` (10 on every Region X form seen so far; the JSON states each task's maximum); `a story with other than crlaComprehensionMax(grade, variant) questions is a problem`; `a title differing from crla_stories is a problem`; `the seed is idempotent SQL: update ... where region/language/grade/story_no; insert ... on conflict do update`.
- [ ] **Step 2: Run** `flutter test test/tool/crla_content_test.dart` — FAIL.
- [ ] **Step 3: Implement** the tool. The stored map for real runs is read from a file the owner exports (`select language, grade, story_no, title, word_count from crla_stories where region_id = 13`) or, on the dev cloud, through the bootstrap superadmin.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Type the 19 forms** into `region10.json`: story sentences and questions/answers from the `*LearnerRecordForm.pdf` text (sample-files/crla/Region 10/...), Part 1 items from the `*Tool.pdf` learner sheets. Run `check.dart` until every form is OK. Report per language to the owner for the spot-check (one form each against the PDF).
- [ ] **Step 6: Commit message** `feat(crla): Region X CRLA content (19 forms) with its checker and seed builder`.

### Task 3: Server migration

**Files:**
- Create: `supabase/migrations/20261127010000_crla_digitized.sql` (generated like `20261126010000`: a hand-written head + the latest `sync_ref_columns`, `sync_check_payload`, `sync_apply` copied with the four tables added, the new constraint names in the three "set constraints" lists, and `set statement_timeout = '60s'` kept)
- Modify: `lib/core/release.dart`, `README.md` (2b), `tool/command_pass/scenarios/21_t1.pass`
- Test: `test/supabase/migration_grants_test.dart` green; PG harness steps in `D:\0_CAPSTONE\verify\crla-digitized\pg\` (copy of `D:\0_CAPSTONE\verify\rls-perf\harness\`, `run.sh <repo> with steps.sql`)

**Interfaces:**
- Produces: the tables/columns in Global Constraints; `basa_private.crla_digitized_problem(assessment_id) returns text` (null = consistent); constraint triggers `crla_digitized_check` on the part rows and the evidence tables (deferrable initially immediate; `sync_apply` defers them); insert triggers: timer order/time (Task 1 rules, reset exempt from the clock check, compared within the segment, as `20261126030000`), one story per attempt, Task 2 allowed by Task 1, word index within the story and ≤ `last_word_reached`; `check_crla_part2_limits` with the digitized words-read rule; RLS: content select all signed-in / write superadmin; evidence select `crla_assessment_readable(assessment_id)`, insert/update/delete `crla_assessment_writable(assessment_id)` (FOR each command, no write policy without FOR), timer insert only.

- [ ] **Step 1: PG steps (failing first, `without` the migration)** — `content readable by a tutor, not writable`; `marks by the learner's tutor accepted, by another school's tutor refused`; `RETURNING works for a tutor's insert (F14)`; `task2_low mark refused when task1 marks give 8`; `word mark after last_word_reached refused`; `second story refused`; `timer: pause before start refused; reset after a clock jump accepted`; `mismatched totals refused` (Review Focus 5) at commit, `matching totals accepted`; `typed attempt (no evidence) unchanged`; `sync_apply applies a digitized upload in one go` (negative ids, children after the parent).
- [ ] **Step 2: Run** `NEW=20261127010000 run.sh <repo> without steps.sql` — FAIL; **Step 3:** write the migration; **Step 4:** `run.sh <repo> with steps.sql` — all PASS; `flutter test test/supabase` green.
- [ ] **Step 5: Owner applies** the migration on the dev cloud (all devices synced first: app update required), pastes back `select id, app_update_required from basa_migrations where id = '20261127010000'`; then loads `crla_content_region10.sql`.
- [ ] **Step 6: Commit message** `feat(crla): digitized CRLA tables, rules and evidence check (server)`.

### Task 4: Device: SQLite v51, repositories, sync plumbing

**Files:**
- Create: `lib/core/data/local/crla_local_schema.dart` (the content tables + `crla_stories.body`, the evidence tables, `last_word_reached`, insert triggers mirroring Task 3 for local rows `WHEN NEW.row_version IS NULL`, the words-read trigger rule); `lib/core/repositories/crla_digitized_repository.dart` + `lib/core/data/local/crla_digitized_repository_sqlite.dart` (+ `lib/core/data/remote/crla_digitized_repository_supabase.dart` throwing `UnimplementedError` for writes, as session writes)
- Modify: `lib/core/data/local/local_database.dart` (v51), `lib/core/data/pull_tables.dart` (content tables pulled; evidence in all four maps after `crla_assessments`, parent `('crla_assessments', 'assessment_id')`), `lib/core/data/local/sync_local_schema.dart` (timer: `_noServerUpdate`/`_noServerDelete`), `lib/core/services/sync_review_lines.dart` + `lib/core/models/sync_upload.dart` (nouns "CRLA mark", "CRLA word mark", "CRLA answer", "CRLA timer tap"), `lib/core/data/local/crla_assessment_repository_sqlite.dart` (`delete` removes evidence under `withSyncBypass`)
- Test: `test/core/data/crla_digitized_v51_test.dart`

**Interfaces:**
- Produces: `CrlaDigitizedRepository`: `Future<List<CrlaPart1Item>> part1Items({required int regionId, required String language, required int grade})`; `Future<String?> storyBody(int storyId)`; `Future<List<CrlaStoryQuestion>> questions(int storyId)`; `Future<void> setPart1Mark(CrlaPart1Mark)` / `deletePart1Mark(int assessmentId, CrlaTask task, int itemNo)` / `deletePart1Marks(int assessmentId, CrlaTask task)`; `setWordMark(CrlaWordMark)` / `deleteWordMark(int assessmentId, int wordIndex)`; `setAnswer(CrlaAnswer)`; `insertTimerEvent(CrlaTimerEvent)`; `Future<CrlaEvidence> evidence(int assessmentId)` (all four lists, timer by `seq`); `Future<bool> hasEvidence(int assessmentId)`.

- [ ] **Step 1: Failing tests** — `database is v51 with the tables`; `marks stored and read back`; `trigger refuses task2_low after task1 score 8`; `word mark after last_word_reached refused`; `pulled timer tap can't change or be deleted`; `deleting an attempt removes its evidence, unjournaled`; `tables synced and pulled after crla_assessments`.
- [ ] **Step 2: Run** `flutter test test/core/data/crla_digitized_v51_test.dart` — FAIL; **Step 3:** implement; **Step 4:** PASS, plus `test/core/data` and the sync tests green.
- [ ] **Step 5: Commit message** `feat(crla): digitized CRLA on the device (SQLite v51, sync)`.

### Task 5: ViewModel

**Files:**
- Modify: `lib/viewmodels/crla_viewmodel.dart` (new dependency `CrlaDigitizedRepository`, wired in `lib/core/wiring/wire_tutor.dart`)
- Test: `test/viewmodels/crla_digitized_test.dart`, `test/viewmodels/session_guard_test.dart` (new methods), `test/viewmodels/crla_screen_calls_test.dart` (screen calls list)

**Interfaces:**
- Consumes: Tasks 1 and 4.
- Produces (all `{DateTime? at}` on timer calls; every write refreshes the totals and the profile):
  - `Future<CrlaForm> form(int assessmentId)` (items per task, the story's sentences/words and questions with accepted answers; refusal when no form).
  - `Future<CrlaDigitizedState> digitized(int assessmentId, {DateTime? now})` (marks, answers, timer status/elapsed, `isDigitized`, `lastWordNeeded`, Part 1 task scores, which Task 2 applies, words read, label).
  - `markItem(int assessmentId, CrlaTask task, int itemNo, {required bool correct, bool selfCorrected = false, bool confirm = false})`, `unmarkItem(int assessmentId, CrlaTask task, int itemNo)`, `closeTask(int assessmentId, CrlaTask task)`.
  - `chooseStory(int assessmentId, int storyNo)` (refused once Part 2 evidence exists for another story).
  - `toggleWord(int assessmentId, int wordIndex, {CrlaWordMarkKind kind = CrlaWordMarkKind.miscue})` (marked with the same kind → removed; other kind → changed).
  - `startStoryTimer`, `pauseStoryTimer`, `resumeStoryTimer`, `stopStoryTimer`, `resetStoryTimer` (`int assessmentId, {DateTime? at}`), `storyTimer(int assessmentId, {DateTime? now})` (writes the automatic stop at the limit), `setLastWordReached(int assessmentId, int wordIndex)`.
  - `answerQuestion(int assessmentId, int questionNo, CrlaAnswerMark mark)`.
  - `savePart1Standard`, `savePart1English`, `savePart2Fluency` refuse a digitized attempt (Global Constraints text); `savePart2Fluency` stays the way to set observation level, learner experience and remarks only when given just those (a digitized attempt keeps its computed numbers).
  - Timer writes go through the per-attempt one-at-a-time chain and the signed-in / pending-lock checks, as `PhilIriViewModel._tap`.

- [ ] **Step 1: Failing tests** — `digitized part 1 standard: task1 8 right -> task2High allowed, totals and level follow`; `english task1 all wrong then closeTask -> test ends, Full Refresher`; Review Focus 1-4 tests by name; `timed story stopped by the tutor at 95 s, 3 miscues on a 100-word story -> words read 97, time 1:35`; `answers: 4 correct, 1 incorrect, 1 not asked -> comprehension 4`; `typed save refused on a digitized attempt`; `typed attempt unchanged`; `no form for the region -> refusal`; `discarding (removeAttempt) leaves no evidence`; `profile equals the typed path for the same totals`.
- [ ] **Step 2: Run** `flutter test test/viewmodels/crla_digitized_test.dart` — FAIL; **Step 3:** implement; **Step 4:** PASS; full `flutter test` green; `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart` OK.
- [ ] **Step 5: Commit message** `feat(crla): mark CRLA in BASA (ViewModel)`.

### Task 6: Console, handoff, docs, command pass

**Files:**
- Modify: `lib/core/console/commands/crla_commands.dart` (both builds): `crla-form <assessmentId>`, `crla-digitized <assessmentId>`, `crla-mark <assessmentId> <task> <itemNo> right|wrong|self [confirm]`, `crla-unmark <assessmentId> <task> <itemNo>`, `crla-task-done <assessmentId> <task>`, `crla-story <assessmentId> <storyNo>`, `crla-word <assessmentId> <wordIndex> [self]`, `crla-timer-start|pause|resume|stop|reset <assessmentId> [time]`, `crla-timer <assessmentId>`, `crla-last-word <assessmentId> <wordIndex>`, `crla-answer <assessmentId> <questionNo> right|wrong|na`; `test/core/wiring/tutor_commands.txt` + `admin_commands.txt` (+15 each, sorted); `test/tool/command_pass/coverage_test.dart` totals; `tool/command_pass/scenarios/` (the CRLA batch: a digitized Grade 3 English attempt with an auto-stop and last word, a standard attempt with a Task 2 switch confirmed, refusals, upload approved); `docs/handoff/screens/crla.md` (split-screen section: learner side large items/story, tutor side marks, timer, questions with accepted answers; the calls; labels); `CLAUDE.md` (CRLA line, command counts), `lib/core/CLAUDE.md` (three places for the CRLA rules, v51).
- Test: wiring tests; command pass (short run of the changed batch, then a full run before the commit).

- [ ] **Step 1:** commands + lists (the wiring test fails first on the missing names); **Step 2:** scenario steps; **Step 3:** `dart run tool/command_pass/run.dart` — 0 failed (**DO NOT PLAY RESOURCE INTENSIVE GAMES**); **Step 4:** docs; consultation log M1-02 note; verify kit `D:\0_CAPSTONE\verify\crla-digitized\README.md` (console walkthrough with real ids).
- [ ] **Step 5: Commit message** `feat(crla): digitized CRLA console commands, screen handoff and command pass`.

### Task 7: Demo data

**Files:**
- Create: `tool/demo_data/phases/crla_digitized.dart`; Modify: `tool/demo_data/build.dart`, `tool/demo_data/phases/report.dart` (coverage line count `crla.digitized` ≥ 10; walkthrough row)
- Test: `test/tool/demo_data/coverage_test.dart` (row count unchanged at 19; the CRLA row gains the check)

**Interfaces:**
- Consumes: Task 5 calls; `mosyPlan` (learners not yet assessed in 2026-2027 CRLA MOSY, by their class tutor where placed).
- Produces: step `crla-digitized.mosy-2026`: about 12 Grade 1-3 learners not yet read at MOSY get a digitized attempt whose planned profile (`crlaPlanFor`) is reached through marks (Part 1 items, miscue words, a timed reading under the limit, answers); profile read back = planned (mismatch count in `mismatch.crla.digitized`).

- [ ] **Step 1:** failing coverage test (new check); **Step 2:** implement; **Step 3:** live run `--only crla-digitized` then `--only report` — mismatches 0, 19 of 19 OK.
- [ ] **Step 4: Commit message** `feat(demo): digitized CRLA attempts at 2026-2027 MOSY`.
