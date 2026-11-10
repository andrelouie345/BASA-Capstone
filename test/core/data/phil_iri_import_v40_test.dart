// SQLite v40: imported Phil-IRI sessions (cloud 20261109010000, spec
// 2026-11-09-phil-iri-import). phil_iri_miscues is rebuilt with a nullable
// word_index (rows and row_version kept); import_source / imported_correct
// get the cloud's rules in the device triggers; phil_iri_workbook_imports is
// mirrored and synced.
import 'dart:io';

import 'package:basa_capstone/core/data/local/aral_local_schema.dart';
import 'package:basa_capstone/core/data/local/calendar_local_schema.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/phil_iri_local_schema.dart';
import 'package:basa_capstone/core/data/local/report_local_schema.dart';
import 'package:basa_capstone/core/data/local/srp_local_schema.dart';
import 'package:basa_capstone/core/data/local/sync_local_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/sync_local_schema.dart';
import 'package:basa_capstone/core/data/local/tutor_assignment_local_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// phil_iri_miscues as a v39 device has it (row_version added by the sync schema).
const _v39Miscues = '''
    CREATE TABLE phil_iri_miscues (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reading_id INTEGER NOT NULL REFERENCES phil_iri_readings(id),
      word_index INTEGER NOT NULL CHECK (word_index >= 0),
      miscue_type TEXT NOT NULL CHECK (miscue_type IN ('mispronunciation', 'omission', 'substitution',
        'insertion', 'repetition', 'transposition', 'reversal')),
      spoken_text TEXT,
      self_corrected INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      row_version INTEGER
    )
  ''';

const _year = '2026-2027';

