// lib/core/data/remote/aral_tutor_setting_repository_supabase.dart
//
// Same interface as the SQLite repository (the main write path today); used
// online and by the future sync. The database stamps updated_by/updated_at.
import 'package:supabase/supabase.dart';
import '../../models/aral_tutor_setting.dart';
import '../../repositories/aral_tutor_setting_repository.dart';

class AralTutorSettingRepositorySupabase implements AralTutorSettingRepository {
  final SupabaseClient client;
  AralTutorSettingRepositorySupabase(this.client);

  @override
  Future<AralTutorSetting?> find(String tutorId) async {
    final rows = await client.from('aral_tutor_settings').select().eq('tutor_id', tutorId);
    return (rows as List).isEmpty ? null : AralTutorSetting.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<List<AralTutorSetting>> getBySchool(int schoolId) async {
    final rows = await client.from('aral_tutor_settings').select().eq('school_id', schoolId);
    return (rows as List).map((r) => AralTutorSetting.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<AralTutorSetting> save(AralTutorSetting setting) async {
    final payload = setting.toMap()
      ..remove('updated_by')
      ..remove('updated_at');
    final rows = await client.from('aral_tutor_settings').upsert(payload, onConflict: 'tutor_id').select();
    if ((rows as List).isEmpty) throw Exception('ARAL tutor setting not saved — check your permissions');
    return AralTutorSetting.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<AralTutorSetting> upsertMirrored(AralTutorSetting setting) =>
      throw UnimplementedError('upsertMirrored is for local mirroring only');
}
