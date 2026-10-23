// lib/core/data/local/sync_upload_local_sqlite.dart
//
// The local side of an upload (sync spec sections 4-5). The package holds:
// - every new row (row_version NULL) as an insert under its negative id
//   (CRLA parts by assessment_id, tutor settings by tutor_id);
// - every sync_changes line as an update (the current local row) or a
//   delete, with the server version it was based on;
// skipping records already waiting in an upload (sync_pending). Order:
// deletes (children first), inserts (parents first), updates (children
// first); see _records.
//
// Lock lifecycle: beginUpload locks every record of the package under upload
// 0 and keeps the package as in flight (sync_meta); confirmUpload moves the
// lock to the server's id, abandonUpload lifts it. takeInApplied turns an
// applied upload's records into server copies.
import 'dart:convert';

import 'package:sqflite_common/sqflite.dart';

import '../../models/sync_upload.dart';
import '../../repositories/sync_upload_local_repository.dart';
import '../../services/sync_upload_rules.dart';
import '../pull_tables.dart';
import 'sync_local_repository_sqlite.dart';
import 'sync_local_schema.dart' show withOtherSyncTableTriggersOff, followLocalIds;
import 'sync_local_writes.dart';

/// sync_meta key of the upload being sent.
const _inFlightKey = 'upload_in_flight';

class SyncUploadLocalSqlite implements SyncUploadLocalRepository {
  final Database db;
  SyncUploadLocalSqlite(this.db);

  @override
  Future<String> deviceId() async {
    final rows = await db.query('sync_meta', columns: ['value'], where: "key = 'device_id'");
    final existing = rows.isEmpty ? null : rows.first['value'] as String?;
    if (existing != null) return existing;
    final id = newUuidV4();
    // IGNORE: if two callers race, both read back the one that was stored.
    await db.insert('sync_meta', {'key': 'device_id', 'value': id}, conflictAlgorithm: ConflictAlgorithm.ignore);
    return deviceId();
  }

  @override
  Future<SyncPackage> buildPackage({required String release}) async {
    final records = await _records(db);
    final summary = (await SyncLocalRepositorySqlite(db).localWork())
        .where((l) => !l.kind.startsWith(pendingWorkKind))
        .toList();
    return SyncPackage(release: release, deviceId: await deviceId(), records: records, summary: summary);
  }

  /// The package's records, in the order the server applies them:
  /// 1. deletes, children first (pullClearOrder): a record deleted and
  ///    entered again with the same natural key (a mark, a reading, an IRIP
  ///    week) frees the key before the new one arrives;
  /// 2. inserts, parents first (pullOrder; negative ids in creation order);
  /// 3. updates, children first: a change that closes a record (a learner
  ///    exited, a session finalized) comes after the work under it. Follow-
  ///    up updates (no base_version; migration 20261021010000) come right
  ///    after: the columns the server resets on a new record, and a server
  ///    session's finalize step (sync_upload_rules.dart).
  /// A record re-opened and then given new work fails on the server (error,
  /// with its reason); syncing right after re-opening avoids it.
  static Future<List<SyncRecord>> _records(DatabaseExecutor db) async {
    final records = <SyncRecord>[];
    String notPending(String t, String key) => "NOT EXISTS (SELECT 1 FROM sync_pending p WHERE p.table_name = '$t' "
        'AND p.row_key = CAST(c.$key AS TEXT))';

    for (final t in pullClearOrder.where(syncedTables.containsKey)) {
      final key = syncedTables[t]!;
      final lines = await db.rawQuery('''
          SELECT j.row_key, j.base_version FROM sync_changes j
          WHERE j.table_name = ? AND j.op = 'delete'
            AND NOT EXISTS (SELECT 1 FROM sync_pending p WHERE p.table_name = j.table_name AND p.row_key = j.row_key)
          ORDER BY j.row_key''', [t]);
      for (final l in lines) {
        final k = l['row_key'] as String;
        records.add(SyncRecord(
          table: t,
          op: 'delete',
          keyColumn: key,
          key: key == 'tutor_id' ? k : int.parse(k),
          baseVersion: l['base_version'] as int,
        ));
      }
    }

    for (final t in pullOrder.keys.where(syncedTables.containsKey)) {
      final key = syncedTables[t]!;
      // Negative ids in creation order (-1, -2, ...).
      final order = key == 'id' ? 'c.id DESC' : 'c.$key';
      for (final r in await db
          .rawQuery('SELECT c.* FROM $t c WHERE c.row_version IS NULL AND ${notPending(t, key)} ORDER BY $order')) {
        records.add(SyncRecord(
          table: t,
          op: 'insert',
          keyColumn: key,
          key: r[key]!,
          row: toServerRow(t, r, keyColumn: key, insert: true),
        ));
      }
    }

    for (final t in pullClearOrder.where(syncedTables.containsKey)) {
      final key = syncedTables[t]!;
      for (final r in await db.rawQuery('''
          SELECT c.*, j.base_version AS sync_base_version FROM $t c
          JOIN sync_changes j ON j.table_name = '$t' AND j.row_key = CAST(c.$key AS TEXT)
          WHERE j.op = 'update' AND ${notPending(t, key)} ORDER BY c.$key''')) {
        final row = Map<String, Object?>.of(r)..remove('sync_base_version');
        final (first, more) = splitServerUpdate(t, toServerRow(t, row, keyColumn: key, insert: false));
        records.add(SyncRecord(
          table: t,
          op: 'update',
          keyColumn: key,
          key: r[key]!,
          baseVersion: r['sync_base_version'] as int,
          row: first,
        ));
        for (final f in more) {
          records.add(SyncRecord(table: t, op: 'update', keyColumn: key, key: r[key]!, row: f));
        }
      }
      // New records whose insert the server resets (followUpsForNew).
      for (final insert in records.where((r) => r.table == t && r.op == 'insert').toList()) {
        for (final f in followUpsForNew(t, insert.row!)) {
          records.add(SyncRecord(table: t, op: 'update', keyColumn: key, key: insert.key, row: f));
        }
      }
    }
    return records;
  }

