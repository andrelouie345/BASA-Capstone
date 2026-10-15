// lib/core/repositories/aral_tutor_setting_repository.dart
import '../models/aral_tutor_setting.dart';

/// Per-tutor ARAL settings. SQLite is the main write path (offline-first);
/// the Supabase implementation has the same interface for online use and the
/// future sync.
abstract class AralTutorSettingRepository {
  /// The tutor's settings, or null (= the defaults).
  Future<AralTutorSetting?> find(String tutorId);

  Future<List<AralTutorSetting>> getBySchool(int schoolId);

  /// Creates or replaces the tutor's settings.
  Future<AralTutorSetting> save(AralTutorSetting setting);

  /// Local-mirroring only: stores a cloud row as-is (origin 'cloud').
  /// Supabase impl throws UnimplementedError.
  Future<AralTutorSetting> upsertMirrored(AralTutorSetting setting);
}
