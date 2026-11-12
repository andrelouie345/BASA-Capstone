# Phil-IRI import (ma's workbook and the BASA scoresheet file)

Admin build only (admins and coordinators; the superadmin too). It works on the device copy, offline included. Nothing is uploaded by the import: the coordinator uploads afterwards with the normal sync screen (a coordinator's upload is applied at once). Design: `docs/superpowers/specs/2026-11-09-phil-iri-import-design.md`.

Get the ViewModel with `AdminScope.of(context).philIriImport` (`PhilIriImportViewModel`). Every call refuses a tutor with `PhilIriImportViewModel.forbiddenMessage` and a signed-out device with the usual `Not signed in. Sign in first.`

Where it lives: an import screen under **Reports & files** (see *Reports & files (hub)* in `reports.md`), plus a **Download template** action per section.

### Import: pick a file
Build: admin    Roles: admin / coordinator / superadmin
Purpose: the coordinator picks a file and says what it is: ma's Phil-IRI/ARAL workbook (one sheet per section) or a BASA scoresheet file (one section, picked first).
Calls:
- `previewWorkbook(bytes, {choices})` → `PhilIriImportPreview`
- `previewScoresheet(sectionId, bytes, fileName)` → `PhilIriImportPreview`
Live previews: none (each preview reads the whole file; show a spinner).
Errors: `This is not a readable .xlsx workbook: …`; a section that isn't the user's school's (scoresheet).
Console: `phil-iri-import-workbook-preview`, `phil-iri-import-scoresheet-preview`

### Headers step (only when needed)
Build: admin    Roles: admin / coordinator
Purpose: when a preview has `headerIssues` (not empty), nothing was read: a column header in the file differs from the label BASA looks for. Show each issue (`field`, the `block` where it's missing, the headers `found` there) and let the coordinator pick the file's header for that field, then preview again.
Calls:
- `headerSamples(bytes, field, label)` → `List<String>`: the first values under a header, so the coordinator can check a pick (names are refused: `Names are not shown here.`)
- `setHeader(field, label)` → `String?` (the error, or null when saved on this device)
- `headerLabels()` → `Map<String, String>` (field → label); `resetHeaders()`
Live previews: none.
Console: `phil-iri-import-headers`, `phil-iri-import-headers-set`, `phil-iri-import-headers-reset`, `phil-iri-import-header-samples`

### Preview
Build: admin    Roles: admin / coordinator
Purpose: what would be imported, before anything is written.
Shows (from `PhilIriImportPreview`):
- `sections`: one `PhilIriImportSectionPreview` per section sheet: `ref.sheet`, `section` (BASA's, or null), `status` (`importable`, `empty`, `not in BASA`, `already imported`), `notes` (why, or "sheets X and Y both name section Z: tick one"), `uploadBytes`, `count(outcome)`.
- per section `rows` (`PhilIriImportRow`): `outcome` (`import`, `importFlagged`, `skipped`), `notes` (the flags or the skip reason), the learner (`student` when matched; `candidates` when the learner **needs a pick**), `round`, `passage` (null = "Untitled"), `gst`, `basaProfile`/`basaAdjustedLevel` (what BASA will compute).
- `proposedDates` (workbook): the date each round would get; null = the coordinator must type one.
- size: `uploadBytes` of the ticked sections + `unsentBytes` against `maxUploadBytes` (one upload).
- `plan.problems`: cells that couldn't be read (shown with their sheet/row/column).
Choices the screen collects into `PhilIriImportChoices`:
- `sheets`: ticked section sheets (workbook only; only `importable` ones);
- `picks`: `row.learnerRef` ("sheet 03, row 17") → the student id the coordinator picked from `candidates`;
- `dates`: round → `YYYY-MM-DD` (workbook).
After a change of picks or dates, call `previewWorkbook(bytes, choices: …)` again: the preview and its `fingerprint` change with them.
Console: same as above (masked names).

### Import (the button)
Build: admin    Roles: admin / coordinator
Purpose: write the ticked sections (workbook) or the file (scoresheet).
**Before the button**, show `preview.oneTimeWarning` for a workbook ("This makes BASA the record for this section's school year. You can't import this section's workbook again."). The scoresheet can be imported again (what BASA has is skipped, never overwritten).
Calls:
- `importWorkbook(bytes, choices, fingerprint: preview.fingerprint)` → `PhilIriImportResult`
- `importScoresheet(sectionId, bytes, fileName, fingerprint: preview.fingerprint)` → `PhilIriImportResult`
Result: `sessionIds`, `gstIds` (new, not uploaded yet), `failed` (learner row → reason; the others were written), `nothingToImport` (ticked sheets with only skipped rows). Then point the coordinator to the upload (sync screen).
Errors: `PhilIriImportViewModel.staleMessage` (the data changed since the preview: preview again), `Tick at least one section.`, `Sheet X can't be imported: <status>.`, `Give a date for <round>.`, `<round>: … is not a date (YYYY-MM-DD).`, `<round>: … is outside school year …` / `<round>: … is in the future.` (a calendar date like that is not proposed: the round shows as needing a date), upload-size refusals (`Upload first.` or a section too big for one upload), header issues.
Console: `phil-iri-import-workbook`, `phil-iri-import-scoresheet`

### Download template (per section)
Build: admin    Roles: admin / coordinator
Purpose: the section's scoresheet file (.xlsx) for teachers to fill from the paper (learners pre-filled; round, method and passage lists).
Calls: `scoresheetTemplate(sectionId)` → `List<int>` (save as `<section>.xlsx`)
Console: `phil-iri-import-template`

Finalizing imported sessions uses the existing finalize screen (`phil-iri.md`).
