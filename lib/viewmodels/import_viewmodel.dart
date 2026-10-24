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

  const ImportCloudRepos({
    required this.schools,
    required this.sections,
    required this.students,
    required this.conflicts,
  });
}

/// What resolving one conflict did.
class ConflictResolution {
  final int conflictId;
  final String action; // 'skip' | 'update'
  final int? studentId; // set for 'update'
  final Section? enrolledIn; // null when the conflict had no (visible) section

  const ConflictResolution(this.conflictId, this.action, {this.studentId, this.enrolledIn});
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

  List<ImportConflict> pendingConflicts = [];

  ImportViewModel({
    required AuthViewModel auth,
    required ImportCloudRepos Function(SupabaseClient client) cloudFactory,
    required SchoolRepository localSchools,
    required SectionRepository localSections,
    required StudentRepository localStudents,
    required this.columnMap,
    Logger? logger,
  })  : _auth = auth,
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
    if (pendingConflicts.isNotEmpty || result.conflicts > 0) await loadPendingConflicts();
    return result;
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

    final existing = await cloud.students.findByLrn(conflict.lrn);
    if (existing == null) {
      throw ViewModelException(conflict.reason == transferConflictReason
          ? 'LRN ${conflict.lrn} belongs to a learner in another school; only the superadmin can resolve it.'
          : 'No existing learner with LRN ${conflict.lrn}.');
    }

    final incoming = jsonDecode(conflict.incomingDataJson) as Map<String, Object?>;
    await cloud.students.update(Student.fromMap({...incoming, 'id': existing.id, 'school_id': existing.schoolId}));

    Section? enrolledIn;
    if (conflict.sectionId != null) {
      final section = await cloud.sections.getById(conflict.sectionId!);
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
    }

    await _markResolved(cloud, id, 'resolved_updated');
    return ConflictResolution(id, action, studentId: existing.id, enrolledIn: enrolledIn);
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
