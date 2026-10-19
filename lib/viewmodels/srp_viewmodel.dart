// lib/viewmodels/srp_viewmodel.dart
//
// Summer Remediation Program (SRP), part 1: per Grade 4-10 section, the
// learners not grade level ready by the end of the year, ranked weakest first
// (srp_rules.dart), the weakest [perSection] recommended. Read-only, from this
// device's copy. Classes (grouping by adjusted grade, tutor, room, schedule)
// come in part 2.
//
// Reading coordinator's workbook (sheets 01-40, GZ/HA; owner 2026-10-19):
//  * not grade level ready = EOSY profile Frustration or Non-Reader; a learner
//    without an EOSY reading keeps the latest round's result (it carries);
//  * comprehension = the EOSY reading's own score when there is one, else the
//    carried one (her sheet compared her EOSY score in percent with the
//    carried one as a fraction, so learners without an EOSY reading always
//    ranked weakest; BASA compares both as fractions);
//  * learners not assessed at all are in, ranked weakest, flagged (as ARAL).
import '../core/console/logger.dart';
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/section.dart';
import '../core/models/student.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/csv.dart';
import '../core/services/normalizers.dart';
import '../core/services/phil_iri_results.dart' show philIriNotAssessedResult;
import '../core/services/phil_iri_rules.dart' show PhilIriLevel;
import '../core/services/srp_rules.dart';
import 'nla_report_viewmodel.dart' show NlaReportViewModel, progressPercent;
import 'phil_iri_viewmodel.dart';
import 'viewmodel_exception.dart';

class SrpCandidate {
  final Student student;
  final int rank;                  // 1 = weakest; equal results share a rank
  final bool recommended;          // rank within the section's cap
  final bool notAssessed;          // no Phil-IRI result at all this year
  final PhilIriRound? basisRound;  // the round the result comes from (null if not assessed)
  final PhilIriLevel profile;      // Frustration or Non-Reader
  final int adjustedLevel;         // 0 for a Non-Reader
  final int? levelsDown;
  final SrpRankKey key;

  const SrpCandidate({
    required this.student,
    required this.rank,
    required this.recommended,
    required this.notAssessed,
    required this.basisRound,
    required this.profile,
    required this.adjustedLevel,
    required this.levelsDown,
    required this.key,
  });

  String get name => '${student.lastName}, ${student.firstName}';
}

class SrpSection {
  final Section section;
  final int grade;
  final int enrolled;
  final List<SrpCandidate> candidates; // weakest first, then by name

  const SrpSection(this.section, this.grade, this.enrolled, this.candidates);

  int get recommendedCount => candidates.where((c) => c.recommended).length;
}

class SrpList {
  final int schoolId;
  final String schoolYear;
  final String asOf;
  final int perSection;
  final List<SrpSection> sections; // by grade, then name

  const SrpList(this.schoolId, this.schoolYear, this.asOf, this.perSection, this.sections);
}

/// The list as CSV: one row per candidate ([recommendedOnly]: only those
/// within the cap).
String srpListCsv(SrpList list, {bool recommendedOnly = false}) {
  String pct(double v) => progressPercent(v);
  return csvTable([
    ['Grade', 'Section', 'Rank', 'Recommended', 'LRN', 'Learner', 'Sex', 'Adjusted grade level', 'Levels down',
      'Profile', 'Comprehension %', 'Word recognition %', 'Speed (wpm)', 'Result from', 'Not assessed'],
    for (final s in list.sections)
      for (final c in s.candidates)
        if (!recommendedOnly || c.recommended)
          [
            s.grade, s.section.sectionName, c.rank, c.recommended ? 'yes' : '', c.student.lrn, c.name,
            c.student.sex ?? '', c.adjustedLevel, c.levelsDown ?? '', c.profile.label,
            c.notAssessed ? '' : pct(c.key.comprehension), c.notAssessed ? '' : pct(c.key.wordRecognition),
            c.notAssessed ? '' : c.key.speed.toStringAsFixed(0), c.basisRound?.label ?? '',
            c.notAssessed ? 'yes' : '',
          ],
  ]);
}

