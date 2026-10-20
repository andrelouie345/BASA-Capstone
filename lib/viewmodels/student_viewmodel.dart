// lib/viewmodels/student_viewmodel.dart
import 'package:supabase/supabase.dart';
import '../core/console/logger.dart';
import '../core/models/student.dart';
import '../core/repositories/student_repository.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Learners, read through the signed-in user's client. RLS scopes the
/// result: superadmin all, admin/coordinator their school, tutor the
/// learners of their assigned sections.
class StudentViewModel {
  static const sorts = ['lastname', 'lrn', 'id'];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final StudentRepository Function(SupabaseClient client) _repoFor;
  List<Student> items = [];

  StudentViewModel({
    required AuthViewModel auth,
    required StudentRepository Function(SupabaseClient client) repoFactory,
    Logger? logger,
  })  : _auth = auth,
        _repoFor = repoFactory,
        _log = ScopedLogger(logger, 'StudentViewModel');

  StudentRepository _repo() {
    final sessionError = _auth.requireOnlineSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    return _repoFor(_auth.client!);
  }

  Future<void> loadAll({String sort = 'lastname'}) async {
    _log('loadAll(sort: $sort)');
    if (!sorts.contains(sort)) throw ViewModelException('Invalid sort "$sort" (expected ${sorts.join(", ")}).');
    items = await _repo().getAll(sort);
  }

  /// Active enrollments of one section, by last then first name.
  Future<void> loadForSection(int sectionId) async {
    _log('loadForSection($sectionId)');
    items = await _repo().getBySection(sectionId);
  }
}
