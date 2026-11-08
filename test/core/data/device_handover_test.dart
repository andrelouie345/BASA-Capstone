// Shared device (SyncLocalRepository.handOver, called by the online sign-in):
// the device copy is one user's. Another user signing in gets it cleared,
// or is refused while it holds work not on the server yet (owner decision
// 2026-11-08: no override, the owner uploads first).
import 'dart:io';

import 'package:basa_capstone/core/data/local/aral_class_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/sync_local_repository_sqlite.dart';
import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/offline_owner.dart';

void main() {
  late Database db;
  late SyncLocalRepositorySqlite repo;
  const admin = '00000000-0000-0000-0000-00000000d001';
  const coord = '00000000-0000-0000-0000-00000000d002';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_handover_').path);
    repo = SyncLocalRepositorySqlite(db);
  });

  tearDownAll(LocalDatabase.close);

  /// The admin's pulled copy: two schools with a section each, and the admin
  /// as owner with their offline sign-in.
  Future<void> adminCopy() async {
    for (final t in ['sections', 'schools']) {
      await db.delete(t);
    }
    await seedOfflineOwner(db, userId: admin, email: 'admin@zz', role: 'admin');
    await db.insert('sync_meta', {'key': 'last_pull_at', 'value': '2026-11-01T00:00:00Z'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    for (final (id, code) in [(9401, 'ZZH1'), (9402, 'ZZH2')]) {
      await db.insert('schools', {'id': id, 'school_id': code, 'school_name': 'ZZ $code'});
      await db.insert('sections',
          {'id': id, 'school_id': id, 'school_year': '2026-2027', 'grade_level': '7', 'section_name': 'Rose'});
    }
  }

  Future<int> count(String table) async => (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n'] as int;

  test('the owner signing in again changes nothing', () async {
    await adminCopy();
    final h = await repo.handOver(userId: admin, email: 'admin@zz');
    expect(h.cleared, isFalse);
    expect(h.refused, isFalse);
    expect(await count('sections'), 2);
  });

  test("another user's sign-in clears the copy and takes the device", () async {
    await adminCopy();
    final h = await repo.handOver(userId: coord, email: 'coord@zz');
    expect(h.cleared, isTrue);
    expect(h.previous!.email, isNull, reason: 'the helper stores no owner email');
    expect(h.previous!.userId, admin);
    expect(await count('sections'), 0);
    expect(await count('schools'), 0);
    expect(await count('users'), 0);
    expect(await count('offline_credentials'), 0, reason: "the admin's offline sign-in goes with their copy");
    final owner = (await repo.owner())!;
    expect(owner.userId, coord);
    expect(owner.email, 'coord@zz');
    expect(owner.pulledAt, isNull, reason: 'not pulled yet');
    expect(await count('regions'), greaterThan(0), reason: 'seed data stays');
  });

  test('work not on the server yet refuses the hand-over and keeps everything', () async {
    await adminCopy();
    final made = await AralClassRepositorySqlite(db).insert(AralClass(
        schoolId: 9401, schoolYear: '2026-2027', className: 'ZZ-7A', gradeLevel: 7, program: AralClassProgram.ks3Basic));
    final h = await repo.handOver(userId: coord, email: 'coord@zz');
    expect(h.refused, isTrue);
    expect(h.cleared, isFalse);
    expect(h.unsent.map((l) => l.toString()).join(), contains('ARAL class'));
    expect(await count('sections'), 2);
    expect((await repo.owner())!.userId, admin);
    expect(await count('offline_credentials'), 1);
    await db.delete('aral_classes', where: 'id = ?', whereArgs: [made.id]);
  });

  test('a device never pulled is taken over (nothing unsent)', () async {
    await db.delete('sync_meta', where: "key LIKE 'last_pull_%'");
    final h = await repo.handOver(userId: coord, email: 'coord@zz');
    expect(h.cleared, isTrue);
    expect(h.previous, isNull);
    expect((await repo.owner())!.userId, coord);
  });
}
