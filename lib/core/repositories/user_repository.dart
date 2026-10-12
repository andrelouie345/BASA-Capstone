// lib/core/repositories/user_repository.dart
import '../models/user.dart';

abstract class UserRepository {
  /// Creates the account. Returns the one-time temporary password when the
  /// backend issues one (Supabase), or null when it doesn't (local mirror).
  Future<String?> create(User user);
  Future<User?> getById(String id);
  Future<User?> getByEmail(String email);
  Future<List<User>> getAll();
  Future<void> setActive(String id, bool isActive);
}