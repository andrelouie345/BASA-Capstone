// lib/viewmodels/aral_class_viewmodel.dart
//
// ARAL classes (spec docs/superpowers/specs/2026-10-23-aral-classes-design.md).
// Offline-first like the roster: reads and writes this device's copy; the
// classes travel with sync-upload.
//
// Owner decisions (2026-10-23):
//  * A class belongs to a school and a school year (not a section), with one
//    program, one grade band and at most 15 active learners (aral_rules.dart).
//  * One tutor per class, possibly blank for a while; a tutor may teach
//    several classes.
//  * Admins and coordinators create, change and delete classes; a tutor reads
//    the classes they teach.
// The device checks here mirror the cloud triggers, so the device refuses
// first with a readable message.
import '../core/console/logger.dart';
import '../core/models/aral_class.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_class_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/normalizers.dart';
import '../core/services/sync_upload_rules.dart' show pendingLockMessage;
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

class AralClassViewModel {
  /// The local trigger texts, shown as they are.
  static const _dbRefusals = [
    "The ARAL class tutor must be an active tutor of the class's school",
    'An ARAL class keeps its school and school year',
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralClassRepository _classes;
  final UserRepository _users;

  AralClassViewModel({
    required AuthViewModel auth,
    required AralClassRepository classes,
    required UserRepository users,
    Logger? logger,
  })  : _auth = auth,
        _classes = classes,
        _users = users,
        _log = ScopedLogger(logger, 'AralClassViewModel');

  /// Every public method starts here: signed in, online or offline. Screens
  /// call this ViewModel directly, so the console's own check is not enough.
  void _requireSignIn() {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
  }

  // ---- Reading ----

  /// The school's classes for [schoolYear] (all years when null), by name. A
  /// tutor gets only the classes they teach.
  Future<List<AralClass>> classes({required int schoolId, String? schoolYear}) async {
    _requireSignIn();
    _log('classes(school: $schoolId, year: $schoolYear)');
    final year = schoolYear == null ? null : _year(schoolYear);
    final me = _auth.currentUser!;
    if (me.role == UserRole.tutor) {
      return (await _classes.getByTutor(me.id, schoolYear: year)).where((c) => c.schoolId == schoolId).toList();
    }
    _requireOwnSchool(schoolId);
    return _classes.getBySchool(schoolId, schoolYear: year);
  }

  /// One class. A tutor reads only the classes they teach.
  Future<AralClass> getClass(int classId) async {
    _requireSignIn();
    _log('getClass($classId)');
    return _readable(classId);
  }

  // ---- Writing (admin / coordinator) ----

  Future<AralClass> createClass({
    required int schoolId,
    required String schoolYear,
    required String className,
    required AralClassProgram program,
    required AralGradeBand gradeBand,
    String? tutorId,
    String? room,
    String? schedule,
    String? notes,
  }) async {
    _requireSignIn();
    _log('createClass(school: $schoolId, year: $schoolYear, name: $className, ${program.value}, ${gradeBand.value}, '
        'tutor: $tutorId)');
    _requireManager();
    _requireOwnSchool(schoolId);
    final year = _year(schoolYear);
    final name = _name(className);
    await _checkName(schoolId, year, name, null);
    tutorId = _blankToNull(tutorId);
    if (tutorId != null) await _checkTutor(tutorId, schoolId);
    return _write(() => _classes.insert(AralClass(
          schoolId: schoolId,
          schoolYear: year,
          className: name,
          program: program,
          gradeBand: gradeBand,
          tutorId: tutorId,
          room: _blankToNull(room),
          schedule: _blankToNull(schedule),
          notes: _blankToNull(notes),
          createdBy: _auth.currentUser?.id,
        )));
  }

  /// Saves a changed class: name, program, band, tutor, room, schedule,
  /// notes. School and year never change.
  Future<AralClass> editClass(AralClass changed) async {
    _requireSignIn();
    _log('editClass(${changed.id})');
    _requireManager();
    if (changed.id == null) throw const ViewModelException('editClass needs a class id.');
    final current = await _require(changed.id!);
    if (changed.schoolId != current.schoolId || changed.schoolYear != current.schoolYear) {
      throw const ViewModelException('A class keeps its school and school year.');
    }
    final name = _name(changed.className);
    if (name.toLowerCase() != current.className.trim().toLowerCase()) {
      await _checkName(current.schoolId, current.schoolYear, name, current.id);
    }
    final tutorId = _blankToNull(changed.tutorId);
    if (tutorId != null && tutorId != current.tutorId) await _checkTutor(tutorId, current.schoolId);
    return _write(() => _classes.update(changed.copyWith(
          className: name,
          tutorId: () => tutorId,
          room: () => _blankToNull(changed.room),
          schedule: () => _blankToNull(changed.schedule),
          notes: () => _blankToNull(changed.notes),
        )));
  }

  Future<void> deleteClass(int classId) async {
    _requireSignIn();
    _log('deleteClass($classId)');
    _requireManager();
    await _require(classId);
    await _write(() => _classes.delete(classId));
  }

  // ---- helpers ----

  void _requireManager() {
    final role = _auth.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: admin or coordinator only.');
    }
  }

