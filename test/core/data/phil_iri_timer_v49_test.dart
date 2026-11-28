// v49 (cloud 20261126010000; spec 2026-11-26 timed reading D1, D4, D11):
// phil_iri_reading_timer_events on the device: the order and time rules for
// taps made here, pulled taps can't change, a reading's taps go with it, and
// the table is synced after its reading.
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/phil_iri_assessment_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/sync_local_writes.dart';
import 'package:basa_capstone/core/data/pull_tables.dart';
import 'package:basa_capstone/core/models/phil_iri_timer_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _year = '2026-2027';

void main() {
  late Database db;
  late PhilIriAssessmentRepositorySqlite repo;
  final dir = Directory.systemTemp.createTempSync('basa_v49_').path;
  var learner = 600;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    repo = PhilIriAssessmentRepositorySqlite(db);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ49', 'school_name': 'ZZ v49'});
    await db.insert('sections', {'id': 49, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S49'});
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded v49', 'is_grade_leveled': 1});
    await db.insert('phil_iri_passages', {
      'id': 349, 'collection_id': 1, 'level': 7, 'title': 'P349',
      'body': List.filled(120, 'word').join(' '), 'word_count': 120, 'is_active': 1,
    });
  });

  Future<int> localId() async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));

  /// A new (device) reading of a new learner.
  Future<int> reading() async {
    final student = ++learner;
    await db.insert('students', {'id': student, 'lrn': '99999999$student', 'last_name': 'L', 'first_name': 'F', 'school_id': 1});
    await db.insert('enrollments', {'student_id': student, 'section_id': 49, 'school_year': _year, 'status': 'active'});
    final session = await localId();
    await db.insert('phil_iri_assessments', {
      'id': session, 'student_id': student, 'school_id': 1, 'section_id': 49, 'school_year': _year,
      'round': 'bosy', 'assessed_at': '2026-07-01',
    });
    final id = await localId();
    await db.insert('phil_iri_readings',
        {'id': id, 'assessment_id': session, 'sequence_no': 1, 'passage_id': 349, 'method': 'whole_text'});
    return id;
  }

  final t0 = DateTime.parse('2026-07-01T09:00:00+08:00');
  PhilIriTimerEvent tap(int readingId, int seq, PhilIriTimerKind kind, int seconds) =>
      PhilIriTimerEvent(readingId: readingId, seq: seq, kind: kind, at: t0.add(Duration(seconds: seconds)));

  test('the database is v51 (v50 timer rules, v51 digitized CRLA) and has the table', () async {
    expect((await db.rawQuery('PRAGMA user_version')).first.values.first, 51);
    final cols = {for (final c in await db.rawQuery('PRAGMA table_info(phil_iri_reading_timer_events)')) c['name']};
    expect(cols, containsAll(['id', 'reading_id', 'seq', 'kind', 'at', 'created_by', 'row_version']));
  });

  test('taps are stored and read back by seq', () async {
    final r = await reading();
    await repo.insertTimerEvent(tap(r, 1, PhilIriTimerKind.start, 0));
    await repo.insertTimerEvent(tap(r, 2, PhilIriTimerKind.pause, 68));
    final got = await repo.timerEvents(r);
    expect(got.map((e) => e.kind), [PhilIriTimerKind.start, PhilIriTimerKind.pause]);
    expect(got.every((e) => e.id! < 0), isTrue);
    expect(got[1].at.isAtSameMomentAs(t0.add(const Duration(seconds: 68))), isTrue);
  });

  test('a local tap out of order is refused by the trigger', () async {
    final r = await reading();
    await expectLater(repo.insertTimerEvent(tap(r, 1, PhilIriTimerKind.pause, 0)),
        throwsA(predicate((e) => '$e'.contains('Start the timer first.'))));
    await repo.insertTimerEvent(tap(r, 1, PhilIriTimerKind.start, 0));
    await repo.insertTimerEvent(tap(r, 2, PhilIriTimerKind.stop, 30));
    await expectLater(repo.insertTimerEvent(tap(r, 3, PhilIriTimerKind.stop, 31)),
        throwsA(predicate((e) => '$e'.contains('The timer is already stopped.'))));
  });

  test('an earlier time and a skipped seq are refused', () async {
    final r = await reading();
    await repo.insertTimerEvent(tap(r, 1, PhilIriTimerKind.start, 100));
    await expectLater(repo.insertTimerEvent(tap(r, 2, PhilIriTimerKind.stop, 50)),
        throwsA(predicate((e) => '$e'.contains("earlier than the timer's last tap"))));
    await expectLater(repo.insertTimerEvent(tap(r, 5, PhilIriTimerKind.stop, 150)),
        throwsA(predicate((e) => '$e'.contains('seq'))));
  });

  test('a restart is allowed after the clock jumped back, then the new timing counts (review I3)', () async {
    final r = await reading();
    await repo.insertTimerEvent(tap(r, 1, PhilIriTimerKind.start, 100));
    await repo.insertTimerEvent(tap(r, 2, PhilIriTimerKind.reset, 50));
    await repo.insertTimerEvent(tap(r, 3, PhilIriTimerKind.start, 60));
    await expectLater(repo.insertTimerEvent(tap(r, 4, PhilIriTimerKind.stop, 55)),
        throwsA(predicate((e) => '$e'.contains("earlier than the timer's last tap"))));
    await repo.insertTimerEvent(tap(r, 4, PhilIriTimerKind.stop, 90));
  });

  test('no tap on a session that is not in progress (review I5)', () async {
    final r = await reading();
    await db.rawUpdate("UPDATE phil_iri_assessments SET status = 'completed' "
        'WHERE id = (SELECT assessment_id FROM phil_iri_readings WHERE id = ?)', [r]);
    await expectLater(repo.insertTimerEvent(tap(r, 1, PhilIriTimerKind.start, 0)),
        throwsA(predicate((e) => '$e'.contains('Reopen the session to time it again.'))));
  });

  test('a pulled tap cannot be changed or deleted', () async {
    final r = await reading();
    await db.transaction((txn) => withSyncBypass(txn, () async {
          await txn.insert('phil_iri_reading_timer_events', {
            'id': 9001, 'reading_id': r, 'seq': 1, 'kind': 'start', 'at': '2026-07-01T09:00:00.000+08:00', 'row_version': 1,
          });
        }));
    await expectLater(db.update('phil_iri_reading_timer_events', {'kind': 'pause'}, where: 'id = 9001'), throwsA(anything));
    await expectLater(db.delete('phil_iri_reading_timer_events', where: 'id = 9001'), throwsA(anything));
  });

  test('deleteReading removes its taps, unjournaled', () async {
    final r = await reading();
    await repo.insertTimerEvent(tap(r, 1, PhilIriTimerKind.start, 0));
    await repo.insertTimerEvent(tap(r, 2, PhilIriTimerKind.stop, 30));
    await repo.deleteReading(r);
    expect(await repo.timerEvents(r), isEmpty);
    expect(await db.query('sync_changes', where: "table_name = 'phil_iri_reading_timer_events'"), isEmpty);
  });

  test('the table is synced and pulled after its reading', () {
    final synced = syncedTables.keys.toList();
    expect(synced.indexOf('phil_iri_reading_timer_events'), greaterThan(synced.indexOf('phil_iri_readings')));
    expect(syncedParents['phil_iri_reading_timer_events'], ('phil_iri_readings', 'reading_id'));
    final pull = pullOrder.keys.toList();
    expect(pull.indexOf('phil_iri_reading_timer_events'), greaterThan(pull.indexOf('phil_iri_readings')));
    expect(pullClearOrder.indexOf('phil_iri_reading_timer_events'), lessThan(pullClearOrder.indexOf('phil_iri_readings')));
  });
}
