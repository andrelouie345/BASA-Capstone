// lib/core/repositories/login_log_repository.dart
import '../models/login_log.dart';

abstract class LoginLogRepository {
  Future<void> log(LoginLog attempt);
  Future<List<LoginLog>> getRecent({int limit = 50});
  Future<List<LoginLog>> getForUser(String userId);
}