void main() {
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_v40_').path);

    await db.insert('schools', {'id': 1, 'school_id': 'ZZ40', 'school_name': 'ZZ v40'});
    await db.insert('schools', {'id': 2, 'school_id': 'ZZ41', 'school_name': 'ZZ v40 other'});
    await db.insert('sections', {'id': 70, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S70'});
    await db.insert('students', {'id': 500, 'lrn': '999999994000', 'last_name': 'L', 'first_name': 'F', 'school_id': 1});
    await db.insert('enrollments', {'student_id': 500, 'section_id': 70, 'school_year': _year, 'status': 'active'});
    await db.insert('phil_iri_collections', {'id': 1, 'name': 'Graded v40', 'is_grade_leveled': 1});
    Future<void> passage(int id, int level, String body, {String? test = 'mosy', int active = 1}) =>
        db.insert('phil_iri_passages', {
          'id': id, 'collection_id': 1, 'test_type': test, 'level': level, 'title': 'P$id',
          'body': body, 'word_count': 5, 'is_active': active,
        });
    await passage(101, 7, 'one two three four five');
    await passage(103, 2, 'level two text here now', test: null);
    await passage(104, 7, 'an inactive passage text here', active: 0);
    await passage(105, 7, 'the live reading passage text');
    await passage(106, 7, 'a mosy passage read in bosy'); // v43: any round
    for (var q = 1; q <= 3; q++) {
      await db.insert('phil_iri_questions',
          {'passage_id': 101, 'question_no': q, 'prompt': 'Q$q', 'choices': '["a","b"]', 'answer_key': 'a'});
    }
  });

  tearDownAll(LocalDatabase.close);

  Future<int> localId() async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));

  Future<int> session(String round, {String? source}) async {
    final id = await localId();
    await db.insert('phil_iri_assessments', {
      'id': id, 'student_id': 500, 'school_id': 1, 'section_id': 70, 'school_year': _year,
      'round': round, 'assessed_at': '2026-07-01', 'import_source': source,
    });
    return id;
  }

  Future<int> reading(int sessionId, int passageId, {int seq = 1, int? importedCorrect}) async {
    final id = await localId();
    await db.insert('phil_iri_readings', {
      'id': id, 'assessment_id': sessionId, 'sequence_no': seq, 'passage_id': passageId,
      'reading_seconds': 60, 'imported_correct': importedCorrect,
    });
    return id;
  }

  Future<int> miscue(int readingId, int? wordIndex) async {
    final id = await localId();
    await db.insert('phil_iri_miscues',
        {'id': id, 'reading_id': readingId, 'word_index': wordIndex, 'miscue_type': 'omission'});
    return id;
  }

  Matcher refused(String message) =>
      throwsA(isA<DatabaseException>().having((e) => '$e', 'message', contains(message)));

  test('v39 miscues survive the rebuild with row_version; word_index becomes nullable', () async {
    final triggers = {
      for (final r in await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' AND sql LIKE '%phil_iri_miscues%'"))
        r['name'] as String,
    };
    await db.transaction((txn) async {
      for (final t in triggers) {
        await txn.execute('DROP TRIGGER IF EXISTS $t');
      }
      await txn.execute('DROP TABLE phil_iri_miscues');
      await txn.execute(_v39Miscues);
      await txn.insert('phil_iri_miscues',
          {'id': 41, 'reading_id': 9, 'word_index': 3, 'miscue_type': 'omission', 'row_version': 7});
    });

    await rebuildPhilIriMiscuesForV40(db);
    await createPhilIriLocalSchema(db);
    await createAralLocalSchema(db);
    await createSrpLocalSchema(db);
    await createCalendarLocalSchema(db);
    await createReportLocalSchema(db);
    await createTutorAssignmentLocalSchema(db);
    await createSyncLocalSchema(db);

    final row = (await db.query('phil_iri_miscues', where: 'id = 41')).single;
    expect(row['word_index'], 3);
    expect(row['row_version'], 7);
    final wordIndex = (await db.rawQuery('PRAGMA table_info(phil_iri_miscues)')).firstWhere((c) => c['name'] == 'word_index');
    expect(wordIndex['notnull'], 0);
    final after = {
      for (final r in await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' AND sql LIKE '%phil_iri_miscues%'"))
        r['name'] as String,
    };
    expect(after, triggers);
    await db.delete('phil_iri_miscues', where: 'id = 41');
  }, timeout: const Timeout(Duration(minutes: 3))); // the creators are slow

  test('the v40 rebuild is a no-op without the table', () async {
    final empty = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await rebuildPhilIriMiscuesForV40(empty);
    await empty.close();
  });

  test('a miscue without a position: refused on a live reading, accepted on an imported one', () async {
    final live = await reading(await session('mosy1'), 105);
    await expectLater(miscue(live, null), refused('A miscue without a position belongs to an imported reading'));
    await expectLater(miscue(live, 9), refused('Word position is outside the passage'));
    await miscue(live, 2);

    final imported = await reading(await session('mosy2', source: 'scoresheet'), 104);
    await miscue(imported, null);
    expect((await db.query('phil_iri_miscues', where: 'reading_id = ?', whereArgs: [imported])).single['word_index'], isNull);
  });

  test('an imported session skips the no-repeat and active checks, keeps the own grade; no round check for any session', () async {
    // A BOSY session reading a 'mosy' passage, twice (two imported sessions).
    await reading(await session('bosy', source: 'workbook'), 101);
    await reading(await session('bosy', source: 'scoresheet'), 101);
    // An inactive passage.
    await reading(await session('mosy3', source: 'scoresheet'), 104, seq: 1);
    // Own grade stays.
    await expectLater(reading(await session('eosy', source: 'workbook'), 103),
        refused('A learner reads a passage of their own grade'));
    // A live reading of the imported text afterwards: already read.
    await expectLater(reading(await session('mosy1'), 101), refused('This learner has already read this passage'));
    // v43 (spec 2026-11-10-phil-iri-any-round-passages): a live session has
    // no round check either; 106 is an unread 'mosy' passage read in BOSY.
    await reading(await session('bosy'), 106);
  });

  test('imported_correct: workbook only, at most the question count, never with answers', () async {
    await expectLater(reading(await session('mosy1', source: 'scoresheet'), 101, importedCorrect: 2),
        refused('An imported correct count belongs to a reading imported from the workbook'));
    await expectLater(reading(await session('mosy1'), 105, importedCorrect: 0),
        refused('An imported correct count belongs to a reading imported from the workbook'));
    await expectLater(reading(await session('mosy1', source: 'workbook'), 101, importedCorrect: 4),
        refused("Imported correct count is more than the passage's questions"));

    // Correct count first, then an answer.
    final counted = await reading(await session('mosy2', source: 'workbook'), 101, importedCorrect: 3);
    final question = (await db.query('phil_iri_questions', where: 'passage_id = 101 AND question_no = 1')).single['id'];
    await expectLater(db.insert('phil_iri_answers', {'id': await localId(), 'reading_id': counted, 'question_id': question, 'chosen': 'a'}),
        refused('This reading has an imported correct count; it takes no answers'));

    // An answer first, then a correct count.
    final answered = await reading(await session('mosy3', source: 'workbook'), 101, seq: 2);
    await db.insert('phil_iri_answers', {'id': await localId(), 'reading_id': answered, 'question_id': question, 'chosen': 'a'});
    await expectLater(db.update('phil_iri_readings', {'imported_correct': 1}, where: 'id = ?', whereArgs: [answered]),
        refused('This reading has answers; an imported correct count replaces answers, not both'));
  });

  test('import_source cannot change', () async {
    final s = await session('eosy', source: 'workbook');
    await expectLater(db.update('phil_iri_assessments', {'import_source': 'scoresheet'}, where: 'id = ?', whereArgs: [s]),
        refused('Only the status of a Phil-IRI assessment can change'));
    await expectLater(db.update('phil_iri_assessments', {'import_source': null}, where: 'id = ?', whereArgs: [s]),
        refused('Only the status of a Phil-IRI assessment can change'));
    final live = await session('eosy');
    await expectLater(db.update('phil_iri_assessments', {'import_source': 'workbook'}, where: 'id = ?', whereArgs: [live]),
        refused('Only the status of a Phil-IRI assessment can change'));
    await expectLater(session('eosy', source: 'other'), throwsA(isA<DatabaseException>()));
  });

  test('the workbook lock is synced, unsent work, unique per section and year', () async {
    expect(syncedTables['phil_iri_workbook_imports'], 'id');
    expect(syncedTables.keys.toList().indexOf('phil_iri_workbook_imports'),
        syncedTables.keys.toList().indexOf('phil_iri_rubric_scores') + 1);
    final cols = {for (final c in await db.rawQuery('PRAGMA table_info(phil_iri_workbook_imports)')) c['name']};
    expect(cols, containsAll(['id', 'school_id', 'section_id', 'school_year', 'imported_by', 'imported_at', 'row_version', 'origin']));

    Map<String, Object?> lock(int id, {int school = 1, int section = 70, String year = _year}) =>
        {'id': id, 'school_id': school, 'section_id': section, 'school_year': year};
    await expectLater(db.insert('phil_iri_workbook_imports', lock(5)), refused('needs a local id'));
    await expectLater(db.insert('phil_iri_workbook_imports', lock(await localId(), school: 2)),
        refused('Section is not a section of that school and school year'));
    await expectLater(db.insert('phil_iri_workbook_imports', lock(await localId(), year: '2027-2028')),
        refused('Section is not a section of that school and school year'));

    await db.insert('phil_iri_workbook_imports', lock(await localId()));
    await expectLater(db.insert('phil_iri_workbook_imports', lock(await localId())), throwsA(isA<DatabaseException>()
        .having((e) => e.isUniqueConstraintError(), 'unique', isTrue)));

    final work = await SyncLocalRepositorySqlite(db).localWork();
    expect(work.where((l) => l.kind == 'Phil-IRI workbook import(s)' && l.sectionId == 70).single.count, 1);
  });

  test('a pulled lock row cannot be changed or deleted on the device', () async {
    await db.insert('sections', {'id': 71, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'S71'});
    await db.insert('phil_iri_workbook_imports',
        {'id': 900, 'school_id': 1, 'section_id': 71, 'school_year': _year, 'row_version': 1, 'origin': 'cloud'});
    await expectLater(
        db.update('phil_iri_workbook_imports', {'imported_by': 'x'}, where: 'id = 900'), refused('cannot be changed'));
    await expectLater(db.delete('phil_iri_workbook_imports', where: 'id = 900'), refused('cannot be deleted'));
  });
}
