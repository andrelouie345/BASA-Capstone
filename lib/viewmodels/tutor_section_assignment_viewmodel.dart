// lib/viewmodels/tutor_section_assignment_viewmodel.dart
import 'package:supabase/supabase.dart';
import '../core/console/logger.dart';
import '../core/models/tutor_section_assignment.dart';
import '../core/models/user_role.dart';
import '../core/repositories/tutor_section_assignment_repository.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Tutor <-> section assignments, through the signed-in user's client.
/// Managed by admins/coordinators; the database checks that the tutor is an
/// active tutor of the section's school and stamps assigned_by/assigned_at.
class TutorSectionAssignmentViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final TutorSectionAssignmentRepository Function(SupabaseClient client) _repoFor;
  List<TutorSectionAssignment> items = [];

  // Tracks which query populated `items`, so refresh() can repeat it
  // after a create/delete without the caller having to remember.
  String? _lastTutorId;
  int? _lastSectionId;

  TutorSectionAssignmentViewModel({
    required AuthViewModel auth,
    required TutorSectionAssignmentRepository Function(SupabaseClient client) repoFactory,
    Logger? logger,
  })  : _auth = auth,
        _repoFor = repoFactory,
        _log = ScopedLogger(logger, 'TutorSectionAssignmentViewModel');

  TutorSectionAssignmentRepository _repo() {
    final sessionError = _auth.requireActiveSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    final role = _auth.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: admin or coordinator only.');
    }
    return _repoFor(_auth.client!);
  }

  /// Oldest assignment first.
  Future<void> loadForTutor(String tutorId) async {
    _log('loadForTutor(tutorId: $tutorId)');
    final repo = _repo();
    _lastTutorId = tutorId;
    _lastSectionId = null;
    items = await repo.getByTutor(tutorId);
  }

  /// Oldest assignment first.
  Future<void> loadForSection(int sectionId) async {
    _log('loadForSection(sectionId: $sectionId)');
    final repo = _repo();
    _lastSectionId = sectionId;
    _lastTutorId = null;
    items = await repo.getBySection(sectionId);
  }

  Future<void> refresh() async {
    if (_lastTutorId != null) {
      await loadForTutor(_lastTutorId!);
    } else if (_lastSectionId != null) {
      await loadForSection(_lastSectionId!);
    }
    // If neither is set, refresh() is a no-op — nothing's been loaded yet.
  }

  Future<TutorSectionAssignment> assign({required String tutorId, required int sectionId}) async {
    _log('assign(tutorId: $tutorId, sectionId: $sectionId)');
    final repo = _repo();
    final TutorSectionAssignment created;
    try {
      created = await repo.create(TutorSectionAssignment(tutorId: tutorId, sectionId: sectionId));
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ViewModelException('That tutor is already assigned to this section.');
      }
      if (e.code == 'P0001') throw ViewModelException(e.message); // validation trigger
      rethrow;
    }
    await refresh();
    return created;
  }

  Future<void> unassign(int id) async {
    _log('unassign(id: $id)');
    await _repo().delete(id);
    await refresh();
  }
}
