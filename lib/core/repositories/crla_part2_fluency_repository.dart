// lib/core/repositories/crla_part2_fluency_repository.dart
import '../models/crla_part2_fluency.dart';

abstract class CrlaPart2FluencyRepository {
  /// Returns the stored row, including the DB-computed wpm.
  Future<CrlaPart2Fluency> insert(CrlaPart2Fluency fluency);

  /// Corrects an existing row (keyed by assessment_id).
  Future<void> update(CrlaPart2Fluency fluency);

  Future<CrlaPart2Fluency?> findByAssessmentId(int assessmentId);

  /// Local-mirroring only. Supabase impl throws UnimplementedError.
  Future<CrlaPart2Fluency> upsertWithId(CrlaPart2Fluency fluency);
}