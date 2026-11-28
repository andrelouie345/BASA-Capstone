// lib/viewmodels/reminder_viewmodel.dart
//
// Dashboard reminders (D2: coordinators; D3 adds tutors). Data the UI shows,
// not notifications. Per scheduled round of the school's calendar (D1):
//  * upcoming and opening within reminderHeadsUpDays -> heads-up;
//  * open -> in progress, with the sections still below the done threshold;
//  * closed with sections below the threshold -> overdue (closed and all done
//    -> nothing).
// Phil-IRI (Grade 4-10) completion is NlaReportViewModel.progress, the same
// definition of "done"; CRLA (Grade 1-3) counts the learners with a
// crla_results row of that round in the section, against the same threshold.
// The threshold is the saved report setting unless one is passed.
//
// ARAL classes (2026-10-24): coordinators also see the school's ARAL learners
// waiting for a class, learners in a class of another program, and classes
// without a tutor (SchoolReminders.aral).
//
// Tutor reminders (D3): per learner, not per section (a tutor is reminded about
// each learner even when the section passed the done threshold), over the
// tutor's assigned sections (tutor_section_assignments, mirrored locally) and
// ARAL learners (those of the classes they teach): learners not assessed in open or
// closed rounds, check-ins due after a class's 16th/32nd session (the class's
// count, also for learners who joined later), ARAL learners without an IRIP,
// and a class with no session for more than idle_session_days. Nothing dated
// after today counts.
import '../core/console/logger.dart';
import '../core/models/crla_result.dart';
import '../core/models/assessment_calendar.dart';
import '../core/models/crla_assessment.dart' show CrlaRound;
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/aral_class.dart';
import '../core/models/report_setting.dart';
import '../core/models/section.dart';
import '../core/models/user_role.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/aral_session.dart' show AralSession;
import '../core/models/student.dart';
import '../core/repositories/aral_checkin_repository.dart';
import '../core/repositories/aral_class_repository.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/aral_irip_repository.dart';
import '../core/repositories/aral_session_repository.dart';
import '../core/repositories/aral_setting_repository.dart';
import '../core/repositories/crla_result_repository.dart';
import '../core/repositories/school_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/repositories/tutor_section_assignment_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/aral_checkin_rules.dart' show aralCheckinCheckpoints;
import '../core/services/aral_rule_settings.dart' show AralRuleSettings;
import '../core/services/aral_rules.dart' show AralSessionSettings, aralActiveOn;
import '../core/services/auth_messages.dart';
import '../core/services/phil_iri_rules.dart' show philIriGradeOf;
import '../core/services/calendar_rules.dart';
import '../core/services/normalizers.dart';
import 'auth_viewmodel.dart';
import 'aral_class_viewmodel.dart';
import 'nla_report_viewmodel.dart';
import 'phil_iri_viewmodel.dart' show PhilIriReportResults;
import 'report_settings_viewmodel.dart';
import 'round_calendar_viewmodel.dart';
import 'viewmodel_exception.dart';

/// A round that has not opened yet gets a heads-up this many days before.
const reminderHeadsUpDays = 7;

/// In display order: overdue first, heads-up last.
enum ReminderKind { overdue, inProgress, headsUp }

/// One section's completion of a round (only sections with learners).
class SectionCompletion {
  final Section section;
  final int assessed;
  final int enrolled;

  /// At or above the done threshold.
  final bool done;

  const SectionCompletion(this.section, this.assessed, this.enrolled, this.done);

  double get share => assessed / enrolled;
}

class CoordinatorReminder {
  final int schoolId;
  final CalendarInstrument instrument;
  final CalendarWindow window;
  final ReminderKind kind;

  /// Days until opens_on (heads-up), until closes_on (in progress, 0 = closes
  /// today), or since closes_on (overdue).
  final int days;

  /// Sections of the instrument's grades with learners.
  final int sectionCount;

  /// Those still below [doneThreshold] (empty for a heads-up), by grade then name.
  final List<SectionCompletion> below;
  final double doneThreshold;

  const CoordinatorReminder(this.schoolId, this.instrument, this.window, this.kind, this.days, this.sectionCount,
      this.below, this.doneThreshold);

  String get roundName => '${instrument.label} ${roundLabel(window.round)}';

  String get message {
    String n(int d) => d == 1 ? '1 day' : '$d days';
    final pending = below.isEmpty
        ? (sectionCount == 1 ? 'the 1 section done' : 'all $sectionCount sections done')
        : '${below.length} of $sectionCount section${sectionCount == 1 ? '' : 's'} below '
            '${thresholdPercent(doneThreshold)}';
    return switch (kind) {
      ReminderKind.headsUp => '$roundName opens in ${n(days)} (${window.opensOn}).',
      ReminderKind.inProgress => '$roundName ${days == 0 ? 'closes today' : 'closes in ${n(days)}'}: $pending.',
      ReminderKind.overdue => '$roundName closed ${n(days)} ago: $pending.',
    };
  }
}

class SchoolReminders {
  final int schoolId;
  final String schoolName;
  final double doneThreshold;
  final List<CoordinatorReminder> reminders;

  /// ARAL classes: learners waiting for a class, in a class of another
  /// program, classes without a tutor (empty when all is in order).
  final List<AralClassNotice> aral;

  const SchoolReminders(this.schoolId, this.schoolName, this.doneThreshold, this.reminders, [this.aral = const []]);
}

