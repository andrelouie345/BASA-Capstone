// lib/viewmodels/user_viewmodel.dart
import 'package:supabase/supabase.dart' hide User;
import '../core/console/logger.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/user_repository.dart';
import '../core/services/auth_messages.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// User accounts, read and written through the signed-in user's client (RLS
/// applies). The checks here mirror the create-user edge function and the
/// users policies so the UI gets a clear message; the server stays the real
/// enforcement.
///
/// Accounts are only ever created in the cloud (the edge function creates
/// the Auth user and the profile row together). A local-only profile row
/// would have no Auth account behind it and could never log in.
///
/// Creating and (de)activating are mirrored onto this device ([local]), so
/// rules that read the local users table (an ARAL tutor must be an active
/// tutor of the school) know the account before the next pull-cloud.
class UserViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final UserRepository Function(SupabaseClient client) _repoFor;
  final UserRepository? _local;
  List<User> items = [];

  /// Set when a change was saved online but not copied onto this device.
  String? lastMirrorWarning;

  UserViewModel({
    required AuthViewModel auth,
    required UserRepository Function(SupabaseClient client) repoFactory,
    UserRepository? local,
    Logger? logger,
  })  : _auth = auth,
        _repoFor = repoFactory,
        _local = local,
        _log = ScopedLogger(logger, 'UserViewModel');

  bool get _isSuperadmin =>
      _auth.currentUser?.role == UserRole.admin && _auth.currentUser?.schoolId == null;

  bool get _isAdminOrCoordinator =>
      _auth.currentUser?.role == UserRole.admin || _auth.currentUser?.role == UserRole.coordinator;

  UserRepository _repo() {
    final sessionError = _auth.requireOnlineSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    return _repoFor(_auth.client!);
  }

  void _requireAdminOrCoordinator() {
    if (!_isAdminOrCoordinator) throw const ViewModelException('Forbidden: admin or coordinator only.');
  }

  /// Every account the user can see: all of them for a superadmin, their own
  /// school's for a school-bound admin/coordinator. Sorted by full name.
  Future<void> loadAll() async {
    _log('loadAll()');
    final repo = _repo();
    _requireAdminOrCoordinator();
    items = await repo.getAll();
  }

  /// Creates the account through the create-user edge function and returns
  /// the one-time temporary password (null if the function didn't send one).
  /// Show it to the creating admin once; it must be changed on first login.
  ///
  /// [schoolId] null creates a regional admin (superadmin only). A
  /// school-bound admin/coordinator can only create users for their school.
  Future<String?> create({
    required String email,
    required String fullName,
    required UserRole role,
    int? schoolId,
  }) async {
    _log('create(email: "$email", role: ${role.name}, schoolId: $schoolId)');
    final repo = _repo();
    _requireAdminOrCoordinator();
    if (email.trim().isEmpty || fullName.trim().isEmpty) {
      throw const ViewModelException('Email and full name are required.');
    }
    if (schoolId == null && !(_isSuperadmin && role == UserRole.admin)) {
      throw const ViewModelException('Only a superadmin can create an admin with no school.');
    }
    if (schoolId != null && !_isSuperadmin && schoolId != _auth.currentUser?.schoolId) {
      throw const ViewModelException('Forbidden: you can only create users for your own school.');
    }

    final String? tempPassword;
    try {
      tempPassword = await repo.create(User(
        id: '',
        email: email.trim(),
        fullName: fullName.trim(),
        role: role,
        schoolId: schoolId,
        createdAt: DateTime.now(),
        // created_by is taken from the caller's JWT server-side.
      ));
    } on FunctionException catch (e) {
      throw ViewModelException(edgeFunctionErrorMessage(e));
    }
    await _mirror(() async {
      final created = await repo.getByEmail(email.trim());
      if (created == null) throw StateError('the new account is not readable yet');
      await _local!.upsertMirror(created);
    });
    await _refreshIfLoaded();
    return tempPassword;
  }

  Future<User?> findByEmail(String email) async {
    _log('findByEmail(email: "$email")');
    return _repo().getByEmail(email);
  }

  /// Activates or deactivates an account. Changing your own active flag is
  /// refused here (and by RLS) so an admin can't lock themselves out.
  Future<void> setActive(String id, bool isActive) async {
    _log('setActive(id: $id, isActive: $isActive)');
    final repo = _repo();
    _requireAdminOrCoordinator();
    if (id == _auth.currentUser?.id) {
      throw const ViewModelException('You cannot change your own active status.');
    }
    try {
      await repo.setActive(id, isActive);
    } on PostgrestException catch (e) {
      throw ViewModelException(e.message);
    }
    await _mirror(() => _local!.setActive(id, isActive));
    await _refreshIfLoaded();
  }

  Future<void> _mirror(Future<void> Function() write) async {
    lastMirrorWarning = null;
    if (_local == null) return;
    try {
      await write();
    } catch (e) {
      lastMirrorWarning = 'Saved online, but not copied onto this device ($e); run pull-cloud.';
      _log('mirror failed: $e');
    }
  }

  Future<void> _refreshIfLoaded() async {
    if (items.isNotEmpty) items = await _repo().getAll();
  }
}
