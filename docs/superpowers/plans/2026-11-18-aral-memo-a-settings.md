# ARAL memo, Plan A: ARAL rules as school settings — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the DepEd-given ARAL numbers (class size, session rules, basis round, check-in sessions, IRIP length) into school settings whose defaults keep today's behaviour, so Valencia City schools can follow Division Memorandum 180 s. 2026.

**Architecture:** One pure settings model (`AralRuleSettings`) read from the `aral_settings` mirror (default row ← school row) by the ViewModels; the same keys read by the SQLite triggers (json_extract) and by the server checks (a new `aral_setting` helper). One migration (app update required: yes), SQLite v46. Plan B (advisers, tutor type, daily tutor limits, class session type, class names, Forms 1/2/4) follows separately.

**Tech Stack:** Dart (pure core + ViewModels), sqflite_common_ffi (SQLite), Supabase Postgres (PL/pgSQL), flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-18-aral-division-memo-design.md` (sections 1-5, 9; Plan A part).

## Global Constraints

- Every new setting's default = today's behaviour; a school outside the Division sees no change without a setting (spec anti-goal).
- Keys and ranges (spec §1, with one correction below): `class_max_learners` int 1-50 default 15; `class_min_learners` int 0-50, 0 = none, must be <= max; `session_max_minutes` int 1-120, absent = today's rule; `sessions_weekdays_only` bool default false; `class_min_sessions_per_week` int 0-7 default 0; `basis_round` `bosy`/`mosy` default `bosy`; `checkin_after_sessions` two increasing ints 1-200 default [16, 32]; `irip_weeks` int 1-26 default 8.
- Correction to the spec (call, tell the owner): `session_max_minutes` is 1-120, not 1-240, because both databases limit `aral_sessions.minutes` to 1-120; a wider setting could never be used.
- Absent `session_max_minutes` keeps exactly: refuse < 1 or > 120, warn above 60 on weekdays (lastWarning), weekends up to 120.
- Settings resolve school row over default row (`school_id` null) over built-in default, on the device, in SQLite triggers and on the server.
- Only taking a new place is refused in a class over the maximum; exits, attendance and edits still work (the server cap trigger already returns early for a learner who keeps their place).
- Check-in tools and saved check-ins keep checkpoint ids 16 and 32 (= first, second check-in); `checkin_after_sessions` only moves when they are due.
- Lowering `irip_weeks` never deletes saved weeks.
- Migration: header `App update required on all devices: yes` + `Apply only when all work is finalized: every device synced, every upload decided (README "Keeping BASA up to date")`; ends with its `basa_migrations` row; id added to `lib/core/release.dart`; README 2b line; RLS of touched tables reviewed in the same file.
- Admin-only writes and their commands go in `*_admin_commands.dart`; `dart run tool/check_tutor_imports.dart` and `dart run tool/check_vm_boundary.dart` pass.
- Owner rule: never run git. Each task ends by handing the owner a commit message.
- Before any console or kit run, ask the owner to close any open BASA console.

## Review Focus

1. A school with an existing class of 12 when its maximum drops to 10: exits, attendance marks and edits in that class still save, on the device and through `sync_apply`; only a new placement is refused. (Task 2 PG test, Task 3 SQLite test.)
2. A device that never had any of the new keys (old mirror rows, region row only): every rule behaves exactly as before. (Task 1 defaults test, Task 4/5 "absent key" tests.)
3. A malformed stored value (string where an int is expected, [32, 16] for check-ins, min > max) is refused on write and ignored on read (falls back to the default). (Task 1, Task 2 CHECK constraints.)
4. Offline work made under old settings, uploaded after the school tightened them (a Saturday session logged before `sessions_weekdays_only` was turned on): the server refuses it with a readable message and the device can resolve it (keep server / edit). (Task 2 PG test; message wording in Task 5.)
5. An IRIP learner already in week 7 of an 8-week cycle when the school sets `irip_weeks` to 6: the saved weeks stay, the cycle is not stranded (it counts as done once its last saved week is rated), and a week above the new length is refused only in a new cycle. (Task 7 test; server side Task 2 refuses a new week above N, so the device must not offer week 8 either: cycle length = max(N, highest saved week).)

---

### Task 1: AralRuleSettings model and the generic setting commands

**Files:**
- Create: `lib/core/services/aral_rule_settings.dart`
- Modify: `lib/viewmodels/aral_checkin_viewmodel.dart` (settings section, lines ~435-600)
- Modify: `lib/core/console/commands/aral_checkin_admin_commands.dart`
- Test: `test/core/services/aral_rule_settings_test.dart`, `test/viewmodels/aral_setting_layers_test.dart` (extend)

**Interfaces:**
- Produces:
  - `class AralRuleSettings` with fields `int classMaxLearners`, `int classMinLearners`, `int? sessionMaxMinutes`, `bool sessionsWeekdaysOnly`, `int classMinSessionsPerWeek`, `AralBasisRound basisRound`, `List<int> checkinAfterSessions` (length 2), `int iripWeeks`; `static const defaults`; `factory AralRuleSettings.fromMap(Map<String, Object?> m)` (bad values ignored → default; min > max → min ignored); key constants `classMaxLearnersKey = 'class_max_learners'`, … one per key.
  - `enum AralBasisRound { bosy, mosy }` (value strings `'bosy'`, `'mosy'`).
  - `String? aralRuleSettingProblem(String key, Object? value)` — null when valid for that key, else a plain message; unknown key → message listing the keys.
  - `int aralCheckpointForSession(AralRuleSettings s, int sessionNo)` → 16 or 32 when `sessionNo` is the first/second check-in session, else 0.
  - On `AralCheckinViewModel`: `Future<AralRuleSettings> localRuleSettings(int schoolId)`; `Future<({Object? region, Object? school, Object? effective, Object? defaults})> ruleSettingLayers(String key, int? schoolId)` (online); `Future<AralSetting> setRuleSetting(int? schoolId, String key, Object? value)` (online, `value == null` removes the key from that row; refuses via `aralRuleSettingProblem`; for `class_min_learners`/`class_max_learners` also refuses min > max against the effective other value).
  - Console (admin): `aral-setting <key> [schoolId]`, `aral-setting-set <key> <region|schoolId> <value|->` (`-` removes; list values as `16,32`).

- [ ] **Step 1: Write failing tests** in `aral_rule_settings_test.dart`:
  - `defaults keep today's behaviour`: `AralRuleSettings.fromMap({})` → classMax 15, classMin 0, sessionMaxMinutes null, weekdaysOnly false, minPerWeek 0, basisRound bosy, checkins [16, 32], iripWeeks 8.
  - `school values over defaults`: fromMap({'class_max_learners': 10, 'class_min_learners': 5, 'sessions_weekdays_only': true, 'session_max_minutes': 60, 'basis_round': 'mosy', 'class_min_sessions_per_week': 3}) gives those values.
  - `bad values fall back`: 'class_max_learners': '10' → 15; 'session_max_minutes': 121 → null; 'checkin_after_sessions': [32, 16] → [16, 32]; 'irip_weeks': 0 → 8; class_min 12 with max 10 → min 0.
  - `problems name the range`: aralRuleSettingProblem('class_max_learners', 0) contains '1-50'; ('session_max_minutes', 150) contains '120'; ('basis_round','eosy') non-null; ('nope', 1) lists 'class_max_learners'.
  - `checkpoint for a session`: settings [12, 24]: session 12 → 16, 24 → 32, 16 → 0.
