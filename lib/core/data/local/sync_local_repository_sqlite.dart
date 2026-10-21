// lib/core/data/local/sync_local_repository_sqlite.dart
//
// The local side of a pull (sync spec section 7): a merge, not a replace.
// - Tables that don't sync (schools, users, sections, learners, content,
//   settings, calendar, SRP, ...) are replaced by the server's copy.
// - The 18 synced tables keep this device's work: new rows (row_version
//   NULL), pulled rows edited or deleted here (sync_changes) and records in
//   an upload awaiting a decision (sync_pending). Every other row is replaced
//   by the server's copy, or removed if the server no longer gives it.
// - A server row under a record deleted here is not written (the delete
//   would look undone); it goes away once the delete is uploaded.
// - A kept row whose reference is missing afterwards (its section, learner,
//   parent record, ...) refuses the whole pull: rolled back, rows listed.
// One transaction under the sync bypass, so the pull's own writes are never
// journaled or refused by the pending lock.
import 'package:sqflite_common/sqflite.dart';

import '../../models/sync_pull.dart';
import '../../repositories/sync_local_repository.dart';
import '../pull_tables.dart';
import 'sync_local_writes.dart';

/// Tables with the local-only origin column: mirrored rows are 'cloud'.
const _originTables = {
  'crla_assessments', 'phil_iri_gst_results', 'phil_iri_assessments', 'aral_enrollments', 'aral_sessions',
  'aral_tutor_settings',
  'aral_irip_weeks',
  'aral_checkins',
  'aral_readability_logs',
};

/// "Not waiting in an upload" for row [alias] of synced table [table].
String _notPending(String table, String alias) => 'NOT EXISTS (SELECT 1 FROM sync_pending p '
    "WHERE p.table_name = '$table' AND p.row_key = CAST($alias.${syncedTables[table]} AS TEXT))";

/// Pulled CRLA headers that got a new part on this device. Their reading
/// profile was recomputed here and is not journaled (the server recomputes
/// it on upload), so the header is kept as it is until then.
const _crlaWithNewPart = "SELECT CAST(assessment_id AS TEXT) FROM crla_part1_standard WHERE row_version IS NULL "
    "UNION SELECT CAST(assessment_id AS TEXT) FROM crla_part1_english WHERE row_version IS NULL "
    "UNION SELECT CAST(assessment_id AS TEXT) FROM crla_part2_fluency WHERE row_version IS NULL";

/// "Kept by a pull" for row [alias] of synced table [table]: new, journaled
/// or pending (or a CRLA header with a new local part).
String _kept(String table, String alias) {
  final key = 'CAST($alias.${syncedTables[table]} AS TEXT)';
  return "($alias.row_version IS NULL "
      "OR $key IN (SELECT row_key FROM sync_changes WHERE table_name = '$table') "
      "OR $key IN (SELECT row_key FROM sync_pending WHERE table_name = '$table')"
      "${table == 'crla_assessments' ? ' OR $key IN ($_crlaWithNewPart)' : ''})";
}

/// localWork's kind for records waiting in an upload (followed by its id).
const pendingWorkKind = 'record(s) waiting in upload ';

class SyncLocalRepositorySqlite implements SyncLocalRepository {
  final Database db;
  SyncLocalRepositorySqlite(this.db);

  @override
  Future<PullOwner?> owner() async {
    final rows = await db.query('sync_meta');
    final meta = {for (final r in rows) r['key'] as String: r['value'] as String?};
    final id = meta['last_pull_user_id'];
    return id == null ? null : PullOwner(userId: id, email: meta['last_pull_user_email'], pulledAt: meta['last_pull_at']);
  }

