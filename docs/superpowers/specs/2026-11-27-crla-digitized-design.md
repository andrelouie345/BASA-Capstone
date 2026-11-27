# Digitized CRLA (consultation M1-02): design

Date: 2026-11-27. Status: approved by the owner (see the end). Backend only; the screen is the frontend team's
(handoff doc). Sister design: `2026-11-26-phil-iri-timed-reading-design.md` (M1-01), whose patterns this reuses.

## 1. Why

The advisor (consultation 1, 2026-11-24) found BASA a "mere data recorder" for CRLA: the tutor gives the test on
paper and types totals. Objective ii asks for assessment modules that **facilitate administration**, with automatic
scoring and classification. Digitized CRLA moves the administration into BASA: the items and the story are on the
tutor's screen, every answer and word is marked as the learner reads, BASA times the reading, and the totals and the
reading profile come from those marks. The marks are kept as evidence the test was given live.

Typed totals and the scoresheet import stay (owner 2026-11-25: digitized is another way in, not a replacement).

## 2. Goals, non-goals, anti-goals

Goals
- G1. All 19 Region X forms in BASA as content (owner, option B): Part 1 items per task, both stories' text by
  sentence, each story's comprehension questions with the accepted answers.
- G2. Part 1 marked item by item (right / wrong), self-correction counts as right (DepEd guide).
- G3. Part 2 marked word by word: one tap = miscue, tap again = undo, a "self-corrected" mark that does not count
  (owner, option A). No miscue types (DepEd counts miscues only).
- G4. Part 2 timed in BASA with an insert-only timing log (start, pause, resume, stop, restart), as Phil-IRI. The
  timer stops itself at the grade's limit (60 / 120 / 180 s); the tutor then taps the last word reached; words after
  it count against the words read (owner, option A; advisor to confirm: agenda question 9).
- G5. Comprehension questions marked ✓ / ✗ / N/A each, the accepted answers shown to the tutor.
- G6. The existing Part 1 / Part 2 rows (and so the levels, the profile, reports, exports) are computed from the
  marks; the server refuses an upload whose totals don't match its marks.
- G7. Console commands, screen handoff, command-pass steps, demo data that shows digitized attempts.

Non-goals
- Other regions' content (they keep typed entry; content can be added later the same way).
- Audio, a learner-facing screen, learner accounts.
- Listening Comprehension (a different DepEd assessment).
- Changing the CRLA cut-offs, profiles or the per-grade numbers (`crla_rules.dart`).

Anti-goals (a failure even if it works)
- Typed entry or the CRLA2 scoresheet import stops working, or an existing result changes.
- A transcription error goes unnoticed (wrong text = wrong words read for every learner).
- Digitized totals that can drift from their marks.

## 3. Constraints (found in the code and the material)

- Today: `crla_assessments` (one attempt; `subject_variant` mt/fil/eng, `language`, `round`, `reading_profile`,
  `thresholds_snapshot`), `crla_part1_standard` (task1, task2_low, task2_high; total and level computed),
  `crla_part1_english` (task1, task2), `crla_part2_fluency` (story_no, miscues, words_read, time_minutes/seconds,
  comprehension_correct, learner_experience_rating, observation_level, remarks; wpm computed). Part 1 rules:
  Task 1 < 7 uses the low Task 2, else 10 + the high Task 2 (standard); English Task 1 = 0 ends the test.
- `crla_stories` (region, language, grade, story_no, title, word_count) holds 38 stories = 19 forms × 2, region 13
  only; no text. Words read = story words − miscues (`crlaWordsRead`, `check_crla_part2_limits`, F10). Time limit
  and comprehension maximum per grade/variant in `crla_rules.dart` (`crlaTimeCapSeconds`, `crlaComprehensionMax`)
  and their SQL twins.
- Part 1 items are single letters or words; "sentence" tasks are sentences scored one point per word (e.g. Grade 2
  Filipino: two 5-word sentences = 10). Forms differ by grade and language.
- DepEd record forms give each story sentence by sentence with a word count per sentence, and the questions placed
  after a sentence, with "Any of these – …" accepted answers. The learner sheets (Part 1) are images.
- Sync rules (CLAUDE.md): new synced tables need grants, RLS (select must pass for `sync_apply`'s `RETURNING`,
  F14), SQLite mirror + triggers, pull/sync order; the "three places" rule (Dart, SQLite trigger, server) for every
  check; a migration that changes rules is "app update required: yes".

## 4. Approaches (decided: 1)

1. **Mirror the Phil-IRI timed reading (chosen).** Content tables for items, story text and questions; one evidence
   table per kind of mark (Part 1 item marks, Part 2 word marks, answers) plus an insert-only CRLA timing log; the
   existing Part 1 / Part 2 rows filled from the marks; a deferred server check that totals match marks.
   Most tables and work, but a proven pattern, checkable mark by mark, the strongest evidence for objective ii.
2. Store the marks as one JSON bundle per part on the existing rows. Fewer tables, but the server can't easily
   check it, two edits overwrite each other, reports can't count marks.
3. Approach 1 with one timing log shared with Phil-IRI. One table fewer, but it changes the live Phil-IRI timer and
   mixes two parents in one table.

## 5. The design (decided with the owner unless marked "my call")

D1. **Content.** (my call on the shape)
- Story text: `crla_stories` gets the text **one sentence per line**; its words are the text split on spaces
  (punctuation stays attached to its word, as Phil-IRI passages do). Each sentence's word count and the story's
  `word_count` must match the DepEd record form; the seed load refuses otherwise.
- Part 1 items: a content table, one row per item: region, language, grade, task (`task1`, `task2_low`,
  `task2_high` for mt/fil; `task1`, `task2` for English), item number, text, and a sentence number for sentence
  tasks (screens show those as sentences). One point per item.
