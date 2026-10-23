// SQLite v36: aral_enrollments is rebuilt for ARAL classes (cloud
// 20261023040000): tutor_id goes, class_id and the referral columns come in.
// The rebuild must keep every row and column (row_version included: sync),
// the pending-upload lock, and every trigger and view that mentions the
// table. The placement and referral rules hold for rows made on the device.
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

/// aral_enrollments as a v35 device has it.
const _v35Table = '''
    CREATE TABLE aral_enrollments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id INTEGER NOT NULL REFERENCES students(id),
      school_id INTEGER NOT NULL REFERENCES schools(id),
      section_id INTEGER NOT NULL REFERENCES sections(id),
      school_year TEXT NOT NULL,
      key_stage TEXT NOT NULL CHECK (key_stage IN ('foundational', 'ks1', 'ks2', 'ks3')),
      track TEXT CHECK (track IN ('basic', 'plus')),
      tutor_id TEXT REFERENCES users(id),
      status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'exited')),
      entered_on TEXT NOT NULL,
      exited_on TEXT,
      exit_reason TEXT CHECK (exit_reason IN ('grade_level_ready', 'transferred_out', 'dropped_out', 'other',
                                              'classroom_support')),
      basis_source TEXT NOT NULL CHECK (basis_source IN ('crla', 'phil_iri', 'manual')),
      basis_round TEXT,
      basis_level TEXT,
      basis_assessment_id INTEGER,
      suggested_key_stage TEXT,
      suggested_track TEXT,
      suggestion_round TEXT,
      suggestion_level TEXT,
      suggestion_assessment_id INTEGER,
      suggested_on TEXT,
      notes TEXT,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      row_version INTEGER,
      UNIQUE (student_id, school_year)
    )
  ''';

