import '../core/console/logger.dart';
import '../core/models/login_log.dart';
import '../core/models/sourced_login_log.dart';
import '../core/repositories/login_log_repository.dart';

class LoginLogViewModel {
  final ScopedLogger _log;
  LoginLogRepository _repo; // this device's log (SQLite)
  List<SourcedLoginLog> items = [];

  /// Set when the cloud log was requested but couldn't be read; [items] then
  /// holds the local log only.
  String? cloudError;

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

  /// Most recent attempts from this device's log, merged with the cloud log
  /// when [cloud] is given (the cloud side is scoped by RLS to what the
  /// signed-in user may see). Each entry is tagged with where it was found.
  Future<void> loadRecent({int limit = 50, LoginLogRepository? cloud}) async {
    _log('loadRecent(limit: $limit, cloud: ${cloud != null})');
    await _load(
      () => _repo.getRecent(limit: limit),
      cloud == null ? null : () => cloud.getRecent(limit: limit),
      limit: limit,
    );
  }

  Future<void> loadForUser(String userId, {LoginLogRepository? cloud}) async {
    _log('loadForUser(userId: $userId, cloud: ${cloud != null})');
    await _load(
      () => _repo.getForUser(userId),
      cloud == null ? null : () => cloud.getForUser(userId),
    );
  }

  Future<void> _load(
    Future<List<LoginLog>> Function() local,
    Future<List<LoginLog>> Function()? cloud, {
    int? limit,
  }) async {
    cloudError = null;
    final merged = <String, SourcedLoginLog>{};

    void add(List<LoginLog> logs, LogSource source) {
      for (final l in logs) {
        merged.putIfAbsent(_key(l), () => SourcedLoginLog(l, {})).sources.add(source);
      }
    }

    add(await local(), LogSource.local);
    if (cloud != null) {
      try {
        add(await cloud(), LogSource.cloud);
      } catch (e) {
        cloudError = e.toString();
        _log('cloud login-log read failed: $e');
      }
    }

    final sorted = merged.values.toList()
      ..sort((a, b) => b.log.timestamp.compareTo(a.log.timestamp));
    items = limit == null ? sorted : sorted.take(limit).toList();
  }

  // The same attempt in both stores has the same email, outcome and instant.
  // (Cloud rows written before the UTC fix are 8h off and won't pair up.)
  static String _key(LoginLog l) =>
      '${l.emailAttempted}|${l.success}|${l.timestamp.toUtc().microsecondsSinceEpoch}';
}
