// SQLite v35: aral_enrollments is rebuilt so its exit_reason CHECK accepts
// 'classroom_support' (DepEd Memorandum 064, KS1 rules; cloud 20261023030000).
// The rebuild must keep every row and column (row_version included: sync) and
// every trigger and view that mentions the table must come back.
import 'dart:io';

import 'package:basa_capstone/core/data/local/aral_local_schema.dart';
import 'package:basa_capstone/core/data/local/calendar_local_schema.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/phil_iri_local_schema.dart';
import 'package:basa_capstone/core/data/local/report_local_schema.dart';
import 'package:basa_capstone/core/data/local/srp_local_schema.dart';
import 'package:basa_capstone/core/data/local/sync_local_schema.dart';
import 'package:basa_capstone/core/data/local/tutor_assignment_local_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  const year = '2026-2027';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_v35_').path);
  });

  tearDownAll(LocalDatabase.close);

  Future<Map<String, String>> objectsMentioningRoster() async => {
        for (final r in await db.rawQuery(
            "SELECT type, name, sql FROM sqlite_master WHERE type IN ('trigger', 'view', 'index') "
            "AND sql LIKE '%aral_enrollments%'"))
          '${r['type']} ${r['name']}': r['sql'] as String,
      };

  /// What onUpgrade runs after the rebuild.
  Future<void> upgradeCreators() async {
    await createPhilIriLocalSchema(db);
    await createAralLocalSchema(db);
    await createSrpLocalSchema(db);
    await createCalendarLocalSchema(db);
    await createReportLocalSchema(db);
    await createTutorAssignmentLocalSchema(db);
    await createSyncLocalSchema(db);
  }

  test('a v34 roster table is rebuilt with the new exit reason; rows, row_version and triggers survive', () async {
    final fresh = await objectsMentioningRoster();
    expect(fresh, isNotEmpty);

    // Turn the table back into its v34 shape (old CHECK), the way a v34 device has it.
    final v35Sql = (await db.rawQuery("SELECT sql FROM sqlite_master WHERE name = 'aral_enrollments'")).single['sql']
        as String;
    expect(v35Sql, contains("'classroom_support'"));
    await db.transaction((txn) async {
      for (final name in fresh.keys.where((k) => !k.startsWith('index '))) {
        final parts = name.split(' ');
        await txn.execute('DROP ${parts[0].toUpperCase()} IF EXISTS ${parts[1]}');
      }
      await txn.execute(v35Sql
          .replaceFirst('aral_enrollments', 'aral_enrollments_old')
          .replaceFirst(RegExp(r",\s*'classroom_support'"), ''));
      await txn.execute('DROP TABLE aral_enrollments');
      await txn.execute('ALTER TABLE aral_enrollments_old RENAME TO aral_enrollments');
    });
    await upgradeCreators();
    expect((await db.rawQuery("SELECT sql FROM sqlite_master WHERE name = 'aral_enrollments'")).single['sql'],
        isNot(contains('classroom_support')));

    // A pulled row (row_version 3) and a new one (negative id, row_version NULL).
    Future<void> row(int id, int? version) => db.insert('aral_enrollments', {
          'id': id, 'student_id': 100 + id.abs(), 'school_id': 1, 'section_id': 1, 'school_year': year,
          'key_stage': 'ks1', 'entered_on': '2026-10-01', 'basis_source': 'manual', 'origin': 'cloud',
          'row_version': version, 'suggestion_round': 'bosy',
        });
    await row(7, 3);
    await row(-2, null);
    await expectLater(
        db.update('aral_enrollments', {'status': 'exited', 'exited_on': '2026-10-23', 'exit_reason': 'classroom_support'},
            where: 'id = -2'),
        throwsA(isA<DatabaseException>()));

    await rebuildAralEnrollmentsForV35(db);
    await upgradeCreators();

    expect(await objectsMentioningRoster(), fresh, reason: 'every trigger, view and index is back, unchanged');
    final rows = await db.query('aral_enrollments', orderBy: 'id');
    expect(rows.map((r) => (r['id'], r['row_version'], r['suggestion_round'])).toList(),
        [(-2, null, 'bosy'), (7, 3, 'bosy')]);
    await db.update('aral_enrollments', {'status': 'exited', 'exited_on': '2026-10-23', 'exit_reason': 'classroom_support'},
        where: 'id = -2');
    await expectLater(db.update('aral_enrollments', {'exit_reason': 'graduated'}, where: 'id = -2'),
        throwsA(isA<DatabaseException>()));
  }, timeout: const Timeout(Duration(minutes: 3))); // the creators run twice

  test('the rebuild does nothing when the table already accepts the new reason', () async {
    final before = await objectsMentioningRoster();
    await rebuildAralEnrollmentsForV35(db);
    expect(await objectsMentioningRoster(), before);
  });
}