void main() {
  late Database db;
  const year = '2026-2027';
  const tutor = '00000000-0000-0000-0000-0000000094a1';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_v36_').path);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ36', 'school_name': 'ZZ v36'});
    await db.insert('users', {'id': tutor, 'email': 't@zz', 'full_name': 'T', 'role': 'tutor', 'school_id': 1});
    for (final (id, grade) in [(1, '7'), (2, '5')]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': year, 'grade_level': grade, 'section_name': 'S$id'});
    }
    for (var s = 1; s <= 20; s++) {
      await db.insert('students', {'id': s, 'lrn': '9999999940${s.toString().padLeft(2, '0')}', 'last_name': 'L$s', 'first_name': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': s, 'section_id': s == 20 ? 2 : 1, 'school_year': year, 'status': 'active'});
    }
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

  test('a v35 roster is rebuilt for classes; rows, row_version, the pending lock and triggers survive', () async {
    final fresh = await objectsMentioningRoster();
    expect(fresh, isNotEmpty);

    // Turn the table back into its v35 shape, the way a v35 device has it.
    await db.transaction((txn) async {
      for (final name in fresh.keys.where((k) => !k.startsWith('index '))) {
        final parts = name.split(' ');
        await txn.execute('DROP ${parts[0].toUpperCase()} IF EXISTS ${parts[1]}');
      }
      await txn.execute('DROP TABLE aral_enrollments');
      await txn.execute(_v35Table);
    });
    // A pulled row (row_version 3, a tutor) and a new one (negative id) waiting in an upload.
    Future<void> row(int id, int? version) => db.insert('aral_enrollments', {
          'id': id, 'student_id': id.abs(), 'school_id': 1, 'section_id': 1, 'school_year': year,
          'key_stage': 'ks3', 'track': 'basic', 'tutor_id': tutor, 'entered_on': '2026-10-01',
          'basis_source': 'manual', 'origin': id > 0 ? 'cloud' : 'local', 'row_version': version,
          'suggestion_round': 'bosy',
        });
    await row(7, 3);
    await row(-2, null);
    await db.insert('sync_pending', {'table_name': 'aral_enrollments', 'row_key': '-2', 'upload_id': 5});

    await rebuildAralEnrollmentsForV36(db);
    await upgradeCreators();

    expect(await objectsMentioningRoster(), fresh, reason: 'every trigger, view and index is back, unchanged');
    final cols = (await db.rawQuery('PRAGMA table_info(aral_enrollments)')).map((c) => c['name']).toSet();
    expect(cols, isNot(contains('tutor_id')));
    expect(cols, containsAll(['class_id', 'referred_by', 'referral_reason', 'row_version']));
    final rows = await db.query('aral_enrollments', orderBy: 'id');
    expect(rows.map((r) => (r['id'], r['row_version'], r['class_id'], r['suggestion_round'])).toList(),
        [(-2, null, null, 'bosy'), (7, 3, null, 'bosy')]);
    await expectLater(db.update('aral_enrollments', {'notes': 'x'}, where: 'id = -2'),
        throwsA(predicate((e) => '$e'.contains(pendingLockMessage))));
    // class_id is a declared reference (followLocalIds and the pull orphan check use it).
    final fks = await db.rawQuery('PRAGMA foreign_key_list(aral_enrollments)');
    expect(fks.any((f) => f['from'] == 'class_id' && f['table'] == 'aral_classes'), isTrue);
    await db.delete('sync_pending');
  }, timeout: const Timeout(Duration(minutes: 3))); // the creators run twice

  test('the rebuild does nothing when the table already takes classes', () async {
    final before = await objectsMentioningRoster();
    await rebuildAralEnrollmentsForV36(db);
    expect(await objectsMentioningRoster(), before);
  });

  group('placement and referral (rows made on this device)', () {
    late int rose;
    setUpAll(() async {
      await db.delete('aral_enrollments');
      rose = -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));
      await db.insert('aral_classes', {'id': rose, 'school_id': 1, 'school_year': year, 'class_name': '7-Rose',
          'program': 'ks3_basic', 'grade_band': '7-10', 'tutor_id': tutor});
    });

    Future<int> enrol(int student, {String ks = 'ks3', String? track = 'basic', int section = 1, int? classId,
        String basis = 'manual', String? by, String? reason}) async {
      final id = -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));
      await db.insert('aral_enrollments', {
        'id': id, 'student_id': student, 'school_id': 1, 'section_id': section, 'school_year': year,
        'key_stage': ks, 'track': track, 'entered_on': '2026-10-01', 'basis_source': basis,
        'referred_by': by, 'referral_reason': reason, 'class_id': classId,
      });
      return id;
    }

    Matcher refusedWith(String text) => throwsA(predicate((e) => '$e'.contains(text), text));

    test('15 active per class; the 16th is refused, also by reactivation', () async {
      final ids = [for (var s = 1; s <= 15; s++) await enrol(s, classId: rose)];
      await expectLater(enrol(16, classId: rose), refusedWith('An ARAL class has at most 15 active learners'));
      final sixteen = await enrol(16);
      await expectLater(db.update('aral_enrollments', {'class_id': rose}, where: 'id = ?', whereArgs: [sixteen]),
          refusedWith('An ARAL class has at most 15 active learners'));
      await db.update('aral_enrollments', {'status': 'exited', 'exited_on': '2026-10-20', 'exit_reason': 'other'},
          where: 'id = ?', whereArgs: [ids.first]);
      await db.update('aral_enrollments', {'class_id': rose}, where: 'id = ?', whereArgs: [sixteen]);
      await expectLater(
          db.update('aral_enrollments', {'status': 'active', 'exited_on': null, 'exit_reason': null},
              where: 'id = ?', whereArgs: [ids.first]),
          refusedWith('An ARAL class has at most 15 active learners'));
      // The others still save notes in a full class.
      await db.update('aral_enrollments', {'notes': 'n'}, where: 'id = ?', whereArgs: [ids[1]]);
    });

    test('program and band must match', () async {
      await expectLater(enrol(17, ks: 'ks2', classId: rose), refusedWith("The learner's program does not match the ARAL class"));
      await expectLater(enrol(20, section: 2, classId: rose),
          refusedWith("The learner's grade is outside the ARAL class's grade band"));
      // A program change that keeps the class is not re-checked (decision 7).
      final placed = (await db.query('aral_enrollments', where: "class_id = ? AND status = 'active'", whereArgs: [rose])).first['id'];
      await db.update('aral_enrollments', {'key_stage': 'ks2', 'track': 'plus'}, where: 'id = ?', whereArgs: [placed]);
    });

    test('a class of another school or year is refused', () async {
      final next = -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));
      await db.insert('aral_classes', {'id': next, 'school_id': 1, 'school_year': '2027-2028', 'class_name': '7-Rose',
          'program': 'ks3_basic', 'grade_band': '7-10'});
      await expectLater(enrol(18, classId: next), refusedWith('The ARAL class belongs to another school or school year'));
    });

    test('a referral needs who and why, and only then', () async {
      await expectLater(enrol(19, basis: 'referral', reason: 'slow'), throwsA(isA<DatabaseException>()));
      await expectLater(enrol(19, by: 'Ms. Cruz', reason: 'slow'), throwsA(isA<DatabaseException>()));
      final id = await enrol(19, basis: 'referral', by: 'Ms. Cruz', reason: 'reads slowly');
      await expectLater(db.update('aral_enrollments', {'referral_reason': 'x'}, where: 'id = ?', whereArgs: [id]),
          refusedWith('only the placement, class, status and notes change'));
    });

    test('a class with learners keeps its program and band; an empty one may change', () async {
      await expectLater(db.update('aral_classes', {'program': 'ks3_plus'}, where: 'id = ?', whereArgs: [rose]),
          refusedWith('An ARAL class with learners keeps its program and grade band'));
      final empty = -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));
      await db.insert('aral_classes', {'id': empty, 'school_id': 1, 'school_year': year, 'class_name': 'Empty',
          'program': 'ks1', 'grade_band': '1-3'});
      await db.update('aral_classes', {'program': 'ks2_basic', 'grade_band': '4-6'}, where: 'id = ?', whereArgs: [empty]);
    });
  });
}
