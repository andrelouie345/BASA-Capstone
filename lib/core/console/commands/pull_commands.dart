// lib/core/console/commands/pull_commands.dart

/// TEMPORARY one-way cloud -> local copy, until real sync is built.
library;

import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'package:supabase/supabase.dart' show SupabaseClient;
import '../../data/local/mirror_write.dart';
import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/auth_viewmodel.dart';

/// Parents before children (foreign keys), mapped to the column used for
/// stable paging. Part tables must come after crla_assessments: the local
/// variant-check triggers look up the parent row.
const _pullOrder = <String, String>{
  'schools': 'id',
  'users': 'id',
  'sections': 'id',
  'students': 'id',
  'enrollments': 'id',
  'crla_stories': 'id',
  'crla_assessments': 'id',
  'crla_part1_standard': 'assessment_id',
  'crla_part1_english': 'assessment_id',
  'crla_part2_fluency': 'assessment_id',
};

/// Tables still written with INSERT OR REPLACE. The part tables: their
/// primary key is their only unique key, and an UPDATE would re-run the local
/// compute triggers over the cloud's wpm/totals. enrollments: one per
/// learner per year, the cloud's row wins (same as enroll()). Every other
/// table goes through upsertById, so a unique-key clash stops the pull
/// instead of silently deleting a local row.
const _replaceTables = {
  'enrollments',
  'crla_part1_standard',
  'crla_part1_english',
  'crla_part2_fluency',
};

void registerPullCommands(ConsoleRegistry registry, AuthViewModel authVm, Database localDb) {
  registry.register(ConsoleCommand(
    name: 'pull-cloud',
    description: 'pull-cloud yes — copy cloud rows into the local DB (one-way, all or nothing, overwrites rows with the same id)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;

      if (args.isEmpty || args[0] != 'yes') {
        return 'This copies cloud rows into the local DB and overwrites local rows that share an id. '
            'It stops if a cloud row\'s unique key (LRN, school code, section) belongs to a '
            'different local row. Local-only rows are kept. Back up data/basa_local.db first.\n'
            'Run "pull-cloud yes" to continue.';
      }

      final client = authVm.client!;

      // Fetch everything first, then write it in one transaction: a network
      // error or a unique-key clash leaves the local DB exactly as it was.
      final fetched = <String, List<Map<String, dynamic>>>{};
      try {
        for (final entry in _pullOrder.entries) {
          fetched[entry.key] = await _fetchTable(client, entry.key, entry.value);
        }
      } catch (e) {
        return 'Pull stopped while downloading, nothing was written: $e';
      }

      try {
        await localDb.transaction((txn) async {
          for (final entry in _pullOrder.entries) {
            await _writeTable(txn, entry.key, entry.value, fetched[entry.key]!);
          }
        });
      } catch (e) {
        return 'Pull stopped, nothing was written (rolled back): $e';
      }

      final out = StringBuffer();
      for (final entry in fetched.entries) {
        out.writeln('${entry.key}: ${entry.value.length} rows');
      }
      out.write('Done.');
      return out.toString();
    },
  ));
}

Future<List<Map<String, dynamic>>> _fetchTable(SupabaseClient client, String table, String orderBy) async {
  const pageSize = 1000; // Supabase caps a single request at 1000 rows by default
  final all = <Map<String, dynamic>>[];
  var start = 0;
  while (true) {
    final page = await client
        .from(table)
        .select()
        .order(orderBy, ascending: true)
        .range(start, start + pageSize - 1);
    final rows = (page as List).cast<Map<String, dynamic>>();
    all.addAll(rows);
    if (rows.length < pageSize) break;
    start += pageSize;
  }
  return all;
}

Future<void> _writeTable(Transaction txn, String table, String key, List<Map<String, dynamic>> rows) async {
  // Only copy columns the local table has, so extra cloud columns don't break the insert.
  final info = await txn.rawQuery('PRAGMA table_info($table)');
  final localCols = info.map((c) => c['name'] as String).toSet();

  for (final row in rows) {
    final local = _toLocal(row, localCols);
    if (_replaceTables.contains(table)) {
      await txn.insert(table, local, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await upsertById(txn, table, local, key: key);
    }
  }
}

Map<String, Object?> _toLocal(Map<String, dynamic> row, Set<String> localCols) {
  final out = <String, Object?>{};
  row.forEach((key, value) {
    if (!localCols.contains(key)) return;
    out[key] = switch (value) {
      bool b => b ? 1 : 0, // SQLite has no bool (users.is_active)
      Map _ || List _ => jsonEncode(value),
      _ => value,
    };
  });
  return out;
}