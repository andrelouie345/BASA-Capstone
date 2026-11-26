# Digitized Phil-IRI oral reading: the timed reading (design)

Date: 2026-11-26. Owner: backend owner. Consultation log item **M1-01**.
Objective **ii** (assessment *administration*, automated scoring, reading level
classification). Scope: inside "assessment administration" (the tutor
administers with the app; not automated administration, see
`capstone-scope`).

## Intent

The advisor (consultation 1) found BASA records Phil-IRI results instead of
administering the assessment. BASA already has the passage as tappable words,
miscues per word, answers per question, the rubric and automatic scoring; the
one part still done outside BASA is **timing** (typed seconds, or typed words
read in one minute). This piece makes the reading timed **in** BASA and keeps
the timing as **evidence**: when the reading started, every pause and resume,
and when it stopped, so a coordinator (or the panel) can see the reading was
administered live.

Typed timing stays (owner 2026-11-25: digitized assessments are another way to
collect data, not a replacement; the imports stay too).

## Goals

- A tutor times a reading in the app: start, pause, resume, stop, and restart
  after a mistake (owner).
- Every timer tap is stored as its own row, never changed (owner: option A,
  a timing log).
- The seconds BASA scores come from the log (start to stop minus pauses); the
  one-minute method stops at 60 s and the tutor taps the word reached.
- Each reading says whether it was **Timed in BASA** or **Time typed in**.
- The server refuses an upload whose timed reading's seconds don't match its
  log.

## Non-goals

- The screen itself (frontend team, branch `don`): this piece delivers the
  ViewModel calls, console commands and the handoff doc with the owner's
  layout (below).
- When each miscue was tapped (not asked; miscues keep no time).
- The GST (stays a paper test, M1-03), CRLA timing (M1-02, separate piece),
  audio recording.

## Anti-goals

- Evidence that can be edited or quietly replaced (the reason for option A).
- A timer that loses the reading when the app closes or the phone rings.
- Making typed timing impossible: schools that test on paper keep working.

## Approaches (chosen: A)

- **A. A timing log, one row per timer tap (chosen, owner).** New child table
  of `phil_iri_readings`; rows only added. Strongest evidence (exactly what
  happened, in order); mirrors how miscues hang under a reading. Cost: a new
  synced table (pull, upload rules, `sync_apply`, RLS, app update required).
- B. `started_at` / `stopped_at` + a jsonb list of pauses on the reading. One
  table fewer, but the list is rewritten as a whole (weaker evidence) and jsonb
  needs its own sync conversion; app update required too. Not chosen.
- C. Totals only (`started_at`, `stopped_at`, `paused_seconds`,
  `pause_count`). Simplest, but loses when each pause happened, which the owner
  asked to keep. Not chosen.

## Decisions

