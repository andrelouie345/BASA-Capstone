// lib/core/data/local/aral_setting_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/aral_setting.dart';
import '../../repositories/aral_setting_repository.dart';

/// Read + mirror only: ARAL settings are set online by the superadmin and
/// school admins/coordinators.
class AralSettingRepositorySqlite implements AralSettingRepository {
  final Database db;
  AralSettingRepositorySqlite(this.db);

  static Never _online() => throw UnsupportedError('ARAL settings are set online; use the cloud repository');

  @override
  Future<AralSetting> save(int? schoolId, Map<String, Object?> settings) async => _online();
  @override
  Future<void> deleteForSchool(int schoolId) async => _online();

  @override
  Future<AralSetting?> getRegion() async {
    final rows = await db.query('aral_settings', where: 'school_id IS NULL', limit: 1);
    return rows.isEmpty ? null : AralSetting.fromMap(rows.first);
  }

  @override
  Future<AralSetting?> getForSchool(int schoolId) async {
    final rows = await db.query('aral_settings', where: 'school_id = ?', whereArgs: [schoolId], limit: 1);
    return rows.isEmpty ? null : AralSetting.fromMap(rows.first);
  }

  @override
  Future<AralSetting> upsertWithId(AralSetting setting) async {
    if (setting.id == null) throw ArgumentError('Cannot upsertWithId an AralSetting with no id');
    await db.transaction((txn) async {
      // The server row of a school (or the region) gets a new id after a
      // reset on another device: the server wins, so the old row for the same
      // key goes (F20).
      await txn.delete('aral_settings',
          where: 'IFNULL(school_id, 0) = ? AND id <> ?', whereArgs: [setting.schoolId ?? 0, setting.id]);
      await upsertById(txn, 'aral_settings', toSqliteRow({
        ...setting.toMap(),
        if (setting.updatedBy != null) 'updated_by': setting.updatedBy,
        if (setting.updatedAt != null) 'updated_at': setting.updatedAt,
      }));
    });
    final rows = await db.query('aral_settings', where: 'id = ?', whereArgs: [setting.id]);
    return AralSetting.fromMap(rows.first);
  }

  @override
  Future<void> removeMirroredForSchool(int schoolId) async {
    await db.delete('aral_settings', where: 'school_id = ?', whereArgs: [schoolId]);
  }
}
