// lib/core/data/local/phil_iri_threshold_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/phil_iri_threshold_setting.dart';
import '../../repositories/phil_iri_threshold_repository.dart';

/// Read + mirror only: thresholds are set online by the superadmin and
/// school admins/coordinators.
class PhilIriThresholdRepositorySqlite implements PhilIriThresholdRepository {
  final Database db;
  PhilIriThresholdRepositorySqlite(this.db);

  static Never _online() =>
      throw UnsupportedError('Phil-IRI thresholds are set online; use the cloud repository');

  @override
  Future<PhilIriThresholdSetting> save(int? schoolId, Map<String, Object?> settings) async => _online();
  @override
  Future<void> deleteForSchool(int schoolId) async => _online();

  @override
  Future<PhilIriThresholdSetting?> getRegion() async {
    final rows = await db.query('phil_iri_thresholds', where: 'school_id IS NULL', limit: 1);
    return rows.isEmpty ? null : PhilIriThresholdSetting.fromMap(rows.first);
  }

  @override
  Future<PhilIriThresholdSetting?> getForSchool(int schoolId) async {
    final rows = await db.query('phil_iri_thresholds', where: 'school_id = ?', whereArgs: [schoolId], limit: 1);
    return rows.isEmpty ? null : PhilIriThresholdSetting.fromMap(rows.first);
  }

  @override
  Future<PhilIriThresholdSetting> upsertWithId(PhilIriThresholdSetting setting) async {
    if (setting.id == null) throw ArgumentError('Cannot upsertWithId a PhilIriThresholdSetting with no id');
    await upsertById(db, 'phil_iri_thresholds', toSqliteRow({
      ...setting.toMap(),
      if (setting.updatedBy != null) 'updated_by': setting.updatedBy,
      if (setting.updatedAt != null) 'updated_at': setting.updatedAt,
    }));
    final rows = await db.query('phil_iri_thresholds', where: 'id = ?', whereArgs: [setting.id]);
    return PhilIriThresholdSetting.fromMap(rows.first);
  }
}
