// lib/core/repositories/sync_upload_local_repository.dart
import '../models/sync_upload.dart';

/// This device's side of an upload (sync spec sections 4-5).
abstract class SyncUploadLocalRepository {
  /// This device's id (made once, kept in sync_meta).
  Future<String> deviceId();

  /// Every new record and every change to a server record that is not
  /// already waiting in an upload, in the order the server applies them.
  Future<SyncPackage> buildPackage({required String release});

  /// sync-resolve mine: the change overwrites the server's [version].
  Future<void> setBaseVersion(String table, String key, int version);

  /// sync-resolve mine on a delete the server already made: nothing to send.
  Future<void> dropJournalLine(String table, String key);

  /// sync-resolve server: the record and its items become the server's copy
  /// in [serverRows] (per table; empty = the server has none, so they are
  /// removed here). Their journal lines go. New items under a record the
  /// server still has are kept.
  Future<void> restoreServerCopy(String table, String key, Map<String, List<Map<String, dynamic>>> serverRows);

  /// Is this record waiting in an upload?
  Future<bool> isPending(String table, String key);

  /// Before sending: keeps [package] as in flight and locks its records
  /// (upload 0), in one transaction.
  Future<void> beginUpload(String clientUploadId, SyncPackage package);

  /// The upload being sent, if its answer never came.
  Future<InFlightUpload?> inFlight();

  /// The server took it as upload [uploadId]: the lock moves to that id and
  /// the in-flight copy goes.
  Future<void> confirmUpload(int uploadId);

  /// The server never got it: lock and in-flight copy go.
  Future<void> abandonUpload();

  /// Uploads (server ids) whose records are locked on this device.
  Future<List<int>> pendingUploadIds();

  /// (table, key) of every record locked under [uploadId].
  Future<List<(String, String)>> pendingRecords(int uploadId);

  /// Lifts the lock of [uploadId] (rejected, failed, withdrawn, conflict).
  Future<void> releaseUpload(int uploadId);

  /// Takes in applied upload [uploadId] in one transaction: device ids become
  /// the server's ([idMap]: table -> device id -> server id, as sync_apply
  /// returns it) everywhere they are used, the records
  /// become the server's copies in [serverRows] (a record the server did not
  /// give back keeps its local values with version 0 = unknown), and their
  /// journal and lock lines go. Returns the records taken in; 0 when already
  /// done.
  Future<int> takeInApplied(int uploadId, Map<String, Map<int, int>> idMap, Map<String, List<Map<String, dynamic>>> serverRows);
}
