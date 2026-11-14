// v45 (same-server transfer, spec docs/superpowers/specs/2026-11-12-sf1-leavers-design.md
// D15; cloud 20261113020000): enrollment_moves gets source 'transfer_in' and
// the other school's side (from_school_id, from_school_name,
// from_section_name, from_status, from_left_on) with the cloud's rule. A
// real v44 device database is upgraded (its rows kept), and
// mirrorLeaverResult copies a transfer's result onto the receiving school's
// device; the learner history names the other school from the snapshot.
import 'dart:io';

import 'package:basa_capstone/core/data/local/learner_history_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/learner_leaver_local_writes.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/models/enrollment_move.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _year = '2026-2027';

void main() {
  late Database db;
  final dir = Directory.systemTemp.createTempSync('basa_v45_').path;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    // School B's device: its school and section; the learner arrives by the transfer.
    await db.insert('schools', {'id': 2, 'school_id': 'ZZ45B', 'school_name': 'ZZ v45 B'});
    for (final (id, name) in [(71, 'G7-B1'), (72, 'G7-B2')]) {
      await db.insert('sections', {'id': id, 'school_id': 2, 'school_year': _year, 'grade_level': '7', 'section_name': name});
    }
    await db.insert('students', {'id': 4501, 'lrn': '999999004501', 'last_name': 'Fixture4501', 'first_name': 'Zed', 'school_id': 2});
    await db.insert('enrollments', {'id': 4501, 'student_id': 4501, 'section_id': 72, 'school_year': _year});
  });

  tearDownAll(LocalDatabase.close);

  Future<List<String>> columns(String t) async =>
      [for (final c in await db.rawQuery('PRAGMA table_info($t)')) c['name'] as String];

  test('a v44 device database is upgraded: rows kept, transfer columns and source added', () async {
    // Put enrollment_moves back in its v44 shape with one move, stamp v44, reopen.
    await db.execute('DROP TABLE enrollment_moves');
    await db.execute('''
      CREATE TABLE enrollment_moves (
        id INTEGER PRIMARY KEY,
        enrollment_id INTEGER NOT NULL REFERENCES enrollments(id),
        student_id INTEGER NOT NULL REFERENCES students(id),
        school_id INTEGER NOT NULL REFERENCES schools(id),
        school_year TEXT NOT NULL,
        from_section_id INTEGER NOT NULL REFERENCES sections(id),
        to_section_id INTEGER NOT NULL REFERENCES sections(id),
        moved_on TEXT NOT NULL,
        moved_by TEXT REFERENCES users(id),
        source TEXT NOT NULL CHECK (source IN ('sf1_missing', 'sf1_incoming', 'return'))
      )
    ''');
    await db.insert('enrollment_moves', {'id': 1, 'enrollment_id': 4501, 'student_id': 4501, 'school_id': 2,
        'school_year': _year, 'from_section_id': 71, 'to_section_id': 72, 'moved_on': '2026-10-01', 'source': 'sf1_missing'});
    await expectLater(
        db.insert('enrollment_moves', {'id': 2, 'enrollment_id': 4501, 'student_id': 4501, 'school_id': 2,
            'school_year': _year, 'from_section_id': 71, 'to_section_id': 72, 'moved_on': '2026-10-02', 'source': 'transfer_in'}),
        throwsA(isA<DatabaseException>()));
    await db.execute('PRAGMA user_version = 44');
    await LocalDatabase.close();
    db = await LocalDatabase.instance(dir);

    expect((await db.rawQuery('PRAGMA user_version')).single.values.single, 45);
    expect(await columns('enrollment_moves'),
        containsAll(['from_school_id', 'from_school_name', 'from_section_name', 'from_status', 'from_left_on']));
    final kept = await db.query('enrollment_moves');
    expect(kept.single['source'], 'sf1_missing');
    expect(kept.single['from_section_id'], 71);
    expect(await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'enrollment_moves_student'"),
        hasLength(1));
  });

  test('the transfer rule: from_* exactly on a transfer row, known statuses only', () async {
    Map<String, Object?> row(int id, String source, {bool from = true, String status = 'transferred_out'}) => {
          'id': id, 'enrollment_id': 4501, 'student_id': 4501, 'school_id': 2, 'school_year': _year,
          'from_section_id': 99, 'to_section_id': 72, 'moved_on': '2026-11-13', 'source': source,
          if (from) ...{'from_school_id': 1, 'from_status': status, 'from_left_on': '2026-11-10'},
        };
    await expectLater(db.insert('enrollment_moves', row(10, 'transfer_in', from: false)), throwsA(isA<DatabaseException>()));
    await expectLater(db.insert('enrollment_moves', row(11, 'sf1_missing')), throwsA(isA<DatabaseException>()));
    await expectLater(db.insert('enrollment_moves', row(12, 'transfer_in', status: 'gone')), throwsA(isA<DatabaseException>()));
    await db.insert('enrollment_moves', row(13, 'transfer_in'));
    await db.delete('enrollment_moves', where: 'id = 13');
  });

  test("a transfer's result is copied onto the receiving device; the history names the other school", () async {
    await mirrorLeaverResult(db, {
      'enrollment': {'id': 4502, 'student_id': 4502, 'section_id': 71, 'school_year': _year, 'status': 'active',
          'left_on': null, 'left_by': null, 'left_note': null},
      'student': {'id': 4502, 'lrn': '999999004502', 'last_name': 'Moved4502', 'first_name': 'Ann', 'school_id': 2},
      'move': {'id': 20, 'enrollment_id': 4502, 'student_id': 4502, 'school_id': 2, 'school_year': _year,
          'from_section_id': 901, 'to_section_id': 71, 'moved_on': '2026-11-13', 'moved_by': null,
          'source': 'transfer_in', 'from_school_id': 1, 'from_school_name': 'ZZ v45 A', 'from_section_name': 'G7-A1',
          'from_status': 'transferred_out', 'from_left_on': '2026-11-10'},
      'from_school': {'id': 1, 'name': 'ZZ v45 A'},
      'from_section': {'id': 901, 'name': 'G7-A1'},
      'exited_aral_enrollment_id': null,
    });
    expect((await db.query('enrollments', where: 'id = 4502')).single['section_id'], 71);
    expect((await db.query('students', where: 'id = 4502')).single['last_name'], 'Moved4502');

    final moves = await LearnerHistoryRepositorySqlite(db).moves(4502);
    final m = moves.single;
    expect(m.move.source, EnrollmentMoveSource.transferIn);
    expect(m.fromSectionName, isNull); // school A's section is not on this device
    expect(m.toSectionName, 'G7-B1');
    expect(m.move.fromSectionName, 'G7-A1');
    expect(m.move.fromSchoolName, 'ZZ v45 A');
    expect(m.move.fromStatus, 'transferred_out');
    expect(m.move.fromLeftOn, '2026-11-10');
    expect(m.move.toMap()['from_school_id'], 1);
    // Nothing was journaled for upload (server rows).
    expect(await db.query('sync_changes'), isEmpty);
  });
}
