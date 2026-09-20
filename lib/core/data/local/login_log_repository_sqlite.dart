// lib/core/data/local/login_log_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/login_log.dart';
import '../../repositories/login_log_repository.dart';

class LoginLogRepositorySqlite implements LoginLogRepository {
  final Database db;
  LoginLogRepositorySqlite(this.db);

  @override
  Future<void> log(LoginLog attempt) async {
    await db.insert('login_logs', {
      'user_id': attempt.userId,
      'email_attempted': attempt.emailAttempted,
      'success': attempt.success ? 1 : 0,
      'method': attempt.method.name,
      'timestamp': attempt.timestamp.toIso8601String(),
      'failure_reason': attempt.failureReason,
    });
  }

  @override
  Future<List<LoginLog>> getRecent({int limit = 50}) async {
    final rows = await db.query('login_logs', orderBy: 'id DESC', limit: limit);
    return rows.map(LoginLog.fromMap).toList();
  }

  @override
  Future<List<LoginLog>> getForUser(String userId) async {
    final rows = await db.query(
      'login_logs',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
    );
    return rows.map(LoginLog.fromMap).toList();
  }
}