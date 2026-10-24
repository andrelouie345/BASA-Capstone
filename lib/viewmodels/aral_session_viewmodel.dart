// lib/viewmodels/aral_session_viewmodel.dart
//
// ARAL-Reading session log and attendance (piece A2b). Offline-first: reads
// and writes the local copy, like the roster (AralViewModel).
//
// Owner decisions (2026-10-15; ARAL classes 2026-10-23, spec
// docs/superpowers/specs/2026-10-23-aral-classes-design.md decisions 6 and 8):
//  * A session is one ARAL class's meeting on one date; its learners may come
//    from several sections. The log keeps minutes, set-up, the session number
//    (assigned by the database, per class), lesson and remarks, and who held
//    it (the class tutor, or a substitute an admin/coordinator names).
//  * Tutors log sessions for the classes they teach; admins/coordinators for
//    any class of their school. Sessions from before classes keep no class.
//  * Marks are present / absent / excused. The default list for a session is
//    the class's learners who were in ARAL on that date; only an
//    admin/coordinator marks a learner of another class.
//  * One session per class per date (replaces the per-tutor setting).
//  * DepEd: at most 1 hour on weekdays (longer is warned about, lastWarning)
//    and 2 hours on weekends (refused). Check-in assessments are due after a
//    class's sessions 16 and 32 (noticed in lastWarning).
//  * After a move, a learner's marks in their earlier class stay with them
//    (learnerAttendance reads every mark this device holds).
import '../core/console/logger.dart';
import '../core/models/aral_class.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/aral_session.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_class_repository.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/aral_session_repository.dart';
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
  /// On the session's default list (the class's learners); false for a
  /// learner of another class marked at it.
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

/// A tutor's year at a glance, over the classes they teach.
class AralTutorSummary {
  final User tutor;
  final int sessions;
  final int totalMinutes;
  final int? lastSessionNo;    // the highest session number among their classes
  final int? nextCheckInAfter; // the check-in (16 or 32) of the class closest to one; null when all are past
  final int? sessionsToNextCheckIn; // that class's sessions to go
  final int activeLearners;
  final AralAttendanceSummary attendance;

  const AralTutorSummary({
    required this.tutor,
    required this.sessions,
    required this.totalMinutes,
    required this.lastSessionNo,
    required this.nextCheckInAfter,
    required this.sessionsToNextCheckIn,
    required this.activeLearners,
    required this.attendance,
  });
}

/// One ARAL class's year at a glance.
class AralClassSummary {
  final AralClass aralClass;
  final int sessions;
  final int totalMinutes;
  final int? lastSessionNo;
  final int? nextCheckInAfter; // the next check-in's session number; null when both are past
  final int activeLearners;
  final AralAttendanceSummary attendance;

  const AralClassSummary({
    required this.aralClass,
    required this.sessions,
    required this.totalMinutes,
    required this.lastSessionNo,
    required this.nextCheckInAfter,
    required this.activeLearners,
    required this.attendance,
  });
}

