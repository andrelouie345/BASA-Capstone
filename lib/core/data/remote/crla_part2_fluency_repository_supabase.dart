// lib/core/data/remote/crla_part2_fluency_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/crla_part2_fluency.dart';
import '../../repositories/crla_part2_fluency_repository.dart';

class CrlaPart2FluencyRepositorySupabase implements CrlaPart2FluencyRepository {
  final SupabaseClient client;
  CrlaPart2FluencyRepositorySupabase(this.client);

  @override
  Future<CrlaPart2Fluency> insert(CrlaPart2Fluency fluency) async {
    // wpm is computed by the DB and comes back on the returned row.
    final inserted = await client.from('crla_part2_fluency').insert(fluency.toMap()).select();
    return CrlaPart2Fluency.fromMap((inserted as List).first as Map<String, Object?>);
  }

  @override
  Future<void> update(CrlaPart2Fluency fluency) async {
    final payload = fluency.toMap()..remove('assessment_id');
    final rows = await client
        .from('crla_part2_fluency')
        .update(payload)
        .eq('assessment_id', fluency.assessmentId)
        .select();
    if ((rows as List).isEmpty) {
      throw Exception('No Part 2 row updated — check the assessment id or your permissions (${fluency.assessmentId})');
    }
  }

  @override
  Future<CrlaPart2Fluency?> findByAssessmentId(int assessmentId) async {
    final rows = await client.from('crla_part2_fluency').select().eq('assessment_id', assessmentId);
    return (rows as List).isEmpty ? null : CrlaPart2Fluency.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<CrlaPart2Fluency> upsertWithId(CrlaPart2Fluency fluency) async {
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }
}