  @override
  Future<void> setBaseVersion(String table, String key, int version) =>
      db.update('sync_changes', {'base_version': version}, where: 'table_name = ? AND row_key = ?', whereArgs: [table, key]);

  @override
  Future<void> dropJournalLine(String table, String key) =>
      db.delete('sync_changes', where: 'table_name = ? AND row_key = ?', whereArgs: [table, key]);

  @override
  Future<void> restoreServerCopy(String table, String key, Map<String, List<Map<String, dynamic>>> serverRows) =>
      db.transaction((txn) => withSyncBypass(txn, () async {
            final serverHasIt = (serverRows[table] ?? const []).isNotEmpty;
            // The record and everything under it (syncedParents, any depth).
            final found = <String, List<String>>{table: [key]};
            final queue = [table];
            while (queue.isNotEmpty) {
              final parent = queue.removeAt(0);
              for (final e in syncedParents.entries.where((e) => e.value.$1 == parent)) {
                final child = e.key;
                final parentKeys = found[parent]!;
                if (parentKeys.isEmpty) continue;
                final marks = List.filled(parentKeys.length, '?').join(', ');
                final keep = serverHasIt ? ' AND row_version IS NOT NULL' : '';
                final rows = await txn.rawQuery(
                    'SELECT CAST(${syncedTables[child]} AS TEXT) AS k FROM $child WHERE ${e.value.$2} IN ($marks)$keep',
                    parentKeys);
                found[child] = [...?found[child], for (final r in rows) r['k'] as String];
                queue.add(child);
              }
            }
            for (final t in pullClearOrder.where(found.containsKey)) {
              final keys = found[t]!;
              if (keys.isEmpty) continue;
              final marks = List.filled(keys.length, '?').join(', ');
              await txn.rawDelete('DELETE FROM sync_changes WHERE table_name = ? AND row_key IN ($marks)', [t, ...keys]);
              await txn.rawDelete('DELETE FROM $t WHERE CAST(${syncedTables[t]} AS TEXT) IN ($marks)', keys);
            }
            for (final t in pullOrder.keys.where(serverRows.containsKey)) {
              final localCols = (await txn.rawQuery('PRAGMA table_info($t)')).map((c) => c['name'] as String).toSet();
              for (final row in serverRows[t]!) {
                // Also an item deleted here (no local row, so not found
                // above): the server's copy comes back, its delete goes.
                await txn.delete('sync_changes',
                    where: 'table_name = ? AND row_key = ?', whereArgs: [t, '${row[syncedTables[t]]}']);
                final local = serverRowToLocal(row, localCols);
                if (localCols.contains('origin')) local['origin'] = 'cloud';
                await txn.insert(t, local);
              }
            }
          }));

  @override
  Future<bool> isPending(String table, String key) async =>
      (await db.query('sync_pending', where: 'table_name = ? AND row_key = ?', whereArgs: [table, key])).isNotEmpty;

