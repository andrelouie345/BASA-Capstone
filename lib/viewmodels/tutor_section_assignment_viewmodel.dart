// lib/viewmodels/tutor_section_assignment_viewmodel.dart
import '../core/console/logger.dart';
import '../core/models/tutor_section_assignment.dart';
import '../core/repositories/tutor_section_assignment_repository.dart';

class TutorSectionAssignmentViewModel {
  final ScopedLogger _log;
  TutorSectionAssignmentRepository _repo;
  List<TutorSectionAssignment> items = [];

  // Tracks which query populated `items`, so refresh() can repeat it
  // after a create/delete without the caller having to remember.
  String? _lastTutorId;
  int? _lastSectionId;

  TutorSectionAssignmentViewModel({required TutorSectionAssignmentRepository repo, Logger? logger})
      : _repo = repo,
        _log = ScopedLogger(logger, 'TutorSectionAssignmentViewModel');

  void useRepository(TutorSectionAssignmentRepository repo, String label) {
    _repo = repo;
    _log('switched backend -> $label');
  }

  Future<void> loadForTutor(String tutorId) async {
    _log('loadForTutor(tutorId: $tutorId)');
    _lastTutorId = tutorId;
    _lastSectionId = null;
    items = await _repo.getByTutor(tutorId);
  }

  Future<void> loadForSection(int sectionId) async {
    _log('loadForSection(sectionId: $sectionId)');
    _lastSectionId = sectionId;
    _lastTutorId = null;
    items = await _repo.getBySection(sectionId);
  }

  Future<void> refresh() async {
    if (_lastTutorId != null) {
      await loadForTutor(_lastTutorId!);
    } else if (_lastSectionId != null) {
      await loadForSection(_lastSectionId!);
    }
    // If neither is set, refresh() is a no-op — nothing's been loaded yet.
  }

  Future<void> assign(TutorSectionAssignment assignment) async {
    _log('assign(tutorId: ${assignment.tutorId}, sectionId: ${assignment.sectionId})');
    await _repo.create(assignment);
    await refresh();
  }

  Future<void> unassign(int id) async {
    _log('unassign(id: $id)');
    await _repo.delete(id);
    await refresh();
  }


  
}