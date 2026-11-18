// lib/viewmodels/aral_class_viewmodel.dart
//
// ARAL classes (spec docs/superpowers/specs/2026-10-23-aral-classes-design.md).
// Offline-first like the roster: reads and writes this device's copy; the
// classes travel with sync-upload.
//
// Owner decisions (2026-10-23):
//  * A class belongs to a school and a school year (not a section), with at
//    most 15 active learners (aral_rules.dart; since the ARAL memo settings,
//    the school's class_max_learners).
//  * One tutor per class, possibly blank for a while; a tutor may teach
//    several classes.
//  * Admins and coordinators create, change and delete classes; a tutor reads
//    the classes they teach.
// The device checks here mirror the cloud triggers, so the device refuses
// first with a readable message.
//  * Placing a learner (or moving them to another class) checks the class's
//    school and year, program (one-program classes) and its 15 active places
//    (aral_rules.dart). A program change by aral-update keeps the learner in
//    their class (decision 7); new placements must match.
//  * A class keeps its grade and program once it has learners, and is
//    deleted only when nobody points at it.
// Owner decisions (2026-10-24, from the reading coordinator; plan
// docs/superpowers/plans/2026-10-24-aral-class-grade.md):
//  * G1-G2: a class has a home grade (1-10) and one program or mixed
//    programs (program null).
//  * G3: a learner of another grade goes in only when the coordinator says
//    so (place(otherGrade: true)); the cloud doesn't check grades.
import '../core/console/logger.dart';
import '../core/models/aral_class.dart';
import '../core/models/aral_enrollment.dart';
import '../core/models/user_role.dart';
import '../core/repositories/aral_class_repository.dart';
import '../core/repositories/aral_enrollment_repository.dart';
import '../core/repositories/aral_setting_repository.dart';
import '../core/repositories/aral_session_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/aral_rule_settings.dart';
import '../core/services/aral_rules.dart';
import '../core/services/normalizers.dart';
import '../core/services/sync_upload_rules.dart' show pendingLockMessage;
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';
import '../core/services/auth_messages.dart';

/// The school's ARAL rule settings on this device: defaults <- region row <-
/// school row of the aral_settings mirror (pull-cloud refreshes it).
Future<AralRuleSettings> aralLocalRuleSettings(AralSettingRepository settings, int schoolId) async {
  final region = await settings.getRegion();
  final school = await settings.getForSchool(schoolId);
  return AralRuleSettings.fromMap({...?region?.settings, ...?school?.settings});
}

/// Why [e] (Grade [grade], named [learner]) can't go into [c], and the
/// reason as a readable sentence; null = they can. [otherGradeOk] = the
/// coordinator confirmed another grade. Counts [c]'s other active learners
/// from [roster] against [maxLearners] (the school's class maximum). Shared
/// by AralClassViewModel and AralViewModel.
Future<(AralPlacementProblem, String)?> aralPlacementRefusal(
    AralEnrollmentRepository roster, AralClass c, AralEnrollment e,
    {required int grade, required String learner, required int maxLearners, bool otherGradeOk = false}) async {
  final others = (await roster.getByClass(c.id!)).where((x) => x.isActive && x.id != e.id).length;
  final program = AralClassProgram.of(e.keyStage, e.track);
  final problem = aralPlacementProblem(
      target: c,
      schoolId: e.schoolId,
      schoolYear: e.schoolYear,
      program: program,
      grade: grade,
      activeOthersInClass: others,
      maxLearners: maxLearners,
      otherGradeOk: otherGradeOk);
  return problem == null
      ? null
      : (problem,
          aralPlacementMessage(problem,
              learner: learner, target: c, grade: grade, program: program, maxLearners: maxLearners));
}

/// The device and cloud placement refusals (trigger texts), mapped back to
/// readable sentences by the ViewModels. The class maximum's text names the
/// school's number: see [aralClassFullDbRefusal].
const aralPlacementDbRefusals = [
  "The learner's program does not match the ARAL class",
  'The ARAL class belongs to another school or school year',
];

/// The device or cloud refusal of a full class in [text] ("An ARAL class has
/// at most N active learners", the number = the school's maximum), or null.
String? aralClassFullDbRefusal(String text) {
  final m = RegExp(r'an ARAL class has at most (\d+) active learners', caseSensitive: false).firstMatch(text);
  return m == null ? null : 'An ARAL class has at most ${m.group(1)} active learners.';
}

