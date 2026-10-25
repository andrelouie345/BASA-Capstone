# Auth: sign-in, password, server settings, version

### Sign in (online)
Build: both    Roles: all
Purpose: sign in to the cloud or LAN server with email and password.
Calls:
- `AuthViewModel.signIn(target: 'cloud'|'lan', email:, password:)` → `String?` (null = signed in, else the message to show)
- afterwards `currentUser`, `mustChangePassword`, `versionWarning`, `offlineWarning`
Live previews: none.
Errors: wrong password, inactive account, version refusal, server not set (returned text).
Console: `sign-in`

### Sign in offline
Build: both    Roles: the device owner
Purpose: sign in without a connection, within the offline window.
Calls:
- `AuthViewModel.signInOffline(email:, password:)` → `String?`
- `AuthViewModel.offlineStatus()` → `OfflineStatus?` (to show "offline sign-in ready for x until y, n of m attempts left")
Live previews: none.
Errors: not the owner, window passed, too many attempts (returned text).
Console: `sign-in-offline`, `offline-status`

### Change password
Build: both    Roles: all (forced after an admin-made account's first sign-in)
Purpose: set a new password.
Calls:
- `AuthViewModel.changePassword(newPassword)` → `String?`
Live previews: none.
Errors: not signed in, too short, server refusal (returned text).
Console: `change-password`

### Sign out
Build: both    Roles: all
Calls:
- `AuthViewModel.signOut()`
Console: `sign-out`

### Server settings
Build: both    Roles: anyone (before sign-in, on setup)
Purpose: see and set the cloud/LAN server URL and anon key.
Calls:
- `ServerConfigViewModel.show()` → `ServerConfigView` (urls, masked keys)
- `ServerConfigViewModel.setCloud({String? url, String? anonKey})`, `setLan(...)`
Live previews: none.
Errors: none today (URLs are not validated: parked follow-up).
Console: `config-show`, `config-set-cloud-url`, `config-set-cloud-key`, `config-set-lan-url`, `config-set-lan-key`

### About / version
Build: both    Roles: all
Purpose: show which release the app is, and compare it with the server.
Calls:
- `AuthViewModel.appRelease()` → `List<String>` (migration ids)
- `AuthViewModel.checkVersion()` → `VersionCheck`
- `AuthViewModel.versionReport()` → `({String label, String message})`
Live previews: none.
Errors: needs an online sign-in; fetch failure text.
Console: `version-app`, `version-check`

## Not a screen
- `help`, `whoami` (the signed-in user block in `common.md` covers it).
