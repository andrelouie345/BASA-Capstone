// lib/core/repositories/offline_credential_repository.dart
import '../models/offline_credential.dart';

/// The single offline sign-in credential kept on this device (local only).
abstract class OfflineCredentialRepository {
  /// The stored credential, or null when none has been saved.
  Future<OfflineCredential?> get();

  /// Replaces whatever is stored (there is only ever one row).
  Future<void> save(OfflineCredential credential);

  /// Removes the credential if it belongs to [userId] (the server refused
  /// or reset that account); a no-op otherwise.
  Future<void> revoke(String userId);

  /// Counts one wrong offline password for [userId].
  Future<void> recordFailure(String userId);

  /// The user whose data is on this device: the last successful pull
  /// (sync_meta last_pull_user_id), or null if the device was never pulled.
  Future<String?> dataOwnerId();
}