/// overMax / underMin: a class above the school's class_max_learners (the
/// maximum was lowered after it filled) or below its class_min_learners
/// (ARAL memo settings; 0 = no minimum). fewSessionsThisWeek: from
/// Wednesday, a class with active learners that held fewer sessions this
/// Monday-Friday week than the school's class_min_sessions_per_week.
/// noImprovement: a class with learners not improving (spec 2026-11-27 ARAL
/// effectiveness D1; `AralClassViewModel.noImprovement`), with or without a tutor.
enum AralClassNoticeKind { waiting, programMismatch, otherGrade, noTutor, overMax, underMin, fewSessionsThisWeek, noImprovement }

/// An ARAL class matter for the coordinator.
class AralClassNotice {
  final AralClassNoticeKind kind;
  final String message;

  /// The learners concerned (waiting, other program, other grade), by name,
  /// each with their ARAL roster row.
  final List<ReminderLearner> learners;

  /// The class concerned (no tutor, over the maximum, under the minimum).
  final AralClass? aralClass;

  const AralClassNotice(this.kind, this.message, {this.learners = const [], this.aralClass});

  /// The roster entries concerned.
  List<int> get enrollmentIds => [for (final l in learners) l.enrollmentId!];
}

/// In display order (spec D3): overdue assessments, check-ins due, learners
/// with no improvement (per own class; spec 2026-11-27 ARAL effectiveness D1),
/// open-round assessments, learners without a GST (BOSY; spec 2026-11-09
/// D13), no IRIP, no session lately.
enum TutorReminderKind {
  overdueAssessment,
  checkinDue,
  noImprovement,
  openAssessment,
  noGst,
  noIrip,
  noSessionLately,
  fewSessionsThisWeek
}

class ReminderLearner {
  final int studentId;
  final String lrn;
  final String name; // "LAST, First"
  final int? enrollmentId; // the ARAL roster row (check-in / IRIP reminders)

  /// No-improvement lines only: why the learner is flagged, in plain words
  /// (one or two); empty everywhere else.
  final List<String> reasons;

  const ReminderLearner(this.studentId, this.lrn, this.name, [this.enrollmentId]) : reasons = const [];

  /// A learner of a no-improvement line or notice.
  const ReminderLearner.flagged(this.studentId, this.lrn, this.name, int this.enrollmentId, this.reasons);
}

class TutorReminder {
  final TutorReminderKind kind;
  final String message;

  /// Assessment reminders: the section, instrument and round window.
  final Section? section;
  final CalendarInstrument? instrument;
  final CalendarWindow? window;

  /// Check-in reminders: 16 or 32.
  final int? checkpoint;

  /// Check-in and no-session reminders: the ARAL class.
  final AralClass? aralClass;

  /// Days since closes_on (overdue), until closes_on (open, 0 = today), or
  /// since the last session (no session lately; null when none this year).
  final int? days;

  /// By last name, first name.
  final List<ReminderLearner> learners;

  const TutorReminder(this.kind, this.message, this.learners,
      {this.section, this.instrument, this.window, this.checkpoint, this.days, this.aralClass});
}

class TutorReminders {
  final String tutorId;
  final String? tutorName;
  final String schoolYear;

  /// The sessions of the tutor's ARAL classes held on or before today.
  final int sessionsHeld;
  final String? lastSession; // YYYY-MM-DD
  final int idleSessionDays;
  final List<TutorReminder> reminders;

  const TutorReminders(this.tutorId, this.tutorName, this.schoolYear, this.sessionsHeld, this.lastSession,
      this.idleSessionDays, this.reminders);
}

class ReminderViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final RoundCalendarViewModel _calendar;
  final NlaReportViewModel _reports;
  final ReportSettingsViewModel _reportSettings;
  final SchoolRepository _schools;
  final SectionRepository _sections;
  final StudentRepository _students;
  final CrlaResultRepository _crlaResults;
  final TutorSectionAssignmentRepository _assignments;
  final UserRepository _users;
  final AralEnrollmentRepository _roster;
  final AralSessionRepository _aralSessions;
  final AralIripRepository _irip;
  final AralCheckinRepository _checkins;
  final AralSettingRepository _aralSettings;
  final AralClassRepository _classes;
  final AralClassViewModel _aralClasses;

  ReminderViewModel({
    required AuthViewModel auth,
    required RoundCalendarViewModel calendar,
    required NlaReportViewModel reports,
    required ReportSettingsViewModel reportSettings,
    required SchoolRepository schools,
    required SectionRepository sections,
    required StudentRepository students,
    required CrlaResultRepository crlaResults,
    required TutorSectionAssignmentRepository assignments,
    required UserRepository users,
    required AralEnrollmentRepository roster,
    required AralSessionRepository aralSessions,
    required AralIripRepository irip,
    required AralCheckinRepository checkins,
    required AralSettingRepository aralSettings,
    required AralClassRepository classes,
    required AralClassViewModel aralClasses,
    Logger? logger,
  })  : _auth = auth,
        _aralClasses = aralClasses,
        _calendar = calendar,
        _reports = reports,
        _reportSettings = reportSettings,
        _schools = schools,
        _sections = sections,
        _students = students,
        _crlaResults = crlaResults,
        _assignments = assignments,
        _users = users,
        _roster = roster,
        _aralSessions = aralSessions,
        _irip = irip,
        _checkins = checkins,
        _aralSettings = aralSettings,
        _classes = classes,
        _log = ScopedLogger(logger, 'ReminderViewModel');

  /// Reminders for [schoolId]'s coordinators in [year] as of [today] (default
  /// now): admin/coordinator of the school, or the superadmin. [schoolId] null
  /// = every school on this device (superadmin only), ordered by name; a school
  /// without reminders is kept with an empty list. [doneThreshold] (a share)
  /// overrides the saved setting for this call only.
  Future<List<SchoolReminders>> coordinatorReminders(int? schoolId, String year,
      {DateTime? today, double? doneThreshold}) async {
    _log('coordinatorReminders($schoolId, $year, today: $today, done: $doneThreshold)');
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException(notSignedInMessage);
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Not allowed: only an admin or coordinator sees coordinator reminders.');
    }
    if (me.schoolId != null && schoolId == null) {
      throw const ViewModelException('Not allowed: only the superadmin sees the reminders of every school.');
    }
    if (me.schoolId != null && schoolId != me.schoolId) {
      throw const ViewModelException('Not allowed: that school is not yours.');
    }
    if (doneThreshold != null && !(doneThreshold > 0 && doneThreshold <= 1)) {
      throw ViewModelException('The done threshold is a share above 0 and up to 1 (got $doneThreshold).');
    }
    try {
      year = normalizeSchoolYear(year);
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
    final day = today ?? DateTime.now();
    final schools = schoolId == null
        ? ((await _schools.getAll())..sort((a, b) => a.schoolName.compareTo(b.schoolName)))
        : [await _schools.getById(schoolId) ?? (throw ViewModelException('No school $schoolId on this device.'))];
    return [
      for (final s in schools) await _forSchool(s.id!, s.schoolName, year, day, doneThreshold),
    ];
  }

  Future<SchoolReminders> _forSchool(int schoolId, String name, String year, DateTime today, double? passed) async {
    final threshold = passed ?? (await _reportSettings.effective(schoolId)).doneThreshold;
    final out = <CoordinatorReminder>[];
    ProgressReport? progress; // computed once, only when a Phil-IRI round needs it
    for (final instrument in CalendarInstrument.values) {
      for (final entry in await _calendar.scheduledRounds(schoolId, year, instrument)) {
        final w = entry.window;
        final status = _calendar.status(w, today: today);
        final ReminderKind kind;
        final int days;
        switch (status) {
          case RoundStatus.upcoming:
            days = _daysBetween(calendarDate(today), w.opensOn!);
            if (days > reminderHeadsUpDays) continue;
            kind = ReminderKind.headsUp;
          case RoundStatus.open:
            days = _daysBetween(calendarDate(today), w.closesOn!);
            kind = ReminderKind.inProgress;
          case RoundStatus.closed:
            days = _daysBetween(w.closesOn!, calendarDate(today));
            kind = ReminderKind.overdue;
        }
        final List<SectionCompletion> all;
        if (instrument == CalendarInstrument.philIri) {
          progress ??= await _reports.progress(
              schoolId: schoolId, schoolYear: year, doneThreshold: threshold, asOf: today);
          final round = PhilIriRound.values.byName(w.round);
          all = [
            for (final r in progress.sections)
              if (r.enrolment.total > 0)
                SectionCompletion(r.section!, r.assessed[round]!.total, r.enrolment.total,
                    progress.status(r, round) == 'DONE'),
          ];
        } else {
          all = await _crlaCompletion(
              schoolId, year, CrlaRound.values.byName(w.round), calendarDate(today), threshold);
        }
        if (all.isEmpty) continue; // no sections of this instrument's grades
        final below = kind == ReminderKind.headsUp
            ? <SectionCompletion>[]
            : all.where((c) => !c.done).toList();
        if (kind == ReminderKind.overdue && below.isEmpty) continue;
        out.add(CoordinatorReminder(schoolId, instrument, w, kind, days, all.length, below, threshold));
      }
    }
    int order(CoordinatorReminder r) =>
        r.instrument.index * 100 + calendarRounds[r.instrument]!.indexOf(r.window.round);
    out.sort((a, b) {
      final k = a.kind.index.compareTo(b.kind.index);
      if (k != 0) return k;
      final d = a.kind == ReminderKind.overdue ? b.days.compareTo(a.days) : a.days.compareTo(b.days);
      return d != 0 ? d : order(a).compareTo(order(b));
    });
    return SchoolReminders(schoolId, name, threshold, out, await _aralNotices(schoolId, year, calendarDate(today)));
  }

  /// "Class "X" has 1 session this week; the school asks for at least 3."
  /// when [day] is a Wednesday or later and [sessions] (the class's) held from
  /// that week's Monday to [day] are fewer than [minPerWeek] (0 = no rule).
  static String? _fewSessionsLine(AralClass c, List<AralSession> sessions, int minPerWeek, String day) {
    if (minPerWeek <= 0) return null;
    final today = DateTime.parse(day);
    if (today.weekday < DateTime.wednesday) return null; // too early in the week to say
    final monday = calendarDate(today.subtract(Duration(days: today.weekday - 1)));
    final n = sessions.where((s) => s.heldOn.compareTo(monday) >= 0 && s.heldOn.compareTo(day) <= 0).length;
    if (n >= minPerWeek) return null;
    return 'Class "${c.className}" has ${n == 1 ? '1 session' : '$n sessions'} this week; '
        'the school asks for at least $minPerWeek.';
  }

  /// The school's ARAL learners waiting for a class or in a class of another
  /// program (one-program classes) or another grade on [day], its classes
  /// without a tutor, and its classes above the school's maximum or below its
  /// minimum (ARAL memo settings).
  Future<List<AralClassNotice>> _aralNotices(int schoolId, String year, String day) async {
    final classes = {for (final c in await _classes.getBySchool(schoolId, schoolYear: year)) c.id!: c};
    final active = (await _roster.getBySchool(schoolId, schoolYear: year)).where((e) => aralActiveOn(e, day)).toList();
    final waiting = [for (final e in active) if (e.classId == null) e];
    final mismatch = [
      for (final e in active)
        if (e.classId != null && classes[e.classId]?.program != null &&
            classes[e.classId]!.program != AralClassProgram.of(e.keyStage, e.track))
          e,
    ];
    final grades = <int, int?>{};
    for (final id in active.map((e) => e.sectionId).toSet()) {
      grades[id] = int.tryParse((await _sections.getById(id))?.gradeLevel ?? '');
    }
    final otherGrade = [
      for (final e in active)
        if (e.classId != null && classes[e.classId] != null && grades[e.sectionId] != null &&
            grades[e.sectionId] != classes[e.classId]!.gradeLevel)
          e,
    ];
    final learnersOf = <int, Map<int, Student>>{}; // section id -> student id -> learner
    Future<List<ReminderLearner>> named(List<AralEnrollment> list) async {
      final out = <ReminderLearner>[];
      for (final e in list) {
        final st = (learnersOf[e.sectionId] ??=
            {for (final st in await _students.getBySection(e.sectionId)) st.id!: st})[e.studentId];
        out.add(st == null
            ? ReminderLearner(e.studentId, '', 'student ${e.studentId}', e.id)
            : ReminderLearner(st.id!, st.lrn, _name(st), e.id));
      }
      return out..sort(_byName);
    }

    String learners(int n) => n == 1 ? '1 ARAL learner' : '$n ARAL learners';
    final rules = AralRuleSettings.fromMap({
      ...?(await _aralSettings.getRegion())?.settings,
      ...?(await _aralSettings.getForSchool(schoolId))?.settings,
    });
    final placed = <int, int>{};
    for (final e in active) {
      if (e.classId != null && classes.containsKey(e.classId)) placed[e.classId!] = (placed[e.classId!] ?? 0) + 1;
    }
    String count(int n) => n == 1 ? '1 active learner' : '$n active learners';
    final byName = classes.values.toList()..sort((a, b) => a.className.compareTo(b.className));
    return [
      if (waiting.isNotEmpty)
        AralClassNotice(AralClassNoticeKind.waiting, '${learners(waiting.length)} waiting for a class.',
            learners: await named(waiting)),
      if (mismatch.isNotEmpty)
        AralClassNotice(AralClassNoticeKind.programMismatch,
            '${learners(mismatch.length)} in a class of another program.', learners: await named(mismatch)),
      if (otherGrade.isNotEmpty)
        AralClassNotice(AralClassNoticeKind.otherGrade,
            '${learners(otherGrade.length)} in a class of another grade.', learners: await named(otherGrade)),
      for (final c in classes.values.where((c) => c.tutorId == null))
        AralClassNotice(AralClassNoticeKind.noTutor, 'Class "${c.className}" has no tutor.', aralClass: c),
      for (final c in byName)
        if ((placed[c.id] ?? 0) > rules.classMaxLearners)
          AralClassNotice(
              AralClassNoticeKind.overMax,
              'Class "${c.className}" has ${count(placed[c.id]!)}, more than the maximum ${rules.classMaxLearners}: '
              'move learners to another class. Their records stay.',
              aralClass: c),
      for (final c in byName)
        if (placed.containsKey(c.id))
          if (_fewSessionsLine(c, await _aralSessions.getByClass(c.id!), rules.classMinSessionsPerWeek, day)
              case final line?)
            AralClassNotice(AralClassNoticeKind.fewSessionsThisWeek, line, aralClass: c),
      for (final c in byName)
        if ((placed[c.id] ?? 0) > 0 && placed[c.id]! < rules.classMinLearners)
          AralClassNotice(
              AralClassNoticeKind.underMin,
              'Class "${c.className}" has ${count(placed[c.id]!)}, fewer than ${rules.classMinLearners}: '
              'combine it with the nearest level of the same grade if there is one.',
              aralClass: c),
      for (final c in byName)
        if (placed.containsKey(c.id))
          if (await _noImprovementLearners(c.id!, day, (e) async => (await named([e])).single) case final flagged
              when flagged.isNotEmpty)
            AralClassNotice(AralClassNoticeKind.noImprovement, _noImprovementLine(c, flagged.length),
                learners: flagged, aralClass: c),
    ];
  }

  /// The class's learners with no improvement on [day], by name, with their
  /// reasons; [named] gives a roster row its learner (LRN and name).
  Future<List<ReminderLearner>> _noImprovementLearners(
      int classId, String day, Future<ReminderLearner> Function(AralEnrollment e) named) async {
    final out = <ReminderLearner>[];
    for (final f in await _aralClasses.noImprovement(classId, asOf: day)) {
      final l = await named(f.progress.enrollment);
      out.add(ReminderLearner.flagged(l.studentId, l.lrn, l.name, f.progress.enrollment.id!,
          [for (final r in f.reasons) r.message]));
    }
    return out..sort(_byName);
  }

  static String _noImprovementLine(AralClass c, int n) =>
      'Class "${c.className}": ${n == 1 ? '1 learner shows' : '$n learners show'} no improvement.';

  /// Reminders for tutor [tutorId] in [year] as of [today] (default now), from
  /// this device's copy. Callers: the tutor themself, an admin/coordinator of
  /// the tutor's school, or the superadmin.
  Future<TutorReminders> tutorReminders(String tutorId, String year, {DateTime? today}) async {
    _log('tutorReminders($tutorId, $year, today: $today)');
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException(notSignedInMessage);
    try {
      year = normalizeSchoolYear(year);
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
    final day = calendarDate(today ?? DateTime.now());
    bool byToday(String date) => date.substring(0, 10).compareTo(day) <= 0;

    // The tutor's sections of the year (local assignments) and ARAL roster
    // active on [day]: entered by then and not exited by then (a learner who
    // left later was still theirs that day).
    final sections = <Section>[];
    for (final a in await _assignments.getByTutor(tutorId)) {
      final s = await _sections.getById(a.sectionId);
      if (s != null && s.schoolYear == year) sections.add(s);
    }
    final roster = (await _roster.getByTutor(tutorId, schoolYear: year)).where((e) => aralActiveOn(e, day)).toList();

    // Access. The tutor's school is their users row, or, when that row is not
    // on this device or has no school, the schools of their sections/roster.
    final tutor = await _users.getById(tutorId);
    final schools = tutor?.schoolId != null
        ? {tutor!.schoolId!}
        : {...sections.map((s) => s.schoolId), ...roster.map((e) => e.schoolId)};
    if (me.role == UserRole.tutor) {
      if (tutorId != me.id) throw const ViewModelException('Not allowed: a tutor sees only their own reminders.');
    } else {
      if (tutor == null && schools.isEmpty) throw ViewModelException('No tutor $tutorId on this device.');
      if (tutor != null && tutor.role != UserRole.tutor) throw ViewModelException('${tutor.fullName} is not a tutor.');
      if (me.schoolId != null && !schools.contains(me.schoolId)) {
        throw const ViewModelException('Not allowed: that tutor is not of your school.');
      }
    }

    // The tutor's classes of the year and their sessions held by today.
    final classes = await _classes.getByTutor(tutorId, schoolYear: year);
    final heldIn = {
      for (final c in classes) c.id!: (await _aralSessions.getByClass(c.id!)).where((s) => byToday(s.heldOn)).toList(),
    };
    final held = [for (final list in heldIn.values) ...list];
    String? latest(Iterable<String> days) => days.isEmpty ? null : days.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    final lastSession = latest(held.map((s) => s.heldOn));
    final schoolId = me.schoolId != null && schools.contains(me.schoolId)
        ? me.schoolId
        : (schools.isEmpty ? null : (schools.toList()..sort()).first);
    final idleDays = schoolId == null
        ? AralSessionSettings.defaults.idleSessionDays
        : AralSessionSettings.fromMap({
            ...?(await _aralSettings.getRegion())?.settings,
            ...?(await _aralSettings.getForSchool(schoolId))?.settings,
          }).idleSessionDays;

    final learnersOf = <int, Map<int, Student>>{}; // section id -> student id -> learner
    Future<Map<int, Student>> sectionLearners(int sectionId) async =>
        learnersOf[sectionId] ??= {for (final st in await _students.getBySection(sectionId)) st.id!: st};
    Future<ReminderLearner> rosterLearner(AralEnrollment e) async {
      final st = (await sectionLearners(e.sectionId))[e.studentId];
      return st == null
          ? ReminderLearner(e.studentId, '', 'student ${e.studentId}', e.id)
          : ReminderLearner(st.id!, st.lrn, _name(st), e.id);
    }

    final out = <TutorReminder>[];

    // MOSY and EOSY of a learner active in an ARAL class with a tutor are the
    // class tutor's (spec 2026-11-27 ARAL class tutor D1; the reading
    // coordinator's rule): they leave the section lines (1) and go on the class
    // lines (1b). BOSY stays with the section's tutors.
    bool classTutorsRound(String round) => round != 'bosy';
    // One Phil-IRI result per learner and section, and one CRLA list per
    // section, for the whole call: the section and class lines share them
    // (final review I4; a tutor's phone reads these per dashboard load).
    final philIriOf = <(int, int), PhilIriReportResults>{};
    Future<PhilIriReportResults> philIriResults(int studentId, int sectionId) async =>
        philIriOf[(studentId, sectionId)] ??=
            await _reports.learnerResults(studentId: studentId, sectionId: sectionId, schoolYear: year, asOf: day);
    final crlaOf = <int, List<CrlaResult>>{};
    Future<List<CrlaResult>> crlaResults(int sectionId) async =>
        crlaOf[sectionId] ??= await _crlaResults.getBySection(sectionId, schoolYear: year);
    Future<bool> assessedIn(CalendarInstrument instrument, int studentId, int sectionId, String round) async {
      if (instrument == CalendarInstrument.philIri) {
        return NlaReportViewModel.assessedIn(await philIriResults(studentId, sectionId))
            .contains(PhilIriRound.values.byName(round));
      }
      return (await crlaResults(sectionId))
          .any((r) => r.studentId == studentId && r.round.name == round && _day(r.assessedAt).compareTo(day) <= 0);
    }
    final classById = <int, AralClass?>{};
    Future<Set<int>> handedOver(int sectionId) async {
      final ids = <int>{};
      for (final e in await _roster.getBySection(sectionId, schoolYear: year)) {
        if (e.classId == null || !aralActiveOn(e, day)) continue;
        final c = classById.containsKey(e.classId) ? classById[e.classId] : (classById[e.classId!] = await _classes.findById(e.classId!));
        // A class not on this device is another tutor's (a tutor's device
        // holds only their own classes); a class without a tutor keeps its
        // learners with the section's tutors.
        if (c == null || c.tutorId != null) ids.add(e.studentId);
      }
      return ids;
    }

    // 1. Learners not assessed, per assigned section of the year and per
    // scheduled round that is open or closed.
    for (final s in sections) {
      final grade = int.tryParse(s.gradeLevel);
      final CalendarInstrument instrument;
      if (philIriGradeOf(s.gradeLevel) != null) {
        instrument = CalendarInstrument.philIri;
      } else if (grade != null && grade >= 1 && grade <= 3) {
        instrument = CalendarInstrument.crla;
      } else {
        continue;
      }
      final all = await sectionLearners(s.id!);
      if (all.isEmpty) continue;
      final handed = await handedOver(s.id!);
      Map<int, PhilIriReportResults>? philIri; // per learner, computed once per section
      for (final entry in await _calendar.scheduledRounds(s.schoolId, year, instrument)) {
        final w = entry.window;
        final status = _calendar.status(w, today: today);
        if (status == RoundStatus.upcoming) continue;
        final learners = classTutorsRound(w.round)
            ? {for (final e in all.entries) if (!handed.contains(e.key)) e.key: e.value}
            : all;
        if (learners.isEmpty) continue;
        final Set<int> assessed;
        if (instrument == CalendarInstrument.philIri) {
          philIri ??= {
            for (final id in all.keys) id: await philIriResults(id, s.id!),
          };
          final round = PhilIriRound.values.byName(w.round);
          assessed = {
            for (final e in philIri.entries)
              if (NlaReportViewModel.assessedIn(e.value).contains(round)) e.key,
          };
          // Every learner must have a GST (reading coordinator, 2026-11-09;
          // spec D13): a BOSY line for learners without one, read or not.
          if (round == PhilIriRound.bosy) {
            final noGst = [
              for (final st in learners.values)
                if (!philIri[st.id]!.gstTaken) ReminderLearner(st.id!, st.lrn, _name(st)),
            ]..sort(_byName);
            if (noGst.isNotEmpty) {
              final closed = status == RoundStatus.closed;
              out.add(TutorReminder(
                TutorReminderKind.noGst,
                'Phil-IRI BOSY: ${noGst.length} of ${learners.length} '
                'learner${learners.length == 1 ? '' : 's'} of Grade ${s.gradeLevel} ${s.sectionName} have no GST.',
                noGst,
                section: s,
                instrument: instrument,
                window: w,
                days: closed ? _daysBetween(w.closesOn!, day) : _daysBetween(day, w.closesOn!),
              ));
            }
          }
        } else {
          assessed = await _crlaAssessed(s.id!, year, CrlaRound.values.byName(w.round), day, learners.keys.toSet());
        }
        final missing = [
          for (final st in learners.values)
            if (!assessed.contains(st.id)) ReminderLearner(st.id!, st.lrn, _name(st)),
        ]..sort(_byName);
        if (missing.isEmpty) continue;
        final closed = status == RoundStatus.closed;
        final days = closed ? _daysBetween(w.closesOn!, day) : _daysBetween(day, w.closesOn!);
        final when = closed
            ? 'closed ${_n(days)} ago'
            : (days == 0 ? 'closes today' : 'closes in ${_n(days)}');
        out.add(TutorReminder(
          closed ? TutorReminderKind.overdueAssessment : TutorReminderKind.openAssessment,
          '${instrument.label} ${roundLabel(w.round)} $when: ${missing.length} of ${learners.length} '
          'learner${learners.length == 1 ? '' : 's'} of Grade ${s.gradeLevel} ${s.sectionName} not assessed.',
          missing,
          section: s,
          instrument: instrument,
          window: w,
          days: days,
        ));
      }
    }

    // 1b. Per class of the tutor: its active learners not assessed in a MOSY
    // or EOSY round that is open or closed, per instrument (by each learner's
    // section grade; a mixed-grade class can get both); assessed as on their
    // section's line.
    for (final cls in classes) {
      final byInstrument = <CalendarInstrument, List<AralEnrollment>>{};
      for (final e in roster.where((e) => e.classId == cls.id)) {
        final sec = await _sections.getById(e.sectionId);
        final instrument = sec == null ? null : _instrumentOf(sec.gradeLevel);
        if (instrument != null) (byInstrument[instrument] ??= []).add(e);
      }
      for (final MapEntry(key: instrument, value: members) in byInstrument.entries) {
        for (final entry in await _calendar.scheduledRounds(cls.schoolId, year, instrument)) {
          final w = entry.window;
          if (!classTutorsRound(w.round)) continue;
          final status = _calendar.status(w, today: today);
          if (status == RoundStatus.upcoming) continue;
          final missing = <ReminderLearner>[
            for (final e in members)
              if (!await assessedIn(instrument, e.studentId, e.sectionId, w.round)) await rosterLearner(e),
          ]..sort(_byName);
          if (missing.isEmpty) continue;
          final closed = status == RoundStatus.closed;
          final days = closed ? _daysBetween(w.closesOn!, day) : _daysBetween(day, w.closesOn!);
          final when = closed
              ? 'closed ${_n(days)} ago'
              : (days == 0 ? 'closes today' : 'closes in ${_n(days)}');
          out.add(TutorReminder(
            closed ? TutorReminderKind.overdueAssessment : TutorReminderKind.openAssessment,
            '${instrument.label} ${roundLabel(w.round)} $when: ${missing.length} of ${members.length} '
            'learner${members.length == 1 ? '' : 's'} of ARAL class ${cls.className} not assessed.',
            missing,
            instrument: instrument,
            window: w,
            days: days,
            aralClass: cls,
          ));
        }
      }
    }

    // 2. Check-ins due, per class: after the class's first / second check-in
    // session (the school's checkin_after_sessions, default 16 and 32; the
    // tools and saved check-ins keep the checkpoint ids 16 and 32), active
    // learners whose program has a tool at that checkpoint and no attempt at
    // one by today.
    final rulesOf = <int, AralRuleSettings>{};
    Future<AralRuleSettings> rules(int schoolId) async => rulesOf[schoolId] ??= AralRuleSettings.fromMap({
          ...?(await _aralSettings.getRegion())?.settings,
          ...?(await _aralSettings.getForSchool(schoolId))?.settings,
        });
    for (final cls in classes) {
      final after = (await rules(cls.schoolId)).checkinAfterSessions;
      for (final (i, checkpoint) in aralCheckinCheckpoints.indexed) {
        final classHeld = heldIn[cls.id]!.length;
        if (classHeld < after[i]) continue;
        final due = <ReminderLearner>[];
        for (final e in roster.where((e) => e.classId == cls.id)) {
          if (e.track == null || await _checkins.toolFor(e.keyStage, e.track!, checkpoint) == null) continue;
          var took = false;
          for (final c in await _checkins.checkins(e.id!)) {
            if (!byToday(c.takenOn)) continue;
            if ((await _checkins.findTool(c.toolId))?.checkpoint == checkpoint) {
              took = true;
              break;
            }
          }
          if (!took) due.add(await rosterLearner(e));
        }
        if (due.isEmpty) continue;
        due.sort(_byName);
        out.add(TutorReminder(
          TutorReminderKind.checkinDue,
          'Class "${cls.className}": check-in due (session ${after[i]} done; $classHeld held): ${due.length} '
          'learner${due.length == 1 ? '' : 's'} without one.',
          due,
          checkpoint: checkpoint,
          aralClass: cls,
        ));
      }
    }

    // 2b. Learners with no improvement, per own class (spec 2026-11-27 ARAL
    // effectiveness D1): the class's learners, whatever this device's roster.
    for (final cls in classes) {
      final flagged = await _noImprovementLearners(cls.id!, day, rosterLearner);
      if (flagged.isEmpty) continue;
      out.add(TutorReminder(TutorReminderKind.noImprovement, _noImprovementLine(cls, flagged.length), flagged,
          aralClass: cls));
    }

    // 3. Active ARAL learners without an IRIP.
    final noIrip = <ReminderLearner>[];
    for (final e in roster) {
      // Weeks added after today did not exist yet (created_at is UTC; a week
      // added just after local midnight counts a day early).
      final weeks = (await _irip.weeks(e.id!)).where((w) => w.createdAt == null || byToday(w.createdAt!));
      if (weeks.isEmpty) noIrip.add(await rosterLearner(e));
    }
    if (noIrip.isNotEmpty) {
      noIrip.sort(_byName);
      out.add(TutorReminder(TutorReminderKind.noIrip,
          '${noIrip.length} ARAL learner${noIrip.length == 1 ? ' has' : 's have'} no IRIP.', noIrip));
    }

    // 4. No session lately, per class with active ARAL learners.
    for (final c in classes) {
      if (!roster.any((e) => e.classId == c.id)) continue;
      final last = latest(heldIn[c.id]!.map((s) => s.heldOn));
      if (last == null) {
        out.add(TutorReminder(TutorReminderKind.noSessionLately,
            'Class "${c.className}": no session yet this school year.', const [], aralClass: c));
      } else {
        final since = _daysBetween(last, day);
        if (since > idleDays) {
          out.add(TutorReminder(TutorReminderKind.noSessionLately,
              'Class "${c.className}": no session since $last (${_n(since)}; reminded after ${_n(idleDays)}).',
              const [], days: since, aralClass: c));
        }
      }
    }

    // 5. Fewer sessions this week than the school asks for (ARAL memo
    // settings, class_min_sessions_per_week), per class with active learners.
    for (final c in classes) {
      if (!roster.any((e) => e.classId == c.id)) continue;
      final line = _fewSessionsLine(c, heldIn[c.id]!, (await rules(c.schoolId)).classMinSessionsPerWeek, day);
      if (line != null) out.add(TutorReminder(TutorReminderKind.fewSessionsThisWeek, line, const [], aralClass: c));
    }

    int sectionOrder(TutorReminder r) {
      final s = r.section;
      return s == null ? 0 : (int.tryParse(s.gradeLevel) ?? 0);
    }

    out.sort((a, b) {
      var c = a.kind.index.compareTo(b.kind.index);
      if (c != 0) return c;
      if (a.kind == TutorReminderKind.overdueAssessment) c = b.days!.compareTo(a.days!);
      if (a.kind == TutorReminderKind.openAssessment) c = a.days!.compareTo(b.days!);
      if (c != 0) return c;
      c = sectionOrder(a).compareTo(sectionOrder(b));
      if (c != 0) return c;
      c = (a.section?.sectionName ?? '').compareTo(b.section?.sectionName ?? '');
      if (c != 0) return c;
      c = (a.instrument?.index ?? 0).compareTo(b.instrument?.index ?? 0);
      if (c != 0) return c;
      final ra = a.window == null ? 0 : calendarRounds[a.instrument]!.indexOf(a.window!.round);
      final rb = b.window == null ? 0 : calendarRounds[b.instrument]!.indexOf(b.window!.round);
      if (ra != rb) return ra.compareTo(rb);
      c = (a.aralClass?.className ?? '').compareTo(b.aralClass?.className ?? '');
      return c != 0 ? c : (a.checkpoint ?? 0).compareTo(b.checkpoint ?? 0);
    });
    return TutorReminders(tutorId, tutor?.fullName ?? (tutorId == me.id ? me.fullName : null), year, held.length,
        lastSession, idleDays, out);
  }

  static String _name(Student st) => '${st.lastName.toUpperCase()}, ${st.firstName}';
  static int _byName(ReminderLearner a, ReminderLearner b) => a.name.compareTo(b.name);
  static String _n(int d) => d == 1 ? '1 day' : '$d days';

  /// CRLA completion of [round] in [schoolId] in [year] as of [today] (default
  /// now): per Grade 1-3 section with learners, by grade then name. The same
  /// numbers the coordinator reminders use. [doneThreshold] (a share) overrides
  /// the saved setting. Admin/coordinator of the school, or the superadmin.
  Future<List<SectionCompletion>> crlaCompletion(int schoolId, String year, CrlaRound round,
      {DateTime? today, double? doneThreshold}) async {
    _log('crlaCompletion($schoolId, $year, ${round.name}, today: $today, done: $doneThreshold)');
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException(notSignedInMessage);
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Not allowed: only an admin or coordinator sees CRLA completion.');
    }
    if (me.schoolId != null && schoolId != me.schoolId) {
      throw const ViewModelException('Not allowed: that school is not yours.');
    }
    if (doneThreshold != null && !(doneThreshold > 0 && doneThreshold <= 1)) {
      throw ViewModelException('The done threshold is a share above 0 and up to 1 (got $doneThreshold).');
    }
    try {
      year = normalizeSchoolYear(year);
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
    final threshold = doneThreshold ?? (await _reportSettings.effective(schoolId)).doneThreshold;
    return _crlaCompletion(schoolId, year, round, calendarDate(today ?? DateTime.now()), threshold);
  }

  /// Per Grade 1-3 section of the school with learners: how many of its
  /// learners have a crla_results row of [round] in that section dated on or
  /// before [asOf] (several attempts count once); done as in progress
  /// monitoring (counts, not the rounded share).
  Future<List<SectionCompletion>> _crlaCompletion(
      int schoolId, String year, CrlaRound round, String asOf, double threshold) async {
    final sections = (await _sections.getAll()).where((s) {
      final g = int.tryParse(s.gradeLevel);
      return s.schoolId == schoolId && s.schoolYear == year && g != null && g >= 1 && g <= 3;
    }).toList()
      ..sort((a, b) {
        final g = int.parse(a.gradeLevel).compareTo(int.parse(b.gradeLevel));
        return g != 0 ? g : a.sectionName.compareTo(b.sectionName);
      });
    final out = <SectionCompletion>[];
    for (final s in sections) {
      final learners = {for (final st in await _students.getBySection(s.id!)) st.id!};
      if (learners.isEmpty) continue;
      final assessed = await _crlaAssessed(s.id!, year, round, asOf, learners);
      out.add(SectionCompletion(
          s, assessed.length, learners.length, assessed.length >= threshold * learners.length - 1e-9));
    }
    return out;
  }

  /// Of [learners] (student ids of section [sectionId]): those with a
  /// crla_results row of [round] in that section dated on or before [asOf]
  /// (several attempts count once). The one CRLA "assessed" test of the
  /// coordinator and tutor reminders.
  /// The instrument of a section's grade: Phil-IRI (Grades 4-10), CRLA
  /// (Grades 1-3), else none.
  static CalendarInstrument? _instrumentOf(String gradeLevel) {
    if (philIriGradeOf(gradeLevel) != null) return CalendarInstrument.philIri;
    final grade = int.tryParse(gradeLevel);
    return grade != null && grade >= 1 && grade <= 3 ? CalendarInstrument.crla : null;
  }

  Future<Set<int>> _crlaAssessed(int sectionId, String year, CrlaRound round, String asOf, Set<int> learners) async => {
        for (final r in await _crlaResults.getBySection(sectionId, schoolYear: year))
          if (r.round == round && learners.contains(r.studentId) && _day(r.assessedAt).compareTo(asOf) <= 0)
            r.studentId,
      };

  static String _day(String timestamp) => timestamp.length >= 10 ? timestamp.substring(0, 10) : timestamp;

  /// Whole days from [from] to [to] (both YYYY-MM-DD).
  static int _daysBetween(String from, String to) =>
      DateTime.utc(int.parse(to.substring(0, 4)), int.parse(to.substring(5, 7)), int.parse(to.substring(8, 10)))
          .difference(DateTime.utc(
              int.parse(from.substring(0, 4)), int.parse(from.substring(5, 7)), int.parse(from.substring(8, 10))))
          .inDays;
}
