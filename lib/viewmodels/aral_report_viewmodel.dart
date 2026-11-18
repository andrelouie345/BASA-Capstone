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
//  * Reading coordinator (2026-10-16): Phil-IRI results are the CARRIED ones
//    (never lower than an earlier round); without a MOSY round the BOSY result
//    carries forward. A Grade 4-10 learner with nothing at all by the report
//    date (no reading; no GST or a GST of 0) counts as 3-LD Frustration,
//    flagged "3-LD (not assessed)". A GST alone (above 0) carries into BOSY
//    and counts like a BOSY result (2026-10-18).
import '../core/console/logger.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/crla_assessment.dart' show CrlaRound;
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/report_setting.dart' show PhilIriValueList, PhilIriValues, philIriValuesLabel;
import '../core/models/section.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/crla_result_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/aral_report_xlsx.dart';
import '../core/services/aral_rules.dart';
import '../core/services/auth_messages.dart';
import '../core/services/csv.dart';
import '../core/services/xlsx_cells.dart' show XlsxException;
import '../core/services/normalizers.dart';
import '../core/services/phil_iri_results.dart';
import '../core/services/phil_iri_rules.dart';
import 'auth_viewmodel.dart';
import 'phil_iri_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Column for an ARAL learner without a result in that round.
const aralReportNoResult = 'no result';

/// Column for a Grade 4-10 ARAL learner not assessed at all by the report
/// date: counted as Frustration, exactly 3 levels down, and flagged (reading
/// coordinator 2026-10-16). The template puts them under Frustration.
const aralReportNotAssessed = '3-LD (not assessed)';

/// The template export's note on the [count] "$aralReportNotAssessed" cells.
/// Under actual the count also holds learners without a reading of their own
/// in those rounds, not only learners not assessed at all (final review m1).
String aralNotAssessedNote(int count, PhilIriValues values, String asOf) {
  final who = values == PhilIriValues.actual
      ? 'learners without a reading of their own in those rounds by $asOf'
      : 'learners not assessed at all by $asOf';
  return '$count BOSY/MOSY count(s) are $who: counted under Frustration (3 levels down) as the reading '
      'coordinator asked; the CSV shows them as "$aralReportNotAssessed".';
}

/// One ARAL learner's BoSY and MoSY result as the implementation report
/// counts it (ARAL memo Plan B; the ARAL forms read these).
class AralLearnerRounds {
  static const crla = 'CRLA';
  static const philIri = 'Phil-IRI';

  final AralEnrollment enrollment;
  final int grade;              // the section's grade
  final String instrument;      // [crla] (Grades 1-3) or [philIri]
  /// Still in ARAL on the as-of date; false = left by then (MoSY fields null).
  final bool inAral;
  /// Phil-IRI: nothing at all by the as-of date (counted as 3-LD, flagged).
  final bool notAssessed;
  /// The report's column: a CRLA profile; for Phil-IRI the levels-down group
  /// (philIriReportGroup, e.g. '3-LD', '2-LD', 'GLR'); or [aralReportNoResult]
  /// / [aralReportNotAssessed].
  final String bosyResult;
  /// As [bosyResult]; Phil-IRI carries BoSY forward when there is no MoSY
  /// round (see [mosyOwn]). Null when the learner left ARAL by the date.
  final String? mosyResult;
  /// Orderable: CRLA profile order (0 Low Emerging ... 4 At Grade Level);
  /// Phil-IRI adjusted level (0 Non-Reader). Null = no result / not assessed.
  final int? bosyRank;
  final int? mosyRank;
  /// The learner has a MoSY result of their own (not BoSY carried forward).
  final bool mosyOwn;

  const AralLearnerRounds({
    required this.enrollment,
    required this.grade,
    required this.instrument,
    required this.inAral,
    required this.notAssessed,
    required this.bosyResult,
    required this.mosyResult,
    required this.bosyRank,
    required this.mosyRank,
    required this.mosyOwn,
  });

  int get enrollmentId => enrollment.id!;
}

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
  final int exitedOther;          // transferred out, dropped out, other, classroom support
  /// The learners these counts add up (AralReportViewModel.learnerRounds).
  final List<AralLearnerRounds> learners;

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
    this.learners = const [],
  });

  int get bosyTotal => bosy.values.fold(0, (a, b) => a + b);
  int get mosyTotal => mosy.values.fold(0, (a, b) => a + b);
  int get exited => exitedGradeLevelReady + exitedOther;

  /// The template's "exited" formula.
  int get bosyMinusMosy => bosyTotal - mosyTotal;
}

