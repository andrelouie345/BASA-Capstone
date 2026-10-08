// lib/core/data/remote/crla_part1_standard_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/crla_part1_standard.dart';
import '../../repositories/crla_part1_standard_repository.dart';

class CrlaPart1StandardRepositorySupabase implements CrlaPart1StandardRepository {
  final SupabaseClient client;
  CrlaPart1StandardRepositorySupabase(this.client);

  @override
  Future<CrlaPart1Standard> insert(CrlaPart1Standard part1) async {
    // total_score and reading_level are computed by the DB and come back on the returned row.
    // The check_crla_part1_variant trigger rejects this insert if the parent assessment
    // is not an 'mt' or 'fil' variant.
    final inserted = await client.from('crla_part1_standard').insert(part1.toMap()).select();
    return CrlaPart1Standard.fromMap((inserted as List).first as Map<String, Object?>);
  }

  @override
  Future<void> update(CrlaPart1Standard part1) async {
    final payload = part1.toMap()..remove('assessment_id');
    final rows = await client
        .from('crla_part1_standard')
        .update(payload)
        .eq('assessment_id', part1.assessmentId)
        .select();
    if ((rows as List).isEmpty) {
      throw Exception('No Part 1 row updated — check the assessment id or your permissions (${part1.assessmentId})');
    }
  }

  @override
  Future<CrlaPart1Standard?> findByAssessmentId(int assessmentId) async {
    final rows = await client.from('crla_part1_standard').select().eq('assessment_id', assessmentId);
    return (rows as List).isEmpty ? null : CrlaPart1Standard.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<CrlaPart1Standard> upsertWithId(CrlaPart1Standard part1) async {
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }
}