class SrpViewModel {
  final ScopedLogger _log;
  final NlaReportViewModel _reports;
  final StudentRepository _students;
  final PhilIriViewModel _philIri;

  SrpViewModel({
    required NlaReportViewModel reports,
    required StudentRepository students,
    required PhilIriViewModel philIri,
    Logger? logger,
  })  : _reports = reports,
        _students = students,
        _philIri = philIri,
        _log = ScopedLogger(logger, 'SrpViewModel');

  /// The SRP candidates of every Grade 4-10 section of the school
  /// ([sectionIds] narrows it) as of [asOf] (default today), the weakest
  /// [perSection] (default 15) recommended: admin/coordinator of the school,
  /// or the superadmin.
  Future<SrpList> candidates({
    required int schoolId,
    required String schoolYear,
    Set<int>? sectionIds,
    int perSection = srpDefaultPerSection,
    DateTime? asOf,
  }) async {
    _log('candidates(school: $schoolId, year: $schoolYear, sections: $sectionIds, perSection: $perSection)');
    if (perSection < 1) throw ViewModelException('Learners per section is at least 1 (got $perSection).');
    schoolYear = normalizeSchoolYear(schoolYear);
    final sections = await _reports.reportSections(schoolId, schoolYear, sectionIds, 'the SRP list');
    final date = _date(asOf ?? DateTime.now());
    final out = <SrpSection>[];
    for (final s in sections) {
      final grade = int.parse(s.gradeLevel);
      final learners = await _students.getBySection(s.id!);
      final drafts = <_Draft>[];
      for (final st in learners) {
        final res = await _philIri.reportResults(studentId: st.id!, sectionId: s.id!, schoolYear: schoolYear, asOf: date);
        if (res.notAssessed) {
          final assumed = philIriNotAssessedResult(PhilIriRound.eosy, grade);
          drafts.add(_Draft(st, true, null, assumed.profile!, assumed.adjustedLevel!, assumed.levelsDown,
              const SrpRankKey(0, 0, 0)));
          continue;
        }
        final eosy = res.round(PhilIriRound.eosy); // carries the latest round when EOSY was not given
        final profile = eosy.profile;
        if (profile != PhilIriLevel.frustration && profile != PhilIriLevel.nonReader) continue;
        final own = res.counted.contains(PhilIriRound.eosy) ? eosy.actual?.comprehensionScore : null;
        drafts.add(_Draft(
          st,
          false,
          res.latest(PhilIriRound.values)?.round,
          profile!,
          eosy.adjustedLevel ?? 0,
          eosy.levelsDown,
          SrpRankKey(own ?? eosy.comprehensionScore ?? 0, eosy.wordReadingScore ?? 0, eosy.wordsPerMinute ?? 0),
        ));
      }
      final ranks = srpRanks([for (final d in drafts) d.key]);
      final list = [
        for (final (i, d) in drafts.indexed)
          SrpCandidate(
            student: d.student,
            rank: ranks[i],
            recommended: ranks[i] <= perSection,
            notAssessed: d.notAssessed,
            basisRound: d.basisRound,
            profile: d.profile,
            adjustedLevel: d.adjustedLevel,
            levelsDown: d.levelsDown,
            key: d.key,
          ),
      ]..sort((a, b) {
          final r = a.rank.compareTo(b.rank);
          if (r != 0) return r;
          final l = a.student.lastName.toUpperCase().compareTo(b.student.lastName.toUpperCase());
          return l != 0 ? l : a.student.firstName.toUpperCase().compareTo(b.student.firstName.toUpperCase());
        });
      out.add(SrpSection(s, grade, learners.length, list));
    }
    return SrpList(schoolId, schoolYear, date, perSection, out);
  }

  static String _date(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

class _Draft {
  final Student student;
  final bool notAssessed;
  final PhilIriRound? basisRound;
  final PhilIriLevel profile;
  final int adjustedLevel;
  final int? levelsDown;
  final SrpRankKey key;

  const _Draft(this.student, this.notAssessed, this.basisRound, this.profile, this.adjustedLevel, this.levelsDown,
      this.key);
}
