# Auth: sign-in, password, server settings, version

### Sign in (online)
Build: both    Roles: all
Purpose: sign in to the cloud or LAN server with email and password.
Calls:
- ✅ `AuthViewModel.signIn(target: 'cloud'|'lan', email:, password:)` → `String?` (null = signed in, else the message to show)
- ✅ afterwards `currentUser`, `mustChangePassword`, `versionWarning`, `offlineWarning`
Live previews: none.
Errors: wrong password, inactive account, version refusal, server not set (returned text).
Console: `sign-in`

### Sign in offline
Build: both    Roles: the device owner
Purpose: sign in without a connection, within the offline window.
Calls:
- ✅ `AuthViewModel.signInOffline(email:, password:)` → `String?`
- 🆕 `AuthViewModel.offlineStatus()` → `OfflineStatus?` — gap AUTH-G1 (to show "offline sign-in ready for x until y, n of m attempts left")
Live previews: none.
Errors: not the owner, window passed, too many attempts (returned text).
Console: `sign-in-offline`, `offline-status`

### Change password
Build: both    Roles: all (forced after an admin-made account's first sign-in)
Purpose: set a new password.
Calls:
- ✅ `AuthViewModel.changePassword(newPassword)` → `String?`
Live previews: none.
Errors: not signed in, too short, server refusal (returned text).
Console: `change-password`

### Sign out
Build: both    Roles: all
Calls:
- ✅ `AuthViewModel.signOut()`
Console: `sign-out`

### Server settings
Build: both    Roles: anyone (before sign-in, on setup)
Purpose: see and set the cloud/LAN server URL and anon key.
Calls:
- 🆕 `ServerConfigViewModel.show()` → `ServerConfigView` (urls, masked keys) — gap AUTH-G2
- 🆕 `ServerConfigViewModel.setCloud({String? url, String? anonKey})`, `setLan(...)` — gap AUTH-G2
Live previews: none.
Errors: none today (URLs are not validated: parked follow-up).
Console: `config-show`, `config-set-cloud-url`, `config-set-cloud-key`, `config-set-lan-url`, `config-set-lan-key`

### About / version
Build: both    Roles: all
Purpose: show which release the app is, and compare it with the server.
Calls:
- 🆕 `AuthViewModel.appRelease()` → `List<String>` (migration ids) — gap AUTH-G3
- ✅ `AuthViewModel.checkVersion()` → `VersionCheck` (type T: gap AUTH-G3)
- 🆕 verdict label + message for a `VersionCheck` — gap AUTH-G3
Live previews: none.
Errors: needs an online sign-in; fetch failure text.
Console: `version-app`, `version-check`

## Not a screen
- `help`, `whoami` (the signed-in user block in `common.md` covers it).

## Gaps

**AUTH-G1** (I, N) — `offline-status` computes the window end and reads `offlineMaxFailedAttempts` from `offline_signin_rules.dart`.
Fix: `AuthViewModel.offlineStatus()` → `OfflineStatus?` (new model `core/models/offline_status.dart`: `email`, `lastOnlineAt`, `windowDays`, `until`, `failedAttempts`, `maxFailedAttempts`); null when not set up. Command prints from it.
Removes baseline: `core/console/commands/auth_commands.dart -> core/services/offline_signin_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).

**AUTH-G2** (I, R) — `config-*` commands use `SupabaseConfigStore` (`core/data/remote/supabase_config.dart`) directly; there is no ViewModel, and key masking is command code.
Fix: new `ServerConfigViewModel` (`lib/viewmodels/server_config_viewmodel.dart`, both builds, wired in `wire_tutor.dart` (shared)) with `show()` → `ServerConfigView` (`cloudUrl`, `cloudKeyMasked`, `lanUrl`, `lanKeyMasked`; mask rule moves here unchanged), `setCloud({url, anonKey})`, `setLan({url, anonKey})`. `registerConfigCommands` takes the ViewModel.
Removes baseline: `core/console/commands/config_commands.dart -> core/data/remote/supabase_config.dart`
Decision: fix (owner 2026-10-24, as recommended).

**AUTH-G3** (I, T, N) — `version-app` reads `basaMigrations` (`core/release.dart`); `version-check` formats with `versionLabel`/`versionMessage`/`fetchFailedMessage` (`version_check.dart`); `VersionCheck` is a service type.
Fix: `AuthViewModel.appRelease()` → `List<String>` (`<id>_<name>`, oldest first); `AuthViewModel.versionReport()` → `({String label, String message})` (calls `checkVersion`, the same label/message functions, and `fetchFailedMessage` on a fetch failure); `export '../services/version_check.dart' show VersionCheck, VersionVerdict;` from `core/models/version.dart`.
Removes baseline: `core/console/commands/version_commands.dart -> core/release.dart`, `core/console/commands/version_commands.dart -> core/services/version_check.dart`
Decision: fix (owner 2026-10-24, as recommended).

**AUTH-G4** (R, T) — `AuthViewModel.client` (a `SupabaseClient`) is public "so user-create etc. can reuse the session", and `checkVersion([SupabaseClient? client])` takes one. A screen holding the client could query the server around every ViewModel.
Found: 16 ViewModels read `_auth.client` to build their cloud repositories, so it cannot become private without a wiring redesign. And a screen does not need to import `supabase` to call methods on it, so the import check alone does not stop it.
Fix: (a) keep it public, with a doc line "ViewModels only, never a screen"; (b) `tool/vm_boundary.dart` also refuses the text `.client` (as a member access, `\.client\b`) in `lib/ui/` files, with a fixture test; (c) `checkVersion` loses its `SupabaseClient` parameter if nothing passes one (checked in the batch; else it stays, wiring-only). After ADMIN-G1 no command file uses `.client` either.
Decision: fix (owner 2026-10-24, as recommended).

**AUTH-G5** (E) — `auth_viewmodel.dart:281` puts `$e` in `offlineWarning` ("Offline sign-in was not saved on this device: $e").
Fix: spec rule (sentence kept without the exception text, exception to the logger).
Decision: fix (owner 2026-10-24, as recommended).