class AralClassViewModel {
  /// The local trigger texts, shown as they are.
  static const _dbRefusals = [
    "The ARAL class tutor must be an active tutor of the class's school",
    'An ARAL class keeps its school and school year',
    'An ARAL class with learners keeps its grade and program',
    ...aralPlacementDbRefusals,
  ];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AralClassRepository _classes;
  final AralEnrollmentRepository _roster;
  final AralSessionRepository _sessions;
  final SectionRepository _sections;
  final StudentRepository _students;
  final UserRepository _users;
  final AralSettingRepository _localSettings;

  AralClassViewModel({
    required AuthViewModel auth,
    required AralClassRepository classes,
    required AralEnrollmentRepository roster,
    required AralSessionRepository sessions,
    required SectionRepository sections,
    required StudentRepository students,
    required UserRepository users,
    required AralSettingRepository localSettings,
    Logger? logger,
  })  : _auth = auth,
        _localSettings = localSettings,
        _classes = classes,
        _roster = roster,
        _sessions = sessions,
        _sections = sections,
        _students = students,
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

  /// The learners placed in the class (active and exited).
  Future<List<AralEnrollment>> classRoster(int classId) async {
    _requireSignIn();
    _log('classRoster($classId)');
    await _readable(classId);
    return _roster.getByClass(classId);
  }

  /// The most active learners a class of [schoolId] holds: the school's
  /// class_max_learners on this device (default 15).
  Future<int> classMax(int schoolId) async {
    _requireSignIn();
    return (await aralLocalRuleSettings(_localSettings, schoolId)).classMaxLearners;
  }

  /// The fewest active learners a class of [schoolId] should hold: the
  /// school's class_min_learners on this device (0 = no minimum). A class
  /// below it is a coordinator notice, never a refusal.
  Future<int> classMin(int schoolId) async {
    _requireSignIn();
    return (await aralLocalRuleSettings(_localSettings, schoolId)).classMinLearners;
  }

  /// How many active learners the class holds (at most the school's
  /// maximum, [classMax]; more when the maximum was lowered later).
  Future<int> activeCount(int classId) async {
    _requireSignIn();
    await _readable(classId);
    return (await _roster.getByClass(classId)).where((e) => e.isActive).length;
  }

  // ---- Placing learners (admin / coordinator) ----

  /// Puts an active ARAL learner in a class, or moves them from their class
  /// to another one. The class must be of the learner's school and year, teach
  /// their program (unless it mixes programs) and have a free place (fewer
  /// active learners than the school's maximum, [classMax]). A learner of another grade than the class's goes in only with
  /// [otherGrade] (the coordinator's decision, G3).
  Future<AralEnrollment> place(int enrollmentId, int classId, {bool otherGrade = false}) async {
    _requireSignIn();
    _log('place($enrollmentId, $classId, otherGrade: $otherGrade)');
    _requireManager();
    final e = await _requireLearner(enrollmentId);
    final c = await _require(classId);
    if (!e.isActive) {
      throw const ViewModelException('This learner left ARAL; reactivate them before placing them in a class.');
    }
    if (e.classId == classId) throw ViewModelException('This learner is already in class "${c.className}".');
    final (grade, name) = await _gradeAndName(e);
    final max = (await aralLocalRuleSettings(_localSettings, c.schoolId)).classMaxLearners;
    final refusal = await aralPlacementRefusal(_roster, c, e,
        grade: grade, learner: name, maxLearners: max, otherGradeOk: otherGrade);
    if (refusal != null) {
      throw ViewModelException(refusal.$1 == AralPlacementProblem.otherGrade
          ? '${refusal.$2} To place them in it anyway, confirm the other grade (other-grade).'
          : refusal.$2);
    }
    return _write(() => _roster.update(e.copyWith(classId: () => classId)));
  }

  /// Takes the learner out of their class: they wait for a class.
  Future<AralEnrollment> unplace(int enrollmentId) async {
    _requireSignIn();
    _log('unplace($enrollmentId)');
    _requireManager();
    final e = await _requireLearner(enrollmentId);
    if (e.classId == null) throw const ViewModelException('This learner is not in a class.');
    return _write(() => _roster.update(e.copyWith(classId: () => null)));
  }

  // ---- Writing (admin / coordinator) ----

