// lib/core/repositories/sync_local_repository.dart
import '../models/sync_pull.dart';

/// This device's side of a pull (sync spec section 7).
abstract class SyncLocalRepository {
  /// The last successful puller, or null if the device was never pulled.
  Future<PullOwner?> owner();

  /// New, edited and pending work not on the server yet.
  Future<List<LocalWorkLine>> localWork();

  /// Merges a full download into the local copy in one transaction: server
  /// copies refreshed, local work kept (or deleted first with
  /// [discardLocal]), and the puller recorded as the owner. Throws
  /// [PullOrphansException] (rolled back) when kept work points at data the
  /// download no longer holds.
  Future<PullMerge> mergePull(
    Map<String, List<Map<String, dynamic>>> fetched, {
    required String userId,
    required String? email,
    required bool discardLocal,
  });
}
