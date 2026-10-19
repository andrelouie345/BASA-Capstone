// lib/viewmodels/trend_viewmodel.dart
//
// Dashboard trend charts (D4: Phil-IRI). Owns no rules: the Form 2b bands come
// from NlaReportViewModel.report and the share assessed per round from
// NlaReportViewModel.progress, so a chart always equals those reports for the
// same day. Read-only, from this device's copy.
//
// Scope (owner 2026-10-19): a section or a school (admin/coordinator of that
// school, or the superadmin), or the region = every school on this device
// (superadmin only; loops the per-school reports, no caching).
//  * bands: one chart; the region one sums the schools. The x-axis holds the
//    rounds someone in the scope took (an untaken round is no point at all).
//  * completion: % assessed per round, the done threshold as reference line;
//    rounds no school in the chart holds are left out, and a school's value is
//    null for a round it does not hold. The region chart has one series per
//    school plus "Region total" (over the schools holding that round), and a
//    reference line only when every school has the same threshold.
import '../core/console/logger.dart';
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/school.dart';
import '../core/models/section.dart';
import '../core/models/trend_chart.dart';
import '../core/models/user_role.dart';
import '../core/repositories/school_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/services/nla_form2b.dart';
import '../core/services/normalizers.dart';
import 'auth_viewmodel.dart';
import 'nla_report_viewmodel.dart';
import 'viewmodel_exception.dart';

class TrendViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final SchoolRepository _schools;
  final SectionRepository _sections;
  final NlaReportViewModel _nla;

  TrendViewModel({
    required AuthViewModel auth,
    required SchoolRepository schools,
    required SectionRepository sections,
    required NlaReportViewModel nla,
    Logger? logger,
  })  : _auth = auth,
        _schools = schools,
        _sections = sections,
        _nla = nla,
        _log = ScopedLogger(logger, 'TrendViewModel');

  /// Learners per Form 2b band ([NlaSex] picks M, F or both) per Phil-IRI
  /// round, as of [asOf] (default today). One series per band, in Form 2b
  /// order; counts, not percents.
  Future<TrendChart> bandDistribution(TrendScope scope, String schoolYear,
      {NlaSex sex = NlaSex.total, DateTime? asOf}) async {
    _log('bandDistribution(${_scopeLog(scope)}, $schoolYear, sex: ${sex.name}, asOf: $asOf)');
    final year = _year(schoolYear);
    final target = await _resolve(scope, year);
    final total = NlaSectionReport(null, null);
    for (final school in target.schools) {
      final report = await _nla.report(schoolId: school.id!, schoolYear: year, sectionIds: target.sectionIds, asOf: asOf);
      if (report.sections.isEmpty) continue;
      total.addAll(report.total);
    }
    final rounds = PhilIriRound.values.where(total.conducted.contains).toList();
    return TrendChart(
      'Form 2b bands — ${target.name} — $year',
      [for (final r in rounds) r.label],
      [
        for (final b in NlaBand.values) TrendSeries(b.label, [for (final r in rounds) nlaValue(total.band(r, b), sex)]),
      ],
    );
  }

  /// Percent (0-100) of enrolled Grade 4-10 learners assessed per Phil-IRI
  /// round, as of [asOf] (default today), with the saved done threshold (in
  /// percent) as reference line. See the file comment for the region chart.
  Future<TrendChart> completion(TrendScope scope, String schoolYear, {DateTime? asOf}) async {
    _log('completion(${_scopeLog(scope)}, $schoolYear, asOf: $asOf)');
    final year = _year(schoolYear);
    final target = await _resolve(scope, year);
    final reports = <(School, ProgressReport)>[];
    for (final school in target.schools) {
      final p = await _nla.progress(schoolId: school.id!, schoolYear: year, sectionIds: target.sectionIds, asOf: asOf);
      if (p.sections.isEmpty) continue;
      reports.add((school, p));
    }
    final rounds = PhilIriRound.values.where((r) => reports.any((e) => e.$2.isScheduled(r))).toList();
    // progress's own share (assessed / enrolled), so the chart prints the
    // same decimal as the progress report.
    double? percent(ProgressSectionReport row, PhilIriRound r) {
      final share = row.share(r);
      return share == null ? null : share * 100;
    }

    List<double?> line(ProgressReport p, ProgressSectionReport row) => [
          for (final r in rounds) p.isScheduled(r) ? percent(row, r) : null,
        ];

    final series = <TrendSeries>[];
    if (scope is RegionScope && reports.isNotEmpty) {
      for (final (school, p) in reports) {
        series.add(TrendSeries(school.schoolName, line(p, p.total)));
      }
      // Per round, the totals of the schools holding it.
      ProgressSectionReport holding(PhilIriRound r) {
        final sum = ProgressSectionReport(null, null);
        for (final (_, p) in reports) {
          if (p.isScheduled(r)) sum.addAll(p.total);
        }
        return sum;
      }

      series.add(TrendSeries('Region total', [for (final r in rounds) percent(holding(r), r)]));
    } else if (reports.isNotEmpty) {
      final p = reports.single.$2;
      series.add(TrendSeries(scope is SectionScope ? target.name : 'School total', line(p, p.total)));
    }
    final thresholds = {for (final e in reports) e.$2.doneThreshold};
    return TrendChart(
      'Phil-IRI completion — ${target.name} — $year',
      [for (final r in rounds) r.label],
      series,
      referenceLine: thresholds.length == 1 ? thresholds.single * 100 : null,
    );
  }

  /// The schools a scope covers (and the one section, for a section scope),
  /// after the access check. The per-school reports check the school again.
  Future<({String name, List<School> schools, Set<int>? sectionIds})> _resolve(TrendScope scope, String year) async {
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException('Not signed in.');
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: only an admin or coordinator sees trend charts.');
    }
    switch (scope) {
      case RegionScope():
        if (me.schoolId != null) {
          throw const ViewModelException('Forbidden: only the superadmin sees the region.');
        }
        final schools = (await _schools.getAll())..sort((a, b) => a.schoolName.compareTo(b.schoolName));
        return (name: 'Region', schools: schools, sectionIds: null);
      case SchoolScope(:final schoolId):
        if (me.schoolId != null && me.schoolId != schoolId) {
          throw const ViewModelException('Forbidden: that school is not yours.');
        }
        final school = await _schools.getById(schoolId) ?? (throw ViewModelException('No school $schoolId on this device.'));
        return (name: school.schoolName, schools: [school], sectionIds: null);
      case SectionScope(:final sectionId):
        final Section section =
            await _sections.getById(sectionId) ?? (throw ViewModelException('No section $sectionId on this device.'));
        if (me.schoolId != null && me.schoolId != section.schoolId) {
          throw const ViewModelException('Forbidden: that section is not in your school.');
        }
        if (section.schoolYear != year) {
          throw ViewModelException('Section $sectionId is in ${section.schoolYear}, not $year.');
        }
        final school = await _schools.getById(section.schoolId) ??
            (throw ViewModelException('No school ${section.schoolId} on this device.'));
        return (
          name: 'Grade ${section.gradeLevel} ${section.sectionName}',
          schools: [school],
          sectionIds: {sectionId},
        );
    }
  }

  static String _year(String raw) {
    try {
      return normalizeSchoolYear(raw);
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
  }

  static String _scopeLog(TrendScope s) => switch (s) {
        SectionScope(:final sectionId) => 'section:$sectionId',
        SchoolScope(:final schoolId) => 'school:$schoolId',
        RegionScope() => 'region',
      };
}
