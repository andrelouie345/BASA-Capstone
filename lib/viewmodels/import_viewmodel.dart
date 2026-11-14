// lib/viewmodels/import_viewmodel.dart
import 'dart:convert';
import 'package:supabase/supabase.dart';
import '../core/console/logger.dart';
import '../core/models/import_conflict.dart';
import '../core/models/school.dart';
import '../core/models/section.dart';
import '../core/models/student.dart';
import '../core/models/user_role.dart';
import '../core/repositories/import_conflict_repository.dart';
import '../core/repositories/learner_leaver_repository.dart';
import '../core/repositories/school_repository.dart';
import '../core/repositories/section_repository.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/sf1_column_map.dart';
import '../core/services/sf1_importer.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// The cloud repositories an import needs, built from the signed-in client.
class ImportCloudRepos {
  final SchoolRepository schools;
  final SectionRepository sections;
  final StudentRepository students;
  final ImportConflictRepository conflicts;

  /// Saves each import's LRN set (sf1_last_imports, SF1 leavers D9).
  final LearnerLeaverRepository leavers;

  const ImportCloudRepos({
    required this.schools,
    required this.sections,
    required this.students,
    required this.conflicts,
    required this.leavers,
  });
}

/// What resolving one conflict did.
class ConflictResolution {
  final int conflictId;
  final String action; // 'skip' | 'update'
  final int? studentId; // set for 'update'
  final Section? enrolledIn; // null when the conflict had no (visible) section

  /// Set when 'update' transferred the learner in from another school
  /// (sf1_transfer_in, D15): that school's name and the section they left.
  final ({String? schoolName, String? sectionName})? transferredFrom;

  /// Set when the server change is saved but this device's copy could not
  /// be updated (pull to refresh).
  final String? deviceWarning;

  const ConflictResolution(this.conflictId, this.action,
      {this.studentId, this.enrolledIn, this.transferredFrom, this.deviceWarning});
}

/// SF1 roster import and import-conflict review. Admin/coordinator only;
/// the cloud is the source of truth and every write is mirrored to SQLite.
class ImportViewModel {
  final ScopedLogger _log;
  final Logger? _logger;
  final AuthViewModel _auth;
  final ImportCloudRepos Function(SupabaseClient client) _cloudFor;
  final SchoolRepository _localSchools;
  final SectionRepository _localSections;
  final StudentRepository _localStudents;
  final Sf1ColumnMap columnMap;

  /// Copies a server function's result onto this device
  /// (mirrorLeaverResult); null = nothing to copy (tests).
  final Future<void> Function(Map<String, dynamic> result)? _mirror;

  List<ImportConflict> pendingConflicts = [];

  ImportViewModel({
    required AuthViewModel auth,
    required ImportCloudRepos Function(SupabaseClient client) cloudFactory,
    required SchoolRepository localSchools,
    required SectionRepository localSections,
    required StudentRepository localStudents,
    required this.columnMap,
    Future<void> Function(Map<String, dynamic> result)? mirror,
    Logger? logger,
  })  : _auth = auth,
        _mirror = mirror,
        _cloudFor = cloudFactory,
        _localSchools = localSchools,
        _localSections = localSections,
        _localStudents = localStudents,
        _logger = logger,
        _log = ScopedLogger(logger, 'ImportViewModel');