- [ ] **Step 2: Run** `flutter test test/core/services/aral_rule_settings_test.dart` — expected FAIL (file missing).
- [ ] **Step 3: Implement** `aral_rule_settings.dart` (pure Dart, no Flutter import). Keep `AralSessionSettings`/`AralProgramSettings`/`AralCheckinSettings` as they are.
- [ ] **Step 4: Run** the test — PASS.
- [ ] **Step 5: Extend** `aral_setting_layers_test.dart` with `setRuleSetting writes, mirrors and removes` (fake cloud as the file already does): set school 1 `class_max_learners` 10 → `localRuleSettings(1).classMaxLearners == 10`; set `-` (null) → back to 15; min 12 with max 10 refused with a message containing 'maximum'; a tutor caller refused.
- [ ] **Step 6: Implement** the three ViewModel methods following `setIdleSessionDays` (`_settingsWriter`, `_cloudWrite`, `_mirror`); add the two console commands in `aral_checkin_admin_commands.dart` printing `key: effective (school X / region Y / default Z)`.
- [ ] **Step 7: Run** `flutter test test/viewmodels/aral_setting_layers_test.dart test/core/services/aral_rule_settings_test.dart` and `dart analyze` — PASS, no errors.
- [ ] **Step 8: Commit message to the owner:** `feat(aral): school settings model for the ARAL memo rules (defaults = today)`.

