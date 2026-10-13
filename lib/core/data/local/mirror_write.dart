// lib/core/data/local/mirror_write.dart
import 'package:sqflite_common/sqflite.dart';

/// Thrown when a mirrored row's unique key (LRN, school code, section
/// 4-tuple, ...) already belongs to a different local row.
class MirrorConflictException implements Exception {
  final String table;
  final Object id;
  final String detail;
  MirrorConflictException(this.table, this.id, this.detail);

  @override
  String toString() =>
      'Cannot mirror $table id $id: another local row already has the same unique key ($detail)';
}

/// Writes a cloud row locally under its cloud id: UPDATE by [key], or INSERT
/// when no row has that key.
///
/// Not INSERT OR REPLACE: REPLACE deletes whichever row holds a clashing
/// UNIQUE value, even under a different id, and leaves that row's children
/// orphaned (local foreign keys are off). Here a clash throws instead.
/// Columns missing from [row] keep their local value on update.
///
/// Don't use it for the CRLA Part 1/2 tables: an UPDATE fires their compute
/// triggers and overwrites the cloud's wpm/totals. They keep REPLACE (their
/// primary key is their only unique key and they have no children).
Future<void> upsertById(
  DatabaseExecutor db,
  String table,
  Map<String, Object?> row, {
  String key = 'id',
}) async {
  final id = row[key];
  if (id == null) throw ArgumentError('upsertById on $table needs a $key');
  final values = Map.of(row)..remove(key);
  try {
    if (values.isEmpty) {
      await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.ignore);
      return;
    }
    final updated = await db.update(table, values, where: '$key = ?', whereArgs: [id]);
    if (updated == 0) await db.insert(table, row); // ABORT on a UNIQUE clash
  } on DatabaseException catch (e) {
    if (e.isUniqueConstraintError()) {
      // Keep only "UNIQUE constraint failed: <columns>"; the rest repeats the SQL.
      final msg = '$e';
      final m = RegExp(r'UNIQUE constraint failed: \w+\.\w+(, \w+\.\w+)*').firstMatch(msg);
      throw MirrorConflictException(table, id, m?.group(0) ?? msg);
    }
    rethrow;
  }
}
