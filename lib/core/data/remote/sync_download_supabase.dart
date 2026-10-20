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
    return fetched;
  }

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
