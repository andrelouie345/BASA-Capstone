# Reports: NLA, progress monitoring, BOSY masterlist, SRP, report settings

All admin build (admins and coordinators), except the SRP class list (tutors see their own SRP classes).

### NLA portal report (Phil-IRI JHS Form 2b + Division ARAL)
Build: admin    Roles: admin / coordinator (superadmin: any school)
Purpose: the counts the NLA portal asks for, with sex / round / block / section filters, and its CSV.
Calls:
- ✅ `NlaReportViewModel.report(...)` → `NlaReport` (`NlaCounts` per `NlaBand` / `NlaGstBand` / `PhilIriLevel`: class T, REPORTS-G1)
- ✅ `NlaReportFilter` (model), `nlaValue(counts, sex)` → `int`, `nlaReportCsv(report, filter)` → `String` (functions in `nla_report_viewmodel.dart`: allowed)
- ✅ `assessedPhilIriRounds(...)` → `Set<PhilIriRound>`; `reportSections(...)`
Console: `nla-report`, `nla-report-csv`

### Progress monitoring
Build: admin    Roles: admin / coordinator
Calls:
- ✅ `progress(...)` → `ProgressReport`; `progressReportCsv(report, sectionRows:, schoolTotal:)`; `progressPercent(share)`, `thresholdPercent(share)` (model) → `String`
Console: `progress-report`, `progress-report-csv`

### BOSY masterlist
Build: admin    Roles: admin / coordinator
Calls:
- ✅ `bosyMasterlist(...)` → `BosyMasterlist`; `bosyMasterlistCsv(list)`
Console: `bosy-masterlist`, `bosy-masterlist-csv`

### SRP (Summer Remediation Program)
Build: both (own classes) / admin (build, edit)    Roles: SRP tutor reads their classes; admin / coordinator manage
Purpose: ranked candidates, building classes (per section, class size), moving learners, class tutor/room/schedule.
Calls:
- ✅ `SrpViewModel.candidates(...)` → `SrpList` (`SrpRankKey`: class T, REPORTS-G1); `srpListCsv(list, recommendedOnly:)`
- ✅ `classes(schoolId:, schoolYear:)` → `List<SrpClassView>`; `srpClassesCsv(classes)`
- ✅ admin: `buildClasses(...)`, `updateClass(...)`, `addLearner`, `moveLearner`, `removeLearner`, `deleteClass`, `clearClasses`, `classIdFor(ref)`; `lastMirrorWarning` (class E: REPORTS-G3)
- ✅ `SrpViewModel.defaultPerSection`, `.defaultClassSize` → `int` — REPORTS-G2
Console: `srp-list`, `srp-list-csv`, `srp-classes`, `srp-classes-csv`, `srp-build`, `srp-class-set`, `srp-add`, `srp-move`, `srp-remove`, `srp-class-delete`, `srp-classes-clear`

### Report settings (done threshold, auto-approve, offline days)
Build: admin    Roles: admin / coordinator
Calls:
- ✅ `ReportSettingsViewModel.effective(schoolId)` → `ReportSettings`; `doneThresholdLayers`, `autoApproveLayers`, `offlineDaysLayers` → `(region, school, effective)`
- ✅ `setDoneThreshold`, `setAutoApprove`, `setOfflineDays`, `resetSchool`
Console: `report-settings-show`, `report-settings-set`, `report-settings-reset`, `sync-auto-approve`, `offline-days`, `offline-days-set`

## Gaps

**REPORTS-G1** (I, T) — `NlaBand`, `NlaCounts`, `NlaGstBand` (`nla_form2b.dart`), `PhilIriLevel` (`phil_iri_rules.dart`) and `SrpRankKey` (`srp_rules.dart`) are service types in report results; `nla_report_commands.dart` imports both rule files for them.
Fix: `core/models/report_types.dart` exports `NlaBand, NlaCounts, NlaGstBand` and `SrpRankKey`; `PhilIriLevel` comes from `phil_iri_types.dart` (PHILIRI-G2).
Removes baseline: `core/console/commands/nla_report_commands.dart -> core/services/nla_form2b.dart`, `core/console/commands/nla_report_commands.dart -> core/services/phil_iri_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

**REPORTS-G2** (I, N) — `srp-build` / `srp-list` read `srpDefaultPerSection` and `srpDefaultClassSize` from `srp_rules.dart`.
Fix: `SrpViewModel.defaultPerSection` and `.defaultClassSize` getters (same constants).
Removes baseline: `core/console/commands/srp_admin_commands.dart -> core/services/srp_rules.dart`
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).

**REPORTS-G3** (E) — `srp_viewmodel.dart:538` puts `$e` in `lastMirrorWarning`.
Fix: spec rule.
Decision: fix (owner 2026-10-24, as recommended).
Status: ✅ fixed (VM completeness Task 8).
