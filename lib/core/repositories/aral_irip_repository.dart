// lib/core/repositories/aral_irip_repository.dart
import '../models/aral_irip.dart';

/// IRIP target lists (content, mirrored from the cloud) and learners' IRIP
/// weeks. SQLite is the main write path for weeks (offline-first); the
/// Supabase implementation has the same interface for online use and the
/// future sync.
abstract class AralIripRepository {
  /// The active targets of [program], by strand then seq.
  Future<List<AralIripTarget>> targets(AralIripProgram program);

  Future<AralIripTarget?> findTarget(int id);

  /// Every week of the learner's IRIP, by cycle, week and strand.
  Future<List<AralIripWeek>> weeks(int enrollmentId);

  Future<AralIripWeek?> findWeek(int id);

  Future<AralIripWeek> insertWeek(AralIripWeek week);

  /// Saves the changeable fields (target, status, rated_on, notes).
  Future<AralIripWeek> updateWeek(AralIripWeek week);

  Future<void> deleteWeek(int id);

  /// Local-mirroring only: keep Supabase's ids (weeks get origin 'cloud').
  /// Supabase impl throws UnimplementedError.
  Future<AralIripTarget> upsertTargetWithId(AralIripTarget target);
  Future<AralIripWeek> upsertWeekWithId(AralIripWeek week);
}
