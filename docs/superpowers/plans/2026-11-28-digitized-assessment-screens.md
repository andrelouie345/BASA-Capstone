# Digitized assessment screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The assessor gives Phil-IRI and CRLA from the device: a miscue drawer and a timer on the Phil-IRI reading screen, and a new CRLA marking screen.

**Architecture:** UI only on branch `don`. `lib/ui/phil_iri/reading_screen.dart` gets a bottom-sheet miscue drawer (replacing `_MiscueDialog`) and a timer bar; a new `lib/ui/crla/crla_marking_screen.dart` is opened from `CrlaEntryScreen`. Every call is an existing ViewModel method (`PhilIriViewModel`, `CrlaViewModel`) through `vmsOf(context)`.

**Tech Stack:** Flutter, flutter_test widget tests on a seeded SQLite device copy.

**Spec:** `docs/superpowers/specs/2026-11-28-digitized-assessment-screens-design.md`

## Global Constraints

- Assessor-only screens: no learner side, no split screen; both builds; roles as the backend (tutor own sections + ARAL class learners, coordinator/admin of the school).
- `lib/ui/CLAUDE.md`: ViewModels only via the scope (`vmsOf(context)`), imports only viewmodels/, core/models/, SDK, Flutter; theme colours only (`Theme.of(context).colorScheme`); `screen_kit.dart` helpers (`LoadView`, `runAction`, `runStep`, `confirm`); `ViewModelException.message` shown as is; read the ViewModel before any `await`; don't reformat unchanged lines of Andre's files.
- Texts fixed by the spec: "Time this reading again? The first timing stays in the record."; "Time this story again? The first timing stays in the record."; "Tap the last word the learner read"; "Tap the last word the learner reached"; button "Mark in BASA"; labels from the ViewModel (`PhilIriTimerState.timedInBasa` -> "Timed in BASA" / "Time typed in", `CrlaDigitizedState.label`).
- Clock refresh: a `dart:async` periodic `Timer` of 1 s, only while the timer runs, cancelled on pause/stop/dispose; it calls `timer(readingId)` / `storyTimer(id)` and redraws the clock only; a returned `stopped` reloads the screen.
- Checks after every task: `dart analyze` (0 errors), `dart run tool/check_vm_boundary.dart`, `dart run tool/check_tutor_imports.dart`; `test/ui/screens_smoke_test.dart` stays green.
- Owner commits (no git by me); UI commits on `don` only.

## Review Focus

- Leaving the reading screen while the timer runs, then coming back: the clock continues from the log (no second timer, no lost time) -> Task 2 test `reopen a running reading`.
- A one-minute reading that ran past 60 s while the app was closed: on open it shows stopped + the last-word banner -> Task 2 test `one minute past 60 s on open`.
- Tapping outside the drawer never saves anything (also for an already-marked word) -> Task 1 test `outside tap on a marked word keeps it`.
- A refusal from the ViewModel during marking (e.g. "Finish Task 1 first.") is shown and the screen stays usable -> Task 3 test `refusal shown`.
- An attempt with typed totals or a region without a form: no "Mark in BASA" -> Task 3 test `no button without a form`.

---

### Task 1: Phil-IRI miscue drawer

**Files:** Modify `lib/ui/phil_iri/reading_screen.dart` (`_word`, `_MiscueDialog` -> `_MiscueDrawer` shown with `showModalBottomSheet`, `isScrollControlled: true`, dismissible). Test: `test/ui/phil_iri_reading_screen_test.dart` (new; seed like `test/viewmodels/phil_iri_timer_test.dart`: school, Grade 7 section, learner, collection, passage with 10+ words, session + oral reading; wrap like `screens_data_test.dart` `_show`, 400x860).

**Interfaces:** Produces `_MiscueChoice` unchanged (type, spoken, selfCorrected, remove) so `_word` keeps its three calls.

- [ ] **Step 1: Failing tests:** `tap opens the drawer`: tap a passage word -> a bottom sheet shows every `PhilIriMiscueType.values` label, "Self-corrected", "Done"; `pick and done saves`: choose a type, Done -> sheet gone, the miscue count shows 1, the word is highlighted; `outside tap saves nothing`: open, tap the barrier (`tester.tapAt(const Offset(200, 40))`) -> sheet gone, no miscue (`vm.miscues(readingId)` empty); `outside tap on a marked word keeps it`: marked word, open, tap outside -> miscue unchanged; `remove`: marked word -> "Remove miscue" removes it.
- [ ] **Step 2:** Run `flutter test test/ui/phil_iri_reading_screen_test.dart` -> FAIL (dialog, not a sheet).
- [ ] **Step 3:** Implement the drawer (same fields as the dialog: types as choice chips, Self-corrected, "Said" text field for types that take it, Remove for an existing miscue, Done).
- [ ] **Step 4:** Run -> PASS; checks.
- [ ] **Step 5: Commit message:** `feat(ui,phil-iri): miscue drawer on the reading screen`

### Task 2: Phil-IRI timer bar

**Files:** Modify `lib/ui/phil_iri/reading_screen.dart` (new `_TimerBar` widget, last-word mode in the word tap). Test: same file as Task 1.

**Interfaces:** Consumes `PhilIriViewModel.startTimer/pauseTimer/resumeTimer/stopTimer/resetTimer(readingId)`, `timer(readingId)` -> `PhilIriTimerState` (`status`, `elapsed`, `timedInBasa`, `minuteEndNeeded`), `setMinuteEnd(readingId, wordIndex)`.

