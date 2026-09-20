// lib/core/models/login_log.dart
import 'login_method.dart';

class LoginLog {
  final int? id; // null until persisted (SQLite autoincrement)
  final String? userId; // null if attempt failed before resolving to a known user
  final String emailAttempted;
  final bool success;
  final LoginMethod method;
  final DateTime timestamp;
  final String? failureReason; // e.g. 'wrong_password', 'unknown_email', 'no_connection'

  const LoginLog({
    this.id,
    this.userId,
    required this.emailAttempted,
    required this.success,
    required this.method,
    required this.timestamp,
    this.failureReason,
  });

  factory LoginLog.fromMap(Map<String, dynamic> map) => LoginLog(
        id: map['id'] as int?,
        userId: map['user_id'] as String?,
        emailAttempted: map['email_attempted'] as String,
        success: map['success'] is bool ? map['success'] as bool : (map['success'] as int) == 1,
        method: LoginMethod.fromString(map['method'] as String),
        timestamp: DateTime.parse(map['timestamp'] as String),
        failureReason: map['failure_reason'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'email_attempted': emailAttempted,
        'success': success ? 1 : 0,
        'method': method.name,
        'timestamp': timestamp.toIso8601String(),
        'failure_reason': failureReason,
      };
}