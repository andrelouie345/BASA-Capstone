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
/// variant-check triggers look up the parent row. Likewise the Phil-IRI
/// child tables come after phil_iri_assessments, whose origin tells the local
/// triggers to leave mirrored rows alone.
const _pullOrder = <String, String>{
  'schools': 'id',
  'users': 'id',
  'sections': 'id',
  'students': 'id',
  'enrollments': 'id',
  'crla_stories': 'id',
  'crla_thresholds': 'id',
  'crla_assessments': 'id',
  'crla_part1_standard': 'assessment_id',
  'crla_part1_english': 'assessment_id',
  'crla_part2_fluency': 'assessment_id',
  'phil_iri_collections': 'id',
  'phil_iri_rubric_criteria': 'id',
  'phil_iri_passages': 'id',
  'phil_iri_questions': 'id',
  'phil_iri_thresholds': 'id',
  'phil_iri_gst_results': 'id',
  'phil_iri_assessments': 'id',
  'phil_iri_readings': 'id',
  'phil_iri_miscues': 'id',
  'phil_iri_answers': 'id',
  'phil_iri_rubric_scores': 'id',
  'aral_enrollments': 'id',
  'aral_sessions': 'id',
  'aral_attendance': 'id',
};

/// Tables with the local-only origin column: mirrored rows are 'cloud'.
const _originTables = {
  'crla_assessments', 'phil_iri_gst_results', 'phil_iri_assessments', 'aral_enrollments', 'aral_sessions',
};

/// Local tables a pull empties before writing (children first). Everything
/// the signed-in user can read comes back from the cloud; regions (seed data)
/// and login_logs (this device's sign-in history) are kept. import_conflicts
/// lives in the cloud only; its local copy is unused but may hold old rows.
const _clearedTables = [
  'aral_attendance',
  'aral_sessions',
  'aral_enrollments',
  'phil_iri_rubric_scores',
  'phil_iri_answers',
  'phil_iri_miscues',
  'phil_iri_readings',
  'phil_iri_assessments',
  'phil_iri_gst_results',
  'phil_iri_thresholds',
  'phil_iri_questions',
  'phil_iri_passages',
  'phil_iri_rubric_criteria',
  'phil_iri_collections',
  'crla_part2_fluency',
  'crla_part1_english',
  'crla_part1_standard',
  'crla_assessments',
  'crla_thresholds',
  'crla_stories',
  'import_conflicts',
  'enrollments',
  'students',
  'sections',
  'users',
  'schools',
];

