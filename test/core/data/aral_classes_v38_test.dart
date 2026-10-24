// SQLite v38: ARAL classes get a home grade and may mix programs (cloud
// 20261024010000). aral_classes is rebuilt without grade_band, with
// grade_level (the lowest grade of the old band) and an optional program.
// Rows, ids, row_version, the pending-upload lock and every trigger that
// mentions the table (roster placement, sessions, sync) survive.
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

/// aral_classes as a v37 device has it.
const _v37Classes = '''
    CREATE TABLE aral_classes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      school_id INTEGER NOT NULL REFERENCES schools(id),
      school_year TEXT NOT NULL,
      class_name TEXT NOT NULL CHECK (length(trim(class_name)) > 0),
      program TEXT NOT NULL
        CHECK (program IN ('foundational', 'ks1', 'ks2_basic', 'ks2_plus', 'ks3_basic', 'ks3_plus')),
      grade_band TEXT NOT NULL CHECK (grade_band IN ('1-3', '4-6', '7-10')),
      tutor_id TEXT REFERENCES users(id),
      room TEXT,
      schedule TEXT,
      notes TEXT,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      row_version INTEGER
    )
  ''';

void main() {
  late Database db;
  const year = '2026-2027';
  const tutor = '00000000-0000-0000-0000-0000000098a1';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_v38_').path);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ38', 'school_name': 'ZZ v38'});
    await db.insert('users', {'id': tutor, 'email': 't@zz38', 'full_name': 'T', 'role': 'tutor', 'school_id': 1});
  });

  tearDownAll(LocalDatabase.close);

  Future<Map<String, String>> objectsMentioningClasses() async => {
        for (final r in await db.rawQuery(
            "SELECT type, name, sql FROM sqlite_master WHERE type IN ('trigger', 'view', 'index') "
            "AND sql LIKE '%aral_classes%'"))
          '${r['type']} ${r['name']}': r['sql'] as String,
      };

  /// What onUpgrade runs after the v38 step.
  Future<void> upgradeCreators() async {
    await createPhilIriLocalSchema(db);
    await createAralLocalSchema(db);
    await createSrpLocalSchema(db);
    await createCalendarLocalSchema(db);
    await createReportLocalSchema(db);
    await createTutorAssignmentLocalSchema(db);
    await createSyncLocalSchema(db);
  }

  test('v37 classes get grade_level from their band; ids, row_version, the pending lock and triggers survive', () async {
    final fresh = await objectsMentioningClasses();
    expect(fresh.keys, containsAll(['trigger check_aral_class_upd', 'trigger check_aral_enrollment_ins']));

    // Turn the table back into its v37 shape.
    await db.transaction((txn) async {
      for (final name in fresh.keys.where((k) => !k.startsWith('index '))) {
        final parts = name.split(' ');
        await txn.execute('DROP ${parts[0].toUpperCase()} IF EXISTS ${parts[1]}');
      }
      await txn.execute('DROP TABLE aral_classes');
      await txn.execute(_v37Classes);
    });
    // A pulled class (row_version 3, band 7-10) and a new one (4-6) waiting in an upload.
    for (final (id, version, band, origin) in [(12, 3, '7-10', 'cloud'), (-4, null, '4-6', 'local')]) {
      await db.insert('aral_classes', {
        'id': id, 'school_id': 1, 'school_year': year, 'class_name': 'C$id', 'program': 'ks2_basic',
        'grade_band': band, 'tutor_id': tutor, 'origin': origin, 'row_version': version,
      });
    }
    await db.insert('sync_pending', {'table_name': 'aral_classes', 'row_key': '-4', 'upload_id': 5});

    await rebuildAralClassesForV38(db);
    await upgradeCreators();

    expect(await objectsMentioningClasses(), fresh, reason: 'every trigger and index is back, unchanged');
    final cols = (await db.rawQuery('PRAGMA table_info(aral_classes)')).map((c) => c['name']).toSet();
    expect(cols, isNot(contains('grade_band')));
    expect(cols, containsAll(['grade_level', 'program', 'row_version']));
    final rows = await db.query('aral_classes', orderBy: 'id');
    expect(rows.map((r) => (r['id'], r['row_version'], r['grade_level'], r['program'], r['tutor_id'])).toList(),
        [(-4, null, 4, 'ks2_basic', tutor), (12, 3, 7, 'ks2_basic', tutor)]);
    await expectLater(db.update('aral_classes', {'notes': 'x'}, where: 'id = -4'),
        throwsA(predicate((e) => '$e'.contains(pendingLockMessage))));
    // The roster still points at the class (followLocalIds, the pull orphan check).
    final fks = await db.rawQuery('PRAGMA foreign_key_list(aral_enrollments)');
    expect(fks.any((f) => f['from'] == 'class_id' && f['table'] == 'aral_classes'), isTrue);
    await db.delete('sync_pending');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the v38 step does nothing the second time', () async {
    final before = await objectsMentioningClasses();
    await rebuildAralClassesForV38(db);
    expect(await objectsMentioningClasses(), before);
  });

  test('device trigger: mixed takes any program, one program refuses another, no grade check', () async {
    Future<int> localId() async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));
    for (final (id, grade) in [(1, '7'), (2, '9')]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': year, 'grade_level': grade, 'section_name': 'S$id'});
    }
    final mixed = await localId(), one = await localId();
    await db.insert('aral_classes', {'id': mixed, 'school_id': 1, 'school_year': year, 'class_name': 'Mixed', 'grade_level': 7});
    await db.insert('aral_classes',
        {'id': one, 'school_id': 1, 'school_year': year, 'class_name': 'One', 'grade_level': 7, 'program': 'ks1'});
    Future<void> enrol(int student, int section, String ks, String? track, int classId) async {
      await db.insert('students', {'id': student, 'lrn': '9999999980${student.toString().padLeft(2, '0')}',
          'last_name': 'L$student', 'first_name': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': student, 'section_id': section, 'school_year': year, 'status': 'active'});
      await db.insert('aral_enrollments', {
        'id': await localId(), 'student_id': student, 'school_id': 1, 'section_id': section, 'school_year': year,
        'key_stage': ks, 'track': track, 'entered_on': '2026-10-01', 'basis_source': 'manual', 'class_id': classId,
      });
    }
    await enrol(1, 1, 'ks1', null, mixed);
    await enrol(2, 1, 'ks2', 'basic', mixed);
    await enrol(3, 2, 'ks3', 'plus', mixed); // Grade 9 in a Grade 7 class: the ViewModel asks, not the trigger
    await enrol(4, 2, 'ks1', null, one);
    await expectLater(enrol(5, 1, 'ks2', 'plus', one),
        throwsA(predicate((e) => '$e'.contains("The learner's program does not match the ARAL class"))));
  });
}