  @override
  Future<void> beginUpload(String clientUploadId, SyncPackage package) => db.transaction((txn) async {
        // Work saved since [package] was built would be sent with its old
        // values, then overwritten by the server's copy: refuse instead.
        final now = jsonEncode([for (final r in await _records(txn)) r.toJson()]);
        if (now != jsonEncode([for (final r in package.records) r.toJson()])) {
          throw StateError('Work on this device changed while the upload was being prepared; run it again.');
        }
        await txn.insert(
            'sync_meta',
            {
              'key': _inFlightKey,
              'value': jsonEncode({
                'client_upload_id': clientUploadId,
                'payload': package.toJson(),
                'summary': package.summaryJson(),
              }),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        for (final r in package.records) {
          // A follow-up shares its record's lock line.
          await txn.insert('sync_pending', {'table_name': r.table, 'row_key': r.rowKey, 'upload_id': 0},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });

  @override
  Future<InFlightUpload?> inFlight() async {
    final rows = await db.query('sync_meta', columns: ['value'], where: 'key = ?', whereArgs: [_inFlightKey]);
    final text = rows.isEmpty ? null : rows.first['value'] as String?;
    if (text == null) return null;
    final m = jsonDecode(text) as Map<String, dynamic>;
    return InFlightUpload(
      clientUploadId: m['client_upload_id'] as String,
      payload: Map<String, Object?>.from(m['payload'] as Map),
      summary: Map<String, Object?>.from(m['summary'] as Map),
    );
  }

  @override
  Future<void> confirmUpload(int uploadId) => db.transaction((txn) async {
        await txn.update('sync_pending', {'upload_id': uploadId}, where: 'upload_id = 0');
        await txn.delete('sync_meta', where: 'key = ?', whereArgs: [_inFlightKey]);
      });

  @override
  Future<void> abandonUpload() => db.transaction((txn) async {
        await txn.delete('sync_pending', where: 'upload_id = 0');
        await txn.delete('sync_meta', where: 'key = ?', whereArgs: [_inFlightKey]);
      });

  @override
  Future<List<int>> pendingUploadIds() async => [
        for (final r in await db.rawQuery('SELECT DISTINCT upload_id FROM sync_pending WHERE upload_id > 0 ORDER BY 1'))
          r['upload_id'] as int,
      ];

  @override
  Future<List<(String, String)>> pendingRecords(int uploadId) async => [
        for (final r in await db.query('sync_pending', where: 'upload_id = ?', whereArgs: [uploadId]))
          (r['table_name'] as String, r['row_key'] as String),
      ];

  @override
  Future<void> releaseUpload(int uploadId) => db.delete('sync_pending', where: 'upload_id = ?', whereArgs: [uploadId]);

  @override
  Future<int> takeInApplied(int uploadId, Map<String, Map<int, int>> idMap, Map<String, List<Map<String, dynamic>>> serverRows) =>
      db.transaction((txn) => withSyncBypass(txn, () async {
            final lines = await txn.query('sync_pending', where: 'upload_id = ?', whereArgs: [uploadId]);
            if (lines.isEmpty) return 0;
            // One countdown: negative ids are unique across tables.
            final flat = {for (final m in idMap.values) ...m};
            // A record's key after the swap.
            String now(String table, String key) {
              if (syncedTables[table] == 'tutor_id') return key;
              final k = int.parse(key);
              return '${flat[k] ?? k}';
            }

            await withOtherSyncTableTriggersOff(txn, () async {
              // A pull between the decision and this take-in may already
              // hold server copies under the new ids (e.g. a mark written
              // while its session clashed with the device's): they are the
              // same records and are rewritten below, so they go first.
              // Server ids are unique per table only, so per table (CRLA
              // parts are keyed by their assessment's id).
              for (final e in idMap.entries) {
                final tables = [
                  e.key,
                  if (e.key == 'crla_assessments') ...['crla_part1_standard', 'crla_part1_english', 'crla_part2_fluency'],
                ];
                final targets = e.value.values.toList();
                for (var i = 0; i < targets.length; i += 500) {
                  final chunk = targets.sublist(i, i + 500 > targets.length ? targets.length : i + 500);
                  final marks = List.filled(chunk.length, '?').join(', ');
                  for (final t in tables) {
                    await txn.rawDelete(
                        'DELETE FROM $t WHERE ${syncedTables[t]} IN ($marks) AND row_version IS NOT NULL', chunk);
                  }
                }
              }
              await followLocalIds(txn, flat);
              final given = <String, Set<String>>{};
              for (final t in pullOrder.keys.where(serverRows.containsKey)) {
                final key = syncedTables[t]!;
                final localCols = (await txn.rawQuery('PRAGMA table_info($t)')).map((c) => c['name'] as String).toSet();
                for (final row in serverRows[t]!) {
                  final local = serverRowToLocal(row, localCols);
                  if (localCols.contains('origin')) local['origin'] = 'cloud';
                  await txn.insert(t, local, conflictAlgorithm: ConflictAlgorithm.replace);
                  (given[t] ??= {}).add('${row[key]}');
                }
              }
              // Not given back (out of the user's scope by now): local values
              // stay, as a server copy of unknown version. A delete has no row.
              for (final l in lines) {
                final t = l['table_name'] as String;
                final k = now(t, l['row_key'] as String);
                if (given[t]?.contains(k) ?? false) continue;
                final cols = (await txn.rawQuery('PRAGMA table_info($t)')).map((c) => c['name']).toSet();
                await txn.rawUpdate(
                    'UPDATE $t SET row_version = 0${cols.contains('origin') ? ", origin = 'cloud'" : ''} '
                    'WHERE CAST(${syncedTables[t]} AS TEXT) = ?',
                    [k]);
              }
            });
            for (final l in lines) {
              final t = l['table_name'] as String;
              final k = l['row_key'] as String;
              await txn.delete('sync_changes', where: 'table_name = ? AND row_key IN (?, ?)', whereArgs: [t, k, now(t, k)]);
            }
            await txn.delete('sync_pending', where: 'upload_id = ?', whereArgs: [uploadId]);
            return lines.length;
          }));
}
