// lib/core/data/remote/report_setting_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/report_setting.dart';
import '../../repositories/report_setting_repository.dart';

class ReportSettingRepositorySupabase implements ReportSettingRepository {
  final SupabaseClient client;
  ReportSettingRepositorySupabase(this.client);

  static ReportSetting _s(Object? r) => ReportSetting.fromMap(r as Map<String, Object?>);

  @override
  Future<ReportSetting?> getRegion() async {
    final rows = await client.from('report_settings').select().isFilter('school_id', null);
    return (rows as List).isEmpty ? null : _s(rows.first);
  }

  @override
  Future<ReportSetting?> getForSchool(int schoolId) async {
    final rows = await client.from('report_settings').select().eq('school_id', schoolId);
    return (rows as List).isEmpty ? null : _s(rows.first);
  }

  @override
  Future<ReportSetting> save(int? schoolId, Map<String, Object?> settings) async {
    final existing = schoolId == null ? await getRegion() : await getForSchool(schoolId);
    if (existing == null) {
      // A unique index on coalesce(school_id, 0) catches a concurrent insert.
      final rows = await client.from('report_settings').insert({'school_id': schoolId, 'settings': settings}).select();
      return _s((rows as List).first);
    }
    final rows = await client.from('report_settings').update({'settings': settings}).eq('id', existing.id!).select();
    if ((rows as List).isEmpty) throw Exception('Report settings not saved — check your permissions');
    return _s(rows.first);
  }

  @override
  Future<void> deleteForSchool(int schoolId) async {
    final rows = await client.from('report_settings').delete().eq('school_id', schoolId).select();
    if ((rows as List).isEmpty) {
      throw Exception('No override deleted — the school has none, or check your permissions ("$schoolId")');
    }
  }

  @override
  Future<ReportSetting> upsertWithId(ReportSetting setting) =>
      throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');

  @override
  Future<void> removeMirroredForSchool(int schoolId) => throw UnimplementedError(
      'removeMirroredForSchool is a local-mirroring operation — use deleteForSchool against Supabase');
}
