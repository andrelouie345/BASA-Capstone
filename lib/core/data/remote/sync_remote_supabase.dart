// lib/core/data/remote/sync_remote_supabase.dart
import 'package:supabase/supabase.dart' show SupabaseClient;

import '../../models/sync_upload.dart';
import '../../repositories/sync_remote_repository.dart';

/// Upload columns read back (never the payload: listings stay small).
const _uploadColumns = 'id, status, reason, conflicts, id_map, created_at, decided_at, summary';

class SyncRemoteSupabase implements SyncRemoteRepository {
  final SupabaseClient _client;
  SyncRemoteSupabase(this._client);

  @override
  Future<List<Map<String, dynamic>>> rowsWhere(String table, String column, List<Object> values,
      {String columns = '*'}) async {
    final out = <Map<String, dynamic>>[];
    // Chunks keep the request URL short.
    for (var i = 0; i < values.length; i += 200) {
      final chunk = values.sublist(i, i + 200 > values.length ? values.length : i + 200);
      final rows = await _client.from(table).select(columns).inFilter(column, chunk);
      out.addAll((rows as List).cast<Map<String, dynamic>>());
    }
    return out;
  }

  @override
  Future<SyncUploadRow> insertUpload({
    required String clientUploadId,
    required int? schoolId,
    required String deviceId,
    required String release,
    required Map<String, Object?> payload,
    required Map<String, Object?> summary,
  }) async {
    final row = await _client
        .from('sync_uploads')
        .insert({
          'client_upload_id': clientUploadId,
          'school_id': schoolId,
          'device_id': deviceId,
          'release': release,
          'payload': payload,
          'summary': summary,
        })
        .select(_uploadColumns)
        .single();
    return SyncUploadRow.fromMap(row);
  }

  @override
  Future<SyncUploadRow?> uploadByClientId(String clientUploadId) async {
    final row = await _client
        .from('sync_uploads')
        .select(_uploadColumns)
        .eq('client_upload_id', clientUploadId)
        .eq('uploader_id', _me)
        .maybeSingle();
    return row == null ? null : SyncUploadRow.fromMap(row);
  }

  @override
  Future<List<SyncUploadRow>> myUploads({List<int>? ids, int limit = 20}) async {
    var q = _client.from('sync_uploads').select(_uploadColumns).eq('uploader_id', _me);
    if (ids != null) q = q.inFilter('id', ids);
    final rows = await q.order('id', ascending: false).limit(ids?.length ?? limit);
    return [for (final r in (rows as List).cast<Map<String, dynamic>>()) SyncUploadRow.fromMap(r)];
  }

  @override
  Future<bool> autoApprove(int? schoolId) async =>
      (await _client.rpc('sync_auto_approve', params: {'p_school_id': schoolId})) == true;

  @override
  Future<SyncApplyResult> apply(int uploadId) async {
    final r = Map<String, dynamic>.from(await _client.rpc('sync_apply', params: {'p_id': uploadId}) as Map);
    return SyncApplyResult(status: r['status'] as String, reason: r['reason'] as String?);
  }

  @override
  Future<void> withdraw(int uploadId) => _client.rpc('sync_withdraw', params: {'p_id': uploadId});

  String get _me {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('No signed-in user on this client');
    return id;
  }
}
