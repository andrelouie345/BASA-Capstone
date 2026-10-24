// Mirror-only settings tables (report_settings, aral_settings): the server
// row of a school (or the region) may come back with a new id after a reset
// on another device. Mirroring it replaces the device's old row for the same
// key instead of clashing on the unique key (command pass F20).
import 'dart:io';

import 'package:basa_capstone/core/data/local/aral_setting_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/report_setting_repository_sqlite.dart';
import 'package:basa_capstone/core/models/aral_setting.dart';
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_settings_mirror_').path);
    await db.insert('schools', {'id': 9401, 'school_id': 'ZZM1', 'school_name': 'ZZ Mirror A'});
    await db.insert('schools', {'id': 9402, 'school_id': 'ZZM2', 'school_name': 'ZZ Mirror B'});
  });

  tearDownAll(LocalDatabase.close);

  test('report_settings: a new server id for the same school replaces the old row', () async {
    final repo = ReportSettingRepositorySqlite(db);
    await repo.upsertWithId(ReportSetting(id: 10, schoolId: 9401, settings: {'done_threshold': 0.85}));
    await repo.upsertWithId(ReportSetting(id: 12, schoolId: 9402, settings: {'done_threshold': 0.5}));
    await repo.upsertWithId(ReportSetting(id: 30, settings: {'done_threshold': 0.9}));

    await repo.upsertWithId(ReportSetting(id: 11, schoolId: 9401, settings: {'offline_signin_days': 3}));
    await repo.upsertWithId(ReportSetting(id: 31, settings: {'offline_signin_days': 7}));

    final a = await repo.getForSchool(9401);
    expect(a!.id, 11);
    expect(a.settings, {'offline_signin_days': 3});
    expect((await repo.getRegion())!.id, 31);
    expect((await repo.getForSchool(9402))!.id, 12, reason: 'another school keeps its row');
    expect(await db.query('report_settings'), hasLength(3));
  });

  test('aral_settings: a new server id for the same school replaces the old row', () async {
    final repo = AralSettingRepositorySqlite(db);
    await repo.upsertWithId(AralSetting(id: 40, schoolId: 9401, settings: {'idle_session_days': 7}));
    await repo.upsertWithId(AralSetting(id: 42, schoolId: 9402, settings: {'idle_session_days': 9}));
    await repo.upsertWithId(AralSetting(id: 50, settings: {'idle_session_days': 10}));

    await repo.upsertWithId(AralSetting(id: 41, schoolId: 9401, settings: {'idle_session_days': 5}));
    await repo.upsertWithId(AralSetting(id: 51, settings: {'idle_session_days': 12}));

    final a = await repo.getForSchool(9401);
    expect(a!.id, 41);
    expect(a.settings, {'idle_session_days': 5});
    expect((await repo.getRegion())!.id, 51);
    expect((await repo.getForSchool(9402))!.id, 42, reason: 'another school keeps its row');
    expect(await db.query('aral_settings'), hasLength(3));
  });
}
