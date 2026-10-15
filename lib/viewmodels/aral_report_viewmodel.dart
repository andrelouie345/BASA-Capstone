// lib/viewmodels/aral_report_viewmodel.dart
//
// ARAL-Reading per-section implementation report (piece A5). Read-only,
// generated on demand from the local copy (roster, Phil-IRI, CRLA).
//
// Template: "ARAL Reading Implementation Report.xlsx", sheet GRADES 7-10
// ENGLISH: per section, enrolment; ARAL learners at BOSY and at MOSY split into
// "Frustration (3 Level Down)" and "Instructional (2 Level Down)" with totals;
// learners exited (the template computes BOSY - MOSY). Owner decisions
// (2026-10-16):
//  * The split follows the Phil-IRI levels-down report groups (3+ levels down
//    and non-readers -> 3-LD; 1-2 down -> 2-LD), with the school's thresholds.
//  * Every Grade 1-10 section gets a row; Grades 1-3 use CRLA profiles as the
//    columns (Low/High Emerging, Developing, Transitioning).
//  * Exits are the roster's own (grade-level ready vs other reasons);
//    BOSY - MOSY is shown beside them.
//  * BOSY counts every ARAL learner of the section entered by the report date,
//    by their BOSY result; MOSY counts those still in ARAL on that date, by
//    their latest MOSY round. Only results assessed by the report date count;
//    unfinished Phil-IRI sessions don't.
import '../core/console/logger.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/crla_assessment.dart' show CrlaRound;
import '../core/models/crla_result.dart';
import '../core/models/phil_iri_assessment.dart' show PhilIriRound, PhilIriStatus;
import '../core/models/section.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/crla_result_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/aral_rules.dart';
import '../core/services/normalizers.dart';
import '../core/services/phil_iri_results.dart';
import '../core/services/phil_iri_rules.dart';
import 'auth_viewmodel.dart';
import 'phil_iri_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Column for an ARAL learner without a result in that round.
const aralReportNoResult = 'no result';

/// One section's row.
class AralSectionReportRow {
  final Section section;
  final int grade;
  final bool usesCrla;            // Grades 1-3
  final int enrolment;            // actively enrolled learners of the section
  final List<String> columns;     // result columns, in order (no-result last when used)
  final Map<String, int> bosy;
  final Map<String, int> mosy;
  final int exitedGradeLevelReady;
  final int exitedOther;          // transferred out, dropped out, other

  const AralSectionReportRow({
    required this.section,
    required this.grade,
    required this.usesCrla,
    required this.enrolment,
    required this.columns,
    required this.bosy,
    required this.mosy,
    required this.exitedGradeLevelReady,
    required this.exitedOther,
  });

  int get bosyTotal => bosy.values.fold(0, (a, b) => a + b);
  int get mosyTotal => mosy.values.fold(0, (a, b) => a + b);
  int get exited => exitedGradeLevelReady + exitedOther;

  /// The template's "exited" formula.
  int get bosyMinusMosy => bosyTotal - mosyTotal;
}

class AralImplementationReport {
  final int schoolId;
  final String schoolYear;
  final String asOf; // YYYY-MM-DD
  final List<AralSectionReportRow> rows; // by grade, then section name

  const AralImplementationReport(this.schoolId, this.schoolYear, this.asOf, this.rows);
}

class AralReportViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralEnrollmentRepository _roster;
  final SectionRepository _sections;
  final StudentRepository _students;
  final CrlaResultRepository _crlaResults;
  final PhilIriViewModel _philIri;

  AralReportViewModel({
    required AuthViewModel auth,
    required AralEnrollmentRepository roster,
    required SectionRepository sections,
    required StudentRepository students,
    required CrlaResultRepository crlaResults,
    required PhilIriViewModel philIri,
    Logger? logger,
  })  : _auth = auth,
        _roster = roster,
        _sections = sections,
        _students = students,
        _crlaResults = crlaResults,
        _philIri = philIri,
        _log = ScopedLogger(logger, 'AralReportViewModel');

  /// The implementation report of every Grade 1-10 section of the school
  /// ([sectionId] narrows it to one section) as of [asOf] (default today).
  Future<AralImplementationReport> implementationReport({
    required int schoolId,
    required String schoolYear,
    int? sectionId,
    DateTime? asOf,
  }) async {
    _log('implementationReport(school: $schoolId, year: $schoolYear, section: $sectionId)');
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException('Not signed in.');
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: only an admin or coordinator can generate ARAL reports.');
    }
    if (me.schoolId != null && me.schoolId != schoolId) {
      throw const ViewModelException('Forbidden: that school is not yours.');
    }
    schoolYear = normalizeSchoolYear(schoolYear);
    final date = _date(asOf ?? DateTime.now());

    final sections = (await _sections.getAll()).where((s) {
      final g = int.tryParse(s.gradeLevel);
      return s.schoolId == schoolId && s.schoolYear == schoolYear && g != null && g >= 1 && g <= 10 &&
          (sectionId == null || s.id == sectionId);
    }).toList()
      ..sort((a, b) {
        final g = int.parse(a.gradeLevel).compareTo(int.parse(b.gradeLevel));
        return g != 0 ? g : a.sectionName.compareTo(b.sectionName);
      });
    if (sectionId != null && sections.isEmpty) {
      throw ViewModelException('Section $sectionId is not a Grade 1-10 section of school $schoolId for $schoolYear.');
    }
    final thresholds = await _philIri.effectiveThresholds(schoolId);
    final rows = <AralSectionReportRow>[];
    for (final s in sections) {
      rows.add(await _row(s, schoolYear, date, thresholds));
    }
    return AralImplementationReport(schoolId, schoolYear, date, rows);
  }

  Future<AralSectionReportRow> _row(Section s, String year, String asOf, PhilIriThresholds t) async {
    final grade = int.parse(s.gradeLevel);
    final usesCrla = grade <= 3;
    final enrolment = (await _students.getBySection(s.id!)).length;
    final roster = (await _roster.getBySection(s.id!, schoolYear: year))
        .where((e) => e.enteredOn.compareTo(asOf) <= 0)
        .toList();
    bool inAralOn(AralEnrollment e) => e.exitedOn == null || e.exitedOn!.compareTo(asOf) > 0;
    final exited = roster.where((e) => !inAralOn(e)).toList();

    final bosy = <String, int>{};
    final mosy = <String, int>{};
    void add(Map<String, int> m, String k) => m[k] = (m[k] ?? 0) + 1;

    if (usesCrla) {
      final results = await _crlaResults.getBySection(s.id!, schoolYear: year);
      for (final e in roster) {
        final mine = results.where((r) => r.studentId == e.studentId).toList();
        add(bosy, _crlaProfile(mine, CrlaRound.bosy, asOf) ?? aralReportNoResult);
        if (inAralOn(e)) add(mosy, _crlaProfile(mine, CrlaRound.mosy, asOf) ?? aralReportNoResult);
      }
    } else {
      for (final e in roster) {
        final res = await _philIri.learnerResults(studentId: e.studentId, sectionId: e.sectionId, schoolYear: year);
        String? group(Iterable<PhilIriRound> rounds) {
          PhilIriRoundResult? last;
          for (final r in res.rounds.where((r) => rounds.contains(r.round))) {
            final session = res.sessions[r.round];
            if (r.given && r.profile != null && session != null && session.status != PhilIriStatus.inProgress &&
                session.assessedAt.substring(0, 10).compareTo(asOf) <= 0) {
              last = r;
            }
          }
          if (last == null) return null;
          // Non-readers go with the furthest group (the open last one).
          return last.profile == PhilIriLevel.nonReader
              ? philIriReportGroup(99, t)
              : philIriReportGroup(last.levelsDown, t);
        }
        add(bosy, group(const [PhilIriRound.bosy]) ?? aralReportNoResult);
        if (inAralOn(e)) {
          add(mosy, group(const [PhilIriRound.mosy1, PhilIriRound.mosy2, PhilIriRound.mosy3]) ?? aralReportNoResult);
        }
      }
    }

    final columns = usesCrla ? _crlaColumns(bosy, mosy) : _philIriColumns(bosy, mosy, t, grade);
    return AralSectionReportRow(
      section: s,
      grade: grade,
      usesCrla: usesCrla,
      enrolment: enrolment,
      columns: columns,
      bosy: bosy,
      mosy: mosy,
      exitedGradeLevelReady: exited.where((e) => e.exitReason == AralExitReason.gradeLevelReady).length,
      exitedOther: exited.where((e) => e.exitReason != AralExitReason.gradeLevelReady).length,
    );
  }

  /// The learner's profile in [round] (assessed by [asOf]): latest attempt per
  /// variant, the weakest.
  static String? _crlaProfile(List<CrlaResult> results, CrlaRound round, String asOf) {
    final latest = <String, CrlaResult>{};
    for (final r in results.where((r) =>
        r.round == round && r.readingProfile != null && r.assessedAt.substring(0, 10).compareTo(asOf) <= 0)) {
      final prev = latest[r.subjectVariant];
      if (prev == null || r.attemptNo > prev.attemptNo) latest[r.subjectVariant] = r;
    }
    String? weakest;
    for (final r in latest.values) {
      weakest = weakest == null ? r.readingProfile : aralWeakerCrlaProfile(r.readingProfile, weakest);
    }
    return weakest;
  }

  /// CRLA columns: the four below-grade-level profiles, then anything else seen.
  static List<String> _crlaColumns(Map<String, int> a, Map<String, int> b) {
    final base = aralCrlaProfileOrder.where(aralCrlaQualifies).toList();
    return _withExtras(base, a, b);
  }

  /// Phil-IRI columns: the furthest group first (3-LD = Frustration in the
  /// template), then nearer ones; then anything else seen (e.g. GLR).
  static List<String> _philIriColumns(Map<String, int> a, Map<String, int> b, PhilIriThresholds t, int grade) {
    final groups = <String>[];
    // A Grade g learner reads at most g - 1 levels down (Grade 1 is the floor).
    for (var down = grade > 1 ? grade - 1 : 1; down >= 1; down--) {
      final g = philIriReportGroup(down, t);
      if (!groups.contains(g)) groups.add(g);
    }
    return _withExtras(groups, a, b);
  }

  static List<String> _withExtras(List<String> base, Map<String, int> a, Map<String, int> b) {
    final extras = {...a.keys, ...b.keys}.where((k) => !base.contains(k) && k != aralReportNoResult).toList()..sort();
    final hasNone = a.containsKey(aralReportNoResult) || b.containsKey(aralReportNoResult);
    return [...base, ...extras, if (hasNone) aralReportNoResult];
  }

  static String _date(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
