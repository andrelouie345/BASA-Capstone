// lib/core/data/remote/aral_setting_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/aral_setting.dart';
import '../../repositories/aral_setting_repository.dart';

class AralSettingRepositorySupabase implements AralSettingRepository {
  final SupabaseClient client;
  AralSettingRepositorySupabase(this.client);

  static AralSetting _s(Object? r) => AralSetting.fromMap(r as Map<String, Object?>);

  @override
  Future<AralSetting?> getRegion() async {
    final rows = await client.from('aral_settings').select().isFilter('school_id', null);
    return (rows as List).isEmpty ? null : _s(rows.first);
  }

  @override
  Future<AralSetting?> getForSchool(int schoolId) async {
    final rows = await client.from('aral_settings').select().eq('school_id', schoolId);
    return (rows as List).isEmpty ? null : _s(rows.first);
  }

  @override
  Future<AralSetting> save(int? schoolId, Map<String, Object?> settings) async {
    final existing = schoolId == null ? await getRegion() : await getForSchool(schoolId);
    if (existing == null) {
      // A unique index on coalesce(school_id, 0) catches a concurrent insert.
      final rows = await client.from('aral_settings').insert({'school_id': schoolId, 'settings': settings}).select();
      return _s((rows as List).first);
    }
    final rows = await client.from('aral_settings').update({'settings': settings}).eq('id', existing.id!).select();
    if ((rows as List).isEmpty) throw Exception('ARAL settings not saved — check your permissions');
    return _s(rows.first);
  }

  @override
  Future<void> deleteForSchool(int schoolId) async {
    final rows = await client.from('aral_settings').delete().eq('school_id', schoolId).select();
    if ((rows as List).isEmpty) {
      throw Exception('No override deleted — the school has none, or check your permissions ("$schoolId")');
    }
  }

  @override
  Future<AralSetting> upsertWithId(AralSetting setting) =>
      throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');

  @override
  Future<void> removeMirroredForSchool(int schoolId) => throw UnimplementedError(
      'removeMirroredForSchool is a local-mirroring operation — use deleteForSchool against Supabase');
}
