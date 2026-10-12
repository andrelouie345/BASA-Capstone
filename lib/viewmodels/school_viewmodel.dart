// lib/viewmodels/school_viewmodel.dart
import 'package:supabase/supabase.dart';
import '../core/console/logger.dart';
import '../core/models/region.dart';
import '../core/models/school.dart';
import '../core/models/user_role.dart';
import '../core/repositories/school_repository.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Schools, read and written through the signed-in user's client (RLS
/// applies). The checks here mirror the policies so the UI gets a clear
/// message instead of an empty result; RLS stays the real enforcement.
class SchoolViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final SchoolRepository Function(SupabaseClient client) _repoFor;
  List<School> items = [];

  SchoolViewModel({
    required AuthViewModel auth,
    required SchoolRepository Function(SupabaseClient client) repoFactory,
    Logger? logger,
  })  : _auth = auth,
        _repoFor = repoFactory,
        _log = ScopedLogger(logger, 'SchoolViewModel');

  bool get _isSuperadmin =>
      _auth.currentUser?.role == UserRole.admin && _auth.currentUser?.schoolId == null;

  bool get _isAdminOrCoordinator =>
      _auth.currentUser?.role == UserRole.admin || _auth.currentUser?.role == UserRole.coordinator;

  SchoolRepository _repo() {
    final sessionError = _auth.requireActiveSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    return _repoFor(_auth.client!);
  }

  /// Every school visible to the user: all of them for a superadmin, their
  /// own for anyone school-bound (admin, coordinator or tutor).
  Future<void> loadAll() async {
    _log('loadAll()');
    items = await _repo().getAll();
  }

  /// Superadmin only. Returns the existing school (created: false) when the
  /// DepEd school ID is already registered; nothing is changed in that case.
  Future<({School school, bool created})> create({
    required String schoolCode,
    required String schoolName,
    int? regionId,
    String? division,
  }) async {
    _log('create(schoolCode: "$schoolCode", regionId: $regionId)');
    final repo = _repo();
    if (!_isSuperadmin) throw const ViewModelException('Forbidden: superadmin only.');
    _checkRegion(regionId);
    if (schoolCode.trim().isEmpty || schoolName.trim().isEmpty) {
      throw const ViewModelException('School ID and school name are required.');
    }

    final existing = await repo.getByCode(schoolCode.trim());
    if (existing != null) return (school: existing, created: false);

    final school = await repo.getOrCreate(School(
      schoolId: schoolCode.trim(),
      schoolName: schoolName.trim(),
      regionId: regionId,
      division: division,
    ));
    await _refreshIfLoaded();
    return (school: school, created: true);
  }

  /// Superadmin: any school, any field. School-bound admin/coordinator: their
  /// own school, name and division only.
  Future<School> update(School school) async {
    _log('update(id: ${school.id})');
    final repo = _repo();
    if (school.id == null) throw const ViewModelException('Cannot update a school with no id.');
    if (!_isSuperadmin) {
      if (!_isAdminOrCoordinator) throw const ViewModelException('Forbidden: admin or coordinator only.');
      if (_auth.currentUser?.schoolId != school.id) {
        throw const ViewModelException('Forbidden: can only update your own school.');
      }
      // Name and division only; the DB trigger schools_guard_identity enforces it.
      final current = (await repo.getAll()).where((s) => s.id == school.id).firstOrNull;
      if (current != null &&
          (current.schoolId != school.schoolId || current.regionId != school.regionId)) {
        throw const ViewModelException(
            "Forbidden: only the superadmin can change a school's DepEd school ID or region.");
      }
    }
    _checkRegion(school.regionId);
    final updated = await repo.update(school);
    await _refreshIfLoaded();
    return updated;
  }

  /// Superadmin only. The database refuses while sections, students, users
  /// or assessments still reference the school, so only empty schools go.
  Future<void> delete(int id) async {
    _log('delete($id)');
    final repo = _repo();
    if (!_isSuperadmin) throw const ViewModelException('Forbidden: superadmin only.');
    try {
      await repo.delete(id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw const ViewModelException(
            'School is still in use (sections, students, users or assessments). Remove those first.');
      }
      rethrow;
    }
    await _refreshIfLoaded();
  }

  void _checkRegion(int? regionId) {
    if (regionId != null && Region.byId(regionId) == null) {
      throw ViewModelException('Unknown region id $regionId.');
    }
  }

  Future<void> _refreshIfLoaded() async {
    if (items.isNotEmpty) await loadAll();
  }
}
