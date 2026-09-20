// lib/viewmodels/login_log_viewmodel.dart
import '../core/console/logger.dart';
import '../core/models/login_log.dart';
import '../core/repositories/login_log_repository.dart';

class LoginLogViewModel {
  final ScopedLogger _log;
  LoginLogRepository _repo;
  List<LoginLog> items = [];

  LoginLogViewModel({required LoginLogRepository repo, Logger? logger})
      : _repo = repo,
        _log = ScopedLogger(logger, 'LoginLogViewModel');

  void useRepository(LoginLogRepository repo, String label) {
    _repo = repo;
    _log('switched backend -> $label');
  }

  Future<void> record(LoginLog attempt) async {
    _log('record(email: "${attempt.emailAttempted}", success: ${attempt.success})');
    await _repo.log(attempt);
  }

  Future<void> loadRecent({int limit = 50}) async {
    _log('loadRecent(limit: $limit)');
    items = await _repo.getRecent(limit: limit);
  }

  Future<void> loadForUser(String userId) async {
    _log('loadForUser(userId: $userId)');
    items = await _repo.getForUser(userId);
  }
}