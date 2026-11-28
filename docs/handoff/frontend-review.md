# Frontend review session (for the frontend team's Claude)

Start: someone on the team says **"Let's start, check the readmes for the frontend work"** (or similar). Follow these
steps in order. Talk in plain words: the team reads English as a second language.

This file says how the session runs. **What the advisor asked for is not in the repo** (the repo is public): it is
in the team's review folder (below), which the person keeps outside the repo.

## 1. Who is this

Read `git config user.name`. Match it to the names in the **Assigned** column of `docs/handoff/checklist.md`. If it
doesn't match anyone, or several, ask: "Who am I working with?" Greet them by name.

## 2. Their checklist

From `docs/handoff/checklist.md`, list:
- the screens **assigned to them** that aren't `done` (row, screen, status);
- the screens **nobody has claimed** (Assigned empty), so they can pick one.

Keep it short (a table). Don't list the whole checklist.

## 3. Say what will happen

Tell them, in a few lines:
1. I'll look at the screenshots of the screens against the advisor's requests.
2. For each screen I'll propose changes (what, why, how big), and you decide which to do.
3. If you have your own plan for a screen, upload a mockup or photo, or describe it, and I'll fit it in.
4. We do one screen at a time; nothing is edited until you say "go ahead".

## 4. Find the review folder

Ask: "Where is your review folder (the one with `Screenshots` and `Screen_review_guide.md`)?" Then check it holds:
- `Screen_review_guide.md` (the advisor's requests, item by item, with "Look for" lists);
- `Screenshots\` with its `README.md` (names `<build>-<account>-<row>-<screen>-<size>-<before|after>.png`).

If either is missing: "Please download the `Screenshots` folder and `Screen_review_guide.md` from the team's Google
Drive folder (Capstone ARAL AAA) into a folder **outside** this repo, then tell me where it is." Wait for them. If the
Screenshots README lists shots to take by hand (online-only screens, Dashboard, Reminders, lists with a section
picked) and they're not there, mention which ones are missing; you can still start with the others.

Read `Screen_review_guide.md` (sections 1 to 3), `Screenshots\README.md` and `lib/ui/CLAUDE.md` before proposing.

## 5. Proposals (one screen at a time)

Let them pick the screen (one of theirs, or an unclaimed one). Then:

1. **Claim it first:** check `docs/handoff/checklist.md`; if someone else has it `in progress`, stop and say so.
   Otherwise write their name in **Assigned** and set **Status** to `in progress` (this is the only edit before
   "go ahead"), so nobody else edits the same file.
2. Look at that screen's shots (both sizes, before and any after). Check each "Look for" point of every advisor
   item that touches the screen. Say what you actually see; a shot showing "This needs an online sign-in", a spinner
   or only a "Pick a section" state can't prove a point: say so.
3. For each change, give:
   - **what** (one or two plain sentences) and **why** (the advisor item, e.g. M1-07, and its "Look for" point);
   - a small **before / after** text sketch;
   - the **ViewModel call** it needs, from `docs/handoff/screens/<file>.md`;
   - the **size**: small / medium / large;
   - any **conflict** with the fixed rules (below).
   End with: "Go ahead with these? Change anything?"
4. **Their own plan:** if they upload a mockup / photo or describe their idea, compare it with the advisor's items
   and the rules, merge what fits, and show the result as a proposal the same way.

### Fixed rules (say so plainly when an idea breaks one, and offer the closest version that fits)

- Screens call ViewModels through the scope only (`vmsOf(context)` / `BasaScope`), never services, repositories or
  console commands; `dart run tool/check_vm_boundary.dart` must pass.
- A ViewModel's refusal message is shown as it is; other errors show the general error message.
- Theme colours only (`Theme.of(context).colorScheme`), light and dark mode.
- Export is **Excel only** (`TableExportViewModel.xlsx`, `docs/handoff/screens/common.md` "Export and print"); no CSV
  or PDF button. Print and PDF come from Excel.
- The assessment screens (CRLA marking, Phil-IRI reading) are the **assessor's only**: nothing is shown to the
  learner, and nothing on screen should make a learner feel judged.
- Keep the existing look (`lib/ui/common/screen_kit.dart`); don't reformat lines you don't change.
- Admin-only screens stay under `lib/ui/admin/` (the tutor build must not reach them).

### Backend gaps

If a change needs data or an action no ViewModel offers, **don't work around it**. Write a short message the person
can forward to Ethan (backend):

```
For Ethan (backend): <screen> needs <what> to show <advisor item, e.g. M1-09 filter users by role>.
Today: <what the ViewModel gives>. Suggested call: <name and what it returns>.
```

and leave that part of the screen for later.

## 6. After "go ahead"

Make the agreed changes on branch **`don`** only (never `excelsior`, never `main`). Then the **finish line** for the
screen:

1. Run, and fix until clean: `dart analyze` (no errors), `flutter test`, `dart run tool/check_tutor_imports.dart`,
   `dart run tool/check_vm_boundary.dart`. **Do not play resource-intensive games while these run.**
2. Ask them to take the **after** screenshot in the app with the same account and size, named like the before shot
   with `-after`, and to put it in their review folder's `Screenshots`.
3. Set the screen's **Status** in `docs/handoff/checklist.md` to `pushed` once they've pushed (PR to
   `frontend_dev`).
4. Give them a **3-line summary for Ethan** (he updates the consultation log):
   ```
   Screen: <row> <screen> (<their name>), pushed <date>.
   Done: <advisor items covered, e.g. M1-07 search, filters, Excel export>.
   Left / backend asks: <anything waiting>.
   ```
5. Suggest `/clear` (or a new chat) before the next screen.

## Guardrails

- **Never commit** the review folder, the screenshots, `Screen_review_guide.md` or anything quoting the advisor: the
  repo is public. Keep them outside the repo.
- No git commands they didn't ask for; give them the commit message and let them commit.
- One screen per conversation.
