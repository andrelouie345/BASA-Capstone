// lib/viewmodels/dashboard_viewmodel.dart
//
// Dashboard summary (D6): the home-screen numbers of the signed-in user, by
// role. Owns no rules; every figure is a call to an existing ViewModel or a
// plain count of rows on this device:
//  * tutor: their sections of the year with learner counts, their ARAL roster
//    (active / exited on today), sessions held + last session and the D3
//    reminders (both from ReminderViewModel.tutorReminders);
//  * school admin/coordinator: sections + learners per instrument, the
//    current and next round per instrument from the calendar (D1) with
//    completion (Phil-IRI: progress; CRLA: ReminderViewModel.crlaCompletion),
//    the ARAL roster, the BOSY masterlist, SRP candidates + classes and the D2
//    reminders;
//  * superadmin: the school summary of every school on this device + regional
//    sums (no regional round: schools may override the dates).
// Current round = every round open on today, or, when none is open, the most
// recently closed one; next = the earliest upcoming one. Charts are not here:
// the UI calls TrendViewModel. The school year is always passed; schoolYears()
// lists the ones on this device for the UI to preselect (owner 2026-10-20).
import '../core/console/logger.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/assessment_calendar.dart';
import '../core/models/crla_assessment.dart' show CrlaRound;
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/school.dart';
import '../core/models/section.dart';
import '../core/models/user_role.dart';
import '../core/repositories/school_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/repositories/tutor_section_assignment_repository.dart';
import '../core/services/aral_rules.dart' show aralActiveOn, aralExitedBy;
import '../core/services/auth_messages.dart';
import '../core/services/calendar_rules.dart';
import '../core/services/crla_rules.dart' show crlaGradeOf;
import '../core/services/normalizers.dart';
import '../core/services/phil_iri_rules.dart' show philIriGradeOf;
import 'aral_viewmodel.dart';
import 'auth_viewmodel.dart';
import 'nla_report_viewmodel.dart';
import 'reminder_viewmodel.dart';
import 'round_calendar_viewmodel.dart';
import 'srp_viewmodel.dart';
import 'viewmodel_exception.dart';

class SectionLearnerCount {
  final int sections;
  final int learners;

  const SectionLearnerCount(this.sections, this.learners);

  static const zero = SectionLearnerCount(0, 0);

  SectionLearnerCount operator +(SectionLearnerCount o) =>
      SectionLearnerCount(sections + o.sections, learners + o.learners);
}

/// ARAL roster rows of the year on a day: active (entered by then, not
/// exited) and exited by then, per reason. Rows entered later are left out.
class AralRosterCount {
  final int active;
  final int exited;
  final Map<AralExitReason, int> exitedBy; // every reason, 0 included

  const AralRosterCount(this.active, this.exited, this.exitedBy);

  static final zero = AralRosterCount(0, 0, {for (final r in AralExitReason.values) r: 0});

  factory AralRosterCount.of(Iterable<AralEnrollment> roster, String day) {
    var active = 0;
    final by = {for (final r in AralExitReason.values) r: 0};
    for (final e in roster) {
      if (aralActiveOn(e, day)) {
        active++;
      } else if (aralExitedBy(e, day)) {
        final r = e.exitReason ?? AralExitReason.other;
        by[r] = by[r]! + 1;
      }
    }
    return AralRosterCount(active, by.values.fold(0, (a, b) => a + b), by);
  }

  AralRosterCount operator +(AralRosterCount o) => AralRosterCount(active + o.active, exited + o.exited,
      {for (final r in AralExitReason.values) r: exitedBy[r]! + o.exitedBy[r]!});
}

/// One round of the school's calendar with its completion on today.
class RoundSnapshot {
  final CalendarInstrument instrument;
  final CalendarWindow window;
  final RoundStatus status;
  final int assessed;
  final int enrolled;

  /// Sections with learners at or above the done threshold / all of them.
  final int sectionsDone;
  final int sectionCount;

  const RoundSnapshot(
      this.instrument, this.window, this.status, this.assessed, this.enrolled, this.sectionsDone, this.sectionCount);

