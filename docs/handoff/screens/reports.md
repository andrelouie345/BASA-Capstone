# Reports: NLA, progress monitoring, BOSY masterlist, SRP, report settings

All admin build (admins and coordinators), except the SRP class list (tutors see their own SRP classes).

### NLA portal report (Phil-IRI JHS Form 2b + Division ARAL)
Build: admin    Roles: admin / coordinator (superadmin: any school)
Purpose: the counts the NLA portal asks for, with sex / round / block / section filters, and its CSV.
Calls:
- `NlaReportViewModel.report(...)` → `NlaReport` (`NlaCounts` per `NlaBand` / `NlaGstBand` / `PhilIriLevel`; types from `core/models/report_types.dart`)
- `NlaReportFilter` (model), `nlaValue(counts, sex)` → `int`, `nlaReportCsv(report, filter)` → `String` (functions in `nla_report_viewmodel.dart`: allowed)
- `assessedPhilIriRounds(...)` → `Set<PhilIriRound>`; `reportSections(...)`
Console: `nla-report`, `nla-report-csv`

### Progress monitoring
Build: admin    Roles: admin / coordinator
Calls:
- `NlaReportViewModel.progress(...)` → `ProgressReport`; `progressReportCsv(report, sectionRows:, schoolTotal:)`; `progressPercent(share)`, `thresholdPercent(share)` (model) → `String`
Console: `progress-report`, `progress-report-csv`

### BOSY masterlist
Build: admin    Roles: admin / coordinator
Calls:
- `NlaReportViewModel.bosyMasterlist(...)` → `BosyMasterlist`; `bosyMasterlistCsv(list)`
Console: `bosy-masterlist`, `bosy-masterlist-csv`

### SRP (Summer Remediation Program)
Build: both (own classes) / admin (build, edit)    Roles: SRP tutor reads their classes; admin / coordinator manage
Purpose: ranked candidates, building classes (per section, class size), moving learners, class tutor/room/schedule.
Calls:
- `SrpViewModel.candidates(...)` → `SrpList` (`SrpRankKey`; types from `core/models/report_types.dart`); `srpListCsv(list, recommendedOnly:)`
- `classes(schoolId:, schoolYear:)` → `List<SrpClassView>`; `srpClassesCsv(classes)`
- admin: `buildClasses(...)`, `updateClass(...)`, `addLearner`, `moveLearner`, `removeLearner`, `deleteClass`, `clearClasses`, `classIdFor(ref)`; `lastMirrorWarning` → `String?`
- `SrpViewModel.defaultPerSection`, `.defaultClassSize` → `int`
Console: `srp-list`, `srp-list-csv`, `srp-classes`, `srp-classes-csv`, `srp-build`, `srp-class-set`, `srp-add`, `srp-move`, `srp-remove`, `srp-class-delete`, `srp-classes-clear`

### Report settings (done threshold, auto-approve, offline days)
Build: admin    Roles: admin / coordinator
Calls:
- `ReportSettingsViewModel.effective(schoolId)` → `ReportSettings`; `doneThresholdLayers`, `autoApproveLayers`, `offlineDaysLayers` → `(region, school, effective)`
- `setDoneThreshold`, `setAutoApprove`, `setOfflineDays`, `resetSchool`
Console: `report-settings-show`, `report-settings-set`, `report-settings-reset`, `sync-auto-approve`, `offline-days`, `offline-days-set`

### Reports & files (hub)
Build: admin    Roles: coordinator / admin / superadmin
Purpose: every import and export in one place (the reading coordinators asked for this). Imports are also reached from their own screens; the hub only gathers them.
Calls (existing ones, the same as in the screens named in brackets):
- imports: `ImportViewModel` SF1 `trial` / `import` (also in *SF1 import*, `admin.md`); `CrlaImportViewModel.preview` / `importScoresheet` (also in *Scoresheet import*, `crla.md`); `AralRosterImportViewModel.preview` / `importRoster` (also in *Implementation report and roster files*, `aral.md`)
- exports: `StudentViewModel.rosterCsv(sectionId)` (*Learners and roster CSV*); `CrlaExportViewModel.exportScoresheet(...)` (*Scoresheet export*); `AralReportViewModel.implementationReportXlsx(...)`, `implementationReportCsv(...)`, `AralViewModel.rosterCsv(...)` (*Implementation report and roster files*); `AralCheckinViewModel.checkinReportCsv(...)` (*Check-ins*, `aral.md`); `nlaReportCsv(...)`, `progressReportCsv(...)`, `bosyMasterlistCsv(...)`, `srpListCsv(...)`, `srpClassesCsv(...)` (this file)
Live previews: none.
Errors: as in each screen named above.
Console: the commands of those screens.
