// SQLite v37: ARAL sessions belong to a class (cloud 20261023040000).
// aral_sessions gains class_id (a declared reference to aral_classes); the
// per-tutor settings table goes. Rows, row_version, session numbers and the
// pending-upload lock survive; new sessions number per class and a class
// holds one session per date.
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

/// aral_sessions and aral_tutor_settings as a v36 device has them.
const _v36Sessions = '''
    CREATE TABLE aral_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tutor_id TEXT NOT NULL REFERENCES users(id),
      school_id INTEGER NOT NULL REFERENCES schools(id),
      school_year TEXT NOT NULL,
      session_no INTEGER NOT NULL DEFAULT 0 CHECK (session_no >= 0),
      held_on TEXT NOT NULL,
      minutes INTEGER NOT NULL CHECK (minutes BETWEEN 1 AND 120),
      setup TEXT NOT NULL CHECK (setup IN ('pull_out', 'during_class', 'after_class', 'weekend', 'other')),
      lesson TEXT,
      remarks TEXT,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      row_version INTEGER
    )
  ''';
const _v36Settings = '''
    CREATE TABLE aral_tutor_settings (
      tutor_id TEXT PRIMARY KEY REFERENCES users(id),
      school_id INTEGER NOT NULL REFERENCES schools(id),
      multiple_sessions_per_day INTEGER NOT NULL DEFAULT 0,
      updated_by TEXT REFERENCES users(id),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local',
      row_version INTEGER
    )
  ''';

void main() {
  late Database db;
  const year = '2026-2027';
  const tutor = '00000000-0000-0000-0000-0000000097a1';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_v37_').path);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ37', 'school_name': 'ZZ v37'});
    await db.insert('users', {'id': tutor, 'email': 't@zz37', 'full_name': 'T', 'role': 'tutor', 'school_id': 1});
  });

  tearDownAll(LocalDatabase.close);

  Future<Map<String, String>> objectsMentioningSessions() async => {
        for (final r in await db.rawQuery(
            "SELECT type, name, sql FROM sqlite_master WHERE type IN ('trigger', 'view', 'index') "
            "AND sql LIKE '%aral_sessions%'"))
          '${r['type']} ${r['name']}': r['sql'] as String,
      };

  /// What onUpgrade runs after the v37 step.
  Future<void> upgradeCreators() async {
    await createPhilIriLocalSchema(db);
    await createAralLocalSchema(db);
    await createSrpLocalSchema(db);
    await createCalendarLocalSchema(db);
    await createReportLocalSchema(db);
    await createTutorAssignmentLocalSchema(db);
    await createSyncLocalSchema(db);
  }

  Future<int> localId() async => -(await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))"));

  test('v36 sessions take class_id; the tutor settings go; rows and the pending lock survive', () async {
    final fresh = await objectsMentioningSessions();
    expect(fresh, isNotEmpty);

    // Turn the tables back into their v36 shape.
    await db.transaction((txn) async {
      for (final name in fresh.keys.where((k) => !k.startsWith('index '))) {
        final parts = name.split(' ');
        await txn.execute('DROP ${parts[0].toUpperCase()} IF EXISTS ${parts[1]}');
      }
      await txn.execute('DROP TABLE aral_sessions');
      await txn.execute(_v36Sessions);
      await txn.execute('DROP TABLE IF EXISTS aral_tutor_settings');
      await txn.execute(_v36Settings);
    });
    // A pulled session (row_version 3, number 7) and a new one waiting in an upload.
    for (final (id, version, no, origin) in [(7, 3, 7, 'cloud'), (-2, null, 8, 'local')]) {
      await db.insert('aral_sessions', {
        'id': id, 'tutor_id': tutor, 'school_id': 1, 'school_year': year, 'session_no': no,
        'held_on': '2026-08-0${id.abs()}', 'minutes': 45, 'setup': 'pull_out', 'origin': origin, 'row_version': version,
      });
    }
    await db.insert('aral_tutor_settings', {'tutor_id': tutor, 'school_id': 1, 'multiple_sessions_per_day': 1});
    await db.insert('sync_pending', {'table_name': 'aral_sessions', 'row_key': '-2', 'upload_id': 5});

    await upgradeAralSessionsForV37(db);
    await upgradeCreators();

    expect(await objectsMentioningSessions(), fresh, reason: 'every trigger and index is back, unchanged');
    expect(await db.rawQuery("SELECT name FROM sqlite_master WHERE name = 'aral_tutor_settings'"), isEmpty);
    final rows = await db.query('aral_sessions', orderBy: 'id');
    expect(rows.map((r) => (r['id'], r['row_version'], r['session_no'], r['class_id'])).toList(),
        [(-2, null, 8, null), (7, 3, 7, null)]);
    await expectLater(db.update('aral_sessions', {'remarks': 'x'}, where: 'id = -2'),
        throwsA(predicate((e) => '$e'.contains(pendingLockMessage))));
    final fks = await db.rawQuery('PRAGMA foreign_key_list(aral_sessions)');
    expect(fks.any((f) => f['from'] == 'class_id' && f['table'] == 'aral_classes'), isTrue);
    await db.delete('sync_pending');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the v37 step does nothing the second time', () async {
    final before = await objectsMentioningSessions();
    await upgradeAralSessionsForV37(db);
    expect(await objectsMentioningSessions(), before);
  });

  test('sessions number per class; one session per class per date; a new session needs a class', () async {
    final a = await localId(), b = await localId();
    for (final (id, name) in [(a, '7-A'), (b, '7-B')]) {
      await db.insert('aral_classes', {'id': id, 'school_id': 1, 'school_year': year, 'class_name': name,
          'program': 'ks3_basic', 'grade_level': 7, 'tutor_id': tutor});
    }
    Future<int> session(int? classId, String day) async {
      final id = await localId();
      await db.insert('aral_sessions', {'id': id, 'tutor_id': tutor, 'school_id': 1, 'school_year': year,
          'class_id': classId, 'held_on': day, 'minutes': 45, 'setup': 'pull_out'});
      return (await db.query('aral_sessions', columns: ['session_no'], where: 'id = ?', whereArgs: [id])).single['session_no']
          as int;
    }

    expect(await session(a, '2026-09-01'), 1);
    expect(await session(a, '2026-09-02'), 2);
    expect(await session(b, '2026-09-01'), 1, reason: 'class B counts on its own, same day as class A');
    await expectLater(session(a, '2026-09-02'),
        throwsA(predicate((e) => '$e'.contains('An ARAL class already has a session on that date'))));
    await expectLater(session(null, '2026-09-03'), throwsA(predicate((e) => '$e'.contains('A new ARAL session needs a class'))));
    // Moving a session onto a date its class already holds is refused too.
    final third = await localId();
    await db.insert('aral_sessions', {'id': third, 'tutor_id': tutor, 'school_id': 1, 'school_year': year,
        'class_id': a, 'held_on': '2026-09-03', 'minutes': 45, 'setup': 'pull_out'});
    await expectLater(db.update('aral_sessions', {'held_on': '2026-09-01'}, where: 'id = ?', whereArgs: [third]),
        throwsA(predicate((e) => '$e'.contains('An ARAL class already has a session on that date'))));
    await expectLater(db.update('aral_sessions', {'class_id': b}, where: 'id = ?', whereArgs: [third]),
        throwsA(predicate((e) => '$e'.contains('An ARAL session keeps its tutor, class'))));
  });
}
