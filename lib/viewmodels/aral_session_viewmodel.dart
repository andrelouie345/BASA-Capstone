// lib/viewmodels/aral_session_viewmodel.dart
//
// ARAL-Reading session log and attendance (piece A2b). Offline-first: reads
// and writes the local copy, like the roster (AralViewModel).
//
// Owner decisions (2026-10-15):
//  * A session is one tutor's meeting on one date; its learners may come from
//    several sections. The log keeps minutes, set-up, the session number
//    (assigned by the database), lesson and remarks.
//  * Tutors log and edit their own sessions; admins/coordinators any session
//    of their school (for a tutor of that school).
//  * Marks are present / absent / excused. The default list for a session is
//    the tutor's ARAL learners who were in ARAL on that date; a substitute's
//    session may mark other learners of the school (enrollment ids).
//  * One session per tutor per date, unless an admin/coordinator allows
//    several for that tutor (aral_tutor_settings, owner 2026-10-15).
//  * DepEd: at most 1 hour on weekdays (longer is warned about, lastWarning)
//    and 2 hours on weekends (refused). Check-in assessments are due after
//    sessions 16 and 32 (noticed in lastWarning).
import '../core/console/logger.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/aral_session.dart';
import '../core/models/aral_tutor_setting.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/aral_session_repository.dart';
import '../core/repositories/aral_tutor_setting_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/normalizers.dart';
import '../core/services/sync_upload_rules.dart' show pendingLockMessage;
import 'auth_viewmodel.dart';
import '../core/services/auth_messages.dart';
import 'viewmodel_exception.dart';

/// Check-in assessments come after these session numbers (DepEd: 32 sessions,
/// check-ins after 16 and 32).
const aralCheckInAfter = [16, 32];

/// One learner's line on a session's attendance sheet.
class AralSheetLine {
  final AralEnrollment enrollment;
  final AralAttendance? attendance; // null = not marked yet
  /// The session tutor's learner (on the default list); false for a learner
  /// marked from another tutor's group.
  final bool expected;

  const AralSheetLine(this.enrollment, this.attendance, {required this.expected});
}

/// Counts of a learner's (or a group's) marks.
class AralAttendanceSummary {
  final int present;
  final int absent;
  final int excused;

  const AralAttendanceSummary({this.present = 0, this.absent = 0, this.excused = 0});

  int get marked => present + absent + excused;

  /// Present out of the sessions that counted (excused ones don't);
  /// null when nothing counts yet.
  double? get rate => present + absent == 0 ? null : present / (present + absent);

  String get label {
    final r = rate;
    return '$present present, $absent absent, $excused excused'
        '${r == null ? '' : ' (${(r * 100).round()}% attendance)'}';
  }

  static AralAttendanceSummary of(Iterable<AralAttendance> marks) => AralAttendanceSummary(
        present: marks.where((a) => a.mark == AralMark.present).length,
        absent: marks.where((a) => a.mark == AralMark.absent).length,
        excused: marks.where((a) => a.mark == AralMark.excused).length,
      );
}

/// A tutor's year at a glance.
class AralTutorSummary {
  final User tutor;
  final int sessions;
  final int totalMinutes;
  final int? lastSessionNo;
  final int? nextCheckInAfter; // the next check-in's session number; null when both are past
  final int activeLearners;
  final AralAttendanceSummary attendance;
  final bool multipleSessionsPerDay;

  const AralTutorSummary({
    required this.tutor,
    required this.sessions,
    required this.totalMinutes,
    required this.lastSessionNo,
    required this.nextCheckInAfter,
    required this.activeLearners,
    required this.attendance,
    required this.multipleSessionsPerDay,
  });
}

