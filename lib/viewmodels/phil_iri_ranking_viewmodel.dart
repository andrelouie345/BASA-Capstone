// lib/viewmodels/phil_iri_ranking_viewmodel.dart
//
// The Phil-IRI ranking list (spec docs/superpowers/specs/2026-11-14-phil-iri-value-sources-design.md,
// D9, D10, D12). Admin build only: the lowest N learners of one section, one
// grade or the whole school (Grades 4-10 together) by one measure (word
// reading accuracy, speed or comprehension) in one round. Values come from
// the school's values_ranking switch (default actual). Learners without a
// value for the measure never take a place: they are listed in a second
// block with the reason. Read-only, from this device's copy.
import '../core/console/logger.dart';
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/phil_iri_types.dart' show PhilIriLevel, PhilIriRoundView;
import '../core/models/report_setting.dart' show PhilIriValueList, PhilIriValues;
import '../core/models/section.dart';
import '../core/models/student.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/csv.dart';
import '../core/services/normalizers.dart';
import 'auth_viewmodel.dart';
import 'nla_report_viewmodel.dart' show NlaReportViewModel, progressPercent;
import 'phil_iri_viewmodel.dart';
import 'viewmodel_exception.dart';

enum PhilIriRankMeasure {
  accuracy('Accuracy %'),
  wpm('Speed (wpm)'),
  comprehension('Comprehension %');

  final String label;
  const PhilIriRankMeasure(this.label);
}

/// Why a learner has no value for the measure (spec D12).
enum PhilIriRankReason {
  notAssessedThisRound('not assessed this round'),
  silentNoAccuracy('silent reading: no accuracy'),
  comprehensionOnly('comprehension only, no word reading'),
  noComprehension('no comprehension entry');

  final String label;
  const PhilIriRankReason(this.label);
}

/// A ranked learner (block 1).
class PhilIriRankRow {
  final Student student;
  final int grade;
  final Section section;
  final int rank; // 1 = lowest value; equal values share a rank
  final double value; // accuracy / comprehension 0-1, or wpm
  final PhilIriLevel? profile;

  const PhilIriRankRow(this.student, this.grade, this.section, this.rank, this.value, this.profile);

  String get name => '${student.lastName}, ${student.firstName}';
}

/// A learner without a value for the measure (block 2).
class PhilIriUnranked {
  final Student student;
  final int grade;
  final Section section;
  final PhilIriRankReason reason;

  const PhilIriUnranked(this.student, this.grade, this.section, this.reason);

  String get name => '${student.lastName}, ${student.firstName}';
}

class PhilIriRanking {
  final int schoolId;
  final String schoolYear;
  final PhilIriRound round;
  final PhilIriRankMeasure measure;
  final int n;
  final int? sectionId; // null with [grade] null = the whole school
  final int? grade;
  final PhilIriValues values;
  final String asOf; // YYYY-MM-DD
  /// Lowest first; every learner with rank <= n (ties may run past n).
  final List<PhilIriRankRow> ranked;
  /// By name.
  final List<PhilIriUnranked> unranked;

  const PhilIriRanking({
    required this.schoolId,
    required this.schoolYear,
    required this.round,
    required this.measure,
    required this.n,
    required this.sectionId,
    required this.grade,
    required this.values,
    required this.asOf,
    required this.ranked,
    required this.unranked,
  });

  /// More learners than [n] are listed because of a tie at the last rank.
  bool get tiedPastN => ranked.length > n;
}

/// A measure's value as reports show it: accuracy/comprehension as a percent
/// with one decimal, wpm with one decimal.
String philIriRankValueText(PhilIriRankMeasure m, double value) =>
    m == PhilIriRankMeasure.wpm ? value.toStringAsFixed(1) : progressPercent(value);

/// The ranking as CSV: ranked rows, then the not-ranked rows (no rank, no
/// value, a reason); the Values column last (owner 2026-11-14).
String philIriRankingCsv(PhilIriRanking r) => csvTable([
      ['Rank', 'LRN', 'Learner', 'Sex', 'Grade', 'Section', r.measure.label, 'Profile', 'Reason', 'Values'],
      for (final x in r.ranked)
        [
          x.rank, x.student.lrn, x.name, x.student.sex ?? '', x.grade, x.section.sectionName,
          philIriRankValueText(r.measure, x.value), x.profile?.label ?? '', '', r.values.name,
        ],
      for (final x in r.unranked)
        ['', x.student.lrn, x.name, x.student.sex ?? '', x.grade, x.section.sectionName, '', '', x.reason.label,
          r.values.name],
    ]);

/// Ranks ascending: equal values share a rank (1, 2, 2, 4).
List<int> rankAscending(List<double> values) {
  final order = List<int>.generate(values.length, (i) => i)..sort((a, b) => values[a].compareTo(values[b]));
  final ranks = List<int>.filled(values.length, 0);
  for (var pos = 0; pos < order.length; pos++) {
    final i = order[pos];
    ranks[i] = pos > 0 && values[order[pos - 1]] == values[i] ? ranks[order[pos - 1]] : pos + 1;
  }
  return ranks;
}

class PhilIriRankingViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final NlaReportViewModel _reports;
  final StudentRepository _students;
  final PhilIriViewModel _philIri;

  PhilIriRankingViewModel({
    required AuthViewModel auth,
    required NlaReportViewModel reports,
    required StudentRepository students,
    required PhilIriViewModel philIri,
    Logger? logger,
  })  : _auth = auth,
        _reports = reports,
        _students = students,
        _philIri = philIri,
        _log = ScopedLogger(logger, 'PhilIriRankingViewModel');

  /// The lowest [n] learners by [measure] in [round]: one section
  /// ([sectionId]), one grade ([grade], every section of it) or the whole
  /// school (Grades 4-10 together), as of [asOf] (default today). Admin or
  /// coordinator of the school, or the superadmin.
  Future<PhilIriRanking> rank({
    required int schoolId,
    required String schoolYear,
    required PhilIriRound round,
    required PhilIriRankMeasure measure,
    int n = 10,
    int? sectionId,
    int? grade,
    DateTime? asOf,
  }) async {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
    _log('rank(school: $schoolId, year: $schoolYear, round: ${round.name}, measure: ${measure.name}, n: $n, '
        'section: $sectionId, grade: $grade)');
    if (n < 1) throw ViewModelException('Learners to list is at least 1 (got $n).');
    if (sectionId != null && grade != null) throw const ViewModelException('Give a section or a grade, not both.');
    schoolYear = normalizeSchoolYear(schoolYear);
    const what = 'the Phil-IRI ranking';
    var sections =
        await _reports.reportSections(schoolId, schoolYear, sectionId == null ? null : {sectionId}, what);
    if (grade != null) {
      sections = sections.where((s) => int.parse(s.gradeLevel) == grade).toList();
      if (sections.isEmpty) throw ViewModelException('School $schoolId has no Grade $grade section for $schoolYear.');
    }
    final values = await _philIri.valueSource(schoolId, PhilIriValueList.ranking);
    final date = _date(asOf ?? DateTime.now());

    final valued = <(Student, int, Section, double, PhilIriLevel?)>[];
    final unranked = <PhilIriUnranked>[];
    for (final s in sections) {
      final g = int.parse(s.gradeLevel);
      for (final st in await _students.getBySection(s.id!)) {
        final res = await _philIri.reportResults(studentId: st.id!, sectionId: s.id!, schoolYear: schoolYear, asOf: date);
        final v = res.view(round, values);
        final (value, reason) = _value(v, measure);
        if (reason != null) {
          unranked.add(PhilIriUnranked(st, g, s, reason));
        } else {
          valued.add((st, g, s, value!, v.profile));
        }
      }
    }

    final ranks = rankAscending([for (final x in valued) x.$4]);
    final ranked = [
      for (final (i, x) in valued.indexed)
        if (ranks[i] <= n) PhilIriRankRow(x.$1, x.$2, x.$3, ranks[i], x.$4, x.$5),
    ]..sort((a, b) {
        final r = a.rank.compareTo(b.rank);
        return r != 0 ? r : _byName(a.student, b.student);
      });
    unranked.sort((a, b) => _byName(a.student, b.student));
    return PhilIriRanking(
      schoolId: schoolId,
      schoolYear: schoolYear,
      round: round,
      measure: measure,
      n: n,
      sectionId: sectionId,
      grade: grade,
      values: values,
      asOf: date,
      ranked: ranked,
      unranked: unranked,
    );
  }

  /// The measure's value from the round view, or why there is none (D12).
  static (double?, PhilIriRankReason?) _value(PhilIriRoundView v, PhilIriRankMeasure m) {
    if (v.notAssessedThisRound || v.notAssessed || v.profile == null) {
      return (null, PhilIriRankReason.notAssessedThisRound);
    }
    switch (m) {
      case PhilIriRankMeasure.accuracy:
        if (v.wordReadingAssumed) return (null, PhilIriRankReason.comprehensionOnly);
        if (v.silentOnly) return (null, PhilIriRankReason.silentNoAccuracy);
        return v.wordReadingScore == null
            ? (null, PhilIriRankReason.comprehensionOnly)
            : (v.wordReadingScore, null);
      case PhilIriRankMeasure.wpm:
        if (v.wordReadingAssumed || v.wordsPerMinute == null) return (null, PhilIriRankReason.comprehensionOnly);
        return (v.wordsPerMinute, null);
      case PhilIriRankMeasure.comprehension:
        return v.comprehensionScore == null
            ? (null, PhilIriRankReason.noComprehension)
            : (v.comprehensionScore, null);
    }
  }

  static int _byName(Student a, Student b) {
    final l = a.lastName.toUpperCase().compareTo(b.lastName.toUpperCase());
    return l != 0 ? l : a.firstName.toUpperCase().compareTo(b.firstName.toUpperCase());
  }

  static String _date(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