  String get roundName => '${instrument.label} ${roundLabel(window.round)}';

  /// assessed / enrolled, null with nobody enrolled.
  double? get share => enrolled == 0 ? null : assessed / enrolled;
}

class SchoolSummary {
  final School school;
  final double doneThreshold;

  /// Sections of the year and their learners, per instrument (CRLA Grade 1-3,
  /// Phil-IRI Grade 4-10); [otherGrades] = sections of neither.
  final Map<CalendarInstrument, SectionLearnerCount> counts;
  final SectionLearnerCount otherGrades;

  /// Per instrument in order, rounds in calendar order (see the file comment).
  final List<RoundSnapshot> current;
  final List<RoundSnapshot> next;
  final AralRosterCount aral;
  final int masterlistLearners;
  final int masterlistNotAssessed;
  final int srpCandidates;
  final int srpRecommended;
  final int srpClasses;
  final int srpClassLearners;
  final SchoolReminders reminders;

  const SchoolSummary({
    required this.school,
    required this.doneThreshold,
    required this.counts,
    required this.otherGrades,
    required this.current,
    required this.next,
    required this.aral,
    required this.masterlistLearners,
    required this.masterlistNotAssessed,
    required this.srpCandidates,
    required this.srpRecommended,
    required this.srpClasses,
    required this.srpClassLearners,
    required this.reminders,
  });
}

sealed class DashboardSummary {
  final String schoolYear;
  final String today; // YYYY-MM-DD

  const DashboardSummary(this.schoolYear, this.today);
}

class TutorDashboard extends DashboardSummary {
  final String tutorId;
  final String? tutorName;

  /// The tutor's sections of the year (by grade, then name) and their learners.
  final List<(Section, int)> sections;

  /// The tutor's ARAL roster (may hold learners of sections that are not theirs).
  final AralRosterCount aral;

  /// Also sessions held and the last session (sessionsHeld, lastSession).
  final TutorReminders reminders;

  const TutorDashboard(super.schoolYear, super.today, this.tutorId, this.tutorName, this.sections, this.aral,
      this.reminders);
}

class SchoolDashboard extends DashboardSummary {
  final SchoolSummary school;

  const SchoolDashboard(super.schoolYear, super.today, this.school);
}

class RegionDashboard extends DashboardSummary {
  final List<SchoolSummary> schools; // by name
  final Map<CalendarInstrument, SectionLearnerCount> counts;
  final SectionLearnerCount otherGrades;
  final AralRosterCount aral;
  final int masterlistLearners;
  final int masterlistNotAssessed;
  final int srpCandidates;
  final int srpRecommended;
  final int srpClasses;
  final int srpClassLearners;
  final Map<ReminderKind, int> reminders; // every kind, 0 included

  const RegionDashboard(
    super.schoolYear,
    super.today, {
    required this.schools,
    required this.counts,
    required this.otherGrades,
    required this.aral,
    required this.masterlistLearners,
    required this.masterlistNotAssessed,
    required this.srpCandidates,
    required this.srpRecommended,
    required this.srpClasses,
    required this.srpClassLearners,
    required this.reminders,
  });
}

class DashboardViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final RoundCalendarViewModel _calendar;
  final ReminderViewModel _reminders;
  final NlaReportViewModel _reports;
  final SrpViewModel _srp;
  final AralViewModel _aral;
  final SchoolRepository _schools;
  final SectionRepository _sections;
  final StudentRepository _students;
  final TutorSectionAssignmentRepository _assignments;

  DashboardViewModel({
    required AuthViewModel auth,
    required RoundCalendarViewModel calendar,
    required ReminderViewModel reminders,
    required NlaReportViewModel reports,
    required SrpViewModel srp,
    required AralViewModel aral,
    required SchoolRepository schools,
    required SectionRepository sections,
    required StudentRepository students,
    required TutorSectionAssignmentRepository assignments,
    Logger? logger,
  })  : _auth = auth,
        _calendar = calendar,
        _reminders = reminders,
        _reports = reports,
        _srp = srp,
        _aral = aral,
        _schools = schools,
        _sections = sections,
        _students = students,
        _assignments = assignments,
        _log = ScopedLogger(logger, 'DashboardViewModel');

  /// The school years that have sections on this device, latest first.
  Future<List<String>> schoolYears() async {
    _log('schoolYears()');
    if (_auth.currentUser == null) throw const ViewModelException(notSignedInMessage);
    int start(String y) => int.tryParse(y.length >= 4 ? y.substring(0, 4) : y) ?? 0;
    return {for (final s in await _sections.getAll()) s.schoolYear}.toList()
      ..sort((a, b) {
        final c = start(b).compareTo(start(a));
        return c != 0 ? c : b.compareTo(a);
      });
  }

  /// The signed-in user's dashboard for [schoolYear] as of [today] (default
  /// now), from this device's copy.
  Future<DashboardSummary> summary(String schoolYear, {DateTime? today}) async {
    _log('summary($schoolYear, today: $today)');
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException(notSignedInMessage);
    final String year;
    try {
      year = normalizeSchoolYear(schoolYear);
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
    final now = today ?? DateTime.now();
    final day = calendarDate(now);

    if (me.role == UserRole.tutor) {
      final reminders = await _reminders.tutorReminders(me.id, year, today: now);
      final sections = <(Section, int)>[];
      for (final a in await _assignments.getByTutor(me.id)) {
        final s = await _sections.getById(a.sectionId);
        if (s != null && s.schoolYear == year) sections.add((s, (await _students.getBySection(s.id!)).length));
      }
      sections.sort((a, b) => _bySection(a.$1, b.$1));
      final roster = await _aral.tutorRoster(tutorId: me.id, schoolYear: year);
      return TutorDashboard(year, day, me.id, reminders.tutorName, sections, AralRosterCount.of(roster, day), reminders);
    }

    if (me.schoolId != null) {
      final school = await _schools.getById(me.schoolId!) ??
          (throw ViewModelException('No school ${me.schoolId} on this device.'));
      return SchoolDashboard(year, day, await _school(school, year, now, day));
    }

    // Superadmin.
    final schools = (await _schools.getAll())..sort((a, b) => a.schoolName.compareTo(b.schoolName));
    final list = [for (final s in schools) await _school(s, year, now, day)];
    var other = SectionLearnerCount.zero;
    var aral = AralRosterCount.zero;
    final counts = {for (final i in CalendarInstrument.values) i: SectionLearnerCount.zero};
    final kinds = {for (final k in ReminderKind.values) k: 0};
    for (final s in list) {
      for (final i in CalendarInstrument.values) {
        counts[i] = counts[i]! + s.counts[i]!;
      }
      other = other + s.otherGrades;
      aral = aral + s.aral;
      for (final r in s.reminders.reminders) {
        kinds[r.kind] = kinds[r.kind]! + 1;
      }
    }
    int sum(int Function(SchoolSummary) f) => list.fold(0, (a, s) => a + f(s));
    return RegionDashboard(
      year,
      day,
      schools: list,
      counts: counts,
      otherGrades: other,
      aral: aral,
      masterlistLearners: sum((s) => s.masterlistLearners),
      masterlistNotAssessed: sum((s) => s.masterlistNotAssessed),
      srpCandidates: sum((s) => s.srpCandidates),
      srpRecommended: sum((s) => s.srpRecommended),
      srpClasses: sum((s) => s.srpClasses),
      srpClassLearners: sum((s) => s.srpClassLearners),
      reminders: kinds,
    );
  }

  Future<SchoolSummary> _school(School school, String year, DateTime now, String day) async {
    final id = school.id!;
    // The reminders come first: they check access and carry the school's
    // saved threshold, which the round completion below uses too.
    final reminders = (await _reminders.coordinatorReminders(id, year, today: now)).single;
    final threshold = reminders.doneThreshold;

    final counts = {for (final i in CalendarInstrument.values) i: SectionLearnerCount.zero};
    var other = SectionLearnerCount.zero;
    for (final s in (await _sections.getAll()).where((s) => s.schoolId == id && s.schoolYear == year)) {
      final c = SectionLearnerCount(1, (await _students.getBySection(s.id!)).length);
      if (crlaGradeOf(s.gradeLevel) != null) {
        counts[CalendarInstrument.crla] = counts[CalendarInstrument.crla]! + c;
      } else if (philIriGradeOf(s.gradeLevel) != null) {
        counts[CalendarInstrument.philIri] = counts[CalendarInstrument.philIri]! + c;
      } else {
        other = other + c;
      }
    }

    ProgressReport? progress; // once, only when a Phil-IRI round is shown
    Future<RoundSnapshot> snapshot(CalendarInstrument instrument, CalendarWindow w, RoundStatus status) async {
      if (instrument == CalendarInstrument.philIri) {
        progress ??= await _reports.progress(schoolId: id, schoolYear: year, doneThreshold: threshold, asOf: now);
        final p = progress!;
        final round = PhilIriRound.values.byName(w.round);
        final rows = p.sections.where((r) => r.enrolment.total > 0).toList();
        return RoundSnapshot(instrument, w, status, p.total.assessed[round]!.total, p.total.enrolment.total,
            rows.where((r) => p.status(r, round) == 'DONE').length, rows.length);
      }
      final list = await _reminders.crlaCompletion(id, year, CrlaRound.values.byName(w.round),
          today: now, doneThreshold: threshold);
      return RoundSnapshot(instrument, w, status, list.fold(0, (a, c) => a + c.assessed),
          list.fold(0, (a, c) => a + c.enrolled), list.where((c) => c.done).length, list.length);
    }

    final current = <RoundSnapshot>[];
    final next = <RoundSnapshot>[];
    for (final instrument in CalendarInstrument.values) {
      // scheduledRounds is in round order.
      final windows = [
        for (final e in await _calendar.scheduledRounds(id, year, instrument))
          (e.window, _calendar.status(e.window, today: now)),
      ];
      final open = windows.where((w) => w.$2 == RoundStatus.open).toList();
      final closed = windows.where((w) => w.$2 == RoundStatus.closed).toList();
      final upcoming = windows.where((w) => w.$2 == RoundStatus.upcoming).toList();
      final shown = open.isNotEmpty
          ? open
          : closed.isEmpty
              ? <(CalendarWindow, RoundStatus)>[]
              : [closed.reduce((a, b) => b.$1.closesOn!.compareTo(a.$1.closesOn!) >= 0 ? b : a)];
      for (final (w, status) in shown) {
        current.add(await snapshot(instrument, w, status));
      }
      if (upcoming.isNotEmpty) {
        final (w, status) = upcoming.reduce((a, b) => b.$1.opensOn!.compareTo(a.$1.opensOn!) < 0 ? b : a);
        next.add(await snapshot(instrument, w, status));
      }
    }

    final masterlist = await _reports.bosyMasterlist(schoolId: id, schoolYear: year, asOf: now);
    final listed = [for (final s in masterlist.sections) ...s.learners];
    final srp = await _srp.candidates(schoolId: id, schoolYear: year, asOf: now);
    final classes = await _srp.classes(schoolId: id, schoolYear: year);

    return SchoolSummary(
      school: school,
      doneThreshold: threshold,
      counts: counts,
      otherGrades: other,
      current: current,
      next: next,
      aral: AralRosterCount.of(await _aral.schoolRoster(schoolId: id, schoolYear: year), day),
      masterlistLearners: listed.length,
      masterlistNotAssessed: listed.where((e) => e.notAssessed).length,
      srpCandidates: srp.sections.fold(0, (a, s) => a + s.candidates.length),
      srpRecommended: srp.sections.fold(0, (a, s) => a + s.recommendedCount),
      srpClasses: classes.length,
      srpClassLearners: classes.fold(0, (a, c) => a + c.learners.length),
      reminders: reminders,
    );
  }

  static int _bySection(Section a, Section b) {
    final g = (int.tryParse(a.gradeLevel) ?? 0).compareTo(int.tryParse(b.gradeLevel) ?? 0);
    return g != 0 ? g : a.sectionName.compareTo(b.sectionName);
  }
}
