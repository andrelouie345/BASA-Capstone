// lib/core/repositories/crla_part1_standard_repository.dart
import '../models/crla_part1_standard.dart';

abstract class CrlaPart1StandardRepository {
  /// Returns the stored row, including the DB-computed total_score and reading_level.
  Future<CrlaPart1Standard> insert(CrlaPart1Standard part1);

  /// Corrects scores on an existing row (keyed by assessment_id).
  Future<void> update(CrlaPart1Standard part1);

  Future<CrlaPart1Standard?> findByAssessmentId(int assessmentId);

  /// Local-mirroring only. Supabase impl throws UnimplementedError.
  Future<CrlaPart1Standard> upsertWithId(CrlaPart1Standard part1);
}