  /// A new class of Grade [gradeLevel] (1-10) teaching [program], or mixed
  /// programs when [program] is null.
  Future<AralClass> createClass({
    required int schoolId,
    required String schoolYear,
    required String className,
    required int gradeLevel,
    AralClassProgram? program,
    String? tutorId,
    String? room,
    String? schedule,
    String? notes,
  }) async {
    _requireSignIn();
    _log('createClass(school: $schoolId, year: $schoolYear, name: $className, grade $gradeLevel, '
        '${program?.value ?? 'mixed'}, tutor: $tutorId)');
    _requireManager();
    _requireOwnSchool(schoolId);
    _checkGrade(gradeLevel);
    final year = _year(schoolYear);
    final name = _name(className);
    await _checkName(schoolId, year, name, null);
    tutorId = _blankToNull(tutorId);
    if (tutorId != null) await _checkTutor(tutorId, schoolId);
    return _write(() => _classes.insert(AralClass(
          schoolId: schoolId,
          schoolYear: year,
          className: name,
          gradeLevel: gradeLevel,
          program: program,
          tutorId: tutorId,
          room: _blankToNull(room),
          schedule: _blankToNull(schedule),
          notes: _blankToNull(notes),
          createdBy: _auth.currentUser?.id,
        )));
  }

  /// Saves a changed class: name, grade, program (null = mixed), tutor, room,
  /// schedule, notes. School and year never change; grade and program only
  /// while the class has no learners.
  Future<AralClass> editClass(AralClass changed) async {
    _requireSignIn();
    _log('editClass(${changed.id})');
    _requireManager();
    if (changed.id == null) throw const ViewModelException('Save the class first.');
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
    _checkGrade(changed.gradeLevel);
    if ((changed.program != current.program || changed.gradeLevel != current.gradeLevel) &&
        (await _roster.getByClass(current.id!)).isNotEmpty) {
      throw ViewModelException("Class \"${current.className}\" has learners; its grade and program can't change.");
    }
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
    final c = await _require(classId);
    // Sessions too (review C3): the device doesn't enforce foreign keys, and
    // the cloud refuses the delete of a class its sessions point at.
    if ((await _roster.getByClass(classId)).isNotEmpty || (await _sessions.getByClass(classId)).isNotEmpty) {
      throw ViewModelException("Class \"${c.className}\" still has learners or sessions; it can't be deleted.");
    }
    await _write(() => _classes.delete(classId));
  }

  // ---- helpers ----

  void _requireManager() {
    final role = _auth.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      throw const ViewModelException('Not allowed: admin or coordinator only.');
    }
  }

  void _requireOwnSchool(int schoolId) {
    final mine = _auth.currentUser?.schoolId;
    if (mine != null && mine != schoolId) throw const ViewModelException('Not allowed: that school is not yours.');
  }

  /// The class, if the caller may change it (their school, or any for the
  /// superadmin).
  Future<AralClass> _require(int classId) async {
    final c = await _classes.findById(classId);
    if (c == null) throw ViewModelException(notOnDeviceMessage('ARAL class'));
    final mine = _auth.currentUser?.schoolId;
    if (mine != null && mine != c.schoolId) throw const ViewModelException('Not allowed: that class is in another school.');
    return c;
  }

  Future<AralEnrollment> _requireLearner(int enrollmentId) async {
    final e = await _roster.findById(enrollmentId);
    if (e == null) throw ViewModelException(notOnDeviceMessage('ARAL learner'));
    final mine = _auth.currentUser?.schoolId;
    if (mine != null && mine != e.schoolId) throw const ViewModelException('Not allowed: that learner is in another school.');
    return e;
  }

  /// The learner's grade (their section's) and "Last, First".
  Future<(int, String)> _gradeAndName(AralEnrollment e) async {
    final section = await _sections.getById(e.sectionId);
    final grade = int.tryParse(section?.gradeLevel ?? '') ?? 0;
    final s = (await _students.getBySection(e.sectionId)).where((s) => s.id == e.studentId).firstOrNull;
    return (grade, s == null ? 'Learner ${e.studentId}' : '${s.lastName}, ${s.firstName}');
  }

  Future<AralClass> _readable(int classId) async {
    final me = _auth.currentUser!;
    if (me.role != UserRole.tutor) return _require(classId);
    final c = await _classes.findById(classId);
    if (c == null || c.tutorId != me.id) {
      // A tutor's device holds only their own classes; don't tell apart
      // "missing" and "someone else's".
      throw const ViewModelException('This ARAL class is not one of your classes.');
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

  static void _checkGrade(int grade) {
    if (grade < 1 || grade > 10) throw const ViewModelException('ARAL-Reading classes are for Grades 1-10.');
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
      final full = aralClassFullDbRefusal(text);
      if (full != null) throw ViewModelException(full);
      for (final refusal in _dbRefusals) {
        if (text.toLowerCase().contains(refusal.toLowerCase())) throw ViewModelException('$refusal.');
      }
      _log('write failed: $e');
      rethrow;
    }
  }

  static String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
}
