// lib/core/repositories/sync_remote_repository.dart
import '../models/sync_upload.dart';

/// The server's side of an upload (sync spec sections 2, 5.1): the
/// sync_uploads table, its functions, and keyed reads of the synced tables.
/// Every method throws on a network or server error.
abstract class SyncRemoteRepository {
  /// Rows of [table] whose [column] is one of [values] (as the signed-in
  /// user may read them), [columns] as a PostgREST select list.
  Future<List<Map<String, dynamic>>> rowsWhere(String table, String column, List<Object> values, {String columns = '*'});

  /// Inserts a pending upload by the signed-in user.
  Future<SyncUploadRow> insertUpload({
    required String clientUploadId,
    required int? schoolId,
    required String deviceId,
    required String release,
    required Map<String, Object?> payload,
    required Map<String, Object?> summary,
  });

  /// The signed-in user's upload with this device-made id, if it reached the server.
  Future<SyncUploadRow?> uploadByClientId(String clientUploadId);

  /// The signed-in user's uploads, newest first ([ids] limits them).
  Future<List<SyncUploadRow>> myUploads({List<int>? ids, int limit = 20});

  /// Does [schoolId] auto-approve uploads (school, else region-wide, else no)?
  Future<bool> autoApprove(int? schoolId);

  Future<SyncApplyResult> apply(int uploadId);

  Future<void> withdraw(int uploadId);

  // ---- Approver (S6) ----

  /// Uploads of [schoolId] (null = every school the caller may read) with
  /// one of [statuses], oldest first. Never the payload.
  Future<List<SyncUploadRow>> schoolUploads({int? schoolId, required List<String> statuses});

  /// One upload the caller may read, with its payload when [withPayload].
  Future<SyncUploadRow?> uploadById(int id, {bool withPayload = false});

  Future<void> reject(int uploadId, String reason);
}
