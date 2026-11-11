// v41 (cloud 20261109020000; spec 2026-11-09-phil-iri-rules-update D1):
// phil_iri_readings.comprehension_level also allows 'struggling'.
import 'dart:io';

import 'package:basa_capstone/core/data/local/phil_iri_local_schema.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _year = '2026-2027';

// The v40 table: today's columns with the old comprehension CHECK, plus the
// sync schema's row_version.
const _v40Readings = '''
  CREATE TABLE phil_iri_readings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    assessment_id INTEGER NOT NULL,
    sequence_no INTEGER NOT NULL CHECK (sequence_no > 0),
    passage_id INTEGER NOT NULL,
    method TEXT NOT NULL DEFAULT 'whole_text' CHECK (method IN ('whole_text', 'one_minute', 'silent')),
    reading_seconds INTEGER CHECK (reading_seconds > 0),
    words_read INTEGER CHECK (words_read > 0),
    obs_word_by_word INTEGER NOT NULL DEFAULT 0,
    obs_lacks_expression INTEGER NOT NULL DEFAULT 0,
    obs_voice_inaudible INTEGER NOT NULL DEFAULT 0,
    obs_disregards_punctuation INTEGER NOT NULL DEFAULT 0,
    obs_points_to_words INTEGER NOT NULL DEFAULT 0,
    obs_little_analysis INTEGER NOT NULL DEFAULT 0,
    obs_other TEXT,
    word_reading_score REAL,
    words_per_minute REAL,
    accuracy_level TEXT,
    speed TEXT,
    word_reading_level TEXT,
    comprehension_score REAL,
    comprehension_level TEXT CHECK (comprehension_level IN ('independent', 'instructional', 'frustration')),
    profile TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    imported_correct INTEGER CHECK (imported_correct >= 0),
    row_version INTEGER,
    UNIQUE (assessment_id, sequence_no)
  )
''';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh database accepts a struggling comprehension', () async {
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_v41_').path);
    final db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ41', 'school_name': 'ZZ v41'});
    await db.insert('sections', {'id': 41, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S41'});
    await db.insert('students', {'id': 541, 'lrn': '999999994141', 'last_name': 'L', 'first_name': 'F', 'school_id': 1});
    await db.insert('enrollments', {'student_id': 541, 'section_id': 41, 'school_year': _year, 'status': 'active'});
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded v41', 'is_grade_leveled': 1});
    await db.insert('phil_iri_passages', {
      'id': 241, 'collection_id': 1, 'level': 7, 'title': 'P241',
      'body': List.filled(120, 'word').join(' '), 'word_count': 120, 'is_active': 1,
    });
    Future<int> localId() async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));
    final session = await localId();
    final reading = await localId();
    await db.insert('phil_iri_assessments', {
      'id': session, 'student_id': 541, 'school_id': 1, 'section_id': 41, 'school_year': _year,
      'round': 'bosy', 'assessed_at': '2026-07-01',
    });
    await db.insert('phil_iri_readings', {
      'id': reading, 'assessment_id': session, 'sequence_no': 1, 'passage_id': 241,
      'method': 'one_minute', 'words_read': 120, 'comprehension_score': 0.2, 'comprehension_level': 'struggling',
    });
    final row = (await db.query('phil_iri_readings', where: 'id = ?', whereArgs: [reading])).single;
    expect(row['comprehension_level'], 'struggling');
  });

  test('v40 readings survive the v41 rebuild', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(_v40Readings);
    await db.insert('phil_iri_readings', {
      'id': 7, 'assessment_id': 1, 'sequence_no': 1, 'passage_id': 1, 'method': 'one_minute',
      'words_read': 100, 'comprehension_level': 'frustration', 'row_version': 3,
    });
    await rebuildPhilIriReadingsForV41(db);
    final row = (await db.query('phil_iri_readings', where: 'id = 7')).single;
    expect(row['comprehension_level'], 'frustration');
    expect(row['row_version'], 3);
    expect(row['words_read'], 100);
    await db.update('phil_iri_readings', {'comprehension_level': 'struggling'}, where: 'id = 7');
    expect((await db.query('phil_iri_readings', where: 'id = 7')).single['comprehension_level'], 'struggling');
    await db.close();
  });
}
