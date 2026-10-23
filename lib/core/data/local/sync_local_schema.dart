// lib/core/data/local/sync_local_schema.dart
//
// Sync bookkeeping in the local SQLite DB (v34; spec
// docs/superpowers/specs/2026-10-20-sync-design.md, section 3). Called LAST
// from LocalDatabase on create and, unconditionally, on upgrade: everything
// here is IF NOT EXISTS / checked by column, and triggers are dropped and
// recreated.
//
// - Row state comes from row_version: NULL = new on this device (never on the
//   server); not NULL = a copy of a server row (its server version; 0 = copied
//   before v34, version unknown). New rows in the 14 id-keyed tables carry a
//   negative id from nextLocalId (sync_local_writes.dart); a trigger refuses a
//   new row with a positive id.
// - Edits/deletes of server rows are journaled in sync_changes (one line per
//   record, first base version kept, a delete replaces an update). Ops the
//   server refuses are refused here instead (crla_assessments and
//   phil_iri_gst_results are insert-only; CRLA parts are never deleted).
// - Records listed in sync_pending (an upload awaiting a decision) can't be
//   changed or deleted, and no child can be added under them.
// - Every journal/lock/read-only trigger is skipped while sync_meta holds the
//   'sync_bypass' row. Only withSyncBypass writes it, always inside a
//   transaction, so a crash can't leave it on.
// - A future table rebuild (like v21/v26) must copy row_version and run
//   before createSyncLocalSchema, which recreates these triggers.
import 'package:sqflite_common/sqflite.dart';

import '../../services/sync_upload_rules.dart' show pendingLockMessage;
import '../pull_tables.dart';
import 'sync_local_writes.dart';

export '../pull_tables.dart' show syncedTables, syncedParents;
export '../../services/sync_upload_rules.dart' show pendingLockMessage;

/// Server rows of these tables are never changed by the server's rules.
const _noServerUpdate = {'crla_assessments', 'phil_iri_gst_results'};

/// Server rows of these tables are never deleted by the server's rules.
const _noServerDelete = {
  'crla_assessments', 'phil_iri_gst_results', 'crla_part1_standard', 'crla_part1_english', 'crla_part2_fluency',
};

/// The one local change to a server CRLA header: its reading profile, which
/// the server recomputes from the parts itself (so it is not journaled).
const _crlaLocalColumn = 'reading_profile';

const _bypassOff = "NOT EXISTS (SELECT 1 FROM sync_meta WHERE key = 'sync_bypass')";
const _changedMsg = 'This record is already on the server and cannot be changed on this device';
const _deletedMsg = 'This record is already on the server and cannot be deleted on this device';