- **D1 (owner) Timing log.** Table `phil_iri_reading_timer_events`:
  `id`, `reading_id` (FK `phil_iri_readings`, on delete cascade), `seq`
  (1, 2, ... per reading), `kind` (`start` / `pause` / `resume` / `stop` /
  `reset`), `at` (timestamptz, the device's clock with its offset),
  `created_by`, `created_at`, `row_version` (synced-table convention). Unique
  (`reading_id`, `seq`). Insert-only for server rows (no update, no delete
  policy; local triggers refuse edits of pulled rows), like
  `phil_iri_gst_results`.
- **D2 (owner) Pause and resume** are stored as their own rows.
- **D3 (owner) Restart after a mistake** = a `reset` row; the earlier rows stay.
  The timing that counts is the part after the last `reset`.
- **D4 Valid order** (after the last reset): `start`, then any number of
  `pause` / `resume` pairs, then `stop`; `reset` is allowed at any point after
  a `start`. Times never go backwards within a reading. Checked by the
  ViewModel, the SQLite insert trigger and the server insert trigger (three
  places, as for other rules; change them together).
- **D5 Seconds from the log.** `reading_seconds` = (stop − start) − the sum of
  (resume − pause), whole seconds, rounded down; computed by the device and
  saved on the reading as today, so scoring, reports and imports don't change.
  A pure-Dart function `philIriTimedSeconds(events)` holds the rule; the
  server's check (D8) uses the same rule in SQL.
- **D6 One-minute method.** The timer stops itself at 60 s of reading time
  (pauses don't count): the device adds the `stop` row dated at the 60-second
  mark (start + 60 s + the pauses before it), also when it adds it later
  (the app was closed at 59 s and reopened after).
  The tutor then taps the word the learner reached; `wordsRead` = that word's
  position + 1 (`PhilIriPassage.words`), refused beyond the passage.
- **D7 Timed or typed.** A reading with a timing log (a `start` after its last
  reset) is **timed**: its seconds / words read come only from the log and the
  minute-end tap; `saveTiming` is refused for it ("This reading is timed in
  BASA; restart the timer to time it again."). A reading without a log is
  typed exactly as today. `PhilIriReading` gets a getter-level flag from the
  ViewModel (`timedInBasa`) for screens and reports; labels "Timed in BASA" /
  "Time typed in".
- **D8 Server evidence check.** At the end of an upload (deferred, like the ARAL
  end-state checks in `sync_apply`) and on direct writes: a timed reading's
  `reading_seconds` (or, one-minute, the log reaching 60 s with a stop) must
  match its log; otherwise the upload is refused with a plain message naming
  the learner and passage.
- **D9 Survives the app closing.** Each tap is saved at once, so reopening a
  reading shows the timer as the log left it: running (elapsed from the log and
  the clock), paused, or stopped.
- **D10 Complete needs a stopped timer.** `complete` refuses a session with a
  timed reading whose timer is running or paused. Reopen keeps the log; the
  tutor may restart the timer while the session is open.
- **D11 Deleting a reading** (to pick another passage, while the session is
  open) deletes its log with it (cascade). Evidence is about readings that
  stay; a discarded reading leaves nothing to prove.
- **D12 The timer is for oral and silent readings alike** (whole text, silent,
  one minute). Untitled imported readings can't be timed (no passage, as
  today's edit refusal).
- **D13 Who.** Whoever may write the reading (`phil_iri_reading_writable`)
  writes its log; reading follows the reading's read policy (correlated EXISTS
  on `phil_iri_readings`, as `20261125020000`).
- **D14 Release.** One migration (new table, grants, RLS, triggers, the
  `sync_apply` table list, the D8 check), header and ledger **App update
  required on all devices: yes** (a new synced table: older apps can't pull or
  upload it), `release.dart`, README 2b; SQLite v49 (table + triggers in
  `phil_iri_local_schema.dart`, added to `syncedTables` / `pullOrder` after
  `phil_iri_readings`, upload rules for the new `kind` text and `at` text).

## The screen (handoff, frontend team on `don`)

Owner's layout: mobile first; the tutor taps a word and a drawer slides up
from the bottom with the miscue types.

```
+-------------------------------+
| Grade 7 . MOSY #1 . 02:14  ||  |  timer, pause/resume, stop
|                               |
| The [boat] drifted slowly     |
| toward the shore while the    |  passage as tappable words;
| fishermen ~~pulled~~ their    |  marked words highlighted
| nets ...                      |
+-------------------------------+
|  "pulled"                     |  drawer on tap
|  Mispronunciation  Omission   |  types from PhilIriMiscueType
|  Substitution  Insertion ...  |
|  [ ] Self-corrected  Said: __ |
|  Remove miscue        Done    |
+-------------------------------+
```

- Types come from `PhilIriMiscueType.values` (never hard-coded); an insertion
  goes before the tapped word (as `markMiscue` expects).
- Tapping a marked word opens the same drawer (change / remove).
- Timer buttons: Start, Pause / Resume, Stop, Restart (asks to confirm: "Time
  this reading again? The first timing stays in the record.").
- One minute: at 60 s the timer stops and the screen asks "Tap the last word
  the learner read".
- A reading's label: "Timed in BASA" or "Time typed in".
- The learner reads from the printed copy; the tutor keeps the screen (owner,
  Agenda Q6).

## ViewModel and console (both builds)

`PhilIriViewModel`: `startTimer(readingId, {DateTime? at})`,
`pauseTimer`, `resumeTimer`, `stopTimer` (whole text / silent: saves
`reading_seconds`), `resetTimer`, `setMinuteEnd(readingId, wordIndex)`
(one minute), `timer(readingId)` -> a `PhilIriTimerState` (events, `running`
/ `paused` / `stopped` / `none`, elapsed reading seconds, `timedInBasa`).
`at` defaults to now (tests and the demo pass it). Each guarded by
`_requireSignIn` (added to `session_guard_test`), messages in the 2026-11-17
wording rule. Console: `phil-iri-timer-start|pause|resume|stop|reset <readingId>
[at]`, `phil-iri-minute-end <readingId> <wordIndex>`, `phil-iri-timer
<readingId>`; command lists of both builds updated.

## Tests

- Pure Dart: `philIriTimedSeconds` (pauses, reset, rounding, empty);
  order rules.
- ViewModel: timed flow end to end, typed flow unchanged, `saveTiming` refused
  when timed, complete refused while running, minute-end counting, app
  "reopen" (a new ViewModel over the same database shows the running timer).
- SQLite triggers: wrong order and backwards times refused for local rows;
  pulled rows can't change.
- PG harness: RLS (tutor of the section / class tutor / coordinator / other
  school), insert-only, `sync_apply` with a timed reading (accepted) and with
  seconds that don't match (refused); `RETURNING` under the read policy (F14).
- Command pass: a timed whole-text and one-minute reading in a tutor batch,
  plus a refused `saveTiming`; latest-migration line.
- Demo: from Task 11 (2026-2027) the demo's oral readings are timed in BASA,
  so "who administered what" can show timed vs typed.

## Left to the builder

- Exact migration file name/time, SQLite trigger SQL, where D8 sits inside
  `sync_apply` (end-of-upload block) and its message text.
- Whether `seq` is assigned by the device (next number) or a trigger (device:
  simpler offline; the unique key protects it).
- Console argument parsing (`strictDateArg` for `at`).
