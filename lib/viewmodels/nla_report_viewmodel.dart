// lib/viewmodels/nla_report_viewmodel.dart
//
// The NLA portal report (Phil-IRI for JHS Form 2b) and the Division's ARAL
// Reading report, per Grade 4-10 section of a school and for the whole school,
// as the reading coordinator's workbook computes them (sheet "Phil-IRI Form 2";
// categories in nla_form2b.dart). Read-only, from this device's copy.
//
// Reading coordinator (2026-10-19):
//  * every round uses the learner's CARRIED (higher) comprehension;
//  * all learners of the section are counted except those not assessed at all
//    (no comprehension yet, or 0);
//  * a round nobody in the section took yet shows zeros (her sheet's YES/NO);
//  * the Division's ARAL report counts every learner below grade level by the
//    Form 2b bands (3-LD / 2-LD), and "exited by" a round = the learners at
//    grade level in it. BASA's roster-based implementation report stays too.
// Filters (which sexes, rounds, blocks, sections) only choose what is shown:
// see NlaReportFilter and nlaReportCsv.
import '../core/console/logger.dart';
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/section.dart';
import '../core/models/user_role.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/csv.dart';
import '../core/services/nla_form2b.dart';
import '../core/services/normalizers.dart';
import '../core/services/phil_iri_rules.dart' show PhilIriLevel, philIriComprehensionLevel, philIriGradeOf;
import 'auth_viewmodel.dart';
import 'phil_iri_viewmodel.dart';
import 'viewmodel_exception.dart';

/// One section (or the school total, when [section] is null).
class NlaSectionReport {
  final Section? section;
  final int? grade;
  final NlaCounts enrolment;
  final Map<NlaGstBand, NlaCounts> gst;            // BOSY: GST score bands
  final Map<PhilIriLevel, NlaCounts> gstProfile;   // BOSY: GST comprehension profile
  final Map<PhilIriRound, Map<NlaBand, NlaCounts>> rounds;
  final Set<PhilIriRound> conducted;               // rounds someone in the section took

  NlaSectionReport(this.section, this.grade)
      : enrolment = NlaCounts(),
        gst = {for (final b in NlaGstBand.values) b: NlaCounts()},
        gstProfile = {for (final l in _profiles) l: NlaCounts()},
        rounds = {
          for (final r in PhilIriRound.values) r: {for (final b in NlaBand.values) b: NlaCounts()},
        },
        conducted = {};

  static const _profiles = [PhilIriLevel.frustration, PhilIriLevel.instructional, PhilIriLevel.independent];

  NlaCounts band(PhilIriRound r, NlaBand b) => rounds[r]![b]!;
  NlaCounts assessed(PhilIriRound r) => NlaCounts.sum(rounds[r]!.values);
  NlaCounts ld2(PhilIriRound r) => NlaCounts.sum(NlaBand.values.where((b) => b.is2Ld).map((b) => band(r, b)));
  NlaCounts ld3(PhilIriRound r) => NlaCounts.sum(NlaBand.values.where((b) => b.is3Ld).map((b) => band(r, b)));

  void addAll(NlaSectionReport o) {
    enrolment.addAll(o.enrolment);
    for (final b in NlaGstBand.values) {
      gst[b]!.addAll(o.gst[b]!);
    }
    for (final l in _profiles) {
      gstProfile[l]!.addAll(o.gstProfile[l]!);
    }
    for (final r in PhilIriRound.values) {
      for (final b in NlaBand.values) {
        band(r, b).addAll(o.band(r, b));
      }
    }
    conducted.addAll(o.conducted);
  }
}

class NlaReport {
  final int schoolId;
  final String schoolYear;
  final String asOf;
  final List<NlaSectionReport> sections; // by grade, then name
  final NlaSectionReport total;

  const NlaReport(this.schoolId, this.schoolYear, this.asOf, this.sections, this.total);
}

enum NlaSex { male, female, total }

enum NlaBlock {
  enrolment('enrolment'),
  gst('gst'),
  profile('profile'),
  form2b('form2b'),
  aral('aral');

  final String key;
  const NlaBlock(this.key);
}

/// What to show. Defaults: everything.
class NlaReportFilter {
  final Set<NlaSex> sexes;
  final Set<PhilIriRound> rounds;
  final Set<NlaBlock> blocks;
  final bool sectionRows;   // one line per section
  final bool schoolTotal;   // the school total line

  const NlaReportFilter({
    this.sexes = const {NlaSex.male, NlaSex.female, NlaSex.total},
    this.rounds = const {...PhilIriRound.values},
    this.blocks = const {...NlaBlock.values},
    this.sectionRows = true,
    this.schoolTotal = true,
  });

  /// Sexes in the fixed order M, F, T.
  List<NlaSex> get sexList => NlaSex.values.where(sexes.contains).toList();
  List<PhilIriRound> get roundList => PhilIriRound.values.where(rounds.contains).toList();
}

int nlaValue(NlaCounts c, NlaSex s) => switch (s) {
      NlaSex.male => c.male,
      NlaSex.female => c.female,
      NlaSex.total => c.total,
    };

String _sexLabel(NlaSex s) => switch (s) { NlaSex.male => 'M', NlaSex.female => 'F', NlaSex.total => 'T' };

