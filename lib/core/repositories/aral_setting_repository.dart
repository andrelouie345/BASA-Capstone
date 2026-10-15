// lib/core/repositories/aral_setting_repository.dart
import '../models/aral_setting.dart';

/// The stored ARAL settings rows: one region-wide row and at most one per
/// school. Merging them with the built-in defaults is the ViewModel's job. The
/// SQLite implementation reads and mirrors only.
abstract class AralSettingRepository {
  /// The region-wide row, or null when none was saved (defaults apply).
  Future<AralSetting?> getRegion();

  /// That school's override, or null when it has none.
  Future<AralSetting?> getForSchool(int schoolId);

  /// Creates or replaces the row for [schoolId] (null = region-wide) and
  /// returns it. The cloud allows the region row to the superadmin only and
  /// a school row to that school's admin/coordinator.
  Future<AralSetting> save(int? schoolId, Map<String, Object?> settings);

  /// Removes a school's override so the region values apply again.
  /// Throws when nothing was deleted.
  Future<void> deleteForSchool(int schoolId);

  /// Local-mirroring only, keeps Supabase's id. Supabase impl throws UnimplementedError.
  Future<AralSetting> upsertWithId(AralSetting setting);

  /// Local-mirroring only: drops the local copy of a school's override
  /// (no-op when there is none). Supabase impl throws UnimplementedError.
  Future<void> removeMirroredForSchool(int schoolId);
}
