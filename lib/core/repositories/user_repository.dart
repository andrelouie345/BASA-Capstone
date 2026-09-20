// lib/core/repositories/user_repository.dart
import '../models/user.dart';
import '../models/user_role.dart';

abstract class UserRepository {
  Future<void> create(User user);
  Future<User?> getById(String id);
  Future<User?> getByEmail(String email);
  Future<List<User>> getAll();
  Future<void> setActive(String id, bool isActive);
}