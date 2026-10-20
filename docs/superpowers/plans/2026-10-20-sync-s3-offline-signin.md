# Sync S3: offline sign-in Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The device owner can sign in without a connection (salted PBKDF2 hash kept after an online sign-in, within `offline_signin_days`), and nothing that needs the server can run, or crash, in an offline session.

**Architecture:** A pure-Dart PBKDF2 (on `package:crypto` HMAC) and a pure rule function decide offline sign-in; a small SQLite repository holds the one `offline_credentials` row (table already created in v34). `AuthViewModel` stores the credential after every clean online sign-in and password change, adds `signInOffline` and an `isOffline` session with no client, and splits the guard into `requireActiveSession()` (online or offline) and `requireOnlineSession()` (live client). Every `client!` site switches to the online guard.

**Tech Stack:** Dart, sqflite_common (ffi in console), `crypto` ^3.0.6 (already resolved as 3.0.7 transitively), supabase.

**Spec:** `docs/superpowers/specs/2026-10-20-sync-design.md` section 6 (also 2.4 for `offline_signin_days`, 10 for known risks).

## Global Constraints

- No SQLite bump: `offline_credentials` and `login_logs.mode` exist since v34 (`sync_local_schema.dart`). No server migration (offline logs stay local).
- `offline_signin_days`: whole number 1-60, default 14; layered school → region-wide → 14 from the local `report_settings` mirror (the server CHECK from S1 already enforces the range).
- Salt 16 bytes from `Random.secure()`; hash = PBKDF2-HMAC-SHA256, 32 bytes; salt and hash stored as lowercase hex; `iterations` stored per row so the constant can change later.
- Five wrong passwords (`failed_attempts >= 5`) disable offline sign-in until the next online sign-in.
- Never log or print the password, salt or hash (ScopedLogger lines show the email only).
- `core/` and `viewmodels/` never import Flutter. Wire into both `lib/console/main.dart` and `lib/main.dart`.
- `dart analyze`: no new errors.

## Decisions for the owner (proposed; say if any is wrong)

