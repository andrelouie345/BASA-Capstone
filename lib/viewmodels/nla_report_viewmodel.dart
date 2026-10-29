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
//
// Also progress monitoring (her sheets STARTHERE / IRA Summary): per section
// the share of learners assessed in each round against an adjustable "done"
// threshold (saved in report_settings, default 85%; a passed value is a
// one-off override), and the BOSY masterlist of learners not grade level ready
// (her sheet "BOSY Report"). A round the school's calendar does not hold
// shows NOT SCHEDULED (dashboard D2); without a Phil-IRI calendar for the
// year, progress is as before.
import '../core/console/logger.dart';
import '../core/models/assessment_calendar.dart' show CalendarInstrument;
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/section.dart';
import '../core/models/student.dart';
import '../core/models/user_role.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/auth_messages.dart';
import '../core/services/csv.dart';
import '../core/services/nla_form2b.dart';
import '../core/services/normalizers.dart';
import '../core/services/phil_iri_results.dart' show philIriNotAssessedResult, philIriNotGradeReady;
import '../core/services/phil_iri_rules.dart' show PhilIriLevel, philIriComprehensionLevel, philIriGradeOf;
import 'auth_viewmodel.dart';
import 'phil_iri_viewmodel.dart';
import 'report_settings_viewmodel.dart';
import 'round_calendar_viewmodel.dart';
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

// ---- progress monitoring ----

/// One section's progress (or the school total, when [section] is null).
class ProgressSectionReport {
  final Section? section;
  final int? grade;
  final NlaCounts enrolment = NlaCounts();
  final NlaCounts gstTakers = NlaCounts();        // GST score above 0
  final Map<PhilIriRound, NlaCounts> assessed = {for (final r in PhilIriRound.values) r: NlaCounts()};

  ProgressSectionReport(this.section, this.grade);

  /// GST takers / enrolled, or null with nobody enrolled.
  double? gstShare() => _share(gstTakers.total);

  /// Learners assessed in [r] / enrolled, or null with nobody enrolled.
  double? share(PhilIriRound r) => _share(assessed[r]!.total);

  double? _share(int n) => enrolment.total == 0 ? null : n / enrolment.total;

  void addAll(ProgressSectionReport o) {
    enrolment.addAll(o.enrolment);
    gstTakers.addAll(o.gstTakers);
    for (final r in PhilIriRound.values) {
      assessed[r]!.addAll(o.assessed[r]!);
    }
  }
}

class ProgressReport {
  final int schoolId;
  final String schoolYear;
  final String asOf;
  final double doneThreshold;
  final List<ProgressSectionReport> sections; // by grade, then name
  final ProgressSectionReport total;

  /// The Phil-IRI rounds the school's calendar holds this year; null when the
  /// calendar has no Phil-IRI window for the year (every round counts).
  final Set<PhilIriRound>? scheduledRounds;

  const ProgressReport(this.schoolId, this.schoolYear, this.asOf, this.doneThreshold, this.sections, this.total,
      {this.scheduledRounds});

  bool isScheduled(PhilIriRound r) => scheduledRounds == null || scheduledRounds!.contains(r);

  /// DONE, NOT SCHEDULED (a round the school does not hold), or the workbook's
  /// NO IRA (BOSY) / NO MOSY / NO EOSY; null with nobody enrolled.
  String? status(ProgressSectionReport row, PhilIriRound r) {
    if (row.enrolment.total == 0) return null;
    // Counts, not the rounded share: 17 of 20 at 0.85 is DONE.
    final done = row.assessed[r]!.total >= doneThreshold * row.enrolment.total - 1e-9;
    if (done) return 'DONE';
    if (!isScheduled(r)) return 'NOT SCHEDULED';
    return switch (r) {
      PhilIriRound.bosy => 'NO IRA',
      PhilIriRound.eosy => 'NO EOSY',
      _ => 'NO MOSY',
    };
  }
}

/// A share as a percent with one decimal ("98.0"), '' for none.
String progressPercent(double? share) => share == null ? '' : (share * 100).toStringAsFixed(1);

/// The progress report as CSV: one row per section (and/or the school total).
String progressReportCsv(ProgressReport report, {bool sectionRows = true, bool schoolTotal = true}) {
  final header = <Object?>[
    'Grade', 'Section', 'Enrolment M', 'Enrolment F', 'Enrolment T',
    'GST takers M', 'GST takers F', 'GST takers T', 'GST %',
    for (final r in PhilIriRound.values) ...['${r.label} assessed', '${r.label} %', '${r.label} status'],
  ];
  List<Object?> line(ProgressSectionReport r, Object? grade, String name) => [
        grade, name,
        r.enrolment.male, r.enrolment.female, r.enrolment.total,
        r.gstTakers.male, r.gstTakers.female, r.gstTakers.total, progressPercent(r.gstShare()),
        for (final round in PhilIriRound.values) ...[
          r.assessed[round]!.total,
          progressPercent(r.share(round)),
          report.status(r, round) ?? '',
        ],
      ];
  return csvTable([
    header,
    if (sectionRows)
      for (final r in report.sections) line(r, r.grade, r.section!.sectionName),
    if (schoolTotal) line(report.total, '', 'SCHOOL TOTAL'),
  ]);
}

