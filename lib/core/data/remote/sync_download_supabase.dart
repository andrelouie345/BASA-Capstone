// lib/core/data/remote/sync_download_supabase.dart
import 'package:supabase/supabase.dart' show SupabaseClient;

import '../../repositories/sync_download_source.dart';
import '../pull_tables.dart';

/// Full download of the signed-in user's scope; RLS decides what comes back.
class SyncDownloadSupabase implements SyncDownloadSource {
  final SupabaseClient _client;
  SyncDownloadSupabase(this._client);

  @override
  Future<Map<String, List<Map<String, dynamic>>>> downloadAll() async {
    final fetched = <String, List<Map<String, dynamic>>>{};
    for (final entry in pullOrder.entries) {
      fetched[entry.key] = await _fetchTable(entry.key, entry.value);
    }
    // SF1 leavers D15 (review M4): learners transferred away from the
    // admin's school come as name-only rows (RLS no longer gives their
    // students row), so the school's own records of them keep a name.
    final students = fetched['students'] ??= [];
    final have = {for (final s in students) s['id']};
    for (final r in await transferredOutLearners()) {
      if (!have.contains(r['id'])) students.add(r);
    }
    return fetched;
  }

  /// transferred_out_learners(): id, LRN, names, sex and the school the
  /// caller's school sent them to (never their current one) of the learners
  /// transferred away from the caller's school (nothing for a tutor or the
  /// superadmin).
  Future<List<Map<String, dynamic>>> transferredOutLearners() async =>
      [for (final r in (await _client.rpc('transferred_out_learners') as List? ?? const [])) Map<String, dynamic>.from(r as Map)];

  Future<List<Map<String, dynamic>>> _fetchTable(String table, String orderBy) async {
    const pageSize = 1000; // Supabase caps a single request at 1000 rows by default
    final all = <Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final page = await _client
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
}
