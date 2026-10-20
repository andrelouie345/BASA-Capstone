// lib/core/data/local/sync_local_writes.dart
//
// Writes that respect the v34 sync bookkeeping (sync_local_schema.dart):
// - nextLocalId: the id of every new row in the 14 id-keyed synced tables.
// - withSyncBypass: lets a pull, a mirror write or the v34 renumber change
//   server rows without journaling or lock refusals. Takes a Transaction, so
//   the bypass row never outlives the transaction that wrote it.
// - mirrorSyncedRow: a cloud row copied onto this device outside a pull
//   (e.g. CRLA regenerate), the synced-table form of upsertById.
import 'package:sqflite_common/sqflite.dart';

import 'mirror_write.dart';

/// The next local id: -1, -2, ... One countdown for all tables (one INSERT,
/// so two writes can never get the same number), never reused.
Future<int> nextLocalId(DatabaseExecutor db) async =>
    -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));

/// Runs [body] with the sync triggers switched off, inside [txn].
Future<T> withSyncBypass<T>(Transaction txn, Future<T> Function() body) async {
  await txn.insert('sync_meta', {'key': 'sync_bypass', 'value': '1'}, conflictAlgorithm: ConflictAlgorithm.replace);
  try {
    return await body();
  } finally {
    await txn.delete('sync_meta', where: "key = 'sync_bypass'");
  }
}

/// Writes a cloud [row] of a synced table under its cloud key, in one
/// transaction under the bypass. An existing row keeps its local row_version
/// unless [row] carries one; a new row gets row_version `row['row_version'] ?? 0`
/// (0 = server version unknown: a later local edit reports a conflict instead
/// of overwriting). [replace] = INSERT OR REPLACE, for the CRLA part tables
/// (an UPDATE would re-run their compute triggers over the cloud's values);
/// their row_version is carried over the same way.
Future<void> mirrorSyncedRow(
  Database db,
  String table,
  Map<String, Object?> row, {
  String key = 'id',
  bool replace = false,
}) async {
  final id = row[key];
  if (id == null) throw ArgumentError('mirrorSyncedRow on $table needs a $key');
  await db.transaction((txn) => withSyncBypass(txn, () async {
        final existing = await txn.query(table, columns: ['row_version'], where: '$key = ?', whereArgs: [id], limit: 1);
        final full = {
          ...row,
          'row_version': row['row_version'] ?? (existing.isEmpty ? 0 : existing.first['row_version'] ?? 0),
        };
        if (replace) {
          await txn.insert(table, full, conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          // An existing row keeps its row_version: [row] only has one if given.
          await upsertById(txn, table, existing.isEmpty ? full : row, key: key);
        }
      }));
}
