// lib/core/repositories/sync_local_repository.dart
import '../models/sync_pull.dart';

/// This device's side of a pull (sync spec section 7).
abstract class SyncLocalRepository {
  /// The last successful puller, or null if the device was never pulled.
  Future<PullOwner?> owner();

  /// New, edited and pending work not on the server yet.
  Future<List<LocalWorkLine>> localWork();

  /// Hands the device to [userId] at an online sign-in. Nothing changes when
  /// they already own it. Otherwise the device copy is deleted (every table a
  /// pull empties, the sync journal, other users' offline sign-in) and
  /// [userId] becomes the owner, in one transaction; unless the device holds
  /// work not on the server yet (new, edited or pending): then nothing
  /// changes and that work comes back as [DeviceHandover.unsent].
  Future<DeviceHandover> handOver({required String userId, required String? email});

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