  ImportCloudRepos _cloud() {
    final sessionError = _auth.requireOnlineSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    final role = _auth.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: admin or coordinator only.');
    }
    return _cloudFor(_auth.client!);
  }

  Sf1Importer _importer(ImportCloudRepos cloud) => Sf1Importer(
        schoolRepo: cloud.schools,
        localSchoolRepo: _localSchools,
        sectionRepo: cloud.sections,
        localSectionRepo: _localSections,
        studentRepo: cloud.students,
        localStudentRepo: _localStudents,
        conflictRepo: cloud.conflicts,
        columnMap: columnMap,
        logger: _logger,
      );

  /// Raw cell values of one sheet row, to check the column map.
  Future<List<String?>> previewRow(String filePath, int rowIndex) async {
    _log('previewRow($filePath, $rowIndex)');
    return _importer(_cloud()).previewRow(filePath, rowIndex);
  }

  /// What import() would do, without writing anything.
  Future<Sf1TrialResult> trial(String filePath) async {
    _log('trial($filePath)');
    final cloud = _cloud();
    final parsed = await _wrapFormat(() => _importer(cloud).trial(filePath));
    await _checkOwnSchool(cloud, parsed);
    return parsed;
  }

  Future<Sf1ImportResult> import(String filePath) async {
    _log('import($filePath)');
    final cloud = _cloud();
    final result = await _wrapFormat(
        () => _importer(cloud).import(filePath, check: (parsed) => _checkOwnSchool(cloud, parsed)));
    await _saveLastImport(cloud, result);
    if (pendingConflicts.isNotEmpty || result.conflicts > 0) await loadPendingConflicts();
    return result;
  }

  /// The file's LRN set becomes the section's last import, so the learners
  /// active there but not on it are listed as undecided (sf1-missing) on
  /// every admin device. The import itself is already done: a failure here
  /// is a warning on the result, not an error.
  Future<void> _saveLastImport(ImportCloudRepos cloud, Sf1ImportResult result) async {
    if (result.sectionId == null || result.schoolId == null || result.schoolYear == null) return;
    try {
      await cloud.leavers.saveLastImport(result.sectionId!, result.schoolId!, result.schoolYear!, result.fileLrns);
    } catch (e) {
      result.lastImportWarning = 'The import is done, but its list of learners was not saved on the server, '
          'so learners not on this SF1 are not listed: import the file again.';
      _log('WARNING: saveLastImport failed ($e)');
    }
  }

  /// Oldest first.
  Future<void> loadPendingConflicts() async {
    _log('loadPendingConflicts()');
    pendingConflicts = await _cloud().conflicts.getPending();
  }

  /// The conflict plus the section it was raised for (null if none/hidden).
  Future<({ImportConflict conflict, Section? section})> getConflict(int id) async {
    _log('getConflict($id)');
    final cloud = _cloud();
    final conflict = await cloud.conflicts.getById(id);
    if (conflict == null) throw ViewModelException('No conflict with id $id.');
    final section = conflict.sectionId == null ? null : await cloud.sections.getById(conflict.sectionId!);
    return (conflict: conflict, section: section);
  }

  /// 'skip' closes the conflict. 'update' overwrites the stored learner with
  /// the incoming SF1 data and enrolls them into the conflict's section
  /// (which moves them there; for a transfer that is a superadmin action).
  /// Refused when the learner already has an enrollment that school year at
  /// the conflict's school ([importResolveEnrolledRefusal]): sf1-move /
  /// sf1-restore do that. An enrollment that year at another school is a
  /// transfer (sf1_transfer_in, D15): same grade only, that school's records
  /// stay there, the learner history gets a transfer line.
  Future<ConflictResolution> resolve(int id, String action) async {
    _log('resolve($id, $action)');
    if (action != 'skip' && action != 'update') {
      throw ViewModelException('Invalid action "$action" (expected skip or update).');
    }
    final cloud = _cloud();
    final conflict = await cloud.conflicts.getById(id);
    if (conflict == null) throw ViewModelException('No conflict with id $id.');
    if (conflict.status != 'pending') {
      throw ViewModelException('Conflict $id is already ${conflict.status}.');
    }

    if (action == 'skip') {
      await _markResolved(cloud, id, 'resolved_skipped');
      return ConflictResolution(id, action);
    }

    final section = conflict.sectionId == null ? null : await cloud.sections.getById(conflict.sectionId!);
    final existing = await cloud.students.findByLrn(conflict.lrn);
    if (existing == null) {
      // A learner of another school is hidden from this school: the server
      // function looks them up and decides (D15).
      if (isTransferConflictReason(conflict.reason) && section != null) {
        return _transferIn(cloud, conflict, section);
      }
      throw ViewModelException(isTransferConflictReason(conflict.reason)
          ? 'LRN ${conflict.lrn} belongs to a learner in another school, and the conflict has no section to enroll them into.'
          : 'No existing learner with LRN ${conflict.lrn}.');
    }

    if (section != null) {
      final e = await cloud.students.enrollmentInYear(existing.id!, section.schoolYear);
      // Enrolled this school year at another school, archived or still
      // active: a transfer (D15, review I2 q11).
      if (e != null && e.schoolId != section.schoolId) return _transferIn(cloud, conflict, section);
      final refusal = e == null ? null : importResolveEnrolledRefusal(conflict, section, e);
      if (refusal != null) {
        _log('refused: learner ${existing.id} already enrolled in ${section.schoolYear} (${e!.status})');
        throw ViewModelException(refusal);
      }
    }

    final incoming = jsonDecode(conflict.incomingDataJson) as Map<String, Object?>;
    await cloud.students.update(Student.fromMap({...incoming, 'id': existing.id, 'school_id': existing.schoolId}));

    Section? enrolledIn;
    if (section != null) {
      final enrollmentId = await cloud.students.enroll(
        studentId: existing.id!,
        sectionId: section.id!,
        schoolYear: section.schoolYear,
      );
      await _localSections.upsertWithId(section);
      await _localStudents.upsertWithId(Student.fromMap({
        ...incoming,
        'id': existing.id,
        'school_id': section.schoolId, // the enrollment moved the learner there
      }));
      await _localStudents.enroll(
        studentId: existing.id!,
        sectionId: section.id!,
        schoolYear: section.schoolYear,
        id: enrollmentId,
      );
      enrolledIn = section;
    }

    await _markResolved(cloud, id, 'resolved_updated');
    return ConflictResolution(id, action, studentId: existing.id, enrolledIn: enrolledIn);
  }

  /// sf1_transfer_in: the learner leaves the other school's section this
  /// school year (archived there as transferred out if still active) and
  /// becomes active in [section]; that school's records of the year stay
  /// there; the transfer is written to the learner's history.
  Future<ConflictResolution> _transferIn(ImportCloudRepos cloud, ImportConflict conflict, Section section) async {
    final Map<String, dynamic> r;
    try {
      r = await cloud.leavers.transferIn(conflict.id!);
    } on PostgrestException catch (e) {
      _log('transfer refused: ${e.message}');
      throw ViewModelException('The database refused it: ${e.message}.');
    }
    pendingConflicts.removeWhere((c) => c.id == conflict.id);
    String? warning;
    try {
      await _localSections.upsertWithId(section);
      await _mirror?.call(r);
    } catch (e) {
      warning = "Saved on the server, but this device's copy was not updated: pull to refresh (pull-cloud yes).";
      _log('WARNING: transfer mirror failed ($e)');
    }
    final student = r['student'] as Map;
    final from = r['from_school'] as Map?;
    final fromSection = r['from_section'] as Map?;
    _log('transferred learner ${student['id']} in from school ${from?['id']}');
    return ConflictResolution(conflict.id!, 'update',
        studentId: (student['id'] as num).toInt(),
        enrolledIn: section,
        transferredFrom: (schoolName: from?['name'] as String?, sectionName: fromSection?['name'] as String?),
        deviceWarning: warning);
  }

  /// Resolves every pending conflict the same way. One failure doesn't stop
  /// the rest; each entry is either a resolution or the error message.
  Future<List<({int id, ConflictResolution? resolution, String? error})>> resolveAll(String action) async {
    _log('resolveAll($action)');
    await loadPendingConflicts();
    final outcomes = <({int id, ConflictResolution? resolution, String? error})>[];
    for (final c in List.of(pendingConflicts)) {
      try {
        outcomes.add((id: c.id!, resolution: await resolve(c.id!, action), error: null));
      } catch (e) {
        outcomes.add((id: c.id!, resolution: null, error: e.toString()));
      }
    }
    await loadPendingConflicts();
    return outcomes;
  }

  Future<void> _markResolved(ImportCloudRepos cloud, int id, String status) async {
    if (!await cloud.conflicts.resolve(id, status)) {
      throw ViewModelException('Conflict $id was not resolved (already resolved, or not visible to you).');
    }
    pendingConflicts.removeWhere((c) => c.id == id);
  }

  /// A school-bound admin or coordinator imports only their own school's
  /// rosters (F24: the school insert was refused by RLS with a raw error).
  /// The superadmin may import any school, and creates new ones this way.
  Future<void> _checkOwnSchool(ImportCloudRepos cloud, Sf1TrialResult parsed) async {
    final schoolId = _auth.currentUser?.schoolId;
    if (schoolId == null) return;
    final refusal = sf1OtherSchoolRefusal(
      fileSchoolCode: parsed.schoolIdCode,
      fileSchoolName: parsed.schoolName,
      ownSchool: await cloud.schools.getById(schoolId),
    );
    if (refusal != null) {
      _log('refused: roster of school ${parsed.schoolIdCode}');
      throw ViewModelException(refusal);
    }
  }

  Future<T> _wrapFormat<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
  }
}

