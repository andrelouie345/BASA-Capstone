// lib/core/data/remote/crla_threshold_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/crla_threshold_setting.dart';
import '../../repositories/crla_threshold_repository.dart';

class CrlaThresholdRepositorySupabase implements CrlaThresholdRepository {
  final SupabaseClient client;
  CrlaThresholdRepositorySupabase(this.client);

  static CrlaThresholdSetting _s(Object? r) => CrlaThresholdSetting.fromMap(r as Map<String, Object?>);

  @override
  Future<CrlaThresholdSetting?> getRegion() async {
    final rows = await client.from('crla_thresholds').select().isFilter('school_id', null);
    return (rows as List).isEmpty ? null : _s(rows.first);
  }

  @override
  Future<CrlaThresholdSetting?> getForSchool(int schoolId) async {
    final rows = await client.from('crla_thresholds').select().eq('school_id', schoolId);
    return (rows as List).isEmpty ? null : _s(rows.first);
  }

  @override
  Future<CrlaThresholdSetting> save(int? schoolId, Map<String, Object?> settings) async {
    final existing = schoolId == null ? await getRegion() : await getForSchool(schoolId);
    if (existing == null) {
      // A unique index on coalesce(school_id, 0) catches a concurrent insert.
      final rows = await client
          .from('crla_thresholds')
          .insert({'school_id': schoolId, 'settings': settings})
          .select();
      return _s((rows as List).first);
    }
    final rows = await client
        .from('crla_thresholds')
        .update({'settings': settings})
        .eq('id', existing.id!)
        .select();
    if ((rows as List).isEmpty) {
      throw Exception('Thresholds not saved — check your permissions');
    }
    return _s(rows.first);
  }

  @override
  Future<void> deleteForSchool(int schoolId) async {
    final rows = await client.from('crla_thresholds').delete().eq('school_id', schoolId).select();
    if ((rows as List).isEmpty) {
      throw Exception('No override deleted — the school has none, or check your permissions ("$schoolId")');
    }
  }

  @override
  Future<CrlaThresholdSetting> upsertWithId(CrlaThresholdSetting setting) async {
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }

  @override
  Future<void> removeMirroredForSchool(int schoolId) async {
    throw UnimplementedError('removeMirroredForSchool is a local-mirroring operation — use deleteForSchool against Supabase');
  }
}