class AralSessionViewModel {
  static const _dbRefusals = [
    'The session tutor must be an active tutor of the school',
    'That learner was not in ARAL in this school on the session date',
    'An ARAL session keeps its tutor, class, school, year and number; only the date, minutes, set-up, lesson and remarks change',
    'An attendance mark keeps its session and learner; delete it and add a new one instead',
    'An ARAL class already has a session on that date',
    'A new ARAL session needs a class',
    'The ARAL class belongs to another school or school year',
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralSessionRepository _sessions;
  final AralEnrollmentRepository _roster;
  final UserRepository _users;
  final StudentRepository _students;
  final AralClassRepository _classes;

  /// A non-blocking notice from the last write (a long weekday session, a
  /// check-in that is due).
  String? lastWarning;

  AralSessionViewModel({
    required AuthViewModel auth,
    required AralSessionRepository sessions,
    required AralEnrollmentRepository roster,
    required UserRepository users,
    required StudentRepository students,
    required AralClassRepository classes,
    Logger? logger,
  })  : _auth = auth,
        _classes = classes,
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

  /// Logs a session of the class. A tutor logs for a class they teach, as
  /// themselves; an admin/coordinator for any class of their school, held by
  /// [tutorId] (a substitute) or else the class tutor. The school year is the
  /// class's. [heldOn] defaults to today.
  Future<AralSession> logSession({
    required int classId,
    DateTime? heldOn,
    required int minutes,
    required AralSetup setup,
    String? lesson,
    String? remarks,
    String? tutorId,
  }) async {
    _requireSignIn();
    final me = _me();
    _log('logSession(class: $classId, tutor: ${tutorId ?? 'class tutor'}, '
        'on: ${heldOn == null ? 'today' : _date(heldOn)}, minutes: $minutes, setup: ${setup.value})');
    lastWarning = null;
    final cls = await _class(classId);
    final String tid;
    if (me.role == UserRole.tutor) {
      if (cls.tutorId != me.id || (tutorId != null && tutorId != me.id)) {
        throw const ViewModelException('Forbidden: you can only log sessions for your own classes.');
      }
      tid = me.id;
    } else {
      _requireManager(me);
      if (me.schoolId != null && me.schoolId != cls.schoolId) {
        throw const ViewModelException('Forbidden: that class is in another school.');
      }
      tid = tutorId ??
          cls.tutorId ??
          (throw ViewModelException(
              'Class "${cls.className}" has no tutor yet; set one or name the tutor who held the session.'));
    }
    final tutor = await _tutor(tid);
    if (tutor.schoolId != cls.schoolId) {
      throw const ViewModelException('The session tutor must be an active tutor of the school.');
    }
    final date = _date(heldOn ?? DateTime.now());
    _checkDate(date, cls.schoolYear);
    _checkMinutes(date, minutes);
    await _checkDay(cls, date);

    final stored = await _write(() => _sessions.insertSession(AralSession(
          tutorId: tutor.id,
          schoolId: cls.schoolId,
          schoolYear: cls.schoolYear,
          classId: cls.id,
          heldOn: date,
          minutes: minutes,
          setup: setup,
          lesson: _blankToNull(lesson),
          remarks: _blankToNull(remarks),
          createdBy: me.id,
        )));
    _log('logged session ${stored.id} (class ${cls.id} #${stored.sessionNo})');
    _noteCheckIn(stored, cls);
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
      if (s.classId != null) await _checkDay(await _class(s.classId!), date, exceptId: s.id);
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

  /// The class's sessions, by date (a tutor: the classes they teach).
  Future<List<AralSession>> classSessions(int classId) async {
    _requireSignIn();
    _log('classSessions($classId)');
    await _readableClass(classId);
    return _sessions.getByClass(classId);
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

  /// The session's sheet: the class's learners who were in ARAL on the date
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
    if (_me().role == UserRole.tutor && s.classId != null && e.classId != s.classId) {
      throw const ViewModelException('Only an admin or coordinator can mark a learner of another class.');
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

  /// One ARAL learner's marks across the year, oldest first, in every class
  /// they were in (the marks this device holds).
  Future<(AralAttendanceSummary, List<(AralSession, AralAttendance)>)> learnerAttendance(int enrollmentId) async {
    _requireSignIn();
    _log('learnerAttendance($enrollmentId)');
    final me = _me();
    final e = await _roster.findById(enrollmentId);
    if (e == null) throw ViewModelException('No ARAL enrollment with id $enrollmentId.');
    if (me.role == UserRole.tutor) {
      if (await _roster.classTutorId(e.id!) != me.id) {
        throw const ViewModelException('Forbidden: not your ARAL learner.');
      }
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

  /// A tutor's sessions, minutes, next check-in and attendance for the year,
  /// over the classes they teach.
  Future<AralTutorSummary> tutorSummary({String? tutorId, required String schoolYear}) async {
    _requireSignIn();
    final me = _me();
    final id = tutorId ?? me.id;
    _log('tutorSummary(tutor: $id, year: $schoolYear)');
    schoolYear = normalizeSchoolYear(schoolYear);
    final tutor = await _tutor(id, mustBeActive: false);
    if (id != me.id) _canReadTutor(me, tutor);
    final perClass = [
      for (final c in await _classes.getByTutor(id, schoolYear: schoolYear)) await _classSummary(c),
    ];
    final marks = <AralAttendance>[];
    var sessions = 0, minutes = 0;
    for (final c in perClass) {
      sessions += c.sessions;
      minutes += c.totalMinutes;
    }
    for (final c in perClass) {
      for (final s in await _sessions.getByClass(c.aralClass.id!)) {
        marks.addAll(await _sessions.getAttendance(s.id!));
      }
    }
    final lasts = perClass.map((c) => c.lastSessionNo).whereType<int>();
    // The class closest to its next check-in.
    AralClassSummary? soonest;
    for (final c in perClass.where((c) => c.nextCheckInAfter != null)) {
      int toGo(AralClassSummary x) => x.nextCheckInAfter! - (x.lastSessionNo ?? 0);
      if (soonest == null || toGo(c) < toGo(soonest)) soonest = c;
    }
    return AralTutorSummary(
      tutor: tutor,
      sessions: sessions,
      totalMinutes: minutes,
      lastSessionNo: lasts.isEmpty ? null : lasts.reduce((a, b) => a > b ? a : b),
      nextCheckInAfter: soonest?.nextCheckInAfter,
      sessionsToNextCheckIn: soonest == null ? null : soonest.nextCheckInAfter! - (soonest.lastSessionNo ?? 0),
      activeLearners: perClass.fold(0, (sum, c) => sum + c.activeLearners),
      attendance: AralAttendanceSummary.of(marks),
    );
  }

  /// One class's sessions, minutes, next check-in, active learners and
  /// attendance (excused marks don't count against the rate).
  Future<AralClassSummary> classSummary(int classId) async {
    _requireSignIn();
    _log('classSummary($classId)');
    return _classSummary(await _readableClass(classId));
  }

  Future<AralClassSummary> _classSummary(AralClass c) async {
    final list = await _sessions.getByClass(c.id!);
    final marks = <AralAttendance>[];
    for (final s in list) {
      marks.addAll(await _sessions.getAttendance(s.id!));
    }
    final last = list.isEmpty ? null : list.map((s) => s.sessionNo ?? 0).reduce((a, b) => a > b ? a : b);
    return AralClassSummary(
      aralClass: c,
      sessions: list.length,
      totalMinutes: list.fold(0, (sum, s) => sum + s.minutes),
      lastSessionNo: last,
      nextCheckInAfter: aralCheckInAfter.where((n) => n > (last ?? 0)).firstOrNull,
      activeLearners: (await _roster.getByClass(c.id!)).where((e) => e.isActive).length,
      attendance: AralAttendanceSummary.of(marks),
    );
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

  /// The class, if it exists.
  Future<AralClass> _class(int classId) async =>
      await _classes.findById(classId) ?? (throw ViewModelException('No ARAL class with id $classId.'));

  /// The class, if the caller may read it: a tutor the classes they teach; an
  /// admin/coordinator their school's.
  Future<AralClass> _readableClass(int classId) async {
    final c = await _class(classId);
    final me = _me();
    if (me.role == UserRole.tutor) {
      if (c.tutorId != me.id) throw ViewModelException('No ARAL class with id $classId among your classes.');
    } else {
      _requireManager(me);
      if (me.schoolId != null && me.schoolId != c.schoolId) {
        throw const ViewModelException('Forbidden: that class is in another school.');
      }
    }
    return c;
  }

  Future<AralSession> _requireReadable(int sessionId) async {
    final s = await _sessions.findSession(sessionId);
    if (s == null) throw ViewModelException('No ARAL session with id $sessionId.');
    final me = _me();
    if (me.role == UserRole.tutor) {
      // Held by me, or a session of a class I teach.
      final mine = s.tutorId == me.id || (s.classId != null && (await _classes.findById(s.classId!))?.tutorId == me.id);
      if (!mine) throw const ViewModelException("Forbidden: another tutor's session.");
    } else {
      _requireManager(me);
      if (me.schoolId != null && me.schoolId != s.schoolId) {
        throw const ViewModelException('Forbidden: that session is in another school.');
      }
    }
    return s;
  }

  // Same scope as reading (held by me or of my class, or the school's for a manager).
  Future<AralSession> _requireWritable(int sessionId) => _requireReadable(sessionId);

  /// The class's learners who were in ARAL on the session date (for a session
  /// without a class: the learners of the classes its tutor teaches).
  Future<List<AralEnrollment>> _expected(AralSession s) async =>
      (s.classId != null
              ? await _roster.getByClass(s.classId!)
              : await _roster.getByTutor(s.tutorId, schoolYear: s.schoolYear))
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

  /// One session per class per date.
  Future<void> _checkDay(AralClass c, String date, {int? exceptId}) async {
    final same = (await _sessions.getByClass(c.id!)).where((s) => s.heldOn == date && s.id != exceptId).firstOrNull;
    if (same != null) {
      throw ViewModelException('Class "${c.className}" already has session ${same.sessionNo} (#${same.id}) on $date.');
    }
  }

  void _noteCheckIn(AralSession s, AralClass c) {
    if (!aralCheckInAfter.contains(s.sessionNo)) return;
    final note = 'Class "${c.className}": session ${s.sessionNo} done: the check-in assessment is due.';
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