- [ ] **Step 1: Failing tests:** `not timed yet`: bar shows `00:00`, Start and "Enter the time"; `start`: tap Start -> Pause and Stop shown, "Enter the time" gone, label "Timed in BASA"; `one minute has no Stop`: one-minute reading started -> Pause only; `pause/resume`; `stop whole text`: Stop -> Restart shown, reading time saved (`readings` has `readingSeconds`); `restart asks`: Restart -> the confirm text, confirm -> `00:00` + Start; `reopen a running reading`: seed `startTimer(at: now - 30 s)`, open -> Pause shown, clock >= 00:30; `one minute past 60 s on open`: seed one-minute `startTimer(at: now - 70 s)`, open -> "Tap the last word the learner read" banner; tap word 5 -> banner gone, `wordsRead` set (via `readings`), the drawer did not open.
- [ ] **Step 2:** Run -> FAIL.
- [ ] **Step 3:** Implement (periodic 1 s `Timer` per Global Constraints; buttons by `status`; Stop hidden for `PhilIriReadingMethod.oneMinute`; Restart through `confirm`; bar hidden for an Untitled imported reading).
- [ ] **Step 4:** Run -> PASS (use `tester.runAsync` around the waits; cancel the periodic timer on dispose so no test leaves a pending timer); checks.
- [ ] **Step 5: Commit message:** `feat(ui,phil-iri): reading timer on the reading screen`

### Task 3: CRLA marking screen

**Files:** Create `lib/ui/crla/crla_marking_screen.dart` (`CrlaMarkingScreen({required int assessmentId})`); modify `lib/ui/crla/crla_entry_screen.dart` ("Mark in BASA" button). Test: `test/ui/crla_marking_screen_test.dart` (seed like `test/viewmodels/crla_digitized_test.dart`: region 10 school with Part 1 items, a story with words and questions, Grade 3 section, learner, attempt; and a region-2 school without a form).

**Interfaces:** Consumes `CrlaViewModel.form(id)` -> `CrlaForm` (`items[CrlaTask]`, `stories` -> `CrlaFormStory(storyNo, title, words, questions)`, `timeLimitSeconds`), `digitized(id)` -> `CrlaDigitizedState` (`task1Score`, `task1Done`, `task2`, `task2Score`, `storyNo`, `timerStatus`, `elapsed`, `lastWordNeeded`, `lastWordReached`, `miscues`, `wordsRead`, `comprehension`, `label`, `evidence`), `markItem(id, task, itemNo, correct:, selfCorrected:, confirm:)`, `unmarkItem`, `closeTask(id, task)`, `startStoryTimer(id, storyNo)`, `pause/resume/stop/resetStoryTimer(id)`, `storyTimer(id)`, `toggleWord(id, wordIndex, kind:)`, `setLastWordReached(id, wordIndex)`, `answerQuestion(id, questionNo, CrlaAnswerMark)`, `saveObservation(id, ...)`, `getResult(id)`.

- [ ] **Step 1: Failing tests:** `button with a form`: `CrlaEntryScreen` for the region-10 attempt shows "Mark in BASA", tap opens `CrlaMarkingScreen`; `no button without a form`: region-2 attempt -> no "Mark in BASA"; `part 1`: mark item 1 Right, item 2 Wrong -> score `1/10` shown; "Done with Task 1" -> the Task 2 heading the state names appears; `task 2 confirm`: a Task 1 change that switches Task 2 -> the confirm text "This changes which Task 2 is given; confirm to clear its marks.", confirm -> applied; `story`: Start story 1 -> clock + Pause/Stop; tap a word -> miscues 1; tap again -> 0; long-press -> self-corrected mark (miscues stays 0); `question`: after Stop, mark Q1 Correct -> comprehension 1; `refusal shown`: Start story before Task 1 is done -> the ViewModel's message is shown and the screen still responds.
- [ ] **Step 2:** Run `flutter test test/ui/crla_marking_screen_test.dart` -> FAIL.
- [ ] **Step 3:** Implement per the spec's CRLA section (phone: one scroll page; width >= 840: two columns, Part 1 left, Part 2 right; Task 2 confirm through `confirm` then repeat with `confirm: true`; last-word banner; observation fields; profile from `getResult`).
- [ ] **Step 4:** Run -> PASS; checks; `flutter test test/ui` green.
- [ ] **Step 5: Commit message:** `feat(ui,crla): digitized CRLA marking screen`

### Task 4: Docs, full run, walkthrough

**Files:** Modify `docs/handoff/screens/phil-iri.md` and `crla.md` (one line each: built 2026-11-28, file names), `docs/handoff/checklist.md` (the two screens' rows), `H:/My Drive/Capstone ARAL AAA/Screen_review_guide.md` (M1-01..03: "screens built, take the after shots"); consultation log M1-01..03 notes. Create `D:\0_CAPSTONE\verify\digitized-screens\README.md` (run the admin build, demo account, which learner/attempt, what to tap and see; region with a CRLA form).

- [ ] **Step 1:** Docs.
- [ ] **Step 2:** **DO NOT PLAY RESOURCE INTENSIVE GAMES.** Full `flutter test` -> 0 failed; analyze + both tool checks.
- [ ] **Step 3:** Verify kit + the frontend prompt the owner asked for (paste-ready, for the screenshot comparison).
- [ ] **Step 4: Commit message:** `docs(screens): digitized assessment screens built (handoff, checklist)`
