// lib/core/console/commands/pull_commands.dart

/// TEMPORARY one-way cloud -> local copy, until real sync is built.
library;

import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'package:supabase/supabase.dart' show SupabaseClient;
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

void registerPullCommands(ConsoleRegistry registry, AuthViewModel authVm, Database localDb) {
  registry.register(ConsoleCommand(
    name: 'pull-cloud',
    description: 'pull-cloud yes — copy cloud rows into the local DB (one-way, replaces rows with the same id)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;

      if (args.isEmpty || args[0] != 'yes') {
        return 'This copies cloud rows into the local DB and REPLACES local rows that share an id '
            'or unique key. Local-only rows are kept. Back up data/basa_local.db first.\n'
            'Run "pull-cloud yes" to continue.';
      }

      final client = authVm.client!;
      final out = StringBuffer();
      try {
        for (final entry in _pullOrder.entries) {
          final n = await _pullTable(client, localDb, entry.key, entry.value);
          out.writeln('${entry.key}: $n rows');
        }
        out.write('Done.');
      } catch (e) {
        out.write('Pull stopped: $e');
      }
      return out.toString();
    },
  ));
}

Future<int> _pullTable(SupabaseClient client, Database db, String table, String orderBy) async {
  // Only copy columns the local table has, so extra cloud columns don't break the insert.
  final info = await db.rawQuery('PRAGMA table_info($table)');
  final localCols = info.map((c) => c['name'] as String).toSet();

  const pageSize = 1000; // Supabase caps a single request at 1000 rows by default
  var start = 0;
  var total = 0;
  while (true) {
    final page = await client
        .from(table)
        .select()
        .order(orderBy, ascending: true)
        .range(start, start + pageSize - 1);
    final rows = (page as List).cast<Map<String, dynamic>>();

    if (rows.isNotEmpty) {
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final row in rows) {
          batch.insert(
            table,
            _toLocal(row, localCols),
            conflictAlgorithm: ConflictAlgorithm.replace, // INSERT OR REPLACE
          );
        }
        await batch.commit(noResult: true);
      });
      total += rows.length;
    }
    if (rows.length < pageSize) break;
    start += pageSize;
  }
  return total;
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