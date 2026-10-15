// lib/core/data/local/aral_tutor_setting_repository_sqlite.dart
//
// The main write path for per-tutor ARAL settings (offline-first). The local
// triggers (aral_local_schema.dart) re-check the cloud's rules for rows saved
// on this device; role checks live in the ViewModel.
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/aral_tutor_setting.dart';
import '../../repositories/aral_tutor_setting_repository.dart';

class AralTutorSettingRepositorySqlite implements AralTutorSettingRepository {
  final Database db;
  AralTutorSettingRepositorySqlite(this.db);

  @override
  Future<AralTutorSetting?> find(String tutorId) async {
    final rows = await db.query('aral_tutor_settings', where: 'tutor_id = ?', whereArgs: [tutorId], limit: 1);
    return rows.isEmpty ? null : AralTutorSetting.fromMap(rows.first);
  }

  @override
  Future<List<AralTutorSetting>> getBySchool(int schoolId) async {
    final rows = await db.query('aral_tutor_settings', where: 'school_id = ?', whereArgs: [schoolId]);
    return rows.map(AralTutorSetting.fromMap).toList();
  }

  @override
  Future<AralTutorSetting> save(AralTutorSetting setting) async {
    // A setting saved here is 'local' (not uploaded) until the sync, even if
    // it started as a mirrored row.
    final row = {
      ...toSqliteRow(setting.toMap()),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'origin': 'local',
    };
    await upsertById(db, 'aral_tutor_settings', row, key: 'tutor_id');
    return (await find(setting.tutorId))!;
  }

  @override
  Future<AralTutorSetting> upsertMirrored(AralTutorSetting setting) async {
    await upsertById(db, 'aral_tutor_settings', {...toSqliteRow(setting.toMap()), 'origin': 'cloud'}, key: 'tutor_id');
    return (await find(setting.tutorId))!;
  }
}
