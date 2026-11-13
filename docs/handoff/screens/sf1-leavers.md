# SF1 leavers (learners no longer on a section's SF1)

Admin build only (admins and coordinators; the superadmin too). Every action is online: it calls one server function and then copies the result onto the device. Design: `docs/superpowers/specs/2026-11-12-sf1-leavers-design.md`.

Get the ViewModel with `AdminScope.of(context).learnerLeavers` (`LearnerLeaversViewModel`). Every call refuses a tutor with `LearnerLeaversViewModel.forbiddenMessage` and needs an online sign-in (the usual `requireOnlineSession` message). The superadmin has no school of their own: pass `schoolId` to `missing`, `anonymizePreview` and `anonymize` (otherwise `Give the school: the superadmin has no school of their own.`); a school-bound user may leave it out (another school: `Forbidden: you can only manage your own school's learners.`).

Archive, move, and restore into another section are refused with `leaverUploadFirstMessage(n)` ("This device has n record(s) of this learner that are not on the server yet: upload this device's work first (sync-upload), then try again.") while this device holds that learner's records not on the server yet (new, edited or waiting in an upload): offer the upload screen (`sync.md`). Other learners' unsent work doesn't block.

Server refusals come back as `The database refused it: <reason>.` (e.g. `moves are same grade only: …`, `enrollment N is not an active enrollment …`, a pending upload holding the learner's records); a lost connection as `leaverUnreachableMessage`. Show them as they are.

Where it lives: inside the **SF1 import** flow (`admin.md`, *SF1 import*): after the trial, the new row kinds and the *Not on this SF1* block; plus a school-wide **Undecided learners** list (e.g. under learner management) and **Anonymize archived learners** (an admin tool, rarely used).

### SF1 import trial: moving, returning, not on this SF1
Build: admin    Roles: admin / coordinator
Purpose: the existing trial (`ImportViewModel.trial(filePath)` → `Sf1TrialResult`) now also shows:
- rows with `outcome == 'moving'`: the learner is active in another section of the school, same grade (`fromSectionId`, `fromSectionName`, `enrollmentId`) → a **Move here** button (`move(enrollmentId, thisSectionId)`; the ViewModel records where the move was decided);
- rows with `outcome == 'returning'`: archived this year at this school (`leftOn`, `leftReason` = `transferred_out` / `dropped_out`, `enrollmentId`, `fromSectionId` / `fromSectionName` = the section they were archived in) → a **Restore** button (`restore(enrollmentId, toSectionId: thisSectionId)`; archived in this same section: leave `toSectionId` out);
- `wouldMove`, `wouldReturn` counts;
- `missing` (`List<Sf1MissingLearner>`: `enrollmentId`, `studentId`, `lrn`, `name`): active in this section, not in the file → per learner **Transferred out** / **Dropped out** (archive) or **Moved to section …** (a same-grade section picker → `move(enrollmentId, sectionId)`), or leave undecided (they stay active).
The import (`import(filePath)` → `Sf1ImportResult`) never applies moving or returning rows: `waiting` counts them. Show `lastImportWarning` when set (the import worked but the section's LRN list could not be saved on the server: import the file again).
Console: `import-trial`, `import-students`

### Undecided learners (school-wide)
Build: admin    Roles: admin / coordinator / superadmin
Purpose: learners still active but not on their section's last imported SF1, every section of the school or one.
Calls: `missing({sectionId, schoolId})` → `List<Sf1MissingLearner>` (with `sectionId`, `sectionName`), then the same three actions as above.
Console: `sf1-missing`

### Archive (transferred out / dropped out)
Build: admin    Roles: admin / coordinator
Calls: `archive(enrollmentId, EnrollmentStatus.transferredOut | droppedOut, {note})` → `LearnerLeaverOutcome` (`enrollment`, `mirrored`, `message`). Nothing is deleted; the learner leaves every active list and can't be newly assessed; their active ARAL entry that year is exited (the message says so).
Console: `sf1-archive`

### Move to another section
Build: admin    Roles: admin / coordinator
Calls: `move(enrollmentId, toSectionId, {schoolId})` → `LearnerLeaverOutcome` (`move` = the `EnrollmentMove` row). Same school, year and grade only; this school year's CRLA, Phil-IRI and GST records go along (the message gives the counts). The ViewModel records the source itself: `sf1_missing` when the learner is on their section's missing list, else `sf1_incoming` (don't pass `source`).
Console: `sf1-move`

### Restore
Build: admin    Roles: admin / coordinator
Calls: `restore(enrollmentId, {toSectionId})` → `LearnerLeaverOutcome`. ARAL is not restored (the message says so).
Console: `sf1-restore`

### Anonymize archived learners
Build: admin    Roles: admin / coordinator / superadmin
Purpose: learners whose latest school year's enrollment is archived, more than `archive_keep_months` ago, and only once that school year has ended; earlier years (active or archived) don't block. Never automatic. Show a clear warning: it can't be undone (name, LRN, birth date and contact details cleared; sex and records kept; the learner can't be matched again).
Calls:
- `anonymizePreview({schoolId})` → `(learners: List<AnonymizeCandidate>, code: String)` (`studentId`, `lrn`/`name` from the device copy or null, `leftOn`, `schoolYear`)
- `anonymize(code, {schoolId})` → `int` (how many); `lastMessage`. Refused with `leaverAnonymizeStaleMessage` when the list changed since the preview (preview again).
Console: `learner-anonymize-preview`, `learner-anonymize`

### Archive period (report setting)
Build: admin    Roles: admin / coordinator (school), superadmin (region)
Calls: `ReportSettingsViewModel.archiveKeepMonthsLayers(schoolId)` → `(region, school, effective)`; `setArchiveKeepMonths(schoolId, months)` (whole months 1-120, default 6). Goes with the other report settings (`reports.md`).
Console: `archive-keep-months`

### Learner history and sync (no new screen)
- `LearnerHistoryViewModel`: `LearnerHistoryEnrollment.leftOn` / `leftNote`, `LearnerHistoryYear.moves` (`LearnerHistoryMove`: date, from/to section, source). Show them in the history screen (`admin.md`, *Learner history*). Console: `learner-history`, `learner-history-lrn`.
- Sync: `SyncOutcome.note` / `SyncApproveResult.note` (e.g. "1 record followed a section move") are part of their `toString()`; show them with the upload result (`sync.md`).