### Task 2: Server migration (settings checks, class cap, sessions, IRIP length)

**Files:**
- Create: `supabase/migrations/20261118010000_aral_memo_settings.sql`
- Modify: `lib/core/release.dart`, `README.md` (2b)
- Test: PG 18 throwaway harness (stubs + baseline + every migration in order, the new one twice); steps file kept in the session scratchpad, recipe in the team notes.

**Interfaces:**
- Consumes: the key names and ranges of Task 1.
- Produces (SQL):
  - `aral_settings` CHECK constraints per key (`aral_settings_class_max`, `_class_min`, `_session_max_minutes`, `_weekdays_only`, `_min_sessions_week`, `_basis_round`, `_checkin_after_sessions` (array of 2 numbers, increasing, 1-200), `_irip_weeks`), same shape as `aral_settings_pass_pct`.
  - `public.aral_setting(p_school_id bigint, p_key text) returns jsonb` STABLE SECURITY DEFINER `search_path = public`: school row's value, else default row's (`school_id is null`), else null. `aral_foundational_program_on` unchanged.
  - `aral_check_class_placement` and `aral_enrollments_class_cap` (latest definitions in `20261024010000` / `20261024050000`) read `coalesce((aral_setting(school,'class_max_learners'))::int, 15)`; message `'an ARAL class has at most N active learners'` with the number.
  - Sessions: the BEFORE INSERT/UPDATE session triggers (latest in `20261024050000`) refuse, using the session's school: `sessions_weekdays_only` true and (`extract(isodow from held_on) in (6,7)` or `setup = 'weekend'`) → `'ARAL sessions are held Monday to Friday at this school'`; `session_max_minutes` set and `minutes >` it → `'an ARAL session at this school lasts at most N minutes'`. Existing rows are not re-checked unless updated.
  - IRIP: drop `aral_irip_weeks_week_no_check`, add `check (week_no between 1 and 26)`; the IRIP week BEFORE INSERT trigger refuses `week_no > coalesce(aral_setting(school,'irip_weeks')::int, 8)` with `'an IRIP cycle at this school has N weeks'` (UPDATE can't change week_no already).
  - Ledger row `('20261118010000','aral_memo_settings', true)`.
- [ ] **Step 1: Write the PG steps file** with these cases (each as a `t(...)` or DO block asserting):
  - defaults: no settings rows → a 16th active learner refused, 15th accepted; a 61-minute weekday session accepted; a Saturday session accepted.
  - school 1 `class_max_learners` 10: 11th placement refused with 'at most 10'; existing class of 12 (inserted before the setting): exiting one learner succeeds; editing another's notes succeeds; placing a new one refused.
  - default row 10, school row 15 → school wins (15).
  - `sessions_weekdays_only` true: Saturday refused, `setup='weekend'` on a Monday refused, Monday accepted; `session_max_minutes` 60: 61 refused, 60 accepted.
  - `sync_apply` of an upload that swaps two learners between two classes at the maximum succeeds (deferred end-state).
  - IRIP: `irip_weeks` 6 → week 7 insert refused; with no setting week 8 accepted, week 9 refused; existing week 8 rows survive setting 6.
  - CHECK constraints: `{"class_max_learners":"10"}`, `{"checkin_after_sessions":[32,16]}`, `{"session_max_minutes":150}` each refused.
  - grants: `has_function_privilege('authenticated','public.aral_setting(bigint,text)','execute')`.
- [ ] **Step 2: Run** the harness before writing the migration — expected: the new cases FAIL (cap still 15, no session checks).
- [ ] **Step 3: Write the migration** (idempotent: `create or replace`, `drop constraint if exists`), header per Global Constraints, comments naming the memo and the spec.
- [ ] **Step 4: Run** the harness with the migration applied twice — all cases PASS; `pg_ctl stop` and remove the data dir.
- [ ] **Step 5: Add** the id to `lib/core/release.dart`; README 2b line ("ARAL memo settings: class size, session rules, basis round, check-in sessions and IRIP length as school settings, today's values by default; app update required: **yes**, apply only when every device has synced and every upload is decided"); run `flutter test test/supabase/migration_grants_test.dart` — PASS.
- [ ] **Step 6: Commit message to the owner:** `feat(aral,db): ARAL memo rules read from school settings on the server (20261118010000)`; tell the owner the migration must be applied to the dev cloud before Task 8's command pass.

### Task 3: SQLite v46 (triggers read the settings; IRIP table rebuilt)

**Files:**
- Modify: `lib/core/data/local/aral_local_schema.dart` (placement triggers ~305-360, session triggers ~430-470, IRIP table/triggers ~525-600)
- Modify: `lib/core/data/local/local_database.dart` (version 46, comment, call on create and every upgrade)
- Test: `test/core/data/aral_memo_v46_test.dart`

**Interfaces:**
- Produces: `Future<void> upgradeAralMemoForV46(Database db)` (idempotent; recreates the triggers; rebuilds `aral_irip_weeks` only when its stored SQL still contains `BETWEEN 1 AND 8`, keeping every row and column, indexes and triggers).
- SQL helper string in Dart: `String aralSettingSql(String schoolExpr, String key)` → `COALESCE((SELECT json_extract(settings,'$.<key>') FROM aral_settings WHERE school_id = <schoolExpr>), (SELECT json_extract(settings,'$.<key>') FROM aral_settings WHERE school_id IS NULL))` (the pattern of the SHARP check at ~line 629).
- [ ] **Step 1: Write failing tests** (pattern of `enrollment_moves_v45_test.dart`, a real v45 database upgraded):
  - `v45 IRIP weeks survive the rebuild` (rows of weeks 1-8 kept, ids kept).
  - `class max from the school setting` (mirror row `{'class_max_learners': 10}` for school 1: 11th active learner insert aborts with 'at most 10'; default 15 when no row).
  - `over-max class still edits` (12 active learners present, then setting 10: update notes of one and exit another succeed).
  - `weekday rule` (`sessions_weekdays_only` true: insert on 2026-11-21 (Saturday) aborts; on 2026-11-23 works).
  - `session max minutes` (60: 61 aborts).
  - `IRIP weeks setting` (6: week 7 aborts; no row: week 9 aborts, 8 works).
- [ ] **Step 2: Run** `flutter test test/core/data/aral_memo_v46_test.dart` — FAIL.
- [ ] **Step 3: Implement** `upgradeAralMemoForV46`, bump to version 46, call it in `onCreate` (after `createAralLocalSchema`) and at the end of every `onUpgrade` (like `upgradeEnrollmentMovesForV45`). Remove `_classCap` (the trigger reads `COALESCE(<setting>, 15)`).
- [ ] **Step 4: Run** that test and every `test/core/data/*_test.dart` — PASS.
- [ ] **Step 5: Commit message:** `feat(aral,sqlite): v46 triggers read the ARAL memo settings; IRIP weeks up to 26`.

### Task 4: Class size on the device (cap, over-max and under-min notices)

**Files:**
- Modify: `lib/core/services/aral_rules.dart` (`aralClassCap` → default only; `aralPlacementProblem` gains `required int maxLearners`; `aralPlacementMessage` names the number)
- Modify: `lib/viewmodels/aral_class_viewmodel.dart` (`classCap` getter → `Future<int> classMax(int schoolId)`, `Future<int> classMin(int schoolId)`), `lib/viewmodels/aral_roster_import_viewmodel.dart:242`, `lib/viewmodels/reminder_viewmodel.dart` (`AralClassNoticeKind` + `overMax`, `underMin`), `lib/core/console/commands/aral_class_commands.dart`, `aral_class_admin_commands.dart`, `aral_command_helpers.dart` (`aralClassLine(c, cap:, active:)` shows "12 of 10, over the maximum")
- Test: `test/core/services/aral_placement_rules_test.dart` (extend), `test/viewmodels/aral_roster_classes_test.dart` (extend)

**Interfaces:**
- Consumes: `AralCheckinViewModel.localRuleSettings` is in another ViewModel; read the mirror directly instead: `AralClassViewModel` gets `AralSettingRepository localSettings` (already wired for other ViewModels in `wire_tutor.dart`) and a private `_rules(int schoolId)` doing `AralRuleSettings.fromMap({...?region?.settings, ...?school?.settings})`.
- Produces: `aralPlacementProblem(..., required int maxLearners)`; `AralClassNoticeKind.overMax` message `'Class "X" has 12 active learners, more than the maximum 10: move learners to another class (aral-class-unplace, or aral-class-place into another class). Their records stay.'`; `underMin` message `'Class "X" has 3 active learners, fewer than 5: combine with the nearest level of the same grade if there is one.'`
- [ ] **Step 1: Failing tests:** placement rules: `full at the school's maximum` (maxLearners 10, others 10 → full; others 9 → null); message contains '10'. Roster/classes VM: school setting 10 → 11th `place` throws with '10'; class with 12 active and setting 10 → `coordinatorReminders` has one `overMax` naming the class; `unplace` of one learner keeps their attendance rows (count before == after); class with 3 and min 5 → `underMin`; min 0 → none.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**; update every caller of `aralPlacementProblem` / `aralClassCap` (grep both); keep the public `aralClassCap` const as `AralRuleSettings.defaults.classMaxLearners` alias or remove it if no caller is left.
- [ ] **Step 4: Run** `flutter test test/core/services test/viewmodels` and `dart analyze` — PASS.
- [ ] **Step 5: Commit message:** `feat(aral): class size from the school setting; over-maximum and under-minimum notices`.

### Task 5: Session rules on the device (weekdays, maximum length, sessions a week, check-in sessions)

**Files:**
- Modify: `lib/viewmodels/aral_session_viewmodel.dart` (`_checkMinutes` ~586, `_noteCheckIn` ~605, `classSummary` ~468, `aralCheckInAfter` const removed), `lib/viewmodels/aral_checkin_viewmodel.dart` (~217, ~344), `lib/viewmodels/reminder_viewmodel.dart` (~556 check-ins due; `TutorReminderKind` + `fewSessionsThisWeek`; coordinator side same notice per class)
- Test: `test/viewmodels/aral_class_sessions_test.dart` (extend)

**Interfaces:**
- Consumes: `AralRuleSettings`, `aralCheckpointForSession` (Task 1); `AralSessionViewModel` reads the mirror like Task 4 (`_rules(schoolId)`).
- Produces: `_checkSession(String date, int minutes, AralSetup setup, AralRuleSettings r)` replacing `_checkMinutes`; `TutorReminderKind.fewSessionsThisWeek` message `'Class "X" has 1 session this week; the school asks for at least 3.'`, shown from Wednesday of the current Monday-Friday week (today's weekday >= 3), counting sessions with `held_on` in that week.
- [ ] **Step 1: Failing tests:**
  - `absent settings keep today's rule` (61 on a Monday logs with lastWarning containing '60'; 120 on Saturday logs; 121 refused).
  - `weekdays only` (setting true: Saturday refused 'Monday to Friday'; Monday with setup weekend refused; Monday pull-out works).
  - `maximum length` (60: 61 refused with '60'; no warning text when within).
  - `edit follows the same rules` (editSession to Sunday refused).
  - `check-ins follow the setting` ([12, 24]: logging session 12 sets lastWarning 'check-in assessment is due'; classSummary.nextCheckInAfter == 12 before it; a check-in saved for that class is stored with checkpoint 16).
  - `fewer sessions this week` (min 3, today Wednesday 2026-11-25, one session Monday → reminder; today Tuesday → none; min 0 → none).
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.** Check-in tools are still looked up by checkpoint 16/32 (`aralCheckpointForSession`); every place that compared a session number with `[16, 32]` compares with `r.checkinAfterSessions` instead.
- [ ] **Step 4: Run** `flutter test test/viewmodels` and `dart analyze` — PASS.
- [ ] **Step 5: Commit message:** `feat(aral): session rules and check-in sessions from the school settings; sessions-a-week reminder`.

### Task 6: Basis round for new proposals

**Files:**
- Modify: `lib/viewmodels/aral_viewmodel.dart` (`_crlaCandidate` ~276, `_philIriCandidate` ~320-390, where they are called), `lib/core/services/aral_rules.dart` (`aralCrlaBasisRound(int grade, AralBasisRound setting)`)
- Test: `test/core/services/aral_ks1_rules_test.dart` (extend), `test/viewmodels/aral_roster_classes_test.dart` or a new `test/viewmodels/aral_basis_round_test.dart`

**Interfaces:**
- Consumes: `AralBasisRound` (Task 1).
- Produces: `CrlaRound aralCrlaBasisRound(int grade, AralBasisRound setting)` → G1 always `mosy`; G2-3 `bosy` or `mosy` per setting. Phil-IRI with `mosy`: the latest of `mosy3`, `mosy2`, `mosy1` that counts for the learner (the school's ARAL value source, `results.view(round, values)`), else `bosy`; `basisRound` records the round used.
- [ ] **Step 1: Failing tests:** `aralCrlaBasisRound(2, AralBasisRound.mosy) == CrlaRound.mosy`, `(2, bosy) == bosy`, `(1, bosy) == mosy`. VM: setting `mosy`, a Grade 7 learner with BoSY Instructional-at-grade (not ARAL) and MoSY1 2 levels down → proposed with basisRound 'mosy1'; same learner, setting `bosy` → not proposed (today); a learner with only BoSY under `mosy` → BoSY used; a Grade 2 learner with CRLA BoSY Low Emerging and MoSY Transitioning, `ks1_extended` off, `mosy` → not proposed.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.** Keep the not-assessed stand-in round as the basis round actually used.
- [ ] **Step 4: Run** `flutter test` (whole suite: proposals feed reports) and `dart analyze` — PASS.
- [ ] **Step 5: Commit message:** `feat(aral): choose new ARAL learners from the latest round up to MoSY when the school says so`.

### Task 7: IRIP cycle length on the device

**Files:**
- Modify: `lib/viewmodels/aral_irip_viewmodel.dart` (~47, ~152, ~185, ~280), `lib/core/services/aral_irip_rules.dart` (`aralIripWeeks` → default only)
- Test: a new `test/viewmodels/aral_irip_weeks_test.dart`

**Interfaces:**
- Consumes: `AralRuleSettings.iripWeeks`; the ViewModel reads the mirror for the learner's school.
- Produces: the cycle's length per learner = `max(r.iripWeeks, highest week saved in that cycle)` (so lowering N never strands a cycle); messages say the number.
- [ ] **Step 1: Failing tests:** setting 6: a new cycle's week 7 refused with 'has 6 weeks'; `cycleDone` true after week 6 rated; a cycle already at week 8 under setting 6 counts done after week 8 is rated (not stranded); no setting → 8 as today.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/viewmodels` and `dart analyze` — PASS.
- [ ] **Step 5: Commit message:** `feat(aral): IRIP cycle length from the school setting`.

### Task 8: Docs, command lists, command pass, verify kit

**Files:**
- Modify: `README.md` (section 7: `aral-setting`, `aral-setting-set`), `tool/installer/guide/admin/Functions/ARAL-Reading.txt` (a "School ARAL settings" part: each key in plain words, the Valencia City values, the over-maximum notice and how to move learners, "records stay"), `CLAUDE.md` (module checklist line for the memo work; Parked: CRLA language per grade stays in code), `lib/core/CLAUDE.md` (placement rules: the cap is a setting, read in three places), `docs/handoff/screens/` (a block for the settings screen fields), `test/core/wiring/admin_commands.txt` (+ the two commands; tutor list unchanged), `tool/command_pass/scenarios/` (a new `40_m1.pass` or extend the ARAL batch: set school 10 → place 11th refused, over-max notice, Saturday session refused, reset with `-`), `docs/superpowers/specs/2026-11-18-aral-division-memo-design.md` (the 1-120 correction; daily tutor limits moved to Plan B)
- Test: `flutter test test/core/wiring`, the command pass batch.

- [ ] **Step 1: Update** the command list file; run `flutter test test/core/wiring` — PASS (command counts in CLAUDE.md updated: admin +2).
- [ ] **Step 2: Write** the pass scenario; ask the owner to apply `20261118010000` on the dev cloud (and to close any open BASA console); run `dart run tool/command_pass/run.dart --run r<N> <batch>` — all steps PASS (**DO NOT PLAY RESOURCE INTENSIVE GAMES** while it runs).
- [ ] **Step 3: Run** `dart analyze`, `flutter test`, `dart run tool/check_tutor_imports.dart`, `dart run tool/check_vm_boundary.dart` — no errors, all PASS.
- [ ] **Step 4: Write the docs** listed above; build the verify kit under `D:/0_CAPSTONE/verify/aral-memo-a/` (settings set/show, placement refusal, over-max notice, weekend refusal, reset), ids filled, expected output.
- [ ] **Step 5: Commit message:** `docs(aral): ARAL memo settings in the README, admin guide and project notes; command pass batch`.
