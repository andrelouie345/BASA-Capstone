// lib/core/repositories/sync_review_local_repository.dart

/// Rows the approver's device already holds, read to name the records of an
/// upload (sync spec 5.2): the synced tables plus students, sections, users
/// and schools.
abstract class SyncReviewLocalRepository {
  /// Rows of [table] whose [column] is one of [values]. Throws
  /// [ArgumentError] for any other table.
  Future<List<Map<String, Object?>>> rowsWhere(String table, String column, List<Object> values);
}
