# Handoff: continue BASA in Claude Code

Paste everything below the line as your first message in Claude Code (run it from the BASA repo root, after placing the CLAUDE files).

---

I'm continuing BASA (Flutter/Dart reading-assessment app, capstone) from a long claude.ai chat. Please read `CLAUDE.md`, `lib/core/CLAUDE.md` and `CLAUDE.local.md` first. They were written from my notes, not from the code, so your first job is a **read-only audit**: compare them against the repo and give me a short list of anything wrong or out of date. Do not edit code yet, and do not change the CLAUDE files until I've seen your list.

Follow `CLAUDE.local.md` for how we work: guided, one piece at a time, I type and verify, no git commands from you, just give me a commit message when a piece is done.

## Where things stand
CRLA module is functionally complete on the backend side:
- Models: CrlaStory, CrlaAssessment, CrlaPart1Standard, CrlaPart1English, CrlaPart2Fluency, CrlaResult, plus `crla_language.dart` (Filipino → Tagalog).
- Repositories: interfaces plus Supabase and SQLite implementations for stories, assessments, the three Part tables, and results (read-only).
- Local SQLite schema with triggers and a local `crla_results` view (DB version about 10), verified opening and running.
- `CrlaViewModel` (header, Part 1 ×2, Part 2, results) wired into `lib/console/main.dart` and `lib/main.dart`.
- Console commands: `crla-start`, `crla-part1`, `crla-part2`, `crla-results`, all verified working.
- Temporary `pull-cloud` command copies cloud rows into an empty local DB so offline testing has data.
- All five `crla_*` views are `security_invoker = true` on the cloud DB.

## Things I need you to check during the audit
1. Does the SQLite `upsertWithId` for assessments and the Part tables really preserve the cloud's `id`, `attempt_no` and `wpm` (intended: `INSERT OR REPLACE`)?
2. Are the summary views (`crla_section_summary`, `crla_school_summary`, `crla_school_summary_weighted`, `crla_latest_attempts`) exposed anywhere in Dart (repo, ViewModel, console command), or only in SQL? I believe only in SQL, but I'm not sure.
3. Is `CrlaStory.toMap()` normalizing language, and does `CrlaAssessment.toMap()` use `normalizedLanguage`?
4. Any leftover commented-out code or duplicated normalization logic from the refactor (for example a private `_normalizeCrlaLanguage` still in a Supabase repo).
5. Anything in `local_database.dart` migrations that would be skipped by existing installs (new-table creators inside `oldVersion < N` blocks).

## Parked on purpose (don't start these unprompted)
- DB switching and sync design (after all modules are built, but before real data lives only on devices).
- Grade-based rule checks in the ViewModel (tutor-capabilities phase).
- The admin-only build variant.

## Likely next steps (I'll tell you which)
- CRLA story import from the source workbooks (needs Filipino → Tagalog; stories are currently seeded only for region 13, grades 1–3).
- Exposing the CRLA summary views through the Dart layer, if the audit shows they aren't.
- Starting Phil-IRI, which follows the same module workflow as CRLA.

When the audit is done, give me the list, then ask which step I want next.
