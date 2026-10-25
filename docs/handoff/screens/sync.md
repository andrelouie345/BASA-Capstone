# Sync: pull, upload, status, conflicts, approver review

### Get the latest from the server (pull)
Build: both    Roles: all (online sign-in)
Purpose: show what a pull will do (whose copy, unsent work kept or blocking), then pull; optionally discard this device's unsent work.
Calls:
- `SyncViewModel.pullPreview()` → `PullPreview` (`currentEmail`, `owner`, `ownerSwitch`, `localWork`, `localTotal`)
- `pull(discardLocal:)` → `PullResult` (`merge` counts, `ownerChanged`, `previousOwnerEmail`, `unknownCalendarRounds`)
Errors: unsent work of another owner, kept rows under parents gone (ViewModelException).
Console: `pull-cloud`

### Send my work (upload)
Build: both    Roles: the device owner
Purpose: see what is unsent, resolve conflicts, send it as one upload, follow its status, withdraw it.
Calls:
- `preview()` → `SyncPreview`; `resolve(table, key, SyncChoice.mine|server)` → `SyncResolution`
- `upload()` → `SyncUploadResult`, or `sync(confirm: (preview) async => ...)` → `SyncRunResult` (preview, confirm, upload in one call; the screen supplies the confirm dialog)
- `refreshStatus()` → `List<SyncOutcome>`; `uploads()` → `List<SyncUploadRow>`; `lockedCounts()` → `Map<int, int>`; `withdraw(uploadId)`
- `SyncViewModel.release` → `String` (this app's release)
Errors: not the device owner, conflicts unresolved, nothing to send (ViewModelException).
Console: `sync-preview`, `sync-resolve`, `sync-upload`, `sync-status`, `sync-withdraw`

### Review uploads (approver)
Build: admin    Roles: admin / coordinator
Calls:
- `SyncReviewViewModel.pending(schoolId:)` → `SyncPendingList`; `latestPendingId(...)`; `details(id)` → `SyncUploadDetails`
- `approve(id)` → `SyncApproveResult`; `reject(id, reason)` → `String`
- auto-approve setting: `ReportSettingsViewModel.autoApproveLayers` / `setAutoApprove` (see `reports.md`)
Console: `sync-pending`, `sync-show`, `sync-approve`, `sync-reject`, `sync-auto-approve`

## Not a screen
- `db-use`, `db-add`, `db-list`, `db-delete`: dev-only `testTable` commands (DB-switching redesign is parked).
- `set-text`, `get-text`, `append-text`, `clear-text`, `log-filter`, `list-viewmodels`, `help`: dev / console only.