1. **Owner check = last puller.** Offline sign-in also requires `offline_credentials.user_id == sync_meta.last_pull_user_id` (the data on the device is theirs). Never pulled → refused ("sign in online and pull first"). S4 keeps this key as the device owner.
2. **Every clean online sign-in overwrites the credential**, whoever signs in. So if user B signs in online on A's device, A loses offline sign-in there until A signs in online again; B can't sign in offline either until B pulls (decision 1). S4's owner-switch refusal sits on top of this.
3. **Offline logs:** new `LoginMethod.offline`; the local repo writes `mode = 'offline'` for it, `'online'` otherwise. `cachedSession` stays (unused, kept for the `login-log` dev command).
4. **One vague message** for unknown email and wrong password ("Offline sign-in failed: wrong email or password"); every other refusal says why (window expired, too many attempts, inactive, not the device owner, clock).
5. **Clock set back:** if the device clock is more than 5 minutes before `last_online_at`, refuse ("this device's clock is earlier than your last online sign-in"). Otherwise the window could be stretched by moving the clock back past the last sign-in. (Moving it forward only shortens the window; moving it back within the window can't be detected. Stays a known risk, spec 10.)
6. **Iterations:** start at 100 000, measured in Task 1 on this PC; kept if one hash takes 50-150 ms here (roughly 0.5 s on a low-end phone), else scaled to land in that range. The number goes in the commit body.

## Review Focus

- Clock set back before `last_online_at` → refused, not treated as "0 days elapsed" (Task 2 rule test).
- Five wrong passwords then the right one → still refused; an online sign-in resets the counter (Task 2 rule test, kit file 3).
- Offline session reaching any server action (pull-cloud, user/school/section ViewModels, version-check, login-recent, change-password) → a plain "needs an online sign-in" message, never a null-check crash (Task 4 audit grep + kit file 2).
- Online sign-in with `must_change_password` → no credential stored; after `change-password` → credential stored with the NEW password (Task 3, kit file 1).
- Offline sign-in while an online session is open → the online session is signed out first (no dangling refresh token), and vice versa (Task 3).

---

### Task 1: PBKDF2 + dependency

**Files:**
- Modify: `pubspec.yaml` (dependencies: `crypto: ^3.0.6`)
- Create: `lib/core/services/pbkdf2.dart`
- Test: kit probe `D:/0_CAPSTONE/verify/sync-s3/probe_pbkdf2.dart`

**Interfaces:**
- Produces: `List<int> pbkdf2HmacSha256(List<int> password, List<int> salt, int iterations, {int length = 32})`; `const offlineHashIterations = 100000` (value per decision 6); `String toHex(List<int> bytes)`; `List<int> fromHex(String hex)`; `bool constantTimeEquals(List<int> a, List<int> b)`.

- [ ] **Step 1: Write the probe.** Prints `ok`/`FAIL` per case. Expected bytes computed with `python -I -c "import hashlib;print(hashlib.pbkdf2_hmac('sha256',P,S,c,dklen).hex())"` and pasted in: (`password`,`salt`,1,32), (`password`,`salt`,2,32), (`password`,`salt`,4096,32), (`passwordPASSWORDpassword`,`saltSALTsaltSALTsaltSALTsaltSALTsalt`,4096,40) — the last checks a length that is not a multiple of 32. Also `constantTimeEquals` on equal / different / different-length lists, and `fromHex(toHex(x)) == x`. Prints the ms for one `offlineHashIterations` hash.
- [ ] **Step 2: Run it** (`dart run --packages=... probe_pbkdf2.dart`); expected: fails to compile (no file).
- [ ] **Step 3: Implement `pbkdf2.dart`** with `Hmac(sha256, password)` from `package:crypto` (RFC 8018 F-function: block index big-endian 4 bytes, XOR of U1..Uc). `constantTimeEquals` returns false on length mismatch, else ORs every byte XOR.
- [ ] **Step 4: Run the probe**; expected all `ok`; set the iteration constant per decision 6. `dart analyze`.

### Task 2: credential store + rule + settings key + offline log mode

**Files:**
- Create: `lib/core/models/offline_credential.dart`, `lib/core/repositories/offline_credential_repository.dart`, `lib/core/data/local/offline_credential_repository_sqlite.dart`, `lib/core/services/offline_signin_rules.dart`
- Modify: `lib/core/models/login_method.dart` (add `offline`), `lib/core/data/local/login_log_repository_sqlite.dart` (write `mode`), `lib/core/models/report_setting.dart` (key + field)
- Test: kit probe `D:/0_CAPSTONE/verify/sync-s3/probe_rules.dart`

**Interfaces:**
- Produces:
  - `class OfflineCredential { String userId, email, salt, hash, lastOnlineAt; int iterations, failedAttempts; }` with `fromMap`/`toMap` (column names as in v34; `lastOnlineAt` UTC ISO-8601).
  - `abstract class OfflineCredentialRepository { Future<OfflineCredential?> get(); Future<void> save(OfflineCredential c) /* replaces the single row: delete all, insert */; Future<void> recordFailure(String userId); Future<String?> dataOwnerId() /* sync_meta last_pull_user_id */; }`
  - `ReportSettings.offlineSigninDaysKey = 'offline_signin_days'`, `defaultOfflineSigninDays = 14`, field `int offlineSigninDays` read in `fromMap` (`(m[key] as num?)?.toInt() ?? 14`); update the file header's key list.
  - `enum OfflineRefusal { noCredential, wrongEmailOrPassword, tooManyAttempts, notDeviceOwner, clockBehind, windowExpired, inactive }`
  - `OfflineRefusal? offlineSignInRefusal({required OfflineCredential? stored, required String email, required bool passwordMatches, required String? dataOwnerId, required bool? localUserActive, required int windowDays, required DateTime now})` — checks in this order: noCredential; email (case-insensitive, trimmed) ≠ stored → wrongEmailOrPassword; failedAttempts ≥ 5 → tooManyAttempts (before the password, so the 6th try with the right password is refused); !passwordMatches → wrongEmailOrPassword; dataOwnerId ≠ stored.userId → notDeviceOwner; now < lastOnlineAt − 5 min → clockBehind; now − lastOnlineAt > windowDays days → windowExpired; localUserActive != true (missing row counts as inactive) → inactive.
  - `String offlineRefusalMessage(OfflineRefusal r, {int? windowDays})` — plain messages per decision 4; windowExpired names the days ("more than 14 days since your last online sign-in; sign in online").
  - `const offlineMaxFailedAttempts = 5`.

- [ ] **Step 1: Write the rule probe**: one case per enum value plus the pass case (null); boundary cases: exactly `windowDays` days elapsed → null, +1 minute → windowExpired; now = lastOnlineAt − 4 min → null, − 6 min → clockBehind; failedAttempts 4 + right password → null, 5 + right password → tooManyAttempts; `ReportSettings.fromMap({})`.offlineSigninDays == 14, `{'offline_signin_days': 30}` → 30.
- [ ] **Step 2: Run it**; expected compile failure.
- [ ] **Step 3: Implement** the model, interface, SQLite repo (`recordFailure` = `UPDATE ... SET failed_attempts = failed_attempts + 1 WHERE user_id = ?`), rule, message function, settings field, `LoginMethod.offline`, and `mode` in `LoginLogRepositorySqlite.log` (`attempt.method == LoginMethod.offline ? 'offline' : 'online'`).
- [ ] **Step 4: Run the probe**: all `ok`. `dart analyze`.

### Task 3: AuthViewModel offline session

**Files:**
- Modify: `lib/viewmodels/auth_viewmodel.dart`, `lib/console/main.dart:173`, `lib/main.dart:167`

**Interfaces:**
- Consumes: Task 1 functions, Task 2 repository/rule/settings.
- Produces on `AuthViewModel`:
  - constructor adds `required OfflineCredentialRepository credentials`, `required UserRepository localUsers`, `required ReportSettingRepository localReportSettings` (wired with the SQLite impls on `localDb`).
  - `bool get isOffline` (signed in without a client); `bool get isSignedIn => currentUser != null && (_client != null || isOffline)`.
  - `Future<String?> signInOffline({required String email, required String password})` — null = success.
  - `String? requireOnlineSession()` — `requireActiveSession()` first, then if `_client == null`: `'This needs an online sign-in. Use sign-in <cloud|lan> <email> <password>.'`
  - `Future<OfflineCredential?> offlineCredential()` and `Future<int> offlineWindowDays(int? schoolId)` (for the status command).

- [ ] **Step 1: Store on online success.** In `signIn`, after the session is kept and only when `!mustChangePassword`: `credentials.save(...)` with a new salt, `offlineHashIterations`, hash of the typed password, `lastOnlineAt = now UTC`, `failedAttempts 0`. Wrapped in try/catch: a failure logs and leaves the sign-in successful (set a `offlineWarning` string shown by `sign-in`: "offline sign-in not saved on this device: ..."). Also clears `isOffline`.
- [ ] **Step 2: Store on password change.** `changePassword` success → same save with the new password.
- [ ] **Step 3: `signInOffline`.** Load stored, data owner, local user (`localUsers.getById(stored.userId)`), window = `offlineWindowDays(user?.schoolId)` (school row → region row → 14 via `ReportSettings.fromMap` like `ReportSettingsViewModel.effective`, superadmin = region only); hash with the STORED salt + iterations; call the rule. Wrong password on the owner's email → `recordFailure`. Every attempt → `_recordAttempt(..., method: LoginMethod.offline, client: null)` (add a `method` parameter defaulting to online) with the refusal enum name as `failureReason`. Success: if a client is open, `_abandon` it; `_client = null`, `currentUser = local user`, `mustChangePassword = false`, `versionWarning = null`, offline flag on.
- [ ] **Step 4: `signOut`** clears the offline flag; online `signIn` success clears it too (and the old offline state needs no sign-out call).
- [ ] **Step 5: Wire** both mains; `dart analyze`.

### Task 4: guard audit + console

**Files:**
- Modify: the 13 ViewModels with `_auth.client!` (aral_checkin, aral_material, crla_threshold, import, phil_iri_content, report_settings, round_calendar, school, section, srp, student, tutor_section_assignment, user), `lib/core/console/commands/login_commands.dart`, `pull_commands.dart`, `version_commands.dart`, `auth_commands.dart`

**Interfaces:**
- Consumes: Task 3 `requireOnlineSession`, `signInOffline`, `isOffline`, `offlineCredential`, `offlineWindowDays`.

- [ ] **Step 1: Audit.** Every guard that precedes a `client!` becomes `requireOnlineSession()`; `login-recent`/`login-history`, `pull-cloud`, `version-check` (replace its `isSignedIn` check), `change-password` (needs the server) likewise. Done when `grep -rn "client!" lib` lists only lines whose function's guard is `requireOnlineSession()` (reviewer re-runs the grep), and ViewModels that read only the local copy keep `requireActiveSession()`.
- [ ] **Step 2: Console.** `sign-in-offline <email> <password>` → `Signed in offline as <email> (<role>). Server work needs an online sign-in.` or the refusal message. `offline-status` → `Offline sign-in: <email>, last online <UTC>, window <n> days (until <UTC date>), failed attempts <k>/5` or `Offline sign-in: not set up on this device.` (no session needed: it says nothing secret). `whoami` appends ` — offline` when `isOffline`.
- [ ] **Step 3: Headless run** (recipe [[console-test-harness]], scratch copy of the verify DB): see kit below; then `dart analyze`.

## Verify kit `D:/0_CAPSTONE/verify/sync-s3/`

1. `1_online_then_status.txt`: `sign-in cloud zztest.tutor@...`, `pull-cloud yes discard-local` (makes the tutor the device owner), `offline-status`, `exit`.
2. `2_offline_session.txt` (new process = app restart): `sign-in-offline` good → `whoami` (offline) → a local-copy read (`dashboard 2025-2026`, `reminders-tutor`) works → `pull-cloud`, `school-list`, `version-check`, `change-password x` each print the online-sign-in message → `sign-out`.
3. `3_wrong_x5.txt`: five wrong → five vague failures, sixth with the right password → too many attempts; then `sign-in cloud` (online, resets) → `offline-status` shows 0/5.
4. `4_expired.txt` after `probe_age.py` sets `last_online_at` 15 days back → windowExpired; `probe_clock.py` sets it 1 day ahead → clockBehind.
5. `5_not_owner.txt`: `sign-in cloud zztest.coord` (overwrites the credential; last puller is still the tutor) → `sign-out` → `sign-in-offline zztest.coord` → not the device owner.
Plus `probe_pbkdf2.dart`, `probe_rules.dart`, and the local `login_logs` rows with `mode='offline'` shown by `probe_logs.py`.

## Commit

```
feat(auth,sync): offline sign-in for the device owner (S3)
```
(body written after the build: iterations measured, decisions taken, follow-ups.)
