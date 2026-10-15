// lib/core/data/local/crla_threshold_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/crla_threshold_setting.dart';
import '../../repositories/crla_threshold_repository.dart';

/// Read + mirror only: CRLA thresholds are set online by the superadmin and
/// school admins/coordinators.
class CrlaThresholdRepositorySqlite implements CrlaThresholdRepository {
  final Database db;
  CrlaThresholdRepositorySqlite(this.db);

  static Never _online() =>
      throw UnsupportedError('CRLA thresholds are set online; use the cloud repository');

  @override
  Future<CrlaThresholdSetting> save(int? schoolId, Map<String, Object?> settings) async => _online();
  @override
  Future<void> deleteForSchool(int schoolId) async => _online();

  @override
  Future<CrlaThresholdSetting?> getRegion() async {
    final rows = await db.query('crla_thresholds', where: 'school_id IS NULL', limit: 1);
    return rows.isEmpty ? null : CrlaThresholdSetting.fromMap(rows.first);
  }

  @override
  Future<CrlaThresholdSetting?> getForSchool(int schoolId) async {
    final rows = await db.query('crla_thresholds', where: 'school_id = ?', whereArgs: [schoolId], limit: 1);
    return rows.isEmpty ? null : CrlaThresholdSetting.fromMap(rows.first);
  }

  @override
  Future<CrlaThresholdSetting> upsertWithId(CrlaThresholdSetting setting) async {
    if (setting.id == null) throw ArgumentError('Cannot upsertWithId a CrlaThresholdSetting with no id');
    await upsertById(db, 'crla_thresholds', toSqliteRow({
      ...setting.toMap(),
      if (setting.updatedBy != null) 'updated_by': setting.updatedBy,
      if (setting.updatedAt != null) 'updated_at': setting.updatedAt,
    }));
    final rows = await db.query('crla_thresholds', where: 'id = ?', whereArgs: [setting.id]);
    return CrlaThresholdSetting.fromMap(rows.first);
  }

  @override
  Future<void> removeMirroredForSchool(int schoolId) async {
    await db.delete('crla_thresholds', where: 'school_id = ?', whereArgs: [schoolId]);
  }
}
