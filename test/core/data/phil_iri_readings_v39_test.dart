// SQLite v39: phil_iri_readings accepts the Struggling level (cloud
// 20261029010000, spec 2026-10-29-phil-iri-word-recognition-bands). The table
// is rebuilt with the widened CHECKs; rows, stored levels and row_version
// survive (finalized results are never re-scored). The saved non-reader
// cut-off is removed from the thresholds mirror so the new default applies.
import 'dart:convert';
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

/// phil_iri_readings as a v38 device has it (row_version added by the sync schema).
const _v38Readings = '''
    CREATE TABLE phil_iri_readings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      assessment_id INTEGER NOT NULL REFERENCES phil_iri_assessments(id),
      sequence_no INTEGER NOT NULL CHECK (sequence_no > 0),
      passage_id INTEGER NOT NULL REFERENCES phil_iri_passages(id),
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
      word_reading_score REAL CHECK (word_reading_score BETWEEN 0 AND 1),
      words_per_minute REAL CHECK (words_per_minute >= 0),
      accuracy_level TEXT CHECK (accuracy_level IN ('independent', 'instructional', 'frustration', 'nonReader')),
      speed TEXT CHECK (speed IN ('struggling', 'slow', 'average', 'fast')),
      word_reading_level TEXT CHECK (word_reading_level IN ('independent', 'instructional', 'frustration', 'nonReader')),
      comprehension_score REAL CHECK (comprehension_score BETWEEN 0 AND 1),
      comprehension_level TEXT CHECK (comprehension_level IN ('independent', 'instructional', 'frustration')),
      profile TEXT CHECK (profile IN ('independent', 'instructional', 'frustration', 'nonReader')),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      row_version INTEGER,
      UNIQUE (assessment_id, sequence_no),
      CHECK ((method IN ('whole_text', 'silent') AND words_read IS NULL)
             OR (method = 'one_minute' AND reading_seconds IS NULL))
    )
  ''';

void main() {
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_v39_').path);
  });

  tearDownAll(LocalDatabase.close);

  /// What onUpgrade runs after the v39 rebuild.
  Future<void> upgradeCreators() async {
    await createPhilIriLocalSchema(db);
    await createAralLocalSchema(db);
    await createSrpLocalSchema(db);
    await createCalendarLocalSchema(db);
    await createReportLocalSchema(db);
    await createTutorAssignmentLocalSchema(db);
    await createSyncLocalSchema(db);
  }

  Future<Set<String>> triggersOnReadings() async => {
        for (final r in await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' AND sql LIKE '%phil_iri_readings%'"))
          r['name'] as String,
      };

  Map<String, Object?> reading(int id, int seq, String profile, {int? rowVersion}) => {
        'id': id,
        'assessment_id': 900,
        'sequence_no': seq,
        'passage_id': 110,
        'method': 'whole_text',
        'reading_seconds': 150,
        'word_reading_score': 0.88,
        'words_per_minute': 60.0,
        'accuracy_level': 'frustration',
        'speed': 'struggling',
        'word_reading_level': profile == 'struggling' ? 'struggling' : 'nonReader',
        'comprehension_score': 0.3,
        'comprehension_level': 'frustration',
        'profile': profile,
        'row_version': rowVersion,
      };

  test('a v38 table is rebuilt: the finalized row, its levels, row_version and the triggers survive', () async {
    final fresh = await triggersOnReadings();

    // Turn the table back into its v38 shape with one finalized server row.
    await db.transaction((txn) async {
      for (final t in fresh) {
        await txn.execute('DROP TRIGGER IF EXISTS $t');
      }
      await txn.execute('DROP TABLE phil_iri_readings');
      await txn.execute(_v38Readings);
      await txn.insert('phil_iri_readings', reading(41, 1, 'nonReader', rowVersion: 7));
      await txn.insert('phil_iri_thresholds',
          {'id': 5, 'school_id': null, 'settings': jsonEncode({'non_reader_max': 50, 'speed_slow_max': 120})});
    });

    await rebuildPhilIriReadingsForV39(db);
    await upgradeCreators();
    await stripSavedNonReaderMaxForV39(db);

    final rows = await db.query('phil_iri_readings', where: 'id = 41');
    expect(rows.single['profile'], 'nonReader');
    expect(rows.single['word_reading_level'], 'nonReader');
    expect(rows.single['accuracy_level'], 'frustration');
    expect(rows.single['row_version'], 7);
    expect(await triggersOnReadings(), fresh);

    // accepts struggling (a server copy, so the new-row id rule doesn't apply)
    await db.insert('phil_iri_readings', reading(42, 2, 'struggling', rowVersion: 1));
    expect((await db.query('phil_iri_readings', where: 'id = 42')).single['profile'], 'struggling');
    await expectLater(db.insert('phil_iri_readings', reading(43, 3, 'other', rowVersion: 1)),
        throwsA(isA<DatabaseException>()));

    // drops the saved non-reader cut-off
    final settings = (await db.query('phil_iri_thresholds', where: 'id = 5')).single['settings'] as String;
    expect(jsonDecode(settings), {'speed_slow_max': 120});
  }, timeout: const Timeout(Duration(minutes: 3))); // the creators are slow

  test('no-op without the tables', () async {
    final empty = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await rebuildPhilIriReadingsForV39(empty);
    await stripSavedNonReaderMaxForV39(empty);
    await empty.close();
  });
}