Future<void> createSyncLocalSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS local_ids (
      n INTEGER PRIMARY KEY AUTOINCREMENT,
      made_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_changes (
      table_name TEXT NOT NULL,
      row_key TEXT NOT NULL,
      op TEXT NOT NULL CHECK (op IN ('update', 'delete')),
      base_version INTEGER NOT NULL,
      changed_at TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (table_name, row_key)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_pending (
      table_name TEXT NOT NULL,
      row_key TEXT NOT NULL,
      upload_id INTEGER NOT NULL,
      PRIMARY KEY (table_name, row_key)
    )
  ''');
  // Offline sign-in (spec section 6, used from S3): one row, the device owner.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS offline_credentials (
      user_id TEXT PRIMARY KEY,
      email TEXT NOT NULL,
      salt TEXT NOT NULL,
      iterations INTEGER NOT NULL,
      hash TEXT NOT NULL,
      last_online_at TEXT NOT NULL,
      failed_attempts INTEGER NOT NULL DEFAULT 0
    )
  ''');
  final logCols = (await db.rawQuery('PRAGMA table_info(login_logs)')).map((c) => c['name']).toSet();
  if (!logCols.contains('mode')) {
    await db.execute("ALTER TABLE login_logs ADD COLUMN mode TEXT NOT NULL DEFAULT 'online' "
        "CHECK (mode IN ('online', 'offline'))");
  }

  for (final entry in syncedTables.entries) {
    final t = entry.key;
    final key = entry.value;
    final cols = (await db.rawQuery('PRAGMA table_info($t)')).map((c) => c['name'] as String).toList();
    if (!cols.contains('row_version')) {
      await db.execute('ALTER TABLE $t ADD COLUMN row_version INTEGER');
      cols.add('row_version');
    }
    final oldKey = 'CAST(OLD.$key AS TEXT)';
    final serverRow = 'OLD.row_version IS NOT NULL';

    Future<void> trigger(String name, String body) async {
      await db.execute('DROP TRIGGER IF EXISTS $name');
      await db.execute('CREATE TRIGGER $name $body');
    }

    if (key == 'id') {
      await trigger('sync_new_id_$t', '''
        AFTER INSERT ON $t
        WHEN NEW.id > 0 AND NEW.row_version IS NULL
        BEGIN SELECT RAISE(ABORT, 'A new $t row needs a local id (nextLocalId)'); END''');
    }

    // Pending lock first, so a locked record says why.
    await trigger('sync_lock_upd_$t', '''
      BEFORE UPDATE ON $t
      WHEN $_bypassOff AND EXISTS (SELECT 1 FROM sync_pending WHERE table_name = '$t' AND row_key = $oldKey)
      BEGIN SELECT RAISE(ABORT, '$pendingLockMessage'); END''');
    await trigger('sync_lock_del_$t', '''
      BEFORE DELETE ON $t
      WHEN $_bypassOff AND EXISTS (SELECT 1 FROM sync_pending WHERE table_name = '$t' AND row_key = $oldKey)
      BEGIN SELECT RAISE(ABORT, '$pendingLockMessage'); END''');
    final parent = syncedParents[t];
    if (parent != null) {
      await trigger('sync_lock_child_$t', '''
        BEFORE INSERT ON $t
        WHEN $_bypassOff AND EXISTS (SELECT 1 FROM sync_pending
                                     WHERE table_name = '${parent.$1}' AND row_key = CAST(NEW.${parent.$2} AS TEXT))
        BEGIN SELECT RAISE(ABORT, '$pendingLockMessage'); END''');
    }

    if (_noServerUpdate.contains(t)) {
      // crla_assessments: only the reading profile may change locally.
      final changed = t == 'crla_assessments'
          ? cols.where((c) => c != _crlaLocalColumn).map((c) => 'NEW.$c IS NOT OLD.$c').join(' OR ')
          : '1';
      await trigger('sync_readonly_upd_$t', '''
        BEFORE UPDATE ON $t
        WHEN $_bypassOff AND $serverRow AND ($changed)
        BEGIN SELECT RAISE(ABORT, '$_changedMsg'); END''');
      await db.execute('DROP TRIGGER IF EXISTS sync_journal_upd_$t');
    } else {
      await db.execute('DROP TRIGGER IF EXISTS sync_readonly_upd_$t');
      await trigger('sync_journal_upd_$t', '''
        AFTER UPDATE ON $t
        WHEN $_bypassOff AND $serverRow
        BEGIN
          INSERT OR IGNORE INTO sync_changes (table_name, row_key, op, base_version)
          VALUES ('$t', $oldKey, 'update', OLD.row_version);
        END''');
    }

    if (_noServerDelete.contains(t)) {
      await trigger('sync_readonly_del_$t', '''
        BEFORE DELETE ON $t
        WHEN $_bypassOff AND $serverRow
        BEGIN SELECT RAISE(ABORT, '$_deletedMsg'); END''');
      await db.execute('DROP TRIGGER IF EXISTS sync_journal_del_$t');
    } else {
      await db.execute('DROP TRIGGER IF EXISTS sync_readonly_del_$t');
      // No UPSERT: older Android ships SQLite 3.22.
      await trigger('sync_journal_del_$t', '''
        AFTER DELETE ON $t
        WHEN $_bypassOff AND $serverRow
        BEGIN
          INSERT OR IGNORE INTO sync_changes (table_name, row_key, op, base_version)
          VALUES ('$t', $oldKey, 'delete', OLD.row_version);
          UPDATE sync_changes SET op = 'delete' WHERE table_name = '$t' AND row_key = $oldKey;
        END''');
    }
  }

  // No new reference to a NEW record (negative id) that waits in an upload:
  // the next upload would carry an id its own package can't map (uploads
  // never chain). A pulled record already exists on the server, so pointing
  // at it is fine. One countdown makes a negative id unique across tables, so
  // the ARAL basis/suggestion ids need no routing by source.
  Future<void> refLock(String table, String column, String pendingTables) async {
    final pending = 'NEW.$column < 0 AND EXISTS (SELECT 1 FROM sync_pending '
        'WHERE table_name IN ($pendingTables) AND row_key = CAST(NEW.$column AS TEXT))';
    for (final (suffix, event, extra) in [
      ('ins', 'INSERT', ''),
      ('upd', 'UPDATE OF $column', ' AND NEW.$column IS NOT OLD.$column'),
    ]) {
      final name = 'sync_lock_ref_${suffix}_${table}_$column';
      await db.execute('DROP TRIGGER IF EXISTS $name');
      await db.execute('''
        CREATE TRIGGER $name BEFORE $event ON $table
        WHEN $_bypassOff$extra AND $pending
        BEGIN SELECT RAISE(ABORT, '$pendingLockMessage'); END''');
    }
  }

  for (final t in _enrollmentRefs) {
    await refLock(t, 'enrollment_id', "'aral_enrollments'");
  }
  for (final c in ['basis_assessment_id', 'suggestion_assessment_id']) {
    await refLock('aral_enrollments', c, "'crla_assessments', 'phil_iri_assessments'");
  }
  // v36: a placement in a new class that waits in an upload.
  await refLock('aral_enrollments', 'class_id', "'aral_classes'");
}

