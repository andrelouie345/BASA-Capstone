// lib/core/data/local/sync_review_local_sqlite.dart
import 'package:sqflite_common/sqflite.dart';

import '../../repositories/sync_review_local_repository.dart';
import '../pull_tables.dart' show syncedTables;

const _otherTables = {'students', 'sections', 'users', 'schools'};

class SyncReviewLocalSqlite implements SyncReviewLocalRepository {
  final Database _db;
  SyncReviewLocalSqlite(this._db);

  @override
  Future<List<Map<String, Object?>>> rowsWhere(String table, String column, List<Object> values) async {
    // Names go into the SQL text, so only known tables and their columns.
    if (!syncedTables.containsKey(table) && !_otherTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'not a table an upload is read against');
    }
    final columns = (await _db.rawQuery('PRAGMA table_info($table)')).map((c) => c['name']).toSet();
    if (!columns.contains(column)) throw ArgumentError.value(column, 'column', 'not a column of $table');
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < values.length; i += 500) {
      final chunk = values.sublist(i, i + 500 > values.length ? values.length : i + 500);
      out.addAll(await _db.query(table,
          where: '$column IN (${List.filled(chunk.length, '?').join(', ')})', whereArgs: chunk));
    }
    return out;
  }
}
