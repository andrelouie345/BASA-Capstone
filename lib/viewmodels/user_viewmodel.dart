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
  Future<void> create(User user) async {
    _log('create(email: "${user.email}", role: ${user.role.name})');
    if (user.schoolId == null && user.role != UserRole.admin) {
      throw ArgumentError('schoolId is required for non-admin accounts');
    }
    await _repo.create(user);
    await refresh();
  }

  Future<User?> findByEmail(String email) async {
    _log('findByEmail(email: "$email")');
    return _repo.getByEmail(email);
  }

  Future<void> setActive(String id, bool isActive) async {
    _log('setActive(id: $id, isActive: $isActive)');
    await _repo.setActive(id, isActive);
    await refresh();
  }
}