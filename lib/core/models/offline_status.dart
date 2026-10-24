// lib/core/models/offline_status.dart
// What this device's offline sign-in allows: whose it is, until when, and how
// many wrong passwords are left (AuthViewModel.offlineStatus).
class OfflineStatus {
  final String email;
  final String lastOnlineAt; // UTC ISO-8601
  final int windowDays;
  final DateTime until; // lastOnlineAt + windowDays
  final int failedAttempts;
  final int maxFailedAttempts;

  const OfflineStatus({
    required this.email,
    required this.lastOnlineAt,
    required this.windowDays,
    required this.until,
    required this.failedAttempts,
    required this.maxFailedAttempts,
  });
}
