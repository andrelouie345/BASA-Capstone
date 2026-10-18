// lib/core/data/remote/aral_readability_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/aral_readability_log.dart';
import '../../repositories/aral_readability_repository.dart';

/// Same interface against Supabase (for the future sync and for probes);
/// the cloud trigger stamps created_by/created_at/updated_at.
class AralReadabilityRepositorySupabase implements AralReadabilityRepository {
  final SupabaseClient client;
  AralReadabilityRepositorySupabase(this.client);

  static AralReadabilityLog _l(Object? r) => AralReadabilityLog.fromMap(r as Map<String, Object?>);

  @override
  Future<List<AralReadabilityLog>> forEnrollment(int enrollmentId) async {
    final rows = await client
        .from('aral_readability_logs')
        .select()
        .eq('enrollment_id', enrollmentId)
        .order('read_on')
        .order('id');
    return (rows as List).map(_l).toList();
  }

  @override
  Future<AralReadabilityLog?> findById(int id) async {
    final rows = await client.from('aral_readability_logs').select().eq('id', id);
    return (rows as List).isEmpty ? null : _l(rows.first);
  }

  @override
  Future<AralReadabilityLog> insert(AralReadabilityLog log) async {
    final row = Map.of(log.toMap())
      ..remove('id')
      ..remove('created_by');
    final rows = await client.from('aral_readability_logs').insert(row).select();
    return _l((rows as List).first);
  }

  @override
  Future<AralReadabilityLog> update(AralReadabilityLog log) async {
    final row = Map.of(log.toMap())
      ..remove('id')
      ..remove('enrollment_id')
      ..remove('created_by');
    final rows = await client.from('aral_readability_logs').update(row).eq('id', log.id!).select();
    if ((rows as List).isEmpty) throw Exception('Readability log entry not saved — check your permissions');
    return _l(rows.first);
  }

  @override
  Future<void> delete(int id) async {
    final rows = await client.from('aral_readability_logs').delete().eq('id', id).select();
    if ((rows as List).isEmpty) throw Exception('No readability log entry deleted ($id)');
  }
}
