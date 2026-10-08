// lib/core/repositories/crla_part1_english_repository.dart
import '../models/crla_part1_english.dart';

abstract class CrlaPart1EnglishRepository {
  /// Returns the stored row, including the DB-computed total_score and reading_level.
  Future<CrlaPart1English> insert(CrlaPart1English part1);

  /// Corrects scores on an existing row (keyed by assessment_id).
  Future<void> update(CrlaPart1English part1);

  Future<CrlaPart1English?> findByAssessmentId(int assessmentId);

  /// Local-mirroring only. Supabase impl throws UnimplementedError.
  Future<CrlaPart1English> upsertWithId(CrlaPart1English part1);
}