/// Rows added up: one grade's sections, or the whole school. The school
/// total has no columns (Phil-IRI and CRLA columns differ), only totals.
class AralReportTotals {
  final int enrolment;
  final List<String> columns; // merged in first-seen order
  final Map<String, int> bosy;
  final Map<String, int> mosy;
  final int bosyTotal;
  final int mosyTotal;
  final int exitedGradeLevelReady;
  final int exitedOther;

  const AralReportTotals({
    required this.enrolment,
    required this.columns,
    required this.bosy,
    required this.mosy,
    required this.bosyTotal,
    required this.mosyTotal,
    required this.exitedGradeLevelReady,
    required this.exitedOther,
  });

  /// [rows] summed per column ([withColumns]) or as totals only.
  factory AralReportTotals.of(List<AralSectionReportRow> rows, {required bool withColumns}) {
    final cols = <String>[];
    final bosy = <String, int>{};
    final mosy = <String, int>{};
    if (withColumns) {
      for (final r in rows) {
        for (final c in r.columns) {
          if (!cols.contains(c)) cols.add(c);
        }
        r.bosy.forEach((k, v) => bosy[k] = (bosy[k] ?? 0) + v);
        r.mosy.forEach((k, v) => mosy[k] = (mosy[k] ?? 0) + v);
      }
    }
    int sum(int Function(AralSectionReportRow) f) => rows.fold(0, (a, r) => a + f(r));
    return AralReportTotals(
      enrolment: sum((r) => r.enrolment),
      columns: cols,
      bosy: bosy,
      mosy: mosy,
      bosyTotal: sum((r) => r.bosyTotal),
      mosyTotal: sum((r) => r.mosyTotal),
      exitedGradeLevelReady: sum((r) => r.exitedGradeLevelReady),
      exitedOther: sum((r) => r.exitedOther),
    );
  }

  int get exited => exitedGradeLevelReady + exitedOther;

  /// The template's "exited" formula.
  int get bosyMinusMosy => bosyTotal - mosyTotal;
}

class AralImplementationReport {
  final int schoolId;
  final String schoolYear;
  final String asOf; // YYYY-MM-DD
  final List<AralSectionReportRow> rows; // by grade, then section name
  /// Which Phil-IRI values the Grade 4-10 rows count (values_aral; spec
  /// 2026-11-14 D6): under actual the latest round read, else not assessed.
  final PhilIriValues values;

  const AralImplementationReport(this.schoolId, this.schoolYear, this.asOf, this.rows,
      {this.values = PhilIriValues.actual});

  /// Every grade's sections added up, by grade (lowest first).
  Map<int, AralReportTotals> get gradeTotals {
    final grades = rows.map((r) => r.grade).toSet().toList()..sort();
    return {
      for (final g in grades) g: AralReportTotals.of(rows.where((r) => r.grade == g).toList(), withColumns: true),
    };
  }