/// Owner tables with the local-only origin column ('cloud' = pulled).
const _originTables = [
  'crla_assessments', 'phil_iri_gst_results', 'phil_iri_assessments', 'aral_classes', 'aral_enrollments',
  'aral_sessions', 'aral_tutor_settings', 'aral_irip_weeks', 'aral_checkins', 'aral_readability_logs',
];

/// Rows pointing at an ARAL enrollment (besides syncedParents).
const _enrollmentRefs = ['aral_attendance', 'aral_irip_weeks', 'aral_checkins', 'aral_readability_logs'];

/// v34 upgrade, after [createSyncLocalSchema]: rows from before v34 get their
/// sync state. Pulled rows (origin 'cloud', or a child of a pulled parent; an
/// attendance mark also needs a pulled learner) get row_version 0 (server
/// version unknown). Every other row of the 14 id-keyed tables was entered on
/// this device: it gets a negative id from [nextLocalId] and every row
/// pointing at it follows (children, the part tables' key, enrollment
/// references, ARAL basis/suggestion ids). The basis id points at CRLA or
/// Phil-IRI by basis_source; the suggestion id by the section's grade (CRLA
/// for Grades 1-3), as the ARAL ViewModel picks the latest result.
///
/// One transaction under the sync bypass. The other triggers on these tables
/// (finalized/locked rows, "keeps its session" checks) would refuse the id
/// changes, so they are dropped for the renumber and recreated from their
/// stored SQL in the same transaction. Running it again changes nothing.
Future<void> renumberLocalRowsForV34(Database db) async {
  await db.transaction((txn) => withSyncBypass(txn, () async {
        // 1. Pulled rows.
        for (final t in _originTables) {
          await txn.execute("UPDATE $t SET row_version = 0 WHERE row_version IS NULL AND origin = 'cloud'");
        }
        for (final e in syncedParents.entries) {
          final (parent, fk) = e.value;
          final ownId = syncedTables[e.key] == 'id' ? 'id > 0 AND ' : '';
          final learner = e.key == 'aral_attendance'
              ? " AND enrollment_id IN (SELECT id FROM aral_enrollments WHERE origin = 'cloud')"
              : '';
          await txn.execute('UPDATE ${e.key} SET row_version = 0 WHERE $ownId row_version IS NULL '
              'AND $fk IN (SELECT ${syncedTables[parent]} FROM $parent WHERE row_version IS NOT NULL)$learner');
        }

        // 2. Other triggers off for 3-4.
        await withOtherSyncTableTriggersOff(txn, () async {
        // 3. New ids, parents first.
        final moved = <String, Map<int, int>>{};
        for (final e in syncedTables.entries.where((e) => e.value == 'id')) {
          final rows = await txn.rawQuery('SELECT id FROM ${e.key} WHERE id > 0 AND row_version IS NULL ORDER BY id');
          final map = moved[e.key] = {};
          for (final r in rows) {
            final old = r['id'] as int;
            final now = await nextLocalId(txn);
            await txn.rawUpdate('UPDATE ${e.key} SET id = ? WHERE id = ?', [now, old]);
            map[old] = now;
          }
        }

        // 4. References follow.
        Future<void> follow(String table, String column, String parent, [String where = '']) async {
          for (final m in (moved[parent] ?? const <int, int>{}).entries) {
            await txn.rawUpdate('UPDATE $table SET $column = ? WHERE $column = ?${where.isEmpty ? '' : ' AND $where'}',
                [m.value, m.key]);
          }
        }

        for (final e in syncedParents.entries) {
          await follow(e.key, e.value.$2, e.value.$1);
        }
        for (final t in _enrollmentRefs) {
          await follow(t, 'enrollment_id', 'aral_enrollments');
        }
        await follow('aral_enrollments', 'basis_assessment_id', 'crla_assessments', "basis_source = 'crla'");
        await follow('aral_enrollments', 'basis_assessment_id', 'phil_iri_assessments', "basis_source = 'phil_iri'");
        const crlaGrade = "(SELECT grade_level FROM sections WHERE id = aral_enrollments.section_id) IN ('1', '2', '3')";
        await follow('aral_enrollments', 'suggestion_assessment_id', 'crla_assessments', crlaGrade);
        await follow('aral_enrollments', 'suggestion_assessment_id', 'phil_iri_assessments', 'NOT $crlaGrade');
        });
      }));
}

