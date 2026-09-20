// lib/core/data/remote/login_log_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/login_log.dart';
import '../../repositories/login_log_repository.dart';

class LoginLogRepositorySupabase implements LoginLogRepository {
  final SupabaseClient client;
  LoginLogRepositorySupabase(this.client);

  @override
  Future<void> log(LoginLog attempt) async {
    await client.from('login_logs').insert({
      'user_id': attempt.userId,
      'email_attempted': attempt.emailAttempted,
      'success': attempt.success,
      'method': attempt.method.name,
      'timestamp': attempt.timestamp.toIso8601String(),
      'failure_reason': attempt.failureReason,
    });
  }

  @override
  Future<List<LoginLog>> getRecent({int limit = 50}) async {
    final rows = await client.from('login_logs').select().order('timestamp', ascending: false).limit(limit);
    return (rows as List).map((r) => LoginLog.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<List<LoginLog>> getForUser(String userId) async {
    final rows = await client.from('login_logs').select().eq('user_id', userId).order('timestamp', ascending: false);
    return (rows as List).map((r) => LoginLog.fromMap(r as Map<String, Object?>)).toList();
  }
}