import 'package:supabase/supabase.dart' hide User;

import '../core/console/logger.dart';
import '../core/models/login_log.dart';
import '../core/models/sourced_login_log.dart';
import '../core/models/user_role.dart';
import '../core/repositories/login_log_repository.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Sign-in attempts, this device's log merged with the server's. Admins and
/// coordinators only; the checks are here because screens call this
/// ViewModel directly.
class LoginLogViewModel {
  final ScopedLogger _log;
  final LoginLogRepository _repo; // this device's log (SQLite)
  final AuthViewModel _auth;
  final LoginLogRepository Function(SupabaseClient client) _cloudFor;
  List<SourcedLoginLog> items = [];

  /// Set when the server's log couldn't be read; [items] then holds this
  /// device's log only. A sentence for the user (the detail is logged).
  String? cloudError;

  LoginLogViewModel({
    required LoginLogRepository repo,
    required AuthViewModel auth,
    required LoginLogRepository Function(SupabaseClient client) cloudFor,
    Logger? logger,
  })  : _repo = repo,
        _auth = auth,
        _cloudFor = cloudFor,
        _log = ScopedLogger(logger, 'LoginLogViewModel');

  void _requireAdminOrCoordinator() {
    final role = _auth.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: admin or coordinator only.');
    }
  }

  /// Online session + admin/coordinator; the server's log repository.
  LoginLogRepository _cloud() {
    final error = _auth.requireOnlineSession();
    if (error != null) throw ViewModelException(error);
    _requireAdminOrCoordinator();
    return _cloudFor(_auth.client!);
  }

  /// Writes an attempt to this device's log (a test tool; sign-in logs its
  /// own attempts).
  Future<void> record(LoginLog attempt) async {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
    _requireAdminOrCoordinator();
    _log('record(email: "${attempt.emailAttempted}", success: ${attempt.success})');
    await _repo.log(attempt);
  }

  /// Most recent attempts from this device's log, merged with the server's
  /// (scoped by RLS to what the signed-in user may see). Each entry is tagged
  /// with where it was found.
  Future<void> loadRecent({int limit = 50}) async {
    final cloud = _cloud();
    _log('loadRecent(limit: $limit)');
    await _load(
      () => _repo.getRecent(limit: limit),
      () => cloud.getRecent(limit: limit),
      limit: limit,
    );
  }

  Future<void> loadForUser(String userId) async {
    final cloud = _cloud();
    _log('loadForUser(userId: $userId)');
    await _load(
      () => _repo.getForUser(userId),
      () => cloud.getForUser(userId),
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
        cloudError = "The server's log could not be read.";
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