class AralSessionViewModel {
  static const _dbRefusals = [
    'The session tutor must be an active tutor of the school',
    'That learner was not in ARAL in this school on the session date',
    'An ARAL session keeps its tutor, school, year and number; only the date, minutes, set-up, lesson and remarks change',
    'An attendance mark keeps its session and learner; delete it and add a new one instead',
    'This tutor already has an ARAL session on that date (a coordinator can allow several per day)',
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralSessionRepository _sessions;
  final AralEnrollmentRepository _roster;
  final UserRepository _users;
  final StudentRepository _students;
  final AralTutorSettingRepository _settings;

  /// A non-blocking notice from the last write (a long weekday session, a
  /// check-in that is due).
  String? lastWarning;

  AralSessionViewModel({
    required AuthViewModel auth,
    required AralSessionRepository sessions,
    required AralEnrollmentRepository roster,
    required UserRepository users,
    required StudentRepository students,
    required AralTutorSettingRepository settings,
    Logger? logger,
  })  : _auth = auth,
        _settings = settings,
        _sessions = sessions,
        _roster = roster,
        _users = users,
        _students = students,
        _log = ScopedLogger(logger, 'AralSessionViewModel');

  /// Every public method starts here: signed in, online or offline. Screens
  /// call this ViewModel directly, so the console's own check is not enough.
  void _requireSignIn() {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
  }

  // ---- Sessions ----

  /// Logs a session. A tutor logs their own ([tutorId] omitted or their id);
  /// an admin/coordinator names the tutor. [heldOn] defaults to today.
  Future<AralSession> logSession({
    String? tutorId,
    required String schoolYear,
    DateTime? heldOn,
    required int minutes,
    required AralSetup setup,
    String? lesson,
    String? remarks,
  }) async {
    _requireSignIn();
    final me = _me();
    final tid = tutorId ?? me.id;
    _log('logSession(tutor: $tid, year: $schoolYear, on: ${heldOn == null ? 'today' : _date(heldOn)}, '
        'minutes: $minutes, setup: ${setup.value})');
    lastWarning = null;
    schoolYear = normalizeSchoolYear(schoolYear);
    final tutor = await _tutor(tid);
    _canWriteFor(me, tutor);
    final date = _date(heldOn ?? DateTime.now());
    _checkDate(date, schoolYear);
    _checkMinutes(date, minutes);
    await _checkDay(tutor.id, schoolYear, date);

    final stored = await _write(() => _sessions.insertSession(AralSession(
          tutorId: tutor.id,
          schoolId: tutor.schoolId!,
          schoolYear: schoolYear,
          heldOn: date,
          minutes: minutes,
          setup: setup,
          lesson: _blankToNull(lesson),
          remarks: _blankToNull(remarks),
          createdBy: me.id,
        )));
    _log('logged session ${stored.id} (#${stored.sessionNo})');
    _noteCheckIn(stored);
    return stored;
  }

  /// Changes a session's date, minutes, set-up, lesson or remarks. A new date
  /// must still fall inside every marked learner's time in ARAL.
  Future<AralSession> editSession(
    int sessionId, {
    DateTime? heldOn,
    int? minutes,
    AralSetup? setup,
    String? Function()? lesson,
    String? Function()? remarks,
  }) async {
    _requireSignIn();
    _log('editSession($sessionId)');
    lastWarning = null;
    final s = await _requireWritable(sessionId);
    final date = heldOn == null ? s.heldOn : _date(heldOn);
    if (date != s.heldOn) {
      _checkDate(date, s.schoolYear);
      for (final a in await _sessions.getAttendance(sessionId)) {
        final e = await _roster.findById(a.enrollmentId);
        if (e == null || !_inAralOn(e, date)) {
          throw ViewModelException('Learner ${e?.studentId ?? a.enrollmentId} was not in ARAL on $date; '
              'remove their mark first or keep the date.');
        }
      }
      await _checkDay(s.tutorId, s.schoolYear, date, exceptId: s.id);
    }
    final mins = minutes ?? s.minutes;
    _checkMinutes(date, mins);
    return _write(() => _sessions.updateSession(s.copyWith(
          heldOn: date,
          minutes: mins,
          setup: setup,
          lesson: lesson == null ? null : () => _blankToNull(lesson()),
          remarks: remarks == null ? null : () => _blankToNull(remarks()),
        )));
  }

  /// Deletes a session logged by mistake, with its attendance. The session
  /// numbers of later sessions don't change.
  Future<void> deleteSession(int sessionId) async {
    _requireSignIn();
    _log('deleteSession($sessionId)');
    await _requireWritable(sessionId);
    await _write(() => _sessions.deleteSession(sessionId));
  }

  Future<AralSession> getSession(int sessionId) async {
    _requireSignIn();
    return _requireReadable(sessionId);
  }

  /// The signed-in tutor's sessions (or [tutorId]'s, for a coordinator).
  Future<List<AralSession>> tutorSessions({String? tutorId, String? schoolYear}) async {
    _requireSignIn();
    final me = _me();
    final id = tutorId ?? me.id;
    _log('tutorSessions(tutor: $id, year: $schoolYear)');
    if (id != me.id) _canReadTutor(me, await _tutor(id, mustBeActive: false));
    return _sessions.getByTutor(id, schoolYear: schoolYear == null ? null : normalizeSchoolYear(schoolYear));
  }

  Future<List<AralSession>> schoolSessions({required int schoolId, String? schoolYear}) async {
    _requireSignIn();
    _log('schoolSessions(school: $schoolId, year: $schoolYear)');
    final me = _me();
    _requireManager(me);
    if (me.schoolId != null && me.schoolId != schoolId) {
      throw const ViewModelException('Forbidden: that school is not yours.');
    }
    return _sessions.getBySchool(schoolId, schoolYear: schoolYear == null ? null : normalizeSchoolYear(schoolYear));
  }

  // ---- Attendance ----

  /// The session's sheet: the tutor's learners who were in ARAL on the date
  /// (marked or not), plus anyone else marked at it.
  Future<List<AralSheetLine>> sheet(int sessionId) async {
    _requireSignIn();
    _log('sheet($sessionId)');
    final s = await _requireReadable(sessionId);
    final marks = {for (final a in await _sessions.getAttendance(sessionId)) a.enrollmentId: a};
    final lines = <AralSheetLine>[];
    for (final e in await _expected(s)) {
      lines.add(AralSheetLine(e, marks.remove(e.id), expected: true));
    }
    for (final a in marks.values) {
      final e = await _roster.findById(a.enrollmentId);
      if (e != null) lines.add(AralSheetLine(e, a, expected: false));
    }
    return lines;
  }

  /// Marks one learner ([enrollmentId] = ARAL enrollment id); marking again
  /// replaces the mark.
  Future<AralAttendance> mark(int sessionId, int enrollmentId, AralMark mark, {String? note}) async {
    _requireSignIn();
    _log('mark(session: $sessionId, enrollment: $enrollmentId, ${mark.name})');
    final s = await _requireWritable(sessionId);
    final e = await _roster.findById(enrollmentId);
    if (e == null) throw ViewModelException('No ARAL enrollment with id $enrollmentId.');
    if (e.schoolId != s.schoolId || e.schoolYear != s.schoolYear || !_inAralOn(e, s.heldOn)) {
      throw ViewModelException('That learner was not in ARAL in this school on ${s.heldOn}.');
    }
    return _write(() => _sessions.saveAttendance(
        AralAttendance(sessionId: sessionId, enrollmentId: enrollmentId, mark: mark, note: _blankToNull(note))));
  }

  /// Gives every learner on the default list who has no mark yet [mark]
  /// (e.g. everyone present, then mark the absent ones one by one). Returns
  /// the marks written.
  Future<List<AralAttendance>> markRest(int sessionId, AralMark mark) async {
    _requireSignIn();
    _log('markRest(session: $sessionId, ${mark.name})');
    final s = await _requireWritable(sessionId);
    final marked = {for (final a in await _sessions.getAttendance(sessionId)) a.enrollmentId};
    final out = <AralAttendance>[];
    for (final e in await _expected(s)) {
      if (marked.contains(e.id)) continue;
      out.add(await _write(
          () => _sessions.saveAttendance(AralAttendance(sessionId: sessionId, enrollmentId: e.id!, mark: mark))));
    }
    return out;
  }

  /// Removes a learner's mark from the session.
  Future<void> unmark(int sessionId, int enrollmentId) async {
    _requireSignIn();
    _log('unmark(session: $sessionId, enrollment: $enrollmentId)');
    await _requireWritable(sessionId);
    final a = (await _sessions.getAttendance(sessionId)).where((a) => a.enrollmentId == enrollmentId).firstOrNull;
    if (a == null) throw const ViewModelException('That learner has no mark in this session.');
    await _write(() => _sessions.deleteAttendance(a.id!));
  }

  /// One ARAL learner's marks across the year, oldest first.
  Future<(AralAttendanceSummary, List<(AralSession, AralAttendance)>)> learnerAttendance(int enrollmentId) async {
    _requireSignIn();
    _log('learnerAttendance($enrollmentId)');
    final me = _me();
    final e = await _roster.findById(enrollmentId);
    if (e == null) throw ViewModelException('No ARAL enrollment with id $enrollmentId.');
    if (me.role == UserRole.tutor) {
      if (e.tutorId != me.id) throw const ViewModelException('Forbidden: not your ARAL learner.');
    } else if (me.schoolId != null && me.schoolId != e.schoolId) {
      throw const ViewModelException('Forbidden: that learner is in another school.');
    }
    final marks = await _sessions.getAttendanceForEnrollment(enrollmentId);
    final rows = <(AralSession, AralAttendance)>[];
    for (final a in marks) {
      final s = await _sessions.findSession(a.sessionId);
      if (s != null) rows.add((s, a));
    }
    return (AralAttendanceSummary.of(marks), rows);
  }

  /// A tutor's sessions, minutes, next check-in and attendance for the year.
  Future<AralTutorSummary> tutorSummary({String? tutorId, required String schoolYear}) async {
    _requireSignIn();
    final me = _me();
    final id = tutorId ?? me.id;
    _log('tutorSummary(tutor: $id, year: $schoolYear)');
    schoolYear = normalizeSchoolYear(schoolYear);
    final tutor = await _tutor(id, mustBeActive: false);
    if (id != me.id) _canReadTutor(me, tutor);
    final list = await _sessions.getByTutor(id, schoolYear: schoolYear);
    final marks = <AralAttendance>[];
    for (final s in list) {
      marks.addAll(await _sessions.getAttendance(s.id!));
    }
    final last = list.isEmpty ? null : list.map((s) => s.sessionNo ?? 0).reduce((a, b) => a > b ? a : b);
    return AralTutorSummary(
      tutor: tutor,
      sessions: list.length,
      totalMinutes: list.fold(0, (sum, s) => sum + s.minutes),
      lastSessionNo: last,
      nextCheckInAfter: aralCheckInAfter.where((n) => n > (last ?? 0)).firstOrNull,
      activeLearners: (await _roster.getByTutor(id, schoolYear: schoolYear)).where((e) => e.isActive).length,
      attendance: AralAttendanceSummary.of(marks),
      multipleSessionsPerDay: (await _settings.find(id))?.multipleSessionsPerDay ?? false,
    );
  }

  // ---- Per-tutor settings (admin / coordinator) ----

  /// Allows (or stops allowing) [tutorId] to hold several sessions on one
  /// date. Sessions already on the same date stay.
  Future<AralTutorSetting> setMultipleSessionsPerDay(String tutorId, bool allowed) async {
    _requireSignIn();
    _log('setMultipleSessionsPerDay($tutorId, $allowed)');
    final me = _me();
    _requireManager(me);
    final tutor = await _tutor(tutorId);
    _canReadTutor(me, tutor);
    final current = await _settings.find(tutorId);
    return _write(() => _settings.save(AralTutorSetting(
          tutorId: tutorId,
          schoolId: current?.schoolId ?? tutor.schoolId!,
          multipleSessionsPerDay: allowed,
          updatedBy: me.id,
        )));
  }

  Future<bool> allowsMultipleSessionsPerDay(String tutorId) async {
    _requireSignIn();
    return (await _settings.find(tutorId))?.multipleSessionsPerDay ?? false;
  }

  /// "Last, First" by student id for [enrollments] (for sheets and lists).
  Future<Map<int, String>> learnerNames(Iterable<AralEnrollment> enrollments) async {
    _requireSignIn();
    final out = <int, String>{};
    for (final section in enrollments.map((e) => e.sectionId).toSet()) {
      for (final s in await _students.getBySection(section)) {
        out[s.id!] = '${s.lastName}, ${s.firstName}';
      }
    }
    return out;
  }

  // ---- helpers ----

  User _me() {
    final u = _auth.currentUser;
    if (u == null) throw const ViewModelException(notSignedInMessage);
    return u;
  }

  static bool _isManager(User u) => u.role == UserRole.admin || u.role == UserRole.coordinator;

  static void _requireManager(User u) {
    if (!_isManager(u)) throw const ViewModelException('Forbidden: only an admin or coordinator can do that.');
  }

  /// A tutor of the school (active, when logging for them).
  Future<User> _tutor(String id, {bool mustBeActive = true}) async {
    final u = await _users.getById(id);
    if (u == null || u.role != UserRole.tutor || u.schoolId == null || (mustBeActive && !u.isActive)) {
      throw ViewModelException(mustBeActive
          ? 'The session tutor must be an active tutor of the school.'
          : 'No tutor with id $id.');
    }
    return u;
  }

  /// Tutors write their own sessions; admins/coordinators their school's.
  static void _canWriteFor(User me, User tutor) {
    if (me.role == UserRole.tutor) {
      if (me.id != tutor.id) throw const ViewModelException('Forbidden: tutors log only their own sessions.');
      return;
    }
    _canReadTutor(me, tutor);
  }

  static void _canReadTutor(User me, User tutor) {
    if (me.role == UserRole.tutor) {
      if (me.id != tutor.id) throw const ViewModelException("Forbidden: another tutor's sessions.");
      return;
    }
    _requireManager(me);
    if (me.schoolId != null && me.schoolId != tutor.schoolId) {
      throw const ViewModelException('Forbidden: that tutor is in another school.');
    }
  }

  Future<AralSession> _requireReadable(int sessionId) async {
    final s = await _sessions.findSession(sessionId);
    if (s == null) throw ViewModelException('No ARAL session with id $sessionId.');
    final me = _me();
    if (me.role == UserRole.tutor) {
      if (s.tutorId != me.id) throw const ViewModelException("Forbidden: another tutor's session.");
    } else {
      _requireManager(me);
      if (me.schoolId != null && me.schoolId != s.schoolId) {
        throw const ViewModelException('Forbidden: that session is in another school.');
      }
    }
    return s;
  }

  // Same scope as reading (own session, or the school's for a manager).
  Future<AralSession> _requireWritable(int sessionId) => _requireReadable(sessionId);

  /// The session tutor's learners who were in ARAL on the session date.
  Future<List<AralEnrollment>> _expected(AralSession s) async =>
      (await _roster.getByTutor(s.tutorId, schoolYear: s.schoolYear))
          .where((e) => e.schoolId == s.schoolId && _inAralOn(e, s.heldOn))
          .toList();

  static bool _inAralOn(AralEnrollment e, String date) =>
      e.enteredOn.compareTo(date) <= 0 && (e.exitedOn == null || e.exitedOn!.compareTo(date) >= 0);

  /// Not in the future, and inside the school year (June of its first year to
  /// July of its second, generous on both ends).
  static void _checkDate(String date, String schoolYear) {
    if (date.compareTo(_date(DateTime.now())) > 0) {
      throw ViewModelException('The session date $date is in the future.');
    }
    final start = int.parse(schoolYear.substring(0, 4));
    if (date.compareTo('$start-06-01') < 0 || date.compareTo('${start + 1}-07-31') > 0) {
      throw ViewModelException('The session date $date is outside school year $schoolYear.');
    }
  }

  void _checkMinutes(String date, int minutes) {
    if (minutes < 1 || minutes > aralMaxMinutes) {
      throw ViewModelException('A session lasts 1 to $aralMaxMinutes minutes (got $minutes).');
    }
    final weekday = DateTime.parse(date).weekday;
    final weekend = weekday == DateTime.saturday || weekday == DateTime.sunday;
    if (!weekend && minutes > aralWeekdayMaxMinutes) {
      lastWarning = 'A weekday session should last at most $aralWeekdayMaxMinutes minutes ($minutes logged).';
      _log(lastWarning!);
    }
  }

  /// One session per tutor per date unless the tutor is allowed several.
  Future<void> _checkDay(String tutorId, String schoolYear, String date, {int? exceptId}) async {
    if (await allowsMultipleSessionsPerDay(tutorId)) return;
    final same = (await _sessions.getByTutor(tutorId, schoolYear: schoolYear))
        .where((s) => s.heldOn == date && s.id != exceptId)
        .firstOrNull;
    if (same != null) {
      throw ViewModelException('This tutor already has session ${same.sessionNo} (#${same.id}) on $date. '
          'One session per day; an admin/coordinator can allow several for this tutor.');
    }
  }

  void _noteCheckIn(AralSession s) {
    if (!aralCheckInAfter.contains(s.sessionNo)) return;
    final note = 'Session ${s.sessionNo} done: the check-in assessment is due.';
    lastWarning = lastWarning == null ? note : '$lastWarning\n$note';
    _log(note);
  }

  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
      // A record waiting in an upload (sync): say so, whatever else the
      // statement's text happens to contain.
      if ('$e'.contains(pendingLockMessage)) throw const ViewModelException(pendingLockMessage);
      final text = e.toString().toLowerCase();
      for (final refusal in _dbRefusals) {
        if (text.contains(refusal.toLowerCase())) throw ViewModelException('$refusal.');
      }
      if (text.contains('minutes')) throw const ViewModelException('A session lasts 1 to $aralMaxMinutes minutes.');
      rethrow;
    }
  }

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  static String _date(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
