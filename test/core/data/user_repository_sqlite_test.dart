// Local mirror of accounts created or changed online (command pass finding F1).
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/user_repository_sqlite.dart';
import 'package:basa_capstone/core/models/user.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late UserRepositorySqlite repo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_users_').path);
    repo = UserRepositorySqlite(db);
  });

  tearDownAll(LocalDatabase.close);

  User tutor({String name = 'Tutor One', bool active = true, int school = 6}) => User(
        id: '00000000-0000-0000-0000-0000000000f1',
        email: 'zz.f1@basa.test',
        fullName: name,
        role: UserRole.tutor,
        schoolId: school,
        isActive: active,
        createdAt: DateTime.utc(2026, 10, 23, 8),
        createdBy: '00000000-0000-0000-0000-0000000000c0',
      );

  test('upsertMirror adds an account this device has not pulled yet', () async {
    await repo.upsertMirror(tutor());
    final u = await repo.getById('00000000-0000-0000-0000-0000000000f1');
    expect(u, isNotNull);
    expect(u!.email, 'zz.f1@basa.test');
    expect(u.role, UserRole.tutor);
    expect(u.schoolId, 6);
    expect(u.isActive, isTrue);
  });

  test('upsertMirror updates the row in place, keeping rows that point at it', () async {
    await db.insert('login_logs', {
      'user_id': '00000000-0000-0000-0000-0000000000f1',
      'email_attempted': 'zz.f1@basa.test',
      'success': 1,
      'method': 'online',
    });
    await repo.upsertMirror(tutor(name: 'Tutor Renamed', active: false));
    final u = await repo.getById('00000000-0000-0000-0000-0000000000f1');
    expect(u!.fullName, 'Tutor Renamed');
    expect(u.isActive, isFalse);
    final logs = await db.query('login_logs', where: 'user_id = ?', whereArgs: ['00000000-0000-0000-0000-0000000000f1']);
    expect(logs, hasLength(1));
    expect(await db.query('users', where: 'email = ?', whereArgs: ['zz.f1@basa.test']), hasLength(1));
  });
}
