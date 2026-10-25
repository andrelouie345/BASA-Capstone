# Auth: sign-in, password, server settings, colours, version

### Sign in (online)
Build: both    Roles: all
Purpose: sign in to the cloud or LAN server with email and password.
Layout (required): the sign-in screen has a **dropdown** (a collapsible "Server settings" section) with the fields to set the cloud URL and anon key and the LAN URL and anon key (the anon key is the server's public key). A new device is set up from here, before anyone can sign in. It uses the *Server settings* calls below; the separate Server settings screen can reuse the same widget.
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

### Colours (light and dark mode)
Build: both    Roles: anyone (works before sign-in)
Purpose: choose light, dark or follow the device, and change the app's colours for each mode, with defaults preset. Saved on this device (not per user, never synced), like the server settings.
Calls:
- `ThemeSettingsViewModel.current()` → `ThemeSettings` (`mode`: `ThemeModeChoice.system|light|dark`; `light` / `dark`: colour name → ARGB int, **only the colours the user changed**)
- `ThemeSettingsViewModel.setMode(ThemeModeChoice)`, `setColor(ThemeBrightness.light|dark, name, argb)`, `clearColor(brightness, name)` (back to the default), `reset()` (everything back to the defaults) → each returns the new `ThemeSettings`
Live previews: build the preview in the UI (apply the unsaved colours to a sample card) before calling `setColor`.
Errors: a name that isn't letters/digits/underscores starting with a letter, or a value outside 0x00000000-0xFFFFFFFF (`ViewModelException`).
Notes for the UI team:
- **You** choose the colour names (e.g. `primary`, `secondary`, `surface`, `error`) and their **default values**, in one Dart file under `lib/ui/` (e.g. `lib/ui/theme/basa_colors.dart`). A name missing from `light` / `dark` means "use your default", so the defaults stay in your code and can change without touching saved files.
- ARGB is what Flutter's `Color(int)` takes and `Color.toARGB32()` gives.
- Read `current()` once at start-up in `lib/app_shell.dart`, build `theme` and `darkTheme` from defaults + saved colours, set `themeMode` from `mode`, and rebuild the `MaterialApp` after a change (ViewModels don't notify: keep the settings in the app shell's state).
Console: `theme-show`, `theme-mode`, `theme-set`, `theme-clear`, `theme-reset`

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
