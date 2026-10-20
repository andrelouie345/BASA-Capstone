// lib/core/models/offline_credential.dart
//
// The device owner's offline sign-in credential (sync spec section 6): one
// row in the local-only offline_credentials table, written after a clean
// online sign-in or a password change. salt and hash are lowercase hex;
// hash = PBKDF2-HMAC-SHA256(password, salt, iterations). Never leaves the
// device.
class OfflineCredential {
  final String userId;
  final String email;
  final String salt;
  final int iterations;
  final String hash;
  final String lastOnlineAt;   // UTC ISO-8601
  final int failedAttempts;    // wrong offline passwords since the last online sign-in

  const OfflineCredential({
    required this.userId,
    required this.email,
    required this.salt,
    required this.iterations,
    required this.hash,
    required this.lastOnlineAt,
    this.failedAttempts = 0,
  });

  Map<String, Object?> toMap() => {
        'user_id': userId,
        'email': email,
        'salt': salt,
        'iterations': iterations,
        'hash': hash,
        'last_online_at': lastOnlineAt,
        'failed_attempts': failedAttempts,
      };

  factory OfflineCredential.fromMap(Map<String, Object?> m) => OfflineCredential(
        userId: m['user_id'] as String,
        email: m['email'] as String,
        salt: m['salt'] as String,
        iterations: m['iterations'] as int,
        hash: m['hash'] as String,
        lastOnlineAt: m['last_online_at'] as String,
        failedAttempts: m['failed_attempts'] as int? ?? 0,
      );
}
