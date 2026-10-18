// lib/core/repositories/aral_readability_repository.dart
import '../models/aral_readability_log.dart';

/// A learner's readability log. SQLite is the main write path (offline-first,
/// origin 'local'); Supabase has the same interface for the future sync.
abstract class AralReadabilityRepository {
  /// The learner's entries, oldest first.
  Future<List<AralReadabilityLog>> forEnrollment(int enrollmentId);

  Future<AralReadabilityLog?> findById(int id);

  Future<AralReadabilityLog> insert(AralReadabilityLog log);

  /// Saves the selection, counts, date and source (not the learner).
  Future<AralReadabilityLog> update(AralReadabilityLog log);

  /// Throws when nothing was deleted.
  Future<void> delete(int id);
}
