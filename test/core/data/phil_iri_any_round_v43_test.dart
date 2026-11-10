// v43 (cloud 20261110030000; spec 2026-11-10-phil-iri-any-round-passages
// D7): the reading trigger no longer checks the round's test type. No table
// change: the version bump makes onUpgrade recreate the Phil-IRI triggers,
// so a device still carrying the v42 trigger loses the round check.
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _year = '2026-2027';

// The round block of the v16-v42 reading trigger, alone (what an older
// device's copy still refuses).
const _v42RoundTrigger = '''
  CREATE TRIGGER check_phil_iri_reading_ins
  BEFORE INSERT ON phil_iri_readings
  BEGIN
    SELECT RAISE(ABORT, 'This round does not use this passage (BOSY reads pre, MOSY mosy, EOSY post passages)')
    WHERE NEW.passage_id IS NOT NULL
      AND (SELECT test_type FROM phil_iri_passages WHERE id = NEW.passage_id) IS NOT
          (SELECT CASE round WHEN 'bosy' THEN 'pre' WHEN 'eosy' THEN 'post' ELSE 'mosy' END
           FROM phil_iri_assessments WHERE id = NEW.assessment_id)
      AND (SELECT test_type FROM phil_iri_passages WHERE id = NEW.passage_id) IS NOT NULL;
  END
''';

void main() {
  late Database db;
  final dir = Directory.systemTemp.createTempSync('basa_v43_').path;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ43', 'school_name': 'ZZ v43'});
    await db.insert('sections', {'id': 43, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S43'});
    // One learner per reading: a learner never reads the same passage twice.
    for (final id in [543, 544, 545]) {
      await db.insert('students', {'id': id, 'lrn': '99999999$id', 'last_name': 'L', 'first_name': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': id, 'section_id': 43, 'school_year': _year, 'status': 'active'});
    }
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded v43', 'is_grade_leveled': 1});
    await db.insert('phil_iri_passages', {
      'id': 343, 'collection_id': 1, 'level': 7, 'test_type': 'post', 'title': 'P343',
      'body': List.filled(120, 'word').join(' '), 'word_count': 120, 'is_active': 1,
    });
  });

  Future<int> localId() async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));

  Future<int> bosySession(int student) async {
    final id = await localId();
    await db.insert('phil_iri_assessments', {
      'id': id, 'student_id': student, 'school_id': 1, 'section_id': 43, 'school_year': _year,
      'round': 'bosy', 'assessed_at': '2026-07-01',
    });
    return id;
  }

  Future<void> readPost(int sessionId) async => db.insert('phil_iri_readings', {
        'id': await localId(), 'assessment_id': sessionId, 'sequence_no': 1, 'passage_id': 343,
        'method': 'whole_text', 'reading_seconds': 90,
      });

  test('the local database is v43', () async {
    expect((await db.rawQuery('PRAGMA user_version')).single.values.single, 43);
  });

  test('a live BOSY reading of a post passage is accepted', () async {
    await readPost(await bosySession(543));
  });

  tearDownAll(LocalDatabase.close);

  // A real upgrade: the database is stamped v42 with the v42 trigger, closed
  // and reopened, so LocalDatabase's onUpgrade runs (final review minor 4).
  test('a v42 device database reopened by this build loses the round check', () async {
    await db.execute('DROP TRIGGER IF EXISTS check_phil_iri_reading_ins');
    await db.execute(_v42RoundTrigger);
    await expectLater(readPost(await bosySession(544)),
        throwsA(isA<DatabaseException>().having((e) => '$e', 'message', contains('This round does not use this passage'))));
    await db.execute('PRAGMA user_version = 42');
    await LocalDatabase.close();
    db = await LocalDatabase.instance(dir);
    expect((await db.rawQuery('PRAGMA user_version')).single.values.single, 43);
    await readPost(await bosySession(545));
  });
}