  void _requireOwnSchool(int schoolId) {
    final mine = _auth.currentUser?.schoolId;
    if (mine != null && mine != schoolId) throw const ViewModelException('Forbidden: that school is not yours.');
  }

  /// The class, if the caller may change it (their school, or any for the
  /// superadmin).
  Future<AralClass> _require(int classId) async {
    final c = await _classes.findById(classId);
    if (c == null) throw ViewModelException('No ARAL class with id $classId.');
    final mine = _auth.currentUser?.schoolId;
    if (mine != null && mine != c.schoolId) throw const ViewModelException('Forbidden: that class is in another school.');
    return c;
  }

  Future<AralClass> _readable(int classId) async {
    final me = _auth.currentUser!;
    if (me.role != UserRole.tutor) return _require(classId);
    final c = await _classes.findById(classId);
    if (c == null || c.tutorId != me.id) {
      // A tutor's device holds only their own classes; don't tell apart
      // "missing" and "someone else's".
      throw ViewModelException('No ARAL class with id $classId among your classes.');
    }
    return c;
  }

  Future<void> _checkName(int schoolId, String schoolYear, String name, int? exceptId) async {
    final key = name.toLowerCase();
    for (final c in await _classes.getBySchool(schoolId, schoolYear: schoolYear)) {
      if (c.id != exceptId && c.className.trim().toLowerCase() == key) {
        throw ViewModelException('A class named "$name" already exists for $schoolYear.');
      }
    }
  }

  Future<void> _checkTutor(String tutorId, int schoolId) async {
    final u = await _users.getById(tutorId);
    if (u == null || u.role != UserRole.tutor || !u.isActive || u.schoolId != schoolId) {
      throw const ViewModelException('The class tutor must be an active tutor of the school.');
    }
  }

  static String _name(String raw) {
    final name = raw.trim();
    if (name.isEmpty) throw const ViewModelException('A class needs a name.');
    return name;
  }

  static String _year(String raw) {
    try {
      return normalizeSchoolYear(raw);
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
  }

  Future<T> _write<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
      // A record waiting in an upload (sync): say so, whatever else the
      // statement's text happens to contain.
      if ('$e'.contains(pendingLockMessage)) throw const ViewModelException(pendingLockMessage);
      final text = e.toString();
      if (text.contains('aral_classes_name_key')) {
        throw const ViewModelException('A class with that name already exists for that school year.');
      }
      for (final refusal in _dbRefusals) {
        if (text.toLowerCase().contains(refusal.toLowerCase())) throw ViewModelException('$refusal.');
      }
      rethrow;
    }
  }

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
}
