// lib/core/data/local/report_setting_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/report_setting.dart';
import '../../repositories/report_setting_repository.dart';

/// Read + mirror only: Report settings are set online by the superadmin and
/// school admins/coordinators.
class ReportSettingRepositorySqlite implements ReportSettingRepository {
  final Database db;
  ReportSettingRepositorySqlite(this.db);

  static Never _online() => throw UnsupportedError('Report settings are set online; use the cloud repository');

  @override
  Future<ReportSetting> save(int? schoolId, Map<String, Object?> settings) async => _online();
  @override
  Future<void> deleteForSchool(int schoolId) async => _online();

  @override
  Future<ReportSetting?> getRegion() async {
    final rows = await db.query('report_settings', where: 'school_id IS NULL', limit: 1);
    return rows.isEmpty ? null : ReportSetting.fromMap(rows.first);
  }

  @override
  Future<ReportSetting?> getForSchool(int schoolId) async {
    final rows = await db.query('report_settings', where: 'school_id = ?', whereArgs: [schoolId], limit: 1);
    return rows.isEmpty ? null : ReportSetting.fromMap(rows.first);
  }

  @override
  Future<ReportSetting> upsertWithId(ReportSetting setting) async {
    if (setting.id == null) throw ArgumentError('Cannot upsertWithId an ReportSetting with no id');
    await db.transaction((txn) async {
      // The server row of a school (or the region) gets a new id after a
      // reset on another device: the server wins, so the old row for the same
      // key goes (F20).
      await txn.delete('report_settings',
          where: 'IFNULL(school_id, 0) = ? AND id <> ?', whereArgs: [setting.schoolId ?? 0, setting.id]);
      await upsertById(txn, 'report_settings', toSqliteRow({
        ...setting.toMap(),
        if (setting.updatedBy != null) 'updated_by': setting.updatedBy,
        if (setting.updatedAt != null) 'updated_at': setting.updatedAt,
      }));
    });
    final rows = await db.query('report_settings', where: 'id = ?', whereArgs: [setting.id]);
    return ReportSetting.fromMap(rows.first);
  }

  @override
  Future<void> removeMirroredForSchool(int schoolId) async {
    await db.delete('report_settings', where: 'school_id = ?', whereArgs: [schoolId]);
  }
}
