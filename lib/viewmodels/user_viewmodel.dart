// lib/viewmodels/user_viewmodel.dart

import 'package:basa_capstone/core/models/user_role.dart';
import '../core/console/logger.dart';
import '../core/models/user.dart';
import '../core/repositories/user_repository.dart';

class UserViewModel {
  final ScopedLogger _log;
  UserRepository _repo;
  List<User> items = [];

  UserViewModel({required UserRepository repo, Logger? logger})
      : _repo = repo,
        _log = ScopedLogger(logger, 'UserViewModel');

  void useRepository(UserRepository repo, String label) {
    _repo = repo;
    _log('switched backend -> $label');
  }

  Future<void> refresh() async {
    _log('refresh()');
    items = await _repo.getAll();
  }

  // NOTE: only meaningful against a Supabase-backed repo. Calling this
  // against UserRepositorySqlite creates a profile row with no matching
  // Supabase Auth account behind it — an unusable, orphaned "user" that
  // can never actually log in. Local repo is for caching/reading a user
  // that already exists in Auth, not for originating new accounts.
  /// Returns the one-time temporary password for the new account (or null
  /// if the backend didn't issue one). Show it to the creating admin once.
  Future<String?> create(User user) async {
    _log('create(email: "${user.email}", role: ${user.role.name})');
    if (user.schoolId == null && user.role != UserRole.admin) {
      throw ArgumentError('schoolId is required for non-admin accounts');
    }
    final tempPassword = await _repo.create(user);
    await refresh();
    return tempPassword;
  }

  Future<User?> findByEmail(String email) async {
    _log('findByEmail(email: "$email")');
    return _repo.getByEmail(email);
  }

  /// [actingUserId] is the signed-in user; changing your own active flag is
  /// refused here (and by RLS) so an admin can't lock themselves out.
  Future<void> setActive(String id, bool isActive, {String? actingUserId}) async {
    _log('setActive(id: $id, isActive: $isActive)');
    if (actingUserId != null && id == actingUserId) {
      throw ArgumentError('You cannot change your own active status.');
    }
    await _repo.setActive(id, isActive);
    await refresh();
  }
}