  /// Records entered on this device (new rows), per kind and section: CRLA
  /// assessments, Phil-IRI sessions and GST results, ARAL enrollments, ARAL
  /// sessions (with their attendance; no section), ARAL tutor settings (no
  /// section), IRIP weeks, check-ins and readability log entries (by the
  /// learner's section). Children travel with their owner record. Also edits
  /// of server records (sync_changes), new items added under server records,
  /// and records waiting in an upload (one line per upload, not counted again
  /// above).
  @override
  Future<List<LocalWorkLine>> localWork() async {
    final rows = await db.rawQuery('''
      SELECT x.kind, x.section_id, COUNT(*) AS n, s.grade_level, s.section_name, s.school_year
      FROM (
        SELECT 'CRLA assessment(s)' AS kind, section_id FROM crla_assessments a
        WHERE origin = 'local' AND ${_notPending('crla_assessments', 'a')}
        UNION ALL
        SELECT 'Phil-IRI session(s)', section_id FROM phil_iri_assessments a
        WHERE origin = 'local' AND ${_notPending('phil_iri_assessments', 'a')}
        UNION ALL
        SELECT 'Phil-IRI GST result(s)', section_id FROM phil_iri_gst_results a
        WHERE origin = 'local' AND ${_notPending('phil_iri_gst_results', 'a')}
        UNION ALL
        SELECT 'ARAL enrollment(s)', section_id FROM aral_enrollments a
        WHERE origin = 'local' AND ${_notPending('aral_enrollments', 'a')}
        UNION ALL
        SELECT 'ARAL session(s)', NULL FROM aral_sessions a
        WHERE origin = 'local' AND ${_notPending('aral_sessions', 'a')}
        UNION ALL
        SELECT 'ARAL tutor setting(s)', NULL FROM aral_tutor_settings a
        -- an edited pulled setting is also 'local' (save()); it counts as a change below
        WHERE origin = 'local' AND row_version IS NULL AND ${_notPending('aral_tutor_settings', 'a')}
        UNION ALL
        SELECT 'ARAL IRIP week(s)', e.section_id FROM aral_irip_weeks w
        LEFT JOIN aral_enrollments e ON e.id = w.enrollment_id
        WHERE w.origin = 'local' AND ${_notPending('aral_irip_weeks', 'w')}
        UNION ALL
        SELECT 'ARAL check-in(s)', e.section_id FROM aral_checkins c
        LEFT JOIN aral_enrollments e ON e.id = c.enrollment_id
        WHERE c.origin = 'local' AND ${_notPending('aral_checkins', 'c')}
        UNION ALL
        SELECT 'ARAL readability log entr(ies)', e.section_id FROM aral_readability_logs r
        LEFT JOIN aral_enrollments e ON e.id = r.enrollment_id
        WHERE r.origin = 'local' AND ${_notPending('aral_readability_logs', 'r')}
        UNION ALL
        SELECT 'change(s) to records already on the server', NULL FROM sync_changes j
        WHERE NOT EXISTS (SELECT 1 FROM sync_pending p WHERE p.table_name = j.table_name AND p.row_key = j.row_key)
        UNION ALL
        $_newUnderServerRows
        UNION ALL
        SELECT '$pendingWorkKind' || upload_id, NULL FROM sync_pending
      ) x
      LEFT JOIN sections s ON s.id = x.section_id
      GROUP BY x.kind, x.section_id
      ORDER BY x.section_id, x.kind
    ''');
    return [
      for (final r in rows)
        LocalWorkLine(
          kind: r['kind'] as String,
          sectionId: r['section_id'] as int?,
          count: r['n'] as int,
          gradeLevel: r['grade_level'] as String?,
          sectionName: r['section_name'] as String?,
          schoolYear: r['school_year'] as String?,
        ),
    ];
  }

  @override
  Future<PullMerge> mergePull(
    Map<String, List<Map<String, dynamic>>> fetched, {
    required String userId,
    required String? email,
    required bool discardLocal,
  }) =>
      db.transaction((txn) => withSyncBypass(txn, () async {
            var discarded = 0, discardedChanges = 0, discardedPending = 0;
            if (discardLocal) {
              discarded = await _countNew(txn);
              for (final t in syncedTables.keys.toList().reversed) {
                await txn.rawDelete('DELETE FROM $t WHERE row_version IS NULL');
              }
              discardedPending = await txn.delete('sync_pending');
              discardedChanges = await txn.delete('sync_changes');
              // An upload whose answer never came is discarded with its rows.
              await txn.delete('sync_meta', where: 'key = ?', whereArgs: ['upload_in_flight']);
            }

            // What stays: keys per synced table.
            final kept = <String, Set<String>>{};
            final newKeys = <String, Set<String>>{};
            final deletedHere = <String, Set<String>>{};
            for (final e in syncedTables.entries) {
              final t = e.key;
              newKeys[t] = {
                for (final r in await txn.rawQuery('SELECT CAST(${e.value} AS TEXT) AS k FROM $t WHERE row_version IS NULL'))
                  r['k'] as String,
              };
              final journal = await txn.query('sync_changes', columns: ['row_key', 'op'], where: 'table_name = ?', whereArgs: [t]);
              final pending = await txn.query('sync_pending', columns: ['row_key'], where: 'table_name = ?', whereArgs: [t]);
              deletedHere[t] = {for (final r in journal) if (r['op'] == 'delete') r['row_key'] as String};
              kept[t] = {
                ...newKeys[t]!,
                for (final r in journal) r['row_key'] as String,
                for (final r in pending) r['row_key'] as String,
                if (t == 'crla_assessments')
                  for (final r in await txn.rawQuery(_crlaWithNewPart)) r.values.first as String,
              };
            }
            final keptNew = await _countNew(txn);
            final keptChanged = (await txn.rawQuery('SELECT COUNT(*) FROM sync_changes')).first.values.first as int;
            final keptPending = (await txn.rawQuery('SELECT COUNT(*) FROM sync_pending')).first.values.first as int;

            // Clear (children first): everything but the kept rows.
            for (final t in pullClearOrder) {
              if (syncedTables.containsKey(t)) {
                await txn.rawDelete('DELETE FROM $t WHERE NOT ${_kept(t, t)}');
              } else {
                await txn.delete(t);
              }
            }

            // Write (parents first). [skipped] holds server records not
            // written, and why: deleted here, or a clash with a kept row. A
            // server row under a skipped record is skipped for the same
            // reason (parents first, so this reaches grandchildren too).
            final serverRows = <String, int>{};
            var skippedUnderDeleted = 0, skippedNewClash = 0;
            final skipped = {for (final t in syncedTables.keys) t: {for (final k in deletedHere[t]!) k: _Skip.deleted}};
            void countSkip(_Skip why) => why == _Skip.deleted ? skippedUnderDeleted++ : skippedNewClash++;
            for (final t in pullOrder.keys) {
              final info = await txn.rawQuery('PRAGMA table_info($t)');
              final localCols = info.map((c) => c['name'] as String).toSet();
              final key = syncedTables[t];
              final syncedRefs = key == null ? const <_Ref>[] : (await _refs(txn, t)).where((r) => syncedTables.containsKey(r.table));
              var written = 0;
              for (final row in fetched[t] ?? const <Map<String, dynamic>>[]) {
                if (key != null) {
                  final k = '${row[key]}';
                  if (kept[t]!.contains(k)) {
                    if (newKeys[t]!.contains(k)) skippedNewClash++;
                    continue;
                  }
                  final under = syncedRefs
                      .map((r) => row[r.from] == null ? null : skipped[r.table]!['${row[r.from]}'])
                      .firstWhere((why) => why != null, orElse: () => null);
                  if (under != null) {
                    skipped[t]![k] = under;
                    countSkip(under);
                    continue;
                  }
                }
                final local = serverRowToLocal(row, localCols);
                if (_originTables.contains(t)) local['origin'] = 'cloud';
                try {
                  await txn.insert(t, local);
                } on DatabaseException catch (e) {
                  // Every unkept row of this table was just deleted, so a
                  // unique clash means a kept row holds the same natural key
                  // (e.g. a mark for the same session and learner made here).
                  // The device keeps its own; the upload sorts it out.
                  if (key == null || !e.isUniqueConstraintError()) rethrow;
                  skipped[t]!['${row[key]}'] = _Skip.clash;
                  countSkip(_Skip.clash);
                  continue;
                }
                written++;
              }
              serverRows[t] = written;
            }

            final orphans = await _orphans(txn);
            if (orphans.isNotEmpty) throw PullOrphansException(orphans);

            await _setMeta(txn, {
              'last_pull_user_id': userId,
              'last_pull_user_email': email,
              'last_pull_at': DateTime.now().toUtc().toIso8601String(),
            });
            return PullMerge(
              serverRows: serverRows,
              keptNew: keptNew,
              keptChanged: keptChanged,
              keptPending: keptPending,
              skippedUnderDeleted: skippedUnderDeleted,
              skippedNewClash: skippedNewClash,
              discarded: discarded,
              discardedChanges: discardedChanges,
              discardedPending: discardedPending,
            );
          }));

