# Phil-IRI value switches and the ranking list

Admin build only (admins and coordinators of a school; the superadmin for the region default and any school). Design: `docs/superpowers/specs/2026-11-14-phil-iri-value-sources-design.md`.

Each Phil-IRI list shows ONE kind of value, chosen per school (ma, 2026-11-14), never both side by side:
- **carried**: the best so far (a learner keeps their best result into later rounds), today's numbers;
- **actual**: each round's own reading only; a learner without a reading of their own in that round is "Not assessed this round" (the stand-in: Struggling, 3 levels down).

Every list carries its `values` (`PhilIriValues`); show `philIriValuesLabel(values)` ("Values: carried (best so far)" / "Values: actual (each round's own reading)") above the table. Form 2b under actual: `nlaValuesLabel(values)` (adds "; not assessed this round counted as 3-LD Frustration"). The CSVs already end with a `Values` column.

### Phil-IRI value switches (in Report settings)
Build: admin    Roles: admin / coordinator (own school); superadmin (region or any school)
Purpose: per list, carried or actual. Put it in the existing Report settings screen (`admin.md`), one row per list with a two-way choice.
Calls (`AppViewModels.reportSettings`, `ReportSettingsViewModel`):
- `valueSourceLayers(schoolId)` → `Map<PhilIriValueList, ({PhilIriValues? region, PhilIriValues? school, PhilIriValues effective})>` (device copy; `schoolId` null = the region row)
- `setValueSource(schoolId, list, values)` (online)
The six lists (`PhilIriValueList`, in this order; the label is yours):
- `aral`: ARAL proposals, automatic updates/exits, implementation report (default carried)
- `bosyMasterlist`: BOSY masterlist (default carried)
- `form2b`: NLA portal report (Form 2b) and the band trend chart (default carried; under actual a learner not read in a round, or with 0% / no comprehension entry, counts in 3-LD Frustration)
- `srp`: SRP candidates (default carried)
- `learnerPages`: a learner's Phil-IRI results and learner history (default carried)
- `ranking`: the ranking list below (default actual)
Show per list: the school value (or "region: …" when the school has none) and what applies. A change reaches other devices after their next download.
Errors: `Forbidden: only an admin or coordinator sets the report settings.`, `Forbidden: you can only set your own school's report settings.`, `Forbidden: only the superadmin sets the region-wide report settings.`, the online-sign-in message.
Console: `value-sources`, `value-source-set`

### Ranking list
Build: admin    Roles: admin / coordinator / superadmin
Purpose: the learners with the lowest values in one round, for one measure.
Inputs: round (`PhilIriRound`), measure (`PhilIriRankMeasure.accuracy` / `wpm` / `comprehension`, labels in `.label`), how many (`n`, default 10, at least 1), scope: one section, one grade (4-10) or the whole school (Grades 4-10 together; show each learner's grade), as of (default today).
Calls (`AdminScope.of(context).philIriRanking`, `PhilIriRankingViewModel`):
- `rank(schoolId:, schoolYear:, round:, measure:, n:, sectionId:, grade:, asOf:)` → `PhilIriRanking`
- `philIriRankingCsv(ranking)` → CSV text (save as)
Shows (from `PhilIriRanking`):
- header: round, measure, scope, n, `philIriValuesLabel(values)`, as of;
- block 1 `ranked` (`PhilIriRankRow`): rank, name, LRN, grade, section, value (`philIriRankValueText(measure, value)`, add "%" or "wpm"), profile. Equal values share a rank, so the list can be longer than n: when `tiedPastN`, say "N shown: k tied at rank r";
- block 2 `unranked` (`PhilIriUnranked`), by name, with `reason.label`: "not assessed this round", "silent reading: no accuracy", "comprehension only, no word reading", "no comprehension entry". These never take a place in block 1.
Errors: `Learners to list is at least 1 (got 0).`, `Give a section or a grade, not both.`, `School <id> has no Grade <g> section for <year>.`, `Forbidden: only an admin or coordinator can generate the Phil-IRI ranking.`, a section of another school (as the other reports).
Console: `phil-iri-rank`, `phil-iri-rank-export`

### Lists that now show the label
No new calls; each result object has `values`:
- NLA portal report: `NlaReport.values` (`nlaValuesLabel`);
- BOSY masterlist: `BosyMasterlist.values`; under actual a GST-only BOSY is listed as not assessed;
- SRP: `SrpList.values`;
- ARAL implementation report: `AralImplementationReport.values`; ARAL proposals: `AralViewModel.lastProposalValues` after `propose()` (null for Grades 1-3);
- learner pages: `PhilIriLearnerResults.values`, rounds from `view(round)`, end from `endView()` (see `phil-iri.md`).
