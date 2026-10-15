// lib/core/repositories/crla_threshold_repository.dart
import '../models/crla_threshold_setting.dart';

/// The stored CRLA threshold rows: one region-wide row and at most one per
/// school. Merging them with the built-in defaults is the ViewModel's job (see
/// CrlaThresholdSetting). The SQLite implementation reads and mirrors only.
abstract class CrlaThresholdRepository {
  /// The region-wide row, or null when none was saved (defaults apply).
  Future<CrlaThresholdSetting?> getRegion();

  /// That school's override, or null when it has none.
  Future<CrlaThresholdSetting?> getForSchool(int schoolId);

  /// Creates or replaces the row for [schoolId] (null = region-wide) and
  /// returns it. The cloud allows the region row to the superadmin only and
  /// a school row to that school's admin/coordinator.
  Future<CrlaThresholdSetting> save(int? schoolId, Map<String, Object?> settings);

  /// Removes a school's override so the region values apply again.
  /// Throws when nothing was deleted.
  Future<void> deleteForSchool(int schoolId);

  /// Local-mirroring only, keeps Supabase's id. Supabase impl throws UnimplementedError.
  Future<CrlaThresholdSetting> upsertWithId(CrlaThresholdSetting setting);

  /// Local-mirroring only: drops the local copy of a school's override
  /// (no-op when there is none). Supabase impl throws UnimplementedError.
  Future<void> removeMirroredForSchool(int schoolId);
}
