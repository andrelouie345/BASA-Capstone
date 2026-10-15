// lib/core/data/remote/aral_irip_repository_supabase.dart
//
// Same interface as the SQLite repository (the main write path today); used
// online and by the future sync. The database stamps created_by and the times.
import 'package:supabase/supabase.dart';
import '../../models/aral_irip.dart';
import '../../repositories/aral_irip_repository.dart';

class AralIripRepositorySupabase implements AralIripRepository {
  final SupabaseClient client;
  AralIripRepositorySupabase(this.client);

  static AralIripWeek _w(Object? r) => AralIripWeek.fromMap(r as Map<String, Object?>);

  static const _changeable = ['target_id', 'status', 'rated_on', 'notes'];

  @override
  Future<List<AralIripTarget>> targets(AralIripProgram program) async {
    final rows = await client
        .from('aral_irip_targets')
        .select()
        .eq('program', program.value)
        .eq('is_active', true)
        .order('strand', ascending: false)
        .order('seq');
    return (rows as List).map((r) => AralIripTarget.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<AralIripTarget?> findTarget(int id) async {
    final rows = await client.from('aral_irip_targets').select().eq('id', id);
    return (rows as List).isEmpty ? null : AralIripTarget.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<List<AralIripWeek>> weeks(int enrollmentId) async {
    final rows = await client
        .from('aral_irip_weeks')
        .select()
        .eq('enrollment_id', enrollmentId)
        .order('cycle_no')
        .order('week_no')
        .order('strand', ascending: false);
    return (rows as List).map(_w).toList();
  }

  @override
  Future<AralIripWeek?> findWeek(int id) async {
    final rows = await client.from('aral_irip_weeks').select().eq('id', id);
    return (rows as List).isEmpty ? null : _w(rows.first);
  }

  @override
  Future<AralIripWeek> insertWeek(AralIripWeek week) async {
    final payload = week.toMap()
      ..remove('id')
      ..remove('created_by')
      ..remove('created_at')
      ..remove('updated_at');
    final rows = await client.from('aral_irip_weeks').insert(payload).select();
    return _w((rows as List).first);
  }

  @override
  Future<AralIripWeek> updateWeek(AralIripWeek week) async {
    if (week.id == null) throw ArgumentError('updateWeek needs an id');
    final all = week.toMap();
    final rows = await client
        .from('aral_irip_weeks')
        .update({for (final c in _changeable) c: all[c]})
        .eq('id', week.id!)
        .select();
    if ((rows as List).isEmpty) throw Exception('No IRIP week changed — check the id or your permissions');
    return _w(rows.first);
  }

  @override
  Future<void> deleteWeek(int id) async {
    final rows = await client.from('aral_irip_weeks').delete().eq('id', id).select();
    if ((rows as List).isEmpty) throw Exception('No IRIP week deleted — check the id or your permissions');
  }

  @override
  Future<AralIripTarget> upsertTargetWithId(AralIripTarget target) =>
      throw UnimplementedError('upsertTargetWithId is for local mirroring only');

  @override
  Future<AralIripWeek> upsertWeekWithId(AralIripWeek week) =>
      throw UnimplementedError('upsertWeekWithId is for local mirroring only');
}