/// The report as CSV with [filter] applied: a header row and one row per
/// section (and/or the school total).
String nlaReportCsv(NlaReport report, [NlaReportFilter filter = const NlaReportFilter()]) {
  final sexes = filter.sexList;
  final header = <Object?>['Grade', 'Section'];
  final getters = <int Function(NlaSectionReport)>[];
  void col(String name, NlaCounts Function(NlaSectionReport) get) {
    for (final s in sexes) {
      header.add('$name ${_sexLabel(s)}');
      getters.add((r) => nlaValue(get(r), s));
    }
  }

  if (filter.blocks.contains(NlaBlock.enrolment)) col('Enrolment', (r) => r.enrolment);
  if (filter.blocks.contains(NlaBlock.gst)) {
    for (final b in NlaGstBand.values) {
      col('GST ${b.label}', (r) => r.gst[b]!);
    }
  }
  if (filter.blocks.contains(NlaBlock.profile)) {
    for (final l in NlaSectionReport._profiles) {
      col('GST profile ${l.label}', (r) => r.gstProfile[l]!);
    }
  }
  for (final round in filter.roundList) {
    if (filter.blocks.contains(NlaBlock.form2b)) {
      col('${round.label} Total assessed', (r) => r.assessed(round));
      for (final b in NlaBand.values) {
        col('${round.label} ${b.label}', (r) => r.band(round, b));
        if (b == NlaBand.ld2Frustration) col('${round.label} 2-LD Total', (r) => r.ld2(round));
        if (b == NlaBand.ld3Frustration) col('${round.label} 3-LD Total', (r) => r.ld3(round));
      }
    }
    if (filter.blocks.contains(NlaBlock.aral)) {
      col('${round.label} ARAL 3-LD', (r) => r.ld3(round));
      col('${round.label} ARAL 2-LD', (r) => r.ld2(round));
      col('${round.label} ARAL Total', (r) => NlaCounts.sum([r.ld3(round), r.ld2(round)]));
      if (round != PhilIriRound.bosy) col('${round.label} ARAL exited', (r) => r.band(round, NlaBand.glr));
    }
  }
  final rows = <List<Object?>>[header];
  if (filter.sectionRows) {
    for (final r in report.sections) {
      rows.add([r.grade, r.section!.sectionName, ...getters.map((g) => g(r))]);
    }
  }
  if (filter.schoolTotal) rows.add(['', 'SCHOOL TOTAL', ...getters.map((g) => g(report.total))]);
  return csvTable(rows);
}

class NlaReportViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final SectionRepository _sections;
  final StudentRepository _students;
  final PhilIriViewModel _philIri;

  NlaReportViewModel({
    required AuthViewModel auth,
    required SectionRepository sections,
    required StudentRepository students,
    required PhilIriViewModel philIri,
    Logger? logger,
  })  : _auth = auth,
        _sections = sections,
        _students = students,
        _philIri = philIri,
        _log = ScopedLogger(logger, 'NlaReportViewModel');

  /// Every Grade 4-10 section of the school ([sectionIds] narrows it) as of
  /// [asOf] (default today): admin/coordinator of the school, or the superadmin.
  Future<NlaReport> report({
    required int schoolId,
    required String schoolYear,
    Set<int>? sectionIds,
    DateTime? asOf,
  }) async {
    _log('report(school: $schoolId, year: $schoolYear, sections: $sectionIds)');
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException('Not signed in.');
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: only an admin or coordinator can generate the NLA report.');
    }
    if (me.schoolId != null && me.schoolId != schoolId) {
      throw const ViewModelException('Forbidden: that school is not yours.');
    }
    schoolYear = normalizeSchoolYear(schoolYear);
    final date = _date(asOf ?? DateTime.now());
    final sections = (await _sections.getAll())
        .where((s) =>
            s.schoolId == schoolId &&
            s.schoolYear == schoolYear &&
            philIriGradeOf(s.gradeLevel) != null &&
            (sectionIds == null || sectionIds.contains(s.id)))
        .toList()
      ..sort((a, b) {
        final g = int.parse(a.gradeLevel).compareTo(int.parse(b.gradeLevel));
        return g != 0 ? g : a.sectionName.compareTo(b.sectionName);
      });
    if (sectionIds != null && sections.length != sectionIds.length) {
      final missing = sectionIds.difference(sections.map((s) => s.id!).toSet());
      throw ViewModelException('Not Grade 4-10 sections of school $schoolId for $schoolYear: ${missing.join(', ')}.');
    }
    final total = NlaSectionReport(null, null);
    final rows = <NlaSectionReport>[];
    for (final s in sections) {
      final row = await _section(s, schoolYear, date);
      rows.add(row);
      total.addAll(row);
    }
    return NlaReport(schoolId, schoolYear, date, rows, total);
  }

  Future<NlaSectionReport> _section(Section s, String year, String asOf) async {
    final row = NlaSectionReport(s, int.parse(s.gradeLevel));
    final learners = await _students.getBySection(s.id!);
    // Per learner: the carried comprehension of each round, and the GST.
    final perLearner = <(String?, PhilIriReportResults)>[];
    for (final st in learners) {
      row.enrolment.add(st.sex);
      final res = await _philIri.reportResults(studentId: st.id!, sectionId: s.id!, schoolYear: year, asOf: asOf);
      perLearner.add((st.sex, res));
      row.conducted.addAll(res.counted);
      final gst = res.gst;
      if (gst != null) {
        final band = nlaGstBand(gst.totalScore, gst.maxScore);
        if (band != null) row.gst[band]!.add(st.sex);
        row.gstProfile[philIriComprehensionLevel(gst.percent)]?.add(st.sex);
      }
    }
    for (final (sex, res) in perLearner) {
      for (final round in PhilIriRound.values) {
        if (!row.conducted.contains(round)) continue; // nobody took it: zeros
        final band = nlaBand(res.round(round).comprehensionScore);
        if (band != null) row.band(round, band).add(sex);
      }
    }
    return row;
  }

  static String _date(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
