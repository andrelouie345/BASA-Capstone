// lib/core/services/offline_signin_rules.dart
//
// When the device owner may sign in without a connection (sync spec
// section 6). Pure: the caller loads the stored credential, hashes the typed
// password and reads the window; this decides.
import '../models/offline_credential.dart';

/// Wrong offline passwords allowed before offline sign-in is disabled until
/// the next online sign-in.
const offlineMaxFailedAttempts = 5;

/// How far the device clock may be behind the last online sign-in (small
/// clock drift) before offline sign-in is refused.
const offlineClockTolerance = Duration(minutes: 5);

enum OfflineRefusal { noCredential, wrongEmailOrPassword, tooManyAttempts, notDeviceOwner, clockBehind, windowExpired, inactive }

/// Null = allowed. Checked in this order, so a sixth try with the right
/// password is still refused, and a stranger's email learns nothing more
/// than a wrong password would.
OfflineRefusal? offlineSignInRefusal({
  required OfflineCredential? stored,
  required String email,
  required bool passwordMatches,
  required String? dataOwnerId,
  required bool? localUserActive,
  required int windowDays,
  required DateTime now,
}) {
  if (stored == null) return OfflineRefusal.noCredential;
  if (email.trim().toLowerCase() != stored.email.trim().toLowerCase()) return OfflineRefusal.wrongEmailOrPassword;
  if (stored.failedAttempts >= offlineMaxFailedAttempts) return OfflineRefusal.tooManyAttempts;
  if (!passwordMatches) return OfflineRefusal.wrongEmailOrPassword;
  if (dataOwnerId != stored.userId) return OfflineRefusal.notDeviceOwner;
  final lastOnline = DateTime.parse(stored.lastOnlineAt);
  if (now.isBefore(lastOnline.subtract(offlineClockTolerance))) return OfflineRefusal.clockBehind;
  if (now.difference(lastOnline) > Duration(days: windowDays)) return OfflineRefusal.windowExpired;
  if (localUserActive != true) return OfflineRefusal.inactive;
  return null;
}

String offlineRefusalMessage(OfflineRefusal r, {int? windowDays}) => switch (r) {
      OfflineRefusal.noCredential =>
        'Offline sign-in is not set up on this device. Sign in online first.',
      OfflineRefusal.wrongEmailOrPassword => 'Offline sign-in failed: wrong email or password.',
      OfflineRefusal.tooManyAttempts =>
        'Offline sign-in is disabled after $offlineMaxFailedAttempts wrong passwords. Sign in online.',
      OfflineRefusal.notDeviceOwner =>
        'Offline sign-in failed: the data on this device is not yours. Sign in online and pull first.',
      OfflineRefusal.clockBehind =>
        "Offline sign-in failed: this device's clock is earlier than your last online sign-in. Check the date.",
      OfflineRefusal.windowExpired =>
        'Offline sign-in failed: more than ${windowDays ?? '?'} days since your last online sign-in. Sign in online.',
      OfflineRefusal.inactive => 'Offline sign-in failed: account is inactive on this device.',
    };