/// Runs [body] inside [txn] with every trigger on the synced tables dropped
/// except the sync_ ones (finalized/locked rows, "keeps its session" and
/// compute triggers would refuse or redo id changes and copied rows), then
/// recreates them from their stored SQL. If [body] throws, the transaction's
/// rollback restores them.
Future<void> withOtherSyncTableTriggersOff(Transaction txn, Future<void> Function() body) async {
  final names = syncedTables.keys.map((t) => "'$t'").join(', ');
  final saved = (await txn.rawQuery(
          "SELECT name, sql FROM sqlite_master WHERE type = 'trigger' AND tbl_name IN ($names)"))
      .where((t) => !(t['name'] as String).startsWith('sync_'))
      .toList();
  for (final t in saved) {
    await txn.execute('DROP TRIGGER ${t['name']}');
  }
  await body();
  for (final t in saved) {
    await txn.execute(t['sql'] as String);
  }
}

/// Gives this device's records their server ids ([moved]: device id ->
/// server id, every table at once): the records themselves and every column
/// pointing at them (declared foreign keys of every local table, plus the
/// ARAL basis/suggestion ids). Following by value is sound only because the
/// old ids are negative and unique across tables (one countdown); never use
/// it for positive ids. Call inside [withOtherSyncTableTriggersOff].
Future<void> followLocalIds(Transaction txn, Map<int, int> moved) async {
  if (moved.isEmpty) return;
  assert(moved.keys.every((k) => k < 0));
  final idTables = {for (final e in syncedTables.entries) if (e.value == 'id') e.key};
  final columns = <(String, String)>[
    for (final t in idTables) (t, 'id'),
    ('aral_enrollments', 'basis_assessment_id'),
    ('aral_enrollments', 'suggestion_assessment_id'),
  ];
  final tables = await txn.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'");
  for (final t in tables.map((r) => r['name'] as String)) {
    for (final fk in await txn.rawQuery('PRAGMA foreign_key_list($t)')) {
      if (idTables.contains(fk['table'])) columns.add((t, fk['from'] as String));
    }
  }
  // Chunks: older Android SQLite allows 999 bound values per statement.
  final entries = moved.entries.toList();
  for (var i = 0; i < entries.length; i += 500) {
    final chunk = entries.sublist(i, i + 500 > entries.length ? entries.length : i + 500);
    final olds = [for (final e in chunk) e.key];
    final marks = List.filled(olds.length, '?').join(', ');
    final cases = chunk.map((e) => 'WHEN ${e.key} THEN ${e.value}').join(' ');
    for (final (table, column) in columns.toSet()) {
      await txn.rawUpdate('UPDATE $table SET $column = CASE $column $cases END WHERE $column IN ($marks)', olds);
    }
  }
}