  /// Every row added up (totals only).
  AralReportTotals get schoolTotal => AralReportTotals.of(rows, withColumns: false);
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
    if (me == null) throw const ViewModelException(notSignedInMessage);
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Not allowed: only an admin or coordinator can generate ARAL reports.');
    }
    if (me.schoolId != null && me.schoolId != schoolId) {
      throw const ViewModelException('Not allowed: that school is not yours.');
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
    final values = await _philIri.valueSource(schoolId, PhilIriValueList.aral);
    final rows = <AralSectionReportRow>[];
    for (final s in sections) {
      rows.add(await _row(s, schoolYear, date, thresholds, values));
    }
    return AralImplementationReport(schoolId, schoolYear, date, rows, values: values);
  }

  /// The report in the layout of the ARAL Reading Implementation Report
  /// template (IE4): Grades 4-10 (Phil-IRI) only, as the template's two
  /// columns are Phil-IRI levels down. Returns the workbook and notes about
  /// what didn't fit (Grades 1-3, learners without a result, ...).
  Future<(List<int>, List<String>)> implementationReportXlsx({
    required List<int> template,
    required int schoolId,
    required String schoolYear,
    int? sectionId,
    DateTime? asOf,
  }) async {
    final report =
        await implementationReport(schoolId: schoolId, schoolYear: schoolYear, sectionId: sectionId, asOf: asOf);
    final notes = <String>[];
    final crla = report.rows.where((r) => r.usesCrla).toList();
    if (crla.isNotEmpty) {
      notes.add('${crla.length} Grade 1-3 section(s) use CRLA profiles, which the template has no columns for; '
          'they are in the CSV export.');
    }
    var unplaced = 0, notAssessed = 0;
    (int, int) split(Map<String, int> counts) {
      var frustration = 0, instructional = 0;
      for (final e in counts.entries) {
        final down = int.tryParse(RegExp(r'^(\d+)-LD$').firstMatch(e.key)?.group(1) ?? '');
        if (e.key == aralReportNotAssessed) {
          frustration += e.value;
          notAssessed += e.value;
        } else if (e.key == 'Non-Reader' || (down != null && down >= 3)) {
          frustration += e.value;
        } else if (down != null) {
          instructional += e.value;
        } else {
          unplaced += e.value; // no result, GLR
        }
      }
      return (frustration, instructional);
    }

    final rows = <AralReportXlsxRow>[];
    for (final r in report.rows.where((r) => !r.usesCrla)) {
      final (bf, bi) = split(r.bosy);
      final (mf, mi) = split(r.mosy);
      rows.add(AralReportXlsxRow(
        grade: r.grade,
        section: r.section.sectionName,
        enrolment: r.enrolment,
        bosyFrustration: bf,
        bosyInstructional: bi,
        mosyFrustration: mf,
        mosyInstructional: mi,
        bosyTotal: r.bosyTotal,
        mosyTotal: r.mosyTotal,
        exitedGradeLevelReady: r.exitedGradeLevelReady,
        exitedOther: r.exitedOther,
      ));
    }
    if (report.values == PhilIriValues.actual) {
      notes.add('${philIriValuesLabel(report.values)}: each count is the latest round the learner read by '
          '${report.asOf}; a learner without a reading of their own counts as not assessed.');
    }
    if (notAssessed > 0) notes.add(aralNotAssessedNote(notAssessed, report.values, report.asOf));
    if (unplaced > 0) {
      notes.add('$unplaced BOSY/MOSY count(s) had no Phil-IRI result yet (or were at grade level): they are in the '
          'TOTAL ARAL LEARNERS columns but not in Frustration/Instructional; see the CSV for them.');
    }
    if (rows.isEmpty) throw const ViewModelException('No Grade 4-10 sections with ARAL learners to put in the template.');
    try {
      return (fillAralImplementationReport(template, asOf: report.asOf, rows: rows), notes);
    } on XlsxException catch (e) {
      throw ViewModelException(e.message);
    }
  }

  /// The whole report (Grades 1-10) as CSV: one line per section, a column
  /// per result group seen anywhere (BOSY and MOSY), exits.
  Future<String> implementationReportCsv({
    required int schoolId,
    required String schoolYear,
    int? sectionId,
    DateTime? asOf,
  }) async {
    final report =
        await implementationReport(schoolId: schoolId, schoolYear: schoolYear, sectionId: sectionId, asOf: asOf);
    final groups = <String>[];
    for (final r in report.rows) {
      for (final c in r.columns) {
        if (!groups.contains(c)) groups.add(c);
      }
    }
    return csvTable([
      [
        'Grade', 'Section', 'Uses', 'Enrolment',
        ...groups.map((g) => 'BOSY $g'), 'BOSY total',
        ...groups.map((g) => 'MOSY $g'), 'MOSY total',
        'Exited BOSY-MOSY', 'Exited grade-level ready', 'Exited other', 'As of', 'Values',
      ],
      for (final r in report.rows)
        [
          r.grade, r.section.sectionName, r.usesCrla ? 'CRLA' : 'Phil-IRI', r.enrolment,
          ...groups.map((g) => r.bosy[g] ?? 0), r.bosyTotal,
          ...groups.map((g) => r.mosy[g] ?? 0), r.mosyTotal,
          r.bosyMinusMosy, r.exitedGradeLevelReady, r.exitedOther, report.asOf, report.values.name,
        ],
    ]);
  }

  /// Every ARAL learner of the school's Grade 1-10 sections entered by [asOf]
  /// (YYYY-MM-DD, default today) with their BoSY and MoSY result: the
  /// per-learner part of [implementationReport] (which adds these up), shared
  /// with the ARAL forms. By grade, section name, then roster order.
  Future<List<AralLearnerRounds>> learnerRounds({
    required int schoolId,
    required String schoolYear,
    String? asOf,
  }) async {
    _log('learnerRounds(school: $schoolId, year: $schoolYear, asOf: $asOf)');
    final date = asOf == null ? _date(DateTime.now()) : _isoDay(asOf);
    final report = await implementationReport(
        schoolId: schoolId, schoolYear: schoolYear, asOf: DateTime.parse(date));
    return [for (final r in report.rows) ...r.learners];
  }

  static final _isoDayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String _isoDay(String s) {
    final d = _isoDayPattern.hasMatch(s) ? DateTime.tryParse(s) : null;
    if (d == null || _date(d) != s) {
      throw ViewModelException('"$s" is not a date: write it as YYYY-MM-DD, e.g. 2026-11-14.');
    }
    return s;
  }

  /// One section's ARAL learners entered by [asOf] with their results.
  Future<List<AralLearnerRounds>> _learners(
      Section s, int grade, String year, String asOf, PhilIriThresholds t, PhilIriValues values) async {
    final roster = (await _roster.getBySection(s.id!, schoolYear: year))
        .where((e) => e.enteredOn.compareTo(asOf) <= 0)
        .toList();
    bool inAralOn(AralEnrollment e) => e.exitedOn == null || e.exitedOn!.compareTo(asOf) > 0;
    final out = <AralLearnerRounds>[];

    if (grade <= 3) {
      final results = await _crlaResults.getBySection(s.id!, schoolYear: year);
      int? rank(String? profile) {
        final i = profile == null ? -1 : aralCrlaProfileOrder.indexOf(profile);
        return i < 0 ? null : i;
      }

      for (final e in roster) {
        final mine = results.where((r) => r.studentId == e.studentId).toList();
        final b = aralCrlaLearnerProfile(mine, CrlaRound.bosy, asOf, grade: grade);
        final inAral = inAralOn(e);
        final m = inAral ? aralCrlaLearnerProfile(mine, CrlaRound.mosy, asOf, grade: grade) : null;
        out.add(AralLearnerRounds(
          enrollment: e,
          grade: grade,
          instrument: AralLearnerRounds.crla,
          inAral: inAral,
          notAssessed: false,
          bosyResult: b ?? aralReportNoResult,
          bosyRank: rank(b),
          mosyResult: inAral ? m ?? aralReportNoResult : null,
          mosyRank: rank(m),
          mosyOwn: m != null,
        ));
      }
    } else {
      for (final e in roster) {
        final res = await _philIri.reportResults(
            studentId: e.studentId, sectionId: e.sectionId, schoolYear: year, asOf: asOf);
        (String, int?) group(Iterable<PhilIriRound> rounds) {
          // Not assessed at all by the report date: assumed 3-LD, flagged.
          if (res.notAssessed) return (aralReportNotAssessed, null);
          final last = res.latestView(rounds, values);
          // Actual: no reading of their own in these rounds = not assessed.
          if (last == null) {
            return (values == PhilIriValues.actual ? aralReportNotAssessed : aralReportNoResult, null);
          }
          // Non-readers go with the furthest group (the open last one).
          final label = last.profile == PhilIriLevel.nonReader
              ? philIriReportGroup(99, t)
              : philIriReportGroup(last.levelsDown, t);
          return (label, last.adjustedLevel);
        }

        final inAral = inAralOn(e);
        final b = group(const [PhilIriRound.bosy]);
        // MOSY: the latest MOSY round; without one, BOSY carries forward.
        final m = inAral
            ? group(const [PhilIriRound.bosy, PhilIriRound.mosy1, PhilIriRound.mosy2, PhilIriRound.mosy3])
            : null;
        const mosyRounds = [PhilIriRound.mosy1, PhilIriRound.mosy2, PhilIriRound.mosy3];
        out.add(AralLearnerRounds(
          enrollment: e,
          grade: grade,
          instrument: AralLearnerRounds.philIri,
          inAral: inAral,
          notAssessed: res.notAssessed,
          bosyResult: b.$1,
          bosyRank: b.$2,
          mosyResult: m?.$1,
          mosyRank: m?.$2,
          mosyOwn: inAral && !res.notAssessed && res.latestView(mosyRounds, values) != null,
        ));
      }
    }
    return out;
  }

  Future<AralSectionReportRow> _row(
      Section s, String year, String asOf, PhilIriThresholds t, PhilIriValues values) async {
    final grade = int.parse(s.gradeLevel);
    final usesCrla = grade <= 3;
    final enrolment = (await _students.getBySection(s.id!)).length;
    final learners = await _learners(s, grade, year, asOf, t, values);
    final exited = learners.where((x) => !x.inAral).map((x) => x.enrollment).toList();

    final bosy = <String, int>{};
    final mosy = <String, int>{};
    void add(Map<String, int> m, String k) => m[k] = (m[k] ?? 0) + 1;
    for (final x in learners) {
      add(bosy, x.bosyResult);
      if (x.inAral) add(mosy, x.mosyResult!);
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
      learners: learners,
    );
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
