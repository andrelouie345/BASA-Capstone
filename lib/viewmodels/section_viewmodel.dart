// lib/viewmodels/section_viewmodel.dart
import 'package:supabase/supabase.dart';
import '../core/console/logger.dart';
import '../core/models/section.dart';
import '../core/models/user_role.dart';
import '../core/repositories/section_repository.dart';
import '../core/services/normalizers.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Sections, read and written through the signed-in user's client (RLS
/// applies). Writes: superadmin any school, admin/coordinator their own.
/// School year and grade level are normalized here, so every caller stores
/// the same canonical values (see normalizers.dart).
class SectionViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final SectionRepository Function(SupabaseClient client) _repoFor;
  List<Section> items = [];

  SectionViewModel({
    required AuthViewModel auth,
    required SectionRepository Function(SupabaseClient client) repoFactory,
    Logger? logger,
  })  : _auth = auth,
        _repoFor = repoFactory,
        _log = ScopedLogger(logger, 'SectionViewModel');

  SectionRepository _repo() {
    final sessionError = _auth.requireActiveSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    return _repoFor(_auth.client!);
  }

  void _checkCanManage(int schoolId) {
    final user = _auth.currentUser;
    if (user?.role == UserRole.admin && user?.schoolId == null) return; // superadmin
    if (user?.role != UserRole.admin && user?.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: admin or coordinator only.');
    }
    if (user?.schoolId != schoolId) {
      throw const ViewModelException('Forbidden: can only manage sections for your own school.');
    }
  }

  /// Every section the user may see (tutors: their assigned sections).
  Future<void> loadAll() async {
    _log('loadAll()');
    items = await _repo().getAll();
  }

  /// Null when the section doesn't exist or isn't visible to the user.
  Future<Section?> getById(int id) async {
    _log('getById($id)');
    return _repo().getById(id);
  }

  /// Returns the existing section (created: false) when one with the same
  /// school, year, grade and name is already stored.
  Future<({Section section, bool created})> create({
    required int schoolId,
    required String schoolYear,
    required String gradeLevel,
    required String sectionName,
  }) async {
    _log('create(schoolId: $schoolId, year: "$schoolYear", grade: "$gradeLevel", name: "$sectionName")');
    final repo = _repo();
    _checkCanManage(schoolId);
    final wanted = Section(
      schoolId: schoolId,
      schoolYear: _normalize(normalizeSchoolYear, schoolYear),
      gradeLevel: _normalize(normalizeGradeLevel, gradeLevel),
      sectionName: _requireName(sectionName),
    );

    final existing = await repo.findExisting(wanted);
    if (existing != null) return (section: existing, created: false);

    final section = await repo.getOrCreate(wanted);
    await _refreshIfLoaded();
    return (section: section, created: true);
  }

  /// Changes year, grade and name. A section never moves to another school.
  Future<Section> update({
    required int id,
    required String schoolYear,
    required String gradeLevel,
    required String sectionName,
  }) async {
    _log('update(id: $id, year: "$schoolYear", grade: "$gradeLevel", name: "$sectionName")');
    final repo = _repo();
    final existing = await repo.getById(id);
    if (existing == null) throw ViewModelException('No section found with id $id.');
    _checkCanManage(existing.schoolId);

    try {
      final updated = await repo.update(Section(
        id: id,
        schoolId: existing.schoolId,
        schoolYear: _normalize(normalizeSchoolYear, schoolYear),
        gradeLevel: _normalize(normalizeGradeLevel, gradeLevel),
        sectionName: _requireName(sectionName),
      ));
      await _refreshIfLoaded();
      return updated;
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ViewModelException('Another section with that year, grade and name already exists.');
      }
      rethrow;
    }
  }

  /// Refused by the database while anything still points at the section
  /// (enrollments, tutor assignments, CRLA assessments).
  Future<void> delete(int id) async {
    _log('delete($id)');
    final repo = _repo();
    final existing = await repo.getById(id);
    if (existing == null) throw ViewModelException('No section found with id $id.');
    _checkCanManage(existing.schoolId);

    try {
      await repo.delete(id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw const ViewModelException(
            'Section is still in use (enrollments, tutor assignments or assessments). Remove those first.');
      }
      rethrow;
    }
    await _refreshIfLoaded();
  }

  String _normalize(String Function(String) normalizer, String raw) {
    try {
      return normalizer(raw);
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
  }

  String _requireName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) throw const ViewModelException('Section name is required.');
    return name;
  }

  Future<void> _refreshIfLoaded() async {
    if (items.isNotEmpty) await loadAll();
  }
}