// ---- BOSY masterlist of learners below grade level ----

/// One learner on the BOSY masterlist.
class BosyMasterlistEntry {
  final Student student;
  /// No BOSY result at all (no finished BOSY reading, no GST above 0 by
  /// asOf): listed anyway, with the assumed Frustration, 3 levels down.
  final bool notAssessed;
  final PhilIriLevel profile;      // Frustration or Non-Reader
  final int adjustedLevel;         // her ADJ GR; 0 for a Non-Reader
  final int? levelsDown;           // null for a Non-Reader
  final double? comprehension;     // BOSY carried comprehension (0-1); null if blank

  const BosyMasterlistEntry(
      this.student, this.notAssessed, this.profile, this.adjustedLevel, this.levelsDown, this.comprehension);

  String get name => '${student.lastName}, ${student.firstName}';

  /// Her group: Non-Reader, 3-LD (3 or more levels down) or 2-LD (1-2).
  String get group => profile == PhilIriLevel.nonReader
      ? 'Non-Reader'
      : (levelsDown ?? 0) >= 3
          ? '3-LD'
          : '2-LD';
}

class BosyMasterlistSection {
  final Section section;
  final int grade;
  final int enrolled;
  final List<BosyMasterlistEntry> learners; // by name

  const BosyMasterlistSection(this.section, this.grade, this.enrolled, this.learners);
}

class BosyMasterlist {
  final int schoolId;
  final String schoolYear;
  final String asOf;
  final List<BosyMasterlistSection> sections; // by grade, then name

  const BosyMasterlist(this.schoolId, this.schoolYear, this.asOf, this.sections);
}

/// The masterlist as CSV: one row per listed learner.
String bosyMasterlistCsv(BosyMasterlist list) => csvTable([
      ['Grade', 'Section', 'No.', 'LRN', 'Learner', 'Sex', 'Adjusted grade level', 'Group', 'Levels down',
        'Profile', 'BOSY comprehension %', 'Not assessed'],
      for (final s in list.sections)
        for (final (i, e) in s.learners.indexed)
          [
            s.grade, s.section.sectionName, i + 1, e.student.lrn, e.name, e.student.sex ?? '',
            e.adjustedLevel, e.group, e.levelsDown ?? '', e.profile.label,
            e.comprehension == null ? '' : progressPercent(e.comprehension), e.notAssessed ? 'yes' : '',
          ],
    ]);

class NlaReportViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final SectionRepository _sections;
  final StudentRepository _students;
  final PhilIriViewModel _philIri;
  final ReportSettingsViewModel _reportSettings;
  final RoundCalendarViewModel _calendar;

  NlaReportViewModel({
    required AuthViewModel auth,
    required SectionRepository sections,
    required StudentRepository students,
    required PhilIriViewModel philIri,
    required ReportSettingsViewModel reportSettings,
    required RoundCalendarViewModel calendar,
    Logger? logger,
  })  : _auth = auth,
        _sections = sections,
        _students = students,
        _philIri = philIri,
        _reportSettings = reportSettings,
        _calendar = calendar,
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
    schoolYear = normalizeSchoolYear(schoolYear);
    final sections = await reportSections(schoolId, schoolYear, sectionIds, 'the NLA report');
    final date = _date(asOf ?? DateTime.now());
    final total = NlaSectionReport(null, null);
    final rows = <NlaSectionReport>[];
    for (final s in sections) {
      final row = await _section(s, schoolYear, date);
      rows.add(row);
      total.addAll(row);
    }
    return NlaReport(schoolId, schoolYear, date, rows, total);
  }

  /// Progress monitoring (workbook sheets STARTHERE / IRA Summary): per Grade
  /// 4-10 section, enrolment, GST takers, and per round the share of enrolled
  /// learners assessed in it, DONE at the done threshold (a fraction, her
  /// "Assessment 'Done' Threshold") or more: [doneThreshold] when given (a
  /// one-off override), else the saved report setting (default 0.85). Rounds
  /// the school's calendar does not hold are flagged NOT SCHEDULED. Same
  /// access as [report].
  Future<ProgressReport> progress({
    required int schoolId,
    required String schoolYear,
    Set<int>? sectionIds,
    double? doneThreshold,
    DateTime? asOf,
  }) async {
    _log('progress(school: $schoolId, year: $schoolYear, sections: $sectionIds, done: $doneThreshold)');
    if (doneThreshold != null && !(doneThreshold > 0 && doneThreshold <= 1)) {
      throw ViewModelException('The done threshold is a share above 0 and up to 1 (got $doneThreshold).');
    }
    schoolYear = normalizeSchoolYear(schoolYear);
    final sections = await reportSections(schoolId, schoolYear, sectionIds, 'the progress report');
    doneThreshold ??= (await _reportSettings.effective(schoolId)).doneThreshold;
    final scheduled = await _scheduledPhilIriRounds(schoolId, schoolYear);
    final date = _date(asOf ?? DateTime.now());
    final total = ProgressSectionReport(null, null);
    final rows = <ProgressSectionReport>[];
    for (final s in sections) {
      final row = ProgressSectionReport(s, int.parse(s.gradeLevel));
      for (final st in await _students.getBySection(s.id!)) {
        row.enrolment.add(st.sex);
        final res = await _philIri.reportResults(studentId: st.id!, sectionId: s.id!, schoolYear: schoolYear, asOf: date);
        if (res.gst != null) row.gstTakers.add(st.sex);
        for (final r in assessedIn(res)) {
          row.assessed[r]!.add(st.sex);
        }
      }
      rows.add(row);
      total.addAll(row);
    }
    return ProgressReport(schoolId, schoolYear, date, doneThreshold, rows, total, scheduledRounds: scheduled);
  }

  /// The one definition of "assessed in a round" (progress monitoring, tutor
  /// reminders). Her rule: a passage read in that round (BASA: a finished
  /// session dated by asOf); at BOSY a counted GST counts too.
  static Set<PhilIriRound> assessedIn(PhilIriReportResults results) => results.counted;

  /// The Phil-IRI rounds a learner of [sectionId] is assessed in by [asOf]
  /// (YYYY-MM-DD), per [assessedIn]. No access check: the caller decides who
  /// may see the learner (tutor reminders: the tutor's own sections).
  Future<Set<PhilIriRound>> assessedPhilIriRounds({
    required int studentId,
    required int sectionId,
    required String schoolYear,
    required String asOf,
  }) async =>
      assessedIn(await _philIri.reportResults(
          studentId: studentId, sectionId: sectionId, schoolYear: schoolYear, asOf: asOf));

  /// The Phil-IRI rounds [schoolId]'s calendar holds in [year], or null when
  /// it has no Phil-IRI window that year (skipped ones count as windows).
  Future<Set<PhilIriRound>?> _scheduledPhilIriRounds(int schoolId, String year) async {
    final entries = (await _calendar.effectiveCalendar(schoolId, year))
        .where((e) => e.window.instrument == CalendarInstrument.philIri)
        .toList();
    if (entries.isEmpty) return null;
    return {
      for (final e in entries)
        if (!e.skipped) PhilIriRound.values.byName(e.window.round),
    };
  }

  /// The masterlist of learners not grade level ready at BOSY, per Grade 4-10
  /// section (workbook sheet "BOSY Report"): BOSY profile Frustration or
  /// Non-Reader (adjusted level below the grade), by name. Learners with no
  /// BOSY result are listed too, flagged (owner 2026-10-19). Same access as
  /// [report].
  Future<BosyMasterlist> bosyMasterlist({
    required int schoolId,
    required String schoolYear,
    Set<int>? sectionIds,
    DateTime? asOf,
  }) async {
    _log('bosyMasterlist(school: $schoolId, year: $schoolYear, sections: $sectionIds)');
    schoolYear = normalizeSchoolYear(schoolYear);
    final sections = await reportSections(schoolId, schoolYear, sectionIds, 'the BOSY masterlist');
    final date = _date(asOf ?? DateTime.now());
    final out = <BosyMasterlistSection>[];
    for (final s in sections) {
      final grade = int.parse(s.gradeLevel);
      final learners = await _students.getBySection(s.id!);
      final listed = <BosyMasterlistEntry>[];
      for (final st in learners) {
        final res = await _philIri.reportResults(studentId: st.id!, sectionId: s.id!, schoolYear: schoolYear, asOf: date);
        if (!res.counted.contains(PhilIriRound.bosy)) {
          final assumed = philIriNotAssessedResult(PhilIriRound.bosy, grade);
          listed.add(BosyMasterlistEntry(
              st, true, assumed.profile!, assumed.adjustedLevel!, assumed.levelsDown, null));
          continue;
        }
        final bosy = res.round(PhilIriRound.bosy);
        final profile = bosy.profile;
        if (!philIriNotGradeReady(profile)) continue;
        listed.add(BosyMasterlistEntry(
            st, false, profile!, bosy.adjustedLevel ?? 0, bosy.levelsDown, bosy.comprehensionScore));
      }
      listed.sort((a, b) {
        final l = a.student.lastName.toUpperCase().compareTo(b.student.lastName.toUpperCase());
        return l != 0 ? l : a.student.firstName.toUpperCase().compareTo(b.student.firstName.toUpperCase());
      });
      out.add(BosyMasterlistSection(s, grade, learners.length, listed));
    }
    return BosyMasterlist(schoolId, schoolYear, date, out);
  }

  /// The school's Grade 4-10 sections for the year, by grade then name, after
  /// the access check (admin/coordinator of the school, or the superadmin).
  Future<List<Section>> reportSections(int schoolId, String schoolYear, Set<int>? sectionIds, String what) async {
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException(notSignedInMessage);
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw ViewModelException('Forbidden: only an admin or coordinator can generate $what.');
    }
    if (me.schoolId != null && me.schoolId != schoolId) {
      throw const ViewModelException('Forbidden: that school is not yours.');
    }
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
    return sections;
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