  /// Kept rows whose declared reference (or ARAL basis/suggestion id) points
  /// at nothing. References to users are not checked: audit columns, a tutor
  /// can't read every user, and the server checks them on upload.
  Future<List<PullOrphan>> _orphans(Transaction txn) async {
    final out = <PullOrphan>[];
    Future<void> check(String t, String column, String refTable, String refColumn, [String extra = '']) async {
      final key = syncedTables[t]!;
      final rows = await txn.rawQuery('''
        SELECT CAST(c.$key AS TEXT) AS k, c.$column AS v FROM $t c
        WHERE ${_kept(t, 'c')} AND c.$column IS NOT NULL$extra
          AND NOT EXISTS (SELECT 1 FROM $refTable r WHERE r.$refColumn = c.$column)
        ORDER BY c.$key''');
      for (final r in rows) {
        out.add(PullOrphan(table: t, key: r['k'] as String, column: column, refTable: refTable, refValue: r['v']!));
      }
    }

    for (final t in syncedTables.keys) {
      for (final ref in await _refs(txn, t)) {
        if (ref.table == 'users') continue;
        await check(t, ref.from, ref.table, ref.to);
      }
    }
    // Polymorphic ids, routed as the v34 renumber does.
    await check('aral_enrollments', 'basis_assessment_id', 'crla_assessments', 'id', " AND c.basis_source = 'crla'");
    await check('aral_enrollments', 'basis_assessment_id', 'phil_iri_assessments', 'id', " AND c.basis_source = 'phil_iri'");
    const crlaGrade = "(SELECT grade_level FROM sections WHERE id = c.section_id) IN ('1', '2', '3')";
    await check('aral_enrollments', 'suggestion_assessment_id', 'crla_assessments', 'id', ' AND $crlaGrade');
    await check('aral_enrollments', 'suggestion_assessment_id', 'phil_iri_assessments', 'id', ' AND NOT $crlaGrade');
    return out;
  }
}

/// New records as localWork counts them: a new record's own items (parts,
/// marks, readings, ...) travel with it; a new item under a pulled record
/// counts on its own.
Future<int> _countNew(DatabaseExecutor db) async {
  var n = 0;
  for (final t in syncedTables.keys) {
    final parent = syncedParents[t];
    final where = parent == null
        ? 'FROM $t c WHERE c.row_version IS NULL'
        : 'FROM $t c JOIN ${parent.$1} p ON p.${syncedTables[parent.$1]} = c.${parent.$2} '
            'WHERE c.row_version IS NULL AND p.row_version IS NOT NULL';
    n += (await db.rawQuery('SELECT COUNT(*) AS n $where')).first['n'] as int;
  }
  return n;
}

/// Why a server record was not written.
enum _Skip { deleted, clash }

/// A declared foreign key: [from] column -> [table].[to].
class _Ref {
  final String from, table, to;
  const _Ref(this.from, this.table, this.to);
}

Future<List<_Ref>> _refs(DatabaseExecutor db, String table) async => [
      for (final r in await db.rawQuery('PRAGMA foreign_key_list($table)'))
        _Ref(r['from'] as String, r['table'] as String, (r['to'] as String?) ?? 'id'),
    ];

/// One SELECT per child table: new rows (row_version NULL) whose parent came
/// from the server, unless waiting in an upload.
final _newUnderServerRows = [
  for (final e in syncedParents.entries)
    "SELECT 'new item(s) added to records already on the server', NULL FROM ${e.key} c "
        "JOIN ${e.value.$1} p ON p.${syncedTables[e.value.$1]} = c.${e.value.$2} "
        'WHERE c.row_version IS NULL AND p.row_version IS NOT NULL AND ${_notPending(e.key, 'c')}',
].join('\n        UNION ALL\n        ');

Future<void> _setMeta(Transaction txn, Map<String, String?> values) async {
  for (final e in values.entries) {
    await txn.insert('sync_meta', {'key': e.key, 'value': e.value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