void registerPullCommands(ConsoleRegistry registry, AuthViewModel authVm, Database localDb) {
  registry.register(ConsoleCommand(
    name: 'pull-cloud',
    description: 'pull-cloud yes [discard-local] — replace the local data with everything the signed-in '
        'user can read in the cloud (all or nothing)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;

      final previous = await _lastPull(localDb);
      final unsynced = await _unsynced(localDb);
      final unsyncedTotal = unsynced.fold<int>(0, (n, r) => n + (r['n'] as int));

      if (args.isEmpty || args[0] != 'yes') {
        return 'This CLEARS the local data (schools, users, sections, learners, enrollments, CRLA, Phil-IRI, ARAL) and '
            'pulls everything ${authVm.currentUser?.email} can read in the cloud. '
            'Regions and login logs are kept.\n'
            'Local data was last pulled by ${previous ?? "nobody (never pulled)"}.\n'
            '${unsyncedTotal > 0 ? "$unsyncedTotal record(s) entered on this device are not uploaded yet; the pull will refuse.\n" : ""}'
            'Run "pull-cloud yes" to continue.';
      }

      final discardLocal = args.length > 1 && args[1] == 'discard-local';
      if (unsyncedTotal > 0 && !discardLocal) {
        final lines = unsynced.map((r) => r['section_id'] == null
            ? '  ${r['n']} ${r['kind']}'
            : '  ${r['n']} ${r['kind']} in section ${r['section_id']} '
                '(grade ${r['grade_level'] ?? "?"} ${r['section_name'] ?? "unknown"}, ${r['school_year'] ?? ""})');
        return 'Refused: $unsyncedTotal record(s) were entered on this device and are not in the cloud yet:\n'
            '${lines.join('\n')}\n'
            'A pull would delete them. Upload them first, or run "pull-cloud yes discard-local" to delete them.';
      }

      final client = authVm.client!;

      // Fetch everything first, then clear and write in one transaction: a
      // network error or any write error leaves the local DB exactly as it was.
      final fetched = <String, List<Map<String, dynamic>>>{};
      try {
        for (final entry in _pullOrder.entries) {
          fetched[entry.key] = await _fetchTable(client, entry.key, entry.value);
        }
      } catch (e) {
        return 'Pull stopped while downloading, nothing was changed: $e';
      }

      try {
        await localDb.transaction((txn) async {
          for (final table in _clearedTables) {
            await txn.delete(table);
          }
          for (final entry in _pullOrder.entries) {
            await _writeTable(txn, entry.key, fetched[entry.key]!);
          }
          final user = authVm.currentUser;
          await _setMeta(txn, {
            'last_pull_user_id': user?.id,
            'last_pull_user_email': user?.email,
            'last_pull_at': DateTime.now().toUtc().toIso8601String(),
          });
        });
      } catch (e) {
        return 'Pull stopped, nothing was changed (rolled back): $e';
      }

      final out = StringBuffer();
      if (discardLocal && unsyncedTotal > 0) {
        out.writeln('Discarded $unsyncedTotal local record(s).');
      }
      for (final entry in fetched.entries) {
        out.writeln('${entry.key}: ${entry.value.length} rows');
      }
      out.write('Done. Local data now belongs to ${authVm.currentUser?.email}.');
      return out.toString();
    },
  ));
}

/// "email on UTC-time" of the last successful pull, or null if none.
Future<String?> _lastPull(Database db) async {
  final rows = await db.query('sync_meta');
  final meta = {for (final r in rows) r['key'] as String: r['value'] as String?};
  final email = meta['last_pull_user_email'];
  return email == null ? null : '$email on ${meta['last_pull_at']}';
}

/// Records entered on this device (origin 'local'), per kind and section:
/// CRLA assessments, Phil-IRI sessions, Phil-IRI GST results, ARAL
/// enrollments and ARAL sessions (with their attendance; no section).
/// (Phil-IRI readings, miscues and answers belong to their session.)
Future<List<Map<String, Object?>>> _unsynced(Database db) => db.rawQuery('''
      SELECT x.kind, x.section_id, COUNT(*) AS n, s.grade_level, s.section_name, s.school_year
      FROM (
        SELECT 'CRLA assessment(s)' AS kind, section_id FROM crla_assessments WHERE origin = 'local'
        UNION ALL
        SELECT 'Phil-IRI session(s)', section_id FROM phil_iri_assessments WHERE origin = 'local'
        UNION ALL
        SELECT 'Phil-IRI GST result(s)', section_id FROM phil_iri_gst_results WHERE origin = 'local'
        UNION ALL
        SELECT 'ARAL enrollment(s)', section_id FROM aral_enrollments WHERE origin = 'local'
        UNION ALL
        SELECT 'ARAL session(s)', NULL FROM aral_sessions WHERE origin = 'local'
      ) x
      LEFT JOIN sections s ON s.id = x.section_id
      GROUP BY x.kind, x.section_id
      ORDER BY x.section_id, x.kind
    ''');

Future<void> _setMeta(Transaction txn, Map<String, String?> values) async {
  for (final e in values.entries) {
    await txn.insert('sync_meta', {'key': e.key, 'value': e.value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
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

Future<void> _writeTable(Transaction txn, String table, List<Map<String, dynamic>> rows) async {
  // Only copy columns the local table has, so extra cloud columns don't break the insert.
  final info = await txn.rawQuery('PRAGMA table_info($table)');
  final localCols = info.map((c) => c['name'] as String).toSet();

  // The tables were just emptied, so plain inserts: nothing can clash.
  for (final row in rows) {
    final local = _toLocal(row, localCols);
    if (_originTables.contains(table)) local['origin'] = 'cloud';
    await txn.insert(table, local);
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
