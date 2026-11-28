# Digitized assessment screens (M1-01, M1-02, M1-03)

Date: 2026-11-28. Owner approved approach A. UI only, on branch `don` (PR to `frontend_dev`); the backend is done
(Phil-IRI timer `2026-11-26-phil-iri-timed-reading-design.md`, digitized CRLA `2026-11-27-crla-digitized-design.md`).
Built by the backend owner with Claude at the owner's request, so the frontend team has time for the redesign.

## Intent

The tutor gives CRLA and Phil-IRI **from the device**: marks miscues, items and answers while the learner reads, times
the reading in BASA, and BASA works out the scores and levels. Today the Phil-IRI screen has everything but the timer
("Enter the time"), and CRLA has typed totals only. These screens close objective ii's gap: administering the
assessment, not only recording it.

## Decisions (owner)

- **Assessor-only screens** (whoever gives the test holds the screen: a tutor, coordinator or admin; both builds,
  same roles as the backend: tutors for their own sections and ARAL class learners, coordinators and admins of the
  school). No split screen and no learner side (reading coordinator, 2026-11-28: showing the
  learner the screen is a very bad idea; the tutor must not show any action a learner might feel judged or pressured
  by). The learner reads the printed copy; the screen shows the text so the tutor can follow and mark.
- **Phil-IRI miscue = tap the word, a drawer slides up** (bottom sheet) with the miscue types, Self-corrected,
  Said: ..., Remove (for a marked word) and Done. **Tapping outside the drawer closes it, nothing changes.** Not
  "one tap = substitution".
- **Approach A:** extend `lib/ui/phil_iri/reading_screen.dart` (Andre's) with the timer and the drawer; add a new
  `lib/ui/crla/crla_marking_screen.dart`, opened from `CrlaEntryScreen` with **"Mark in BASA"** when the region
  has the digitized form. Typed entry stays for readings timed on paper and for regions without a form.

## Approaches considered

- **A (picked):** extend the Phil-IRI reading screen, new CRLA marking screen. One reading = one screen.
- B: separate "live assessment" screens for both, typed screens kept as is. Two screens for one Phil-IRI
  reading's miscues and answers; a tutor could start in one and continue in the other.

## Phil-IRI reading screen (M1-01, M1-03)

Calls are `PhilIriViewModel` (handoff `docs/handoff/screens/phil-iri.md`, *Timed reading*).

- **Timer bar** at the top of the reading (oral and silent readings with a passage; not for an Untitled imported
  reading): the learner, grade and round, the clock `mm:ss` from `timer(readingId).elapsed`, and the buttons for the
  state: none -> **Start**; running -> **Pause** + **Stop** (Stop not offered for a one-minute reading); paused ->
  **Resume** + **Stop**; stopped -> **Restart** (confirm "Time this reading again? The first timing stays in the
  record."). The label "Timed in BASA" / "Time typed in" under the clock.
- While running, the screen calls `timer(readingId)` about once a second (a periodic timer started on Start/Resume
  and on opening a running reading, cancelled on pause/stop/dispose) and redraws only the clock; when the call shows
  `stopped` (a one-minute reading at 60 s), the whole reading is reloaded.
- **One minute, last word:** when `minuteEndNeeded`, a banner "Tap the last word the learner read" and word taps call
  `setMinuteEnd(readingId, wordIndex)` instead of opening the drawer, until it's set.
- **"Enter the time"** (typed) only while the timer has never run (`status` none and not timed in BASA); the
  ViewModel refuses it once timed, shown as is.
- **Miscue drawer** replaces `_MiscueDialog` (same choices, same calls: `markMiscue`, `updateMiscue`,
  `removeMiscue`; an insertion goes before the tapped word). Comprehension (M1-03) is already on this screen
  (`answer` per question, the score computed): unchanged, checked against the handoff.
- Refusals (`ViewModelException`) shown as they come through the existing `runAction`.

## CRLA marking screen (M1-02)

Calls are `CrlaViewModel` (handoff `docs/handoff/screens/crla.md`, *Digitized CRLA*). Assessor-only; phone = one
scrolling page (Part 1, then Part 2); wide = two columns (Part 1 left, Part 2 right).

- **Opening it:** `CrlaEntryScreen` asks `form(assessmentId)`; when it returns a form and the attempt isn't typed
  (`digitized(id).label` isn't "Totals typed in"), it shows **Mark in BASA**; `crlaNoFormMessage` -> no button (typed
  entry as today).
- **Header:** learner, grade, variant/language, round; the state's `label`.
- **Part 1:** the current task's items (`form.items[task]`: number, text; Grade 1 rhyming pairs show `answerKey`)
  with **Right / Wrong / Self-corrected** (`markItem`, again on the same mark = `unmarkItem`), the task score
  (`task1Score` / `task2Score`), **Done with Task 1** (`closeTask`: unmarked items count wrong). Task 2 appears once
  Task 1 is done (`task2`; null = the test ends, shown as the ViewModel says). A Task 1 change that switches Task 2
  is refused with "This changes which Task 2 is given; confirm to clear its marks.": ask, then repeat with
  `confirm: true`.
- **Part 2:** pick story 1 or 2 and **Start** (`startStoryTimer`), the clock `elapsed / timeLimitSeconds` with
  Pause / Resume / Stop / Restart (confirm "Time this story again? The first timing stays in the record.");
  `storyTimer(id)` about once a second while running (it stops itself at the limit). The story's `words` as tappable
  words: **tap = miscue on/off** (`toggleWord`), **long-press = self-corrected** (`kind: selfCorrected`); marked
  words highlighted (theme colours). When `lastWordNeeded`: banner "Tap the last word the learner reached", taps call
  `setLastWordReached`. Counters: miscues, words read.
- **Questions:** each `questions[n]` with its prompt and `acceptedAnswers`, **Correct / Wrong / Not asked**
  (`answerQuestion`), shown once the story is timed; comprehension count.
- **Observation** (`saveObservation`: learner experience rating, observation level, remarks) after the story is
  timed.
- **Result:** the profile from `getResult(id)` once Part 2 is saved.
- Every refusal shown as is (`runAction`), e.g. "Finish Task 1 first.", "That word is after the last word
  reached.".

## Constraints

- `lib/ui/` rules (`lib/ui/CLAUDE.md`): ViewModels through `vmsOf(context)` / the scope, no services or data imports
  (`check_vm_boundary`), theme colours only, `screen_kit.dart` helpers (`LoadView`, `runAction`, `confirm`), Andre's
  style; don't reformat lines not changed.
- Both builds (tutor and admin; coordinators use the admin build); no admin-only calls, so the same screens compile
  into the tutor build.
- Tests: widget tests for both screens with seeded data (pattern of `test/ui/screens_data_test.dart`): timer bar
  states and buttons, the drawer (open on tap, closes on outside tap with no change), last-word banner; CRLA Part 1
  marking, Task 2 confirm, word toggle, last word, question marks; `screens_smoke_test` stays green.
- Checks: `dart analyze`, `flutter test`, both tool checks.

## Left to the builder

Exact widgets and spacing, how the clock widget refreshes, where the "Mark in BASA" button sits on the entry screen,
the wide/narrow breakpoint (screen_kit's existing one if any).