- Questions: a content table per story: question number, the sentence it follows, the question, the accepted
  answers as printed.
- Read: every signed-in user; write: superadmin only (like `crla_stories` and the Phil-IRI content).
- Seeds: `supabase/seeds/crla_content_region10.sql` (idempotent upsert), all 19 forms.

D2. **Transcription check** (owner chose all 19; my call on the check). The story text is taken from the record
forms (readable as text) and the Part 1 items typed from the learner sheets. A test reads the seed file and checks:
every story's word count = `crla_stories.word_count`; every sentence's count = the form's printed count; every
task has the form's number of items; every story has the grade's number of questions. The owner (or a groupmate who
reads the language) spot-checks one form per language against the PDF before it ships.

D3. **Part 1 marks.** One row per marked item: right or wrong (+ a self-corrected flag, which counts as right). The
ViewModel refuses marks on a Task 2 the Task 1 score doesn't lead to (standard: low vs high; English: none after
Task 1 = 0), and a changed Task 1 that switches the Task 2 clears the other Task 2's marks only after asking (the
screen asks; the ViewModel takes a `confirm`). Task scores = count of right marks; an unmarked item counts as wrong
once the task is closed (my call: the tutor closes a task with "done", which marks the rest wrong, as on paper).

D4. **Part 2 word marks.** One row per marked word: `miscue` or `self_corrected` (owner, A). Unmarked = read
correctly. Tapping a marked word again removes the mark.

D5. **Timing.** An insert-only CRLA timing log (start / pause / resume / stop / reset), the Phil-IRI rules: segment
after the last reset, seconds = (stop − start) − pauses, a restart after a mistake, refusals for taps out of order,
the device-clock rule. At the grade's limit the timer stops itself (stop dated at start + limit + pauses), and the
tutor taps the **last word reached** (owner, A). A reading finished before the limit is stopped by the tutor;
then the last word reached is the story's last word.

D6. **Words read.** `crla_part2_fluency` gets `last_word_reached` (null = the whole story, as today). Words read =
(last word reached, counted from 1) − miscues among those words. Miscue marks after the last word reached are not
allowed. Typed entry keeps today's rule (story words − miscues). The three places (Dart `crlaWordsRead`, the SQLite
trigger, `check_crla_part2_limits`) change together.

D7. **Comprehension.** One row per question: correct / incorrect / not asked (N/A). Comprehension correct = count
of correct. N/A counts as not correct (my call: DepEd's form allows N/A without saying how it scores; this keeps the
grade's maximum unchanged).

D8. **Totals from marks.** When an attempt has any marks or timing taps it is **digitized**: the ViewModel writes the
Part 1 / Part 2 rows from the marks after every mark (task scores, miscues, words read, time, comprehension), and
refuses typed saves for that attempt ("This attempt is marked in BASA; …"), as a timed Phil-IRI reading refuses
typed time. Observation level, learner experience and remarks stay typed fields. An attempt without marks is typed,
exactly as today.

D9. **Evidence check on the server.** A deferred constraint check (like `phil_iri_timed_reading_check`) refuses a
digitized attempt whose Part 1 / Part 2 totals don't match its marks and timing log; `sync_apply` defers it to the
end of the upload. Typed attempts are not checked.

D10. **Sync and access.** The four evidence tables are synced children of `crla_assessments` (pull after it, clear
before it); select = the attempt is readable, insert/update/delete = the attempt is writable (today's CRLA part-row
rules); the timing log is insert-only (no update/delete policy; discarding an attempt removes its taps, as the
Phil-IRI C1 fix). Grants in the migration. App update required: **yes** (new synced tables, a words-read rule).

D10b. **When marks and taps are allowed** (my call). CRLA attempts have no completed status (unlike Phil-IRI
sessions): marks and taps are allowed while the attempt can be edited today (on the device, not in a pending
upload). Digitizing is refused for an attempt whose school has no form for its region, language and grade
("No digitized CRLA form for this school's region, language and grade: enter the totals instead.").

D11. **Who.** Whoever may record the attempt today (section tutors at BOSY; ARAL class tutors at MOSY/EOSY for their
class learners; coordinators).

D12. **Console and handoff.** Commands for each ViewModel call (start/mark/unmark items, close a task, mark/unmark
words, timer start/pause/resume/stop/restart/status, last word reached, answer, show the form); the tutor and admin
command lists and the coverage totals grow accordingly. Screen handoff in `docs/handoff/screens/crla.md`: a split
screen (the learner's side: items or story large; the tutor's side: marks, timer, questions with accepted answers).

D13. **Demo.** A step in the demo builder records some 2026-2027 MOSY CRLA attempts digitized (Grades 1-3, by their
class tutors where placed), so the screens have live examples; the who-administered table keeps working.

## 6. Left to the builder

Table and column names; SQLite version numbers; how a "task closed" is stored (a mark per remaining item, or a
closed flag); the tokenizer details that make the printed counts match (e.g. `Iba't`, `Puting-puti`, `niya'y`
are one word each on the forms); the exact refusal texts (plain, like the Phil-IRI timer's); the order of the plan's
tasks (content and its check first, so the typing can be reviewed while the rest is built).

## 7. Decided by the owner (2026-11-27)

- Part 2 marking: one tap = miscue, tap again = undo, self-corrected mark that doesn't count (A).
- Content: all 19 Region X forms before CRLA ships (B).
- Time limit: the timer stops at the grade's limit; the tutor taps the last word reached; the rest counts against
  the words read (A; advisor to confirm, agenda question 9).
- Approach 1 (separate evidence tables, own CRLA timing log).
