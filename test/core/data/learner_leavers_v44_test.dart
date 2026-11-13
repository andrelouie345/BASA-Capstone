// v44 (SF1 leavers, spec docs/superpowers/specs/2026-11-12-sf1-leavers-design.md;
// cloud 20261112010000 + 20261112020000): enrollment statuses with their
// archive columns, students.anonymized_at, the enrollment_moves mirror, and
// mirrorLeaverResult copying a server move onto the device (finalized
// Phil-IRI session included) without journaling it.
import 'dart:io';

import 'package:basa_capstone/core/data/local/learner_leaver_local_writes.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/pull_tables.dart';
import 'package:basa_capstone/core/models/enrollment.dart';
import 'package:basa_capstone/core/models/enrollment_move.dart';
import 'package:basa_capstone/core/models/student.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _year = '2026-2027';
const _coord = '00000000-0000-0000-0000-00000000c044';

void main() {
  late Database db;
  final dir = Directory.systemTemp.createTempSync('basa_v44_').path;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ44', 'school_name': 'ZZ v44'});
    for (final (id, grade, name) in [(31, '3', 'G3-A'), (32, '3', 'G3-B'), (71, '7', 'G7-A'), (72, '7', 'G7-B')]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': _year, 'grade_level': grade, 'section_name': name});
    }
    // Fixture learners: CRLA (Grade 3) and Phil-IRI (Grade 7).
    for (final (id, section) in [(4401, 31), (4402, 71), (4403, 71)]) {
      await db.insert('students', {'id': id, 'lrn': '9999990$id', 'last_name': 'Fixture$id', 'first_name': 'Zed', 'school_id': 1});
      await db.insert('enrollments', {'id': id, 'student_id': id, 'section_id': section, 'school_year': _year});
    }
  });

  tearDownAll(LocalDatabase.close);

  Future<List<String>> columns(String t) async =>
      [for (final c in await db.rawQuery('PRAGMA table_info($t)')) c['name'] as String];
  Future<int> count(String sql, [List<Object?> args = const []]) async =>
      (await db.rawQuery(sql, args)).first.values.first as int;

  /// Server rows put on the device as a pull would (under the bypass).
  Future<void> serverRow(String table, Map<String, Object?> row) async =>
      db.transaction((txn) async {
        await txn.insert('sync_meta', {'key': 'sync_bypass', 'value': '1'});
        await txn.insert(table, row);
        await txn.delete('sync_meta', where: "key = 'sync_bypass'");
      });

  test('the local database is v44 with the leaver columns and table', () async {
    expect((await db.rawQuery('PRAGMA user_version')).single.values.single, 44);
    expect(await columns('enrollments'), containsAll(['left_on', 'left_by', 'left_note']));
    expect(await columns('students'), contains('anonymized_at'));
    expect(await columns('enrollment_moves'), containsAll([
      'id', 'enrollment_id', 'student_id', 'school_id', 'school_year', 'from_section_id', 'to_section_id',
      'moved_on', 'moved_by', 'source',
    ]));
  });

  test('enrollment_moves is pulled after enrollments, cleared before them, never synced', () {
    final order = pullOrder.keys.toList();
    expect(order.indexOf('enrollment_moves'), order.indexOf('enrollments') + 1);
    expect(pullClearOrder.indexOf('enrollment_moves'), lessThan(pullClearOrder.indexOf('enrollments')));
    expect(syncedTables.containsKey('enrollment_moves'), isFalse);
  });

  test('the status rule refuses other statuses and half-archived rows', () async {
    await expectLater(
        db.insert('enrollments', {'student_id': 4499, 'section_id': 31, 'school_year': _year, 'status': 'moved'}),
        throwsA(isA<DatabaseException>().having((e) => '$e', 'message', contains('active, transferred_out or dropped_out'))));
    await expectLater(db.update('enrollments', {'status': 'moved'}, where: 'id = 4401'),
        throwsA(isA<DatabaseException>().having((e) => '$e', 'message', contains('active, transferred_out or dropped_out'))));
    await expectLater(db.update('enrollments', {'status': 'dropped_out'}, where: 'id = 4401'),
        throwsA(isA<DatabaseException>().having((e) => '$e', 'message', contains('has left_on and left_by'))));
    await expectLater(db.update('enrollments', {'left_note': 'note'}, where: 'id = 4401'),
        throwsA(isA<DatabaseException>().having((e) => '$e', 'message', contains('Only an archived enrollment'))));
  });

  test('models map the new columns', () {
    final e = Enrollment.fromMap({
      'id': 1, 'student_id': 2, 'section_id': 3, 'school_year': _year, 'status': 'transferred_out',
      'left_on': '2026-11-12', 'left_by': _coord, 'left_note': 'n',
    });
    expect(e.status, EnrollmentStatus.transferredOut);
    expect(e.status.isArchived, isTrue);
    expect(e.toMap()['status'], 'transferred_out');
    expect(EnrollmentStatus.fromValue('dropped_out'), EnrollmentStatus.droppedOut);
    expect(() => EnrollmentStatus.fromValue('moved'), throwsArgumentError);

    final m = EnrollmentMove.fromMap({
      'id': 9, 'enrollment_id': 1, 'student_id': 2, 'school_id': 1, 'school_year': _year, 'from_section_id': 3,
      'to_section_id': 4, 'moved_on': '2026-11-12', 'moved_by': _coord, 'source': 'return',
    });
    expect(m.source, EnrollmentMoveSource.returned);
    expect(m.toMap()['source'], 'return');

    final s = Student.fromMap({'id': 5, 'lrn': 'ANON-5', 'last_name': 'Anonymized', 'first_name': '—',
        'anonymized_at': '2027-08-01T00:00:00Z'});
    expect(s.isAnonymized, isTrue);
    expect(s.toMap()['anonymized_at'], '2027-08-01T00:00:00Z');
    expect(Student(lrn: '1', lastName: 'L', firstName: 'F').toMap().containsKey('anonymized_at'), isFalse);
  });

  group('mirrorLeaverResult', () {
    test('a CRLA move renumbers the attempt that collides in the new section', () async {
      // Learner 4401: attempt 1 in G3-A; an attempt 1 of theirs already in G3-B.
      await serverRow('crla_assessments', {
        'id': 501, 'student_id': 4401, 'school_id': 1, 'section_id': 32, 'school_year': _year,
        'subject_variant': 'mt', 'language': 'Cebuano', 'attempt_no': 1, 'assessed_at': '2026-07-01',
        'origin': 'cloud', 'row_version': 1,
      });
      await serverRow('crla_assessments', {
        'id': 502, 'student_id': 4401, 'school_id': 1, 'section_id': 31, 'school_year': _year,
        'subject_variant': 'mt', 'language': 'Cebuano', 'attempt_no': 1, 'assessed_at': '2026-09-01',
        'origin': 'cloud', 'row_version': 1,
      });
      await mirrorLeaverResult(db, {
        'enrollment': {'id': 4401, 'student_id': 4401, 'section_id': 32, 'school_year': _year, 'status': 'active',
            'left_on': null, 'left_by': null, 'left_note': null, 'created_at': '2026-06-01T00:00:00Z'},
        'moved': {
          'crla_assessments': [{'id': 502, 'section_id': 32, 'attempt_no': 2}],
          'phil_iri_assessments': <int>[],
          'phil_iri_gst_results': <int>[],
        },
        'aral_enrollment': null,
        'move': {'id': 801, 'enrollment_id': 4401, 'student_id': 4401, 'school_id': 1, 'school_year': _year,
            'from_section_id': 31, 'to_section_id': 32, 'moved_on': '2026-11-12', 'moved_by': _coord,
            'source': 'sf1_missing'},
      });
      final crla = await db.query('crla_assessments', where: 'id = 502');
      expect(crla.single['section_id'], 32);
      expect(crla.single['attempt_no'], 2);
      expect(crla.single['row_version'], 2, reason: 'the server bumped it with the move');
      expect((await db.query('enrollments', where: 'id = 4401')).single['section_id'], 32);
      final move = EnrollmentMove.fromMap((await db.query('enrollment_moves', where: 'id = 801')).single);
      expect(move.source, EnrollmentMoveSource.sf1Missing);
      expect(await count('SELECT COUNT(*) FROM sync_changes'), 0);
      expect(await count("SELECT COUNT(*) FROM sync_meta WHERE key = 'sync_bypass'"), 0);
    });

    test('a Phil-IRI move re-points a finalized session, the GST and the ARAL entry', () async {
      // A finalized session made on this device and already on the server
      // (origin local, so the lifecycle trigger watches it).
      await serverRow('phil_iri_assessments', {
        'id': 601, 'student_id': 4402, 'school_id': 1, 'section_id': 71, 'school_year': _year, 'attempt_no': 1,
        'round': 'bosy', 'status': 'finalized', 'assessed_at': '2026-07-01', 'completed_at': '2026-07-01',
        'finalized_at': '2026-07-02', 'thresholds_snapshot': '{}', 'origin': 'cloud', 'row_version': 2,
      });
      // A local session can't be inserted finalized; make it local afterwards.
      await db.transaction((txn) async {
        await txn.insert('sync_meta', {'key': 'sync_bypass', 'value': '1'});
        await txn.update('phil_iri_assessments', {'origin': 'local'}, where: 'id = 601');
        await txn.delete('sync_meta', where: "key = 'sync_bypass'");
      });
      await serverRow('phil_iri_gst_results', {
        'id': 602, 'student_id': 4402, 'school_id': 1, 'section_id': 71, 'school_year': _year, 'attempt_no': 1,
        'max_score': 40, 'total_score': 20, 'taken_at': '2026-07-01', 'origin': 'cloud', 'row_version': 1,
      });
      await serverRow('aral_enrollments', {
        'id': 603, 'student_id': 4402, 'school_id': 1, 'section_id': 71, 'school_year': _year, 'key_stage': 'ks3',
        'track': 'basic', 'entered_on': '2026-07-10', 'basis_source': 'manual', 'origin': 'cloud', 'row_version': 1,
      });
      await mirrorLeaverResult(db, {
        'enrollment': {'id': 4402, 'student_id': 4402, 'section_id': 72, 'school_year': _year, 'status': 'active',
            'left_on': null, 'left_by': null, 'left_note': null},
        'moved': {
          'crla_assessments': <Object>[],
          'phil_iri_assessments': [601],
          'phil_iri_gst_results': [602],
        },
        'aral_enrollment': {'id': 603, 'student_id': 4402, 'school_id': 1, 'section_id': 72, 'school_year': _year,
            'key_stage': 'ks3', 'track': 'basic', 'status': 'active', 'entered_on': '2026-07-10',
            'basis_source': 'manual', 'row_version': 2, 'tutor_note_from_server_only': 'x'},
        'move': {'id': 802, 'enrollment_id': 4402, 'student_id': 4402, 'school_id': 1, 'school_year': _year,
            'from_section_id': 71, 'to_section_id': 72, 'moved_on': '2026-11-12', 'moved_by': _coord,
            'source': 'sf1_incoming'},
      });
      final session = (await db.query('phil_iri_assessments', where: 'id = 601')).single;
      expect(session['section_id'], 72);
      expect(session['status'], 'finalized');
      expect(session['row_version'], 3);
      final gst = (await db.query('phil_iri_gst_results', where: 'id = 602')).single;
      expect(gst['section_id'], 72);
      expect(gst['row_version'], 2);
      final aral = (await db.query('aral_enrollments', where: 'id = 603')).single;
      expect(aral['section_id'], 72);
      expect(aral['row_version'], 2);
      expect(aral['origin'], 'cloud');
      expect(await count('SELECT COUNT(*) FROM sync_changes'), 0);
      expect(await count("SELECT COUNT(*) FROM sync_meta WHERE key = 'sync_bypass'"), 0);
    });

    Map<String, Object?> crlaRow(int id, int student, int section, int attempt, String date) => {
          'id': id, 'student_id': student, 'school_id': 1, 'section_id': section, 'school_year': _year,
          'subject_variant': 'mt', 'language': 'Cebuano', 'attempt_no': attempt, 'assessed_at': date,
          'origin': 'cloud', 'row_version': 1,
        };
    Map<String, Object?> moveResult(int student, int from, int to, List<(int, int)> crla, int moveId) => {
          'enrollment': {'id': student, 'student_id': student, 'section_id': to, 'school_year': _year,
              'status': 'active', 'left_on': null, 'left_by': null, 'left_note': null},
          'moved': {
            'crla_assessments': [for (final (id, n) in crla) {'id': id, 'section_id': to, 'attempt_no': n}],
            'phil_iri_assessments': <int>[],
            'phil_iri_gst_results': <int>[],
          },
          'aral_enrollment': null,
          'move': {'id': moveId, 'enrollment_id': student, 'student_id': student, 'school_id': 1,
              'school_year': _year, 'from_section_id': from, 'to_section_id': to, 'moved_on': '2026-11-12',
              'moved_by': _coord, 'source': 'sf1_missing'},
        };
    Future<List<(int, int, int)>> crlaOf(int student) async => [
          for (final r in await db.query('crla_assessments',
              where: 'student_id = ?', whereArgs: [student], orderBy: 'assessed_at, id'))
            (r['id'] as int, r['section_id'] as int, r['attempt_no'] as int),
        ];

    test('X -> Y -> X keeps the attempt order and never hits the unique key (Review Focus 1)', () async {
      // Learner 4404: attempts a#1, b#2 in G3-A (31), y#1 in G3-B (32).
      await db.insert('students', {'id': 4404, 'lrn': '999999044040', 'last_name': 'Fixture4404', 'first_name': 'Zed', 'school_id': 1});
      await db.insert('enrollments', {'id': 4404, 'student_id': 4404, 'section_id': 31, 'school_year': _year});
      await serverRow('crla_assessments', crlaRow(511, 4404, 32, 1, '2026-07-01')); // y
      await serverRow('crla_assessments', crlaRow(512, 4404, 31, 1, '2026-08-01')); // a
      await serverRow('crla_assessments', crlaRow(513, 4404, 31, 2, '2026-09-01')); // b
      // X -> Y: a and b go after y (2, 3).
      await mirrorLeaverResult(db, moveResult(4404, 31, 32, [(512, 2), (513, 3)], 811));
      expect(await crlaOf(4404), [(511, 32, 1), (512, 32, 2), (513, 32, 3)]);
      // Y -> X: X is empty, every attempt keeps its number.
      await mirrorLeaverResult(db, moveResult(4404, 32, 31, [(511, 1), (512, 2), (513, 3)], 812));
      expect(await crlaOf(4404), [(511, 31, 1), (512, 31, 2), (513, 31, 3)]);
      expect(await count('SELECT COUNT(*) FROM enrollment_moves WHERE student_id = 4404'), 2);
    });

    test('a stale device copy: final numbers held by other moved rows are parked first', () async {
      // Server (after another admin moved Y -> X, not pulled here): c X#2,
      // d X#3, e X#1. This device still has c Y#1, d Y#2, e X#1. Moving
      // X -> Y keeps the numbers (Y is empty on the server): c Y#2 is still
      // d's place on this device until d is written.
      await db.insert('students', {'id': 4405, 'lrn': '999999044050', 'last_name': 'Fixture4405', 'first_name': 'Zed', 'school_id': 1});
      await db.insert('enrollments', {'id': 4405, 'student_id': 4405, 'section_id': 32, 'school_year': _year});
      await serverRow('crla_assessments', crlaRow(521, 4405, 32, 1, '2026-07-01')); // c
      await serverRow('crla_assessments', crlaRow(522, 4405, 32, 2, '2026-08-01')); // d
      await serverRow('crla_assessments', crlaRow(523, 4405, 31, 1, '2026-09-01')); // e
      await mirrorLeaverResult(db, moveResult(4405, 31, 32, [(521, 2), (522, 3), (523, 1)], 813));
      expect(await crlaOf(4405), [(521, 32, 2), (522, 32, 3), (523, 32, 1)]);
      expect(await count('SELECT COUNT(*) FROM crla_assessments WHERE section_id < 0'), 0, reason: 'nothing left parked');
      expect(await count('SELECT COUNT(*) FROM sync_changes'), 0);
    });

    test('a swap of numbers between moved rows', () async {
      await db.insert('students', {'id': 4406, 'lrn': '999999044060', 'last_name': 'Fixture4406', 'first_name': 'Zed', 'school_id': 1});
      await db.insert('enrollments', {'id': 4406, 'student_id': 4406, 'section_id': 31, 'school_year': _year});
      await serverRow('crla_assessments', crlaRow(531, 4406, 32, 1, '2026-07-01'));
      await serverRow('crla_assessments', crlaRow(532, 4406, 32, 2, '2026-08-01'));
      await mirrorLeaverResult(db, moveResult(4406, 31, 32, [(531, 2), (532, 1)], 814));
      expect(await crlaOf(4406), [(531, 32, 2), (532, 32, 1)]);
    });

    test('without the bypass a finalized session still cannot change section', () async {
      await expectLater(db.update('phil_iri_assessments', {'section_id': 71}, where: 'id = 601'),
          throwsA(isA<DatabaseException>()
              .having((e) => '$e', 'message', contains('A finalized Phil-IRI assessment cannot be changed'))));
    });

    test('an archive result archives the enrollment and exits ARAL', () async {
      await serverRow('aral_enrollments', {
        'id': 604, 'student_id': 4403, 'school_id': 1, 'section_id': 71, 'school_year': _year, 'key_stage': 'ks3',
        'track': 'plus', 'entered_on': '2026-07-10', 'basis_source': 'manual', 'origin': 'cloud', 'row_version': 1,
      });
      await mirrorLeaverResult(db, {
        'enrollment': {'id': 4403, 'student_id': 4403, 'section_id': 71, 'school_year': _year,
            'status': 'dropped_out', 'left_on': '2026-11-12', 'left_by': _coord, 'left_note': 'fixture note'},
        'aral_enrollment': {'id': 604, 'student_id': 4403, 'school_id': 1, 'section_id': 71, 'school_year': _year,
            'key_stage': 'ks3', 'track': 'plus', 'status': 'exited', 'entered_on': '2026-07-10',
            'exited_on': '2026-11-12', 'exit_reason': 'dropped_out', 'basis_source': 'manual', 'row_version': 2},
      });
      final e = Enrollment.fromMap((await db.query('enrollments', where: 'id = 4403')).single);
      expect(e.status, EnrollmentStatus.droppedOut);
      expect(e.leftOn, '2026-11-12');
      expect(e.leftBy, _coord);
      expect((await db.query('aral_enrollments', where: 'id = 604')).single['status'], 'exited');
      expect(await count('SELECT COUNT(*) FROM sync_changes'), 0);
    });

    test('an anonymize result clears the learner on the device', () async {
      await mirrorLeaverResult(db, {
        'student': {'id': 4403, 'lrn': 'ANON-4403', 'last_name': 'Anonymized', 'first_name': '—', 'middle_name': null,
            'sex': 'F', 'school_id': 1, 'anonymized_at': '2027-08-01T00:00:00+00:00'},
      });
      final s = Student.fromMap((await db.query('students', where: 'id = 4403')).single);
      expect(s.lrn, 'ANON-4403');
      expect(s.sex, 'F');
      expect(s.isAnonymized, isTrue);
    });
  });

  // A real upgrade: the database is put back in its v43 shape (no leaver
  // columns, table or triggers), stamped v43, closed and reopened.
  test('a v43 device database reopened by this build keeps its enrollments and gains v44', () async {
    await db.execute('DROP TRIGGER IF EXISTS check_enrollment_status');
    await db.execute('DROP TRIGGER IF EXISTS check_enrollment_status_upd');
    await db.execute('DROP TABLE enrollment_moves');
    for (final c in ['left_note', 'left_by', 'left_on']) {
      await db.execute('ALTER TABLE enrollments DROP COLUMN $c');
    }
    await db.execute('ALTER TABLE students DROP COLUMN anonymized_at');
    expect(await columns('enrollments'), isNot(contains('left_on')));
    final before = await count('SELECT COUNT(*) FROM enrollments');

    await db.execute('PRAGMA user_version = 43');
    await LocalDatabase.close();
    db = await LocalDatabase.instance(dir);

    expect((await db.rawQuery('PRAGMA user_version')).single.values.single, 44);
    expect(await count('SELECT COUNT(*) FROM enrollments'), before);
    expect(await columns('enrollments'), containsAll(['left_on', 'left_by', 'left_note']));
    expect(await columns('students'), contains('anonymized_at'));
    expect(await columns('enrollment_moves'), contains('source'));
    await expectLater(db.update('enrollments', {'status': 'moved'}, where: 'id = 4401'),
        throwsA(isA<DatabaseException>().having((e) => '$e', 'message', contains('active, transferred_out or dropped_out'))));
  });
}