/// Why `resolve-conflict <id> update` can't enroll the learner into the
/// conflict's [section] when they already have enrollment [e] that school
/// year (SF1 leavers I3): at the same school, a section change goes through
/// the move/restore functions (same grade, this year's records follow, the
/// history is written, pending uploads are checked), never an upsert. Null
/// = go on (another school's enrollment is a transfer: sf1_transfer_in).
String? importResolveEnrolledRefusal(ImportConflict conflict, Section section, EnrollmentInYear e) {
  final id = conflict.id;
  final skip = 'then close this conflict with resolve-conflict $id skip.';
  final where = '${e.sectionName} (Grade ${e.gradeLevel})';
  final sameGrade = e.gradeLevel == section.gradeLevel;
  final archived = e.status != 'active';
  final left = 'archived on ${e.leftOn ?? '?'} (${e.status.replaceAll('_', ' ')})';
  if (e.schoolId != section.schoolId) return null;
  if (!archived) {
    if (e.sectionId == section.id) {
      return 'Refused: LRN ${conflict.lrn} is already active in $where this school year: nothing to enroll; '
          'close this conflict with resolve-conflict $id skip.';
    }
    if (!sameGrade) {
      return 'Refused: LRN ${conflict.lrn} is active in $where this school year, and moves are same grade only, '
          'so this is a decision by hand (e.g. archive them there); $skip';
    }
    return 'Refused: LRN ${conflict.lrn} is already active in $where this school year. Move them with '
        'sf1-move ${e.enrollmentId} ${section.id} (this year\'s records follow), $skip';
  }
  if (e.sectionId == section.id) {
    return 'Refused: LRN ${conflict.lrn} was $left in $where this school year. Restore them with '
        'sf1-restore ${e.enrollmentId}, $skip';
  }
  if (!sameGrade) {
    return 'Refused: LRN ${conflict.lrn} was $left in $where this school year, and a restore into another '
        'section is same grade only: sf1-restore ${e.enrollmentId} puts them back in ${e.sectionName}, or decide '
        'by hand; $skip';
  }
  return 'Refused: LRN ${conflict.lrn} was $left in $where this school year. Restore them into this section '
      'with sf1-restore ${e.enrollmentId} ${section.id} (this year\'s records follow), $skip';
}

/// Null when a school-bound caller may import a roster of school
/// [fileSchoolCode]; otherwise the refusal to show.
String? sf1OtherSchoolRefusal({
  required String fileSchoolCode,
  required String fileSchoolName,
  required School? ownSchool,
}) {
  if (ownSchool == null) return 'Forbidden: your school could not be read, so the roster cannot be checked.';
  if (ownSchool.schoolId.trim() == fileSchoolCode.trim()) return null;
  return 'Forbidden: this roster is for school ${fileSchoolCode.trim()} ($fileSchoolName); '
      "you can only import your own school's rosters.";
}
