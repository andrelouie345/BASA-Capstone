// lib/viewmodels/student_viewmodel.dart
import 'package:supabase/supabase.dart';
import '../core/console/logger.dart';
import '../core/models/student.dart';
import '../core/repositories/student_repository.dart';
import '../core/services/roster_exporter.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Learners, read through the signed-in user's client. RLS scopes the
/// result: superadmin all, admin/coordinator their school, tutor the
/// learners of their assigned sections.
///
/// [localStudents] and [rosterCsv] read this device's copy instead (work
/// offline).
class StudentViewModel {
  static const sorts = ['lastname', 'lrn', 'id'];

  final ScopedLogger _log;
  final AuthViewModel _auth;
  final StudentRepository Function(SupabaseClient client) _repoFor;
  final StudentRepository? _local;
  final RosterExporter _exporter;
  List<Student> items = [];

  StudentViewModel({
    required AuthViewModel auth,
    required StudentRepository Function(SupabaseClient client) repoFactory,
    StudentRepository? local,
    RosterExporter? exporter,
    Logger? logger,
  })  : _auth = auth,
        _repoFor = repoFactory,
        _local = local,
        _exporter = exporter ?? RosterExporter(),
        _log = ScopedLogger(logger, 'StudentViewModel');

  /// The learners of one section on this device. Online or offline sign-in.
  Future<List<Student>> localStudents(int sectionId) async {
    _log('localStudents(sectionId: $sectionId)');
    final sessionError = _auth.requireActiveSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    final local = _local;
    if (local == null) throw const ViewModelException('No local copy on this device.');
    return local.getBySection(sectionId);
  }

  /// The section's roster as CSV text (empty list: header only). The caller
  /// saves it.
  Future<String> rosterCsv(int sectionId) async {
    _log('rosterCsv(sectionId: $sectionId)');
    return _exporter.toCsv(await localStudents(sectionId));
  }

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
