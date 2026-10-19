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
//
// D5 (owner 2026-10-20):
//  * CRLA profiles: Grade 1-3 learners per reading profile per CRLA round. One
//    learner counts once per round, by the ARAL implementation report's rule
//    (aralCrlaLearnerProfile: latest attempt per variant, the weakest); a
//    variant filter counts only that variant. Assessed without a profile (no
//    story match) = "No profile". Profile names come from the data; the known
//    ones only set the order. One chart; the region one sums the schools.
//  * ARAL exits: the Division ARAL report's count from NlaReportViewModel
//    (Phil-IRI Grade 4-10): ARAL = 3-LD + 2-LD, exited = at grade level in
//    MOSY1-3/EOSY (BOSY has no exit). Not the roster's exits, no CRLA.
//  * ARAL activity: sessions per month and attendance per month, through
//    AralSessionViewModel's own access checks (a tutor sees only their own).
//    Attendance = AralAttendanceSummary.rate (present / (present + absent);
//    excused don't count), as the tutor summary. Months = every YYYY-MM from
//    the first to the last session; a month without counted marks has no
//    attendance point. Scope tutor (one series), school (one per tutor +
//    "School total"), region (one per school + "Region total"); not section.
//  * Every trend but ARAL activity refuses the tutor scope.
import '../core/console/logger.dart';
import '../core/models/aral_session.dart';
import '../core/models/crla_assessment.dart' show CrlaRound;
import '../core/models/crla_result.dart';
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/school.dart';
import '../core/models/section.dart';
import '../core/models/trend_chart.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_session_repository.dart';
import '../core/repositories/crla_result_repository.dart';
import '../core/repositories/school_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/aral_rules.dart' show aralCrlaLearnerProfile, aralCrlaProfileOrder;
import '../core/services/calendar_rules.dart' show calendarDate;
import '../core/services/nla_form2b.dart';
import '../core/services/normalizers.dart';
import 'aral_session_viewmodel.dart';
import 'auth_viewmodel.dart';
import 'nla_report_viewmodel.dart';
import 'viewmodel_exception.dart';

/// The CRLA profile series of learners assessed in a round without a profile.
const trendNoCrlaProfile = 'No profile';

/// CRLA variants a profile chart can be limited to.
const trendCrlaVariants = {'mt', 'fil', 'eng'};

class TrendViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final SchoolRepository _schools;
  final SectionRepository _sections;
  final StudentRepository _students;
  final UserRepository _users;
  final CrlaResultRepository _crlaResults;
  final NlaReportViewModel _nla;
  final AralSessionViewModel _aral;
  final AralSessionRepository _aralSessions;

  TrendViewModel({
    required AuthViewModel auth,
    required SchoolRepository schools,
    required SectionRepository sections,
    required StudentRepository students,
    required UserRepository users,
    required CrlaResultRepository crlaResults,
    required NlaReportViewModel nla,
    required AralSessionViewModel aral,
    required AralSessionRepository aralSessions,
    Logger? logger,
  })  : _auth = auth,
        _schools = schools,
        _sections = sections,
        _students = students,
        _users = users,
        _crlaResults = crlaResults,
        _nla = nla,
        _aral = aral,
        _aralSessions = aralSessions,
        _log = ScopedLogger(logger, 'TrendViewModel');

  /// Learners per Form 2b band ([NlaSex] picks M, F or both) per Phil-IRI
  /// round, as of [asOf] (default today). One series per band, in Form 2b
  /// order; counts, not percents.
  Future<TrendChart> bandDistribution(TrendScope scope, String schoolYear,
      {NlaSex sex = NlaSex.total, DateTime? asOf}) async {
    _log('bandDistribution(${_scopeLog(scope)}, $schoolYear, sex: ${sex.name}, asOf: $asOf)');
    final year = _year(schoolYear);
    final target = await _resolve(scope, year);
    final total = await _nlaTotal(target, year, asOf);
    final rounds = PhilIriRound.values.where(total.conducted.contains).toList();
    return TrendChart(
      'Form 2b bands — ${target.name} — $year',
      [for (final r in rounds) r.label],
      [
        for (final b in NlaBand.values) TrendSeries(b.label, [for (final r in rounds) nlaValue(total.band(r, b), sex)]),
      ],
    );
  }

  /// The Division ARAL report's numbers per Phil-IRI round someone in the
  /// scope took, as of [asOf]: learners in ARAL (3-LD + 2-LD) and exited (at
  /// grade level; null at BOSY). [NlaSex] picks M, F or both.
  Future<TrendChart> aralExits(TrendScope scope, String schoolYear, {NlaSex sex = NlaSex.total, DateTime? asOf}) async {
    _log('aralExits(${_scopeLog(scope)}, $schoolYear, sex: ${sex.name}, asOf: $asOf)');
    final year = _year(schoolYear);
    final target = await _resolve(scope, year);
    final total = await _nlaTotal(target, year, asOf);
    final rounds = PhilIriRound.values.where(total.conducted.contains).toList();
    return TrendChart(
      'ARAL exits (Division report) — ${target.name} — $year',
      [for (final r in rounds) r.label],
      [
        TrendSeries('ARAL (3-LD + 2-LD)',
            [for (final r in rounds) nlaValue(NlaCounts.sum([total.ld3(r), total.ld2(r)]), sex)]),
        TrendSeries('Exited (grade level)',
            [for (final r in rounds) r == PhilIriRound.bosy ? null : nlaValue(total.band(r, NlaBand.glr), sex)]),
      ],
    );
  }

  /// The NLA report's total over the scope's schools (summed for the region).
  Future<NlaSectionReport> _nlaTotal(
      ({String name, List<School> schools, Set<int>? sectionIds}) target, String year, DateTime? asOf) async {
    final total = NlaSectionReport(null, null);
    for (final school in target.schools) {
      final report = await _nla.report(schoolId: school.id!, schoolYear: year, sectionIds: target.sectionIds, asOf: asOf);
      if (report.sections.isEmpty) continue;
      total.addAll(report.total);
    }
    return total;
  }

  /// Grade 1-3 learners per CRLA reading profile per CRLA round, as of [asOf]
  /// (default today). [variant] (`mt`, `fil`, `eng`) counts only that
  /// variant. See the file comment.
  Future<TrendChart> crlaProfiles(TrendScope scope, String schoolYear, {String? variant, DateTime? asOf}) async {
    _log('crlaProfiles(${_scopeLog(scope)}, $schoolYear, variant: $variant, asOf: $asOf)');
    final year = _year(schoolYear);
    if (variant != null && !trendCrlaVariants.contains(variant)) {
      throw ViewModelException('A CRLA variant is mt, fil or eng (got "$variant").');
    }
    final target = await _resolve(scope, year);
    final day = calendarDate(asOf ?? DateTime.now());
    final counts = {for (final r in CrlaRound.values) r: <String, int>{}};
    final ids = {for (final s in target.schools) s.id!};
    final sections = (await _sections.getAll()).where((s) {
      final g = int.tryParse(s.gradeLevel);
      return ids.contains(s.schoolId) &&
          s.schoolYear == year &&
          g != null &&
          g >= 1 &&
          g <= 3 &&
          (target.sectionIds == null || target.sectionIds!.contains(s.id));
    });
    for (final s in sections) {
      final learners = {for (final st in await _students.getBySection(s.id!)) st.id!};
      if (learners.isEmpty) continue;
      final byLearner = <int, List<CrlaResult>>{};
      for (final r in await _crlaResults.getBySection(s.id!, schoolYear: year)) {
        if (learners.contains(r.studentId)) (byLearner[r.studentId] ??= []).add(r);
      }
      for (final round in CrlaRound.values) {
        for (final mine in byLearner.values) {
          final took = mine.any((r) =>
              r.round == round &&
              (variant == null || r.subjectVariant == variant) &&
              r.assessedAt.substring(0, 10).compareTo(day) <= 0);
          if (!took) continue;
          final p = aralCrlaLearnerProfile(mine, round, day, variant: variant) ?? trendNoCrlaProfile;
          counts[round]![p] = (counts[round]![p] ?? 0) + 1;
        }
      }
    }
    final rounds = CrlaRound.values.where((r) => counts[r]!.isNotEmpty).toList();
    int rank(String p) => p == trendNoCrlaProfile
        ? 1 << 20
        : (aralCrlaProfileOrder.contains(p) ? aralCrlaProfileOrder.indexOf(p) : aralCrlaProfileOrder.length);
    final names = {for (final r in rounds) ...counts[r]!.keys}.toList()
      ..sort((a, b) {
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : a.compareTo(b);
      });
    return TrendChart(
      'CRLA reading profiles — ${target.name} — $year${variant == null ? '' : ' ($variant)'}',
      [for (final r in rounds) r.label],
      [
        for (final p in names) TrendSeries(p, [for (final r in rounds) counts[r]![p] ?? 0]),
      ],
    );
  }

  /// ARAL sessions held per month and attendance (percent 0-100) per month,
  /// as of [asOf] (default today). See the file comment.
  Future<({TrendChart sessions, TrendChart attendance})> aralActivity(TrendScope scope, String schoolYear,
      {DateTime? asOf}) async {
    _log('aralActivity(${_scopeLog(scope)}, $schoolYear, asOf: $asOf)');
    final year = _year(schoolYear);
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException('Not signed in.');
    final day = calendarDate(asOf ?? DateTime.now());
    // A held_on that is not YYYY-MM-DD (only possible from data loaded around
    // the app) is left out: the month walk below needs real months.
    final isDate = RegExp(r'^\d{4}-(0[1-9]|1[0-2])-\d{2}$');
    List<AralSession> upTo(List<AralSession> all) =>
        all.where((s) => isDate.hasMatch(s.heldOn) && s.heldOn.compareTo(day) <= 0).toList();

    // (series name, its sessions); the total series, when there is one, last.
    final groups = <(String, List<AralSession>)>[];
    String? totalName;
    String name;
    Future<List<(String, List<AralSession>)>> perTutor(List<AralSession> sessions) async {
      final byTutor = <String, List<AralSession>>{};
      for (final s in sessions) {
        (byTutor[s.tutorId] ??= []).add(s);
      }
      final out = [
        for (final e in byTutor.entries) ((await _users.getById(e.key))?.fullName ?? e.key, e.value),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      return out;
    }

    switch (scope) {
      case SectionScope():
        throw const ViewModelException('ARAL activity is per tutor or school, not per section.');
      case TutorScope(:final tutorId):
        final id = tutorId ?? me.id;
        final list = upTo(await _aral.tutorSessions(tutorId: id, schoolYear: year));
        name = (await _users.getById(id))?.fullName ?? (id == me.id ? me.fullName : id);
        groups.add((name, list));
      case SchoolScope(:final schoolId):
        final list = upTo(await _aral.schoolSessions(schoolId: schoolId, schoolYear: year));
        final school = await _schools.getById(schoolId) ?? (throw ViewModelException('No school $schoolId on this device.'));
        name = school.schoolName;
        groups.addAll(await perTutor(list));
        totalName = 'School total';
      case RegionScope():
        if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
          throw const ViewModelException('Forbidden: only an admin or coordinator sees trend charts.');
        }
        if (me.schoolId != null) throw const ViewModelException('Forbidden: only the superadmin sees the region.');
        name = 'Region';
        final schools = (await _schools.getAll())..sort((a, b) => a.schoolName.compareTo(b.schoolName));
        for (final school in schools) {
          final list = upTo(await _aral.schoolSessions(schoolId: school.id!, schoolYear: year));
          if (list.isNotEmpty) groups.add((school.schoolName, list));
        }
        totalName = 'Region total';
    }

    final all = [for (final g in groups) ...g.$2];
    final months = <String>[];
    if (all.isNotEmpty) {
      final keys = all.map((s) => s.heldOn.substring(0, 7)).toList()..sort();
      var y = int.parse(keys.first.substring(0, 4)), m = int.parse(keys.first.substring(5, 7));
      while (true) {
        final k = '$y-${m.toString().padLeft(2, '0')}';
        months.add(k);
        if (k == keys.last) break;
        if (++m > 12) {
          m = 1;
          y++;
        }
      }
    }
    final marks = <int, List<AralAttendance>>{};
    for (final s in all) {
      marks[s.id!] ??= await _aralSessions.getAttendance(s.id!);
    }
    List<AralSession> inMonth(List<AralSession> list, String month) =>
        list.where((s) => s.heldOn.startsWith(month)).toList();
    List<num?> held(List<AralSession> list) => [for (final mo in months) inMonth(list, mo).length];
    List<num?> rate(List<AralSession> list) => [
          for (final mo in months)
            (() {
              final r = AralAttendanceSummary.of([for (final s in inMonth(list, mo)) ...marks[s.id!]!]).rate;
              return r == null ? null : r * 100;
            })(),
        ];
    final lines = [...groups, if (totalName != null) (totalName, all)];
    return (
      sessions: TrendChart('ARAL sessions per month — $name — $year', months, [
        for (final (n, list) in lines) TrendSeries(n, held(list)),
      ]),
      attendance: TrendChart('ARAL attendance per month — $name — $year', months, [
        for (final (n, list) in lines) TrendSeries(n, rate(list)),
      ]),
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
      case TutorScope():
        throw const ViewModelException('Forbidden: tutor scope is only for ARAL activity.');
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
        TutorScope(:final tutorId) => 'tutor:${tutorId ?? 'me'}',
        RegionScope() => 'region',
      };
}
