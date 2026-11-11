# Phil-IRI passages in any round (content fix) — design

Date: 2026-11-10. Status: approved in conversation (owner); this file awaits the owner's review.

## Why

The content fix after R1/R2, before import Task 6 (`docs/superpowers/plans/2026-11-09-phil-iri-import.md`).

Ma (2026-11-09, answering import spec question 1, "may Grade 7 read the A–D graded passages in BOSY?"): **any grade-level passage may be read in any round; each passage once per learner.**

Today a passage's `test_type` ties it to a round (`pre` = BOSY, `mosy` = MOSY 1–3, `post` = EOSY, null = any round), checked in three places: the ViewModel (`availablePassages` filters, `startReading` refuses), the SQLite reading trigger and the cloud `check_phil_iri_reading()`. Imported sessions already skip it. About 83 seeded passages carry a type (2018 set 23 pre / 24 post; graded pool 4 pre / 13 mosy / 4 post; JHS 2024 pre/post tests 7 each; Social Media Spectrum 1 mosy), so the G7 A–D filing is only one case of a rule ma no longer has.

## Decisions

| # | Decision |
|---|----------|
| D1 | **The round rule goes, for every passage** (owner, option A). No layer refuses a passage because of its `test_type`. Rejected: clearing only the G7 A–D types (other grades keep a lock ma doesn't have); nulling every `test_type` (loses the booklet label for nothing). |
| D2 | **`test_type` stays, as a label** (the booklet's pretest / MOSY / posttest). Column, CHECK (`pre`/`mosy`/`post`/null), seeds and the content command's `test` field are unchanged. No data edits on any server. |
| D3 | **Unchanged rules:** active passage in an active collection, own grade for grade-leveled collections, no-repeat (a learner never reads the same text twice, except the oral follow-up of a silent reading in the same round), one passage reading per session, the Untitled and imported-session exemptions (R2, import D8). |
| D4 | **Passage list order** (owner, option A): oral follow-ups first (as today), then passages labelled with this round's type (BOSY `pre`, MOSY `mosy`, EOSY `post`), then the rest (other labels and unlabelled) in today's order. A suggestion order only; nothing is filtered by round. |
| D5 | **Cloud migration `20261110030000_phil_iri_any_round_passages.sql`**: `create or replace function public.check_phil_iri_reading()` copied from its latest version (`20261110020000`) with only the `test_type` block (and its variable) removed. Idempotent; ends with its `basa_migrations` row; id added to `lib/core/release.dart`; README 2b lists it. No table or view created, so no grants; no policy touched (the check lives in the trigger only), RLS unchanged. |
| D6 | **`App update required on all devices: yes`**: a rule change; an older device's SQLite trigger and ViewModel keep refusing what the server accepts. |
| D7 | **SQLite v43**: version bump only (no table change); `onUpgrade` recreates the Phil-IRI triggers, now without the round block (the v16/v17 pattern). |
| D8 | **ViewModel**: `startReading` drops the round refusal; `PhilIriRound.allowsPassageTestType` is deleted; `PhilIriRound.passageTestType` stays (used by D4). Doc comment of `availablePassages` updated. |
| D9 | **Import**: with no round rule, there is no "round clash". Import spec D8 keeps re-reads imported and flagged, lower-grade passages skipped; the round-clash flag goes (spec D8, outcome list item 5, FAQ item 7, question 1 marked answered). Import plan Task 9's preview line `round clash and re-read are imported, flagged` becomes `re-read is imported, flagged`; R2's note drops "round-clash". |

## Tests (written first)

- ViewModel: a BOSY session lists and accepts a `post` and a `mosy` passage of the learner's grade; MOSY and EOSY likewise accept other labels.
- ViewModel: list order = follow-ups, then same-round label, then the rest.
- ViewModel: no-repeat and own-grade refusals still hold.
- SQLite: `test/core/data/phil_iri_import_v40_test.dart` line 166 (expects "This round does not use this passage") flips to acceptance; a v42 → v43 upgrade test: a live BOSY reading of a `post` passage is accepted after the upgrade.
- PG18 (throwaway Postgres 18, baseline + migrations): live BOSY reading of a `post` passage accepted; a re-read and a wrong-grade passage still refused; migration runs twice.
- `dart analyze`, `flutter test --concurrency=2`, both tool checks.

## Rollout and verification

- The owner applies `20261110030000` on dev after every device has synced and every upload is decided (README *Keeping BASA up to date*); sign-in on dev refuses the new release until then.
- Then a full command pass (new run); scenario lines that expected the round refusal (if any) are updated.
- Verify kit: `D:/0_CAPSTONE/verify/phil-iri-any-round` (console steps with ids filled and expected output; SQL check for the function body).

## Docs

`lib/core/CLAUDE.md` (v43 note; Phil-IRI passage rule), `CLAUDE.md` (Phil-IRI line), `docs/handoff/screens/phil-iri.md` (passage picker order, if it describes it), README 2b, import spec and plan (D9).

## Out of scope

- Recommending a specific passage per round beyond the list order.
- Changing seeds or `test_type` values.
- Live (non-import) readings of lower-grade passages (ma 2026-11-09: not allowed).
