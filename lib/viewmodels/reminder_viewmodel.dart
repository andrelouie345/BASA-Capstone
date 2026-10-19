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
// Tutor reminders (D3): per learner, not per section (a tutor is reminded about
// each learner even when the section passed the done threshold), over the
// tutor's assigned sections (tutor_section_assignments, mirrored locally) and
// ARAL roster (aral_enrollments.tutor_id): learners not assessed in open or
// closed rounds, check-ins due after the tutor's 16th/32nd session (the tutor's
// count, also for learners who joined later; owner 2026-10-19), ARAL learners
// without an IRIP, and no session for more than idle_session_days. Nothing
// dated after today counts.
import '../core/console/logger.dart';
import '../core/models/assessment_calendar.dart';
import '../core/models/crla_assessment.dart' show CrlaRound;
import '../core/models/phil_iri_assessment.dart' show PhilIriRound;
import '../core/models/report_setting.dart';
import '../core/models/section.dart';
import '../core/models/user_role.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/student.dart';
import '../core/repositories/aral_checkin_repository.dart';
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
import '../core/services/aral_rules.dart' show AralSessionSettings;
import '../core/services/phil_iri_rules.dart' show philIriGradeOf;
import '../core/services/calendar_rules.dart';
import '../core/services/normalizers.dart';
import 'auth_viewmodel.dart';
import 'nla_report_viewmodel.dart';
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

  const SchoolReminders(this.schoolId, this.schoolName, this.doneThreshold, this.reminders);
}

/// In display order (spec D3): overdue assessments, check-ins due, open-round
/// assessments, no IRIP, no session lately.
enum TutorReminderKind { overdueAssessment, checkinDue, openAssessment, noIrip, noSessionLately }

class ReminderLearner {
  final int studentId;
  final String lrn;
  final String name; // "LAST, First"
  final int? enrollmentId; // the ARAL roster row (check-in / IRIP reminders)

  const ReminderLearner(this.studentId, this.lrn, this.name, [this.enrollmentId]);
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

  /// Days since closes_on (overdue), until closes_on (open, 0 = today), or
  /// since the last session (no session lately; null when none this year).
  final int? days;

  /// By last name, first name.
  final List<ReminderLearner> learners;

  const TutorReminder(this.kind, this.message, this.learners,
      {this.section, this.instrument, this.window, this.checkpoint, this.days});
}

class TutorReminders {
  final String tutorId;
  final String? tutorName;
  final String schoolYear;

  /// The tutor's ARAL sessions of the year held on or before today.
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
    Logger? logger,
  })  : _auth = auth,
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
    if (me == null) throw const ViewModelException('Not signed in.');
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: only an admin or coordinator sees coordinator reminders.');
    }
    if (me.schoolId != null && schoolId == null) {
      throw const ViewModelException('Forbidden: only the superadmin sees the reminders of every school.');
    }
    if (me.schoolId != null && schoolId != me.schoolId) {
      throw const ViewModelException('Forbidden: that school is not yours.');
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
    return SchoolReminders(schoolId, name, threshold, out);
  }

  /// Reminders for tutor [tutorId] in [year] as of [today] (default now), from
  /// this device's copy. Callers: the tutor themself, an admin/coordinator of
  /// the tutor's school, or the superadmin.
  Future<TutorReminders> tutorReminders(String tutorId, String year, {DateTime? today}) async {
    _log('tutorReminders($tutorId, $year, today: $today)');
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException('Not signed in.');
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
    final roster = (await _roster.getByTutor(tutorId, schoolYear: year))
        .where((e) => byToday(e.enteredOn) && (e.exitedOn == null || !byToday(e.exitedOn!)))
        .toList();

    // Access. The tutor's school is their users row, or, when that row is not
    // on this device or has no school, the schools of their sections/roster.
    final tutor = await _users.getById(tutorId);
    final schools = tutor?.schoolId != null
        ? {tutor!.schoolId!}
        : {...sections.map((s) => s.schoolId), ...roster.map((e) => e.schoolId)};
    if (me.role == UserRole.tutor) {
      if (tutorId != me.id) throw const ViewModelException('Forbidden: a tutor sees only their own reminders.');
    } else {
      if (tutor == null && schools.isEmpty) throw ViewModelException('No tutor $tutorId on this device.');
      if (tutor != null && tutor.role != UserRole.tutor) throw ViewModelException('${tutor.fullName} is not a tutor.');
      if (me.schoolId != null && !schools.contains(me.schoolId)) {
        throw const ViewModelException('Forbidden: that tutor is not of your school.');
      }
    }

    final held = (await _aralSessions.getByTutor(tutorId, schoolYear: year)).where((s) => byToday(s.heldOn)).toList();
    final lastSession = held.isEmpty ? null : held.map((s) => s.heldOn).reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
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
      final learners = await sectionLearners(s.id!);
      if (learners.isEmpty) continue;
      Map<int, Set<PhilIriRound>>? philIri; // per learner, computed once per section
      for (final entry in await _calendar.scheduledRounds(s.schoolId, year, instrument)) {
        final w = entry.window;
        final status = _calendar.status(w, today: today);
        if (status == RoundStatus.upcoming) continue;
        final Set<int> assessed;
        if (instrument == CalendarInstrument.philIri) {
          philIri ??= {
            for (final id in learners.keys)
              id: await _reports.assessedPhilIriRounds(studentId: id, sectionId: s.id!, schoolYear: year, asOf: day),
          };
          final round = PhilIriRound.values.byName(w.round);
          assessed = {for (final e in philIri.entries) if (e.value.contains(round)) e.key};
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

    // 2. Check-ins due: after the tutor's 16th / 32nd session, active learners
    // whose program has a tool at that checkpoint and no attempt at one by today.
    for (final checkpoint in aralCheckinCheckpoints) {
      if (held.length < checkpoint) continue;
      final due = <ReminderLearner>[];
      for (final e in roster) {
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
        'Check-in after session $checkpoint due (${held.length} sessions held): ${due.length} '
        'learner${due.length == 1 ? '' : 's'} without one.',
        due,
        checkpoint: checkpoint,
      ));
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

    // 4. No session lately (only with active ARAL learners).
    if (roster.isNotEmpty) {
      if (lastSession == null) {
        out.add(const TutorReminder(TutorReminderKind.noSessionLately, 'No ARAL session yet this school year.', []));
      } else {
        final since = _daysBetween(lastSession, day);
        if (since > idleDays) {
          out.add(TutorReminder(TutorReminderKind.noSessionLately,
              'Last ARAL session ${_n(since)} ago ($lastSession); reminded after ${_n(idleDays)}.', const [],
              days: since));
        }
      }
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
      return ra != rb ? ra.compareTo(rb) : (a.checkpoint ?? 0).compareTo(b.checkpoint ?? 0);
    });
    return TutorReminders(tutorId, tutor?.fullName ?? (tutorId == me.id ? me.fullName : null), year, held.length,
        lastSession, idleDays, out);
  }

  static String _name(Student st) => '${st.lastName.toUpperCase()}, ${st.firstName}';
  static int _byName(ReminderLearner a, ReminderLearner b) => a.name.compareTo(b.name);
  static String _n(int d) => d == 1 ? '1 day' : '$d days';

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
