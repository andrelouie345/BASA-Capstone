// lib/core/repositories/sync_download_source.dart

/// Everything the signed-in user can read on the server, for a pull.
abstract class SyncDownloadSource {
  /// Every table of pullOrder (data/pull_tables.dart), in that order, all
  /// rows. Throws on any network or server error (nothing partial is used).
  Future<Map<String, List<Map<String, dynamic>>>> downloadAll();
}
