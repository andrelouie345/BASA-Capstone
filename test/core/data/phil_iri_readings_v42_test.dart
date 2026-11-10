// v42 (cloud 20261110020000; spec 2026-11-10-phil-iri-untitled-readings
// D2-D6): a reading of a workbook-imported session may have no passage
// ("Untitled", typed word count, comprehension over imported_total), and an
// imported reading may be untimed (comprehension only).
import 'dart:io';

import 'package:basa_capstone/core/data/local/phil_iri_local_schema.dart';
import 'package:basa_capstone/core/models/phil_iri_reading.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _year = '2026-2027';

// The v41 table (today's columns, NOT NULL passage) plus the sync row_version.
const _v41Readings = '''
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
    comprehension_level TEXT,
    profile TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    imported_correct INTEGER CHECK (imported_correct >= 0),
    row_version INTEGER,
    UNIQUE (assessment_id, sequence_no)
  )
''';

void main() {
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_v42_').path);
    db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ42', 'school_name': 'ZZ v42'});
    await db.insert('sections', {'id': 42, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S42'});
    await db.insert('students', {'id': 542, 'lrn': '999999994242', 'last_name': 'L', 'first_name': 'F', 'school_id': 1});
    await db.insert('enrollments', {'student_id': 542, 'section_id': 42, 'school_year': _year, 'status': 'active'});
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded v42', 'is_grade_leveled': 1});
    await db.insert('phil_iri_passages', {
      'id': 242, 'collection_id': 1, 'level': 7, 'title': 'P242',
      'body': List.filled(120, 'word').join(' '), 'word_count': 120, 'is_active': 1,
    });
    for (var q = 1; q <= 5; q++) {
      await db.insert('phil_iri_questions',
          {'passage_id': 242, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]', 'answer_key': 'a'});
    }
  });

  Future<int> localId() async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));

  Future<int> session({String? source = 'workbook', String round = 'bosy'}) async {
    final id = await localId();
    await db.insert('phil_iri_assessments', {
      'id': id, 'student_id': 542, 'school_id': 1, 'section_id': 42, 'school_year': _year,
      'round': round, 'assessed_at': '2026-07-01', 'import_source': source,
    });
    return id;
  }

  Future<int> reading(int sessionId, Map<String, Object?> fields) async {
    final id = await localId();
    await db.insert('phil_iri_readings', {'id': id, 'assessment_id': sessionId, 'sequence_no': 1, ...fields});
    return id;
  }

  Matcher refused(String why) =>
      throwsA(isA<DatabaseException>().having((e) => e.toString(), 'message', contains(why)));
  const check = 'CHECK constraint failed';
  const noPassage = 'A reading without a passage belongs to a session imported from the workbook';

  group('stored', () {
    test('untitled whole text on a workbook session is stored', () async {
      final id = await reading(await session(), {
        'passage_id': null, 'method': 'whole_text', 'reading_seconds': 90,
        'imported_word_count': 120, 'imported_correct': 5, 'imported_total': 8,
      });
      final r = PhilIriReading.fromMap((await db.query('phil_iri_readings', where: 'id = ?', whereArgs: [id])).single);
      expect(r.isUntitled, isTrue);
      expect(r.passageId, isNull);
      expect(r.importedWordCount, 120);
      expect(r.importedCorrect, 5);
      expect(r.importedTotal, 8);
    });

    test('untitled one minute needs no word count', () async {
      final id = await reading(await session(), {'passage_id': null, 'method': 'one_minute', 'words_read': 70});
      expect((await db.query('phil_iri_readings', where: 'id = ?', whereArgs: [id])).single['words_read'], 70);
    });

    test('comprehension-only reading with a passage is stored untimed', () async {
      final id = await reading(await session(), {'passage_id': 242, 'method': 'whole_text', 'imported_correct': 3});
      final row = (await db.query('phil_iri_readings', where: 'id = ?', whereArgs: [id])).single;
      expect(row['reading_seconds'], isNull);
      expect(row['imported_correct'], 3);
    });

    // Final review I1: an Untitled row with comprehension only has no words
    // read, so no word count; the count is required only when timed.
    test('untitled comprehension-only whole text needs no word count', () async {
      final id = await reading(await session(), {
        'passage_id': null, 'method': 'whole_text', 'imported_correct': 5, 'imported_total': 8,
      });
      final row = (await db.query('phil_iri_readings', where: 'id = ?', whereArgs: [id])).single;
      expect(row['imported_word_count'], isNull);
      expect(row['imported_total'], 8);
    });

    test('an unpositioned miscue on an untitled reading is accepted', () async {
      final r = await reading(await session(), {'passage_id': null, 'method': 'one_minute', 'words_read': 70});
      await db.insert('phil_iri_miscues', {'id': await localId(), 'reading_id': r, 'word_index': null, 'miscue_type': 'omission'});
      expect(await db.query('phil_iri_miscues', where: 'reading_id = ?', whereArgs: [r]), hasLength(1));
    });
  });

  group('refused', () {
    test('null passage on a live session', () async {
      expect(reading(await session(source: null), {'passage_id': null, 'method': 'one_minute', 'words_read': 70}), refused(noPassage));
    });

    test('null passage on a scoresheet session', () async {
      expect(reading(await session(source: 'scoresheet'), {'passage_id': null, 'method': 'one_minute', 'words_read': 70}),
          refused(noPassage));
    });

    test('untitled whole text without a word count', () async {
      expect(reading(await session(), {'passage_id': null, 'method': 'whole_text', 'reading_seconds': 90}), refused(check));
    });

    test('untitled silent without a word count', () async {
      expect(reading(await session(), {'passage_id': null, 'method': 'silent', 'reading_seconds': 90}), refused(check));
    });

    test('a word count beside a passage', () async {
      expect(reading(await session(), {'passage_id': 242, 'method': 'whole_text', 'reading_seconds': 90, 'imported_word_count': 120}),
          refused(check));
    });

    test('a total without a correct count', () async {
      expect(reading(await session(), {
        'passage_id': null, 'method': 'one_minute', 'words_read': 70, 'imported_total': 8,
      }), refused(check));
    });

    test('an untitled correct count without a total', () async {
      expect(reading(await session(), {
        'passage_id': null, 'method': 'one_minute', 'words_read': 70, 'imported_correct': 5,
      }), refused(check));
    });

    test('a correct count above the total', () async {
      expect(reading(await session(), {
        'passage_id': null, 'method': 'one_minute', 'words_read': 70, 'imported_correct': 9, 'imported_total': 8,
      }), refused(check));
    });

    test('a positioned miscue on an untitled reading', () async {
      final r = await reading(await session(), {'passage_id': null, 'method': 'one_minute', 'words_read': 70});
      expect(db.insert('phil_iri_miscues', {'id': await localId(), 'reading_id': r, 'word_index': 3, 'miscue_type': 'omission'}),
          refused('A reading without a passage takes only miscues without a position'));
    });

    test('an answer on an untitled reading', () async {
      final r = await reading(await session(), {'passage_id': null, 'method': 'one_minute', 'words_read': 70});
      final q = (await db.query('phil_iri_questions', where: 'passage_id = 242', limit: 1)).single['id'];
      expect(db.insert('phil_iri_answers', {'id': await localId(), 'reading_id': r, 'question_id': q, 'chosen': 'a'}),
          refused('not a question'));
    });
  });

  test('v41 readings survive the v42 rebuild, passage becomes optional', () async {
    final mem = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await mem.execute(_v41Readings);
    await mem.insert('phil_iri_readings', {
      'id': 7, 'assessment_id': 1, 'sequence_no': 1, 'passage_id': 1, 'method': 'one_minute',
      'words_read': 100, 'imported_correct': 2, 'row_version': 3,
    });
    await rebuildPhilIriReadingsForV42(mem);
    final row = (await mem.query('phil_iri_readings', where: 'id = 7')).single;
    expect(row['passage_id'], 1);
    expect(row['imported_correct'], 2);
    expect(row['row_version'], 3);
    final info = {for (final c in await mem.rawQuery('PRAGMA table_info(phil_iri_readings)')) c['name']: c};
    expect(info['passage_id']!['notnull'], 0);
    expect(info.keys, containsAll(['imported_word_count', 'imported_total']));
    await mem.close();
  });
}
