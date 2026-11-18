// v46 (ARAL memo settings, spec docs/superpowers/specs/2026-11-18-aral-division-memo-design.md;
// cloud 20261118010000): the device triggers read the school's ARAL settings
// from the aral_settings mirror (school row over default row over today's
// rule): class maximum, weekdays only, longest session, IRIP cycle length.
// aral_irip_weeks is rebuilt for weeks 1-26; a real v45 device database is
// upgraded with its rows kept.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/sync_local_writes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _year = '2026-2027';
const _tutor = 'tutor-46';

void main() {
  late Database db;
  final dir = Directory.systemTemp.createTempSync('basa_v46_').path;
  var nextStudent = 4600;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ46A', 'school_name': 'ZZ v46 A'});
    await db.insert('sections', {'id': 46, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'G7-46'});
    await db.insert('users', {'id': _tutor, 'email': 't46@t', 'full_name': 'T46', 'role': 'tutor', 'is_active': 1, 'school_id': 1});
    await db.insert('aral_irip_targets',
        {'id': 900, 'program': 'basic_ks23', 'strand': 'filipino', 'seq': 1, 'focus': 'f'});
  });

  tearDownAll(LocalDatabase.close);

  Future<void> setting(Map<String, Object?>? school, {Map<String, Object?>? region}) async {
    await db.delete('aral_settings');
    if (region != null) await db.insert('aral_settings', {'id': 1, 'school_id': null, 'settings': jsonEncode(region)});
    if (school != null) await db.insert('aral_settings', {'id': 2, 'school_id': 1, 'settings': jsonEncode(school)});
  }

  Future<int> newClass() async {
    final id = await nextLocalId(db);
    await db.insert('aral_classes', {'id': id, 'school_id': 1, 'school_year': _year, 'class_name': 'C$id',
        'grade_level': 7, 'program': 'ks3_basic', 'tutor_id': _tutor});
    return id;
  }

  Future<int> place(int? classId) async {
    final student = nextStudent++;
    await db.insert('students', {'id': student, 'lrn': '99999900$student', 'last_name': 'L$student', 'first_name': 'F', 'school_id': 1});
    await db.insert('enrollments', {'id': student, 'student_id': student, 'section_id': 46, 'school_year': _year});
    final id = await nextLocalId(db);
    await db.insert('aral_enrollments', {'id': id, 'student_id': student, 'school_id': 1, 'section_id': 46,
        'school_year': _year, 'key_stage': 'ks3', 'track': 'basic', 'class_id': classId, 'entered_on': '2026-11-02',
        'basis_source': 'manual'});
    return id;
  }

  Future<void> session(int classId, String on, {int minutes = 45, String setup = 'pull_out'}) async =>
      db.insert('aral_sessions', {'id': await nextLocalId(db), 'tutor_id': _tutor, 'school_id': 1, 'school_year': _year,
          'held_on': on, 'minutes': minutes, 'setup': setup, 'class_id': classId});

  Future<void> week(int enrollmentId, int weekNo) async => db.insert('aral_irip_weeks', {'id': await nextLocalId(db),
      'enrollment_id': enrollmentId, 'cycle_no': 1, 'week_no': weekNo, 'strand': 'filipino', 'target_id': 900});

  Matcher aborts(String text) =>
      throwsA(isA<DatabaseException>().having((e) => e.toString(), 'message', contains(text)));

  test('v45 IRIP weeks survive the rebuild', () async {
    await setting(null);
    final c = await newClass();
    final e = await place(c);
    // Put aral_irip_weeks back in its v45 shape (weeks 1-8), with 8 weeks.
    final sql = (await db.rawQuery("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'aral_irip_weeks'"))
        .single['sql'] as String;
    final v45 = sql.replaceAll('BETWEEN 1 AND 26', 'BETWEEN 1 AND 8');
    expect(v45, contains('BETWEEN 1 AND 8'));
    final cols = [for (final r in await db.rawQuery('PRAGMA table_info(aral_irip_weeks)')) r['name'] as String].join(', ');
    await db.execute('ALTER TABLE aral_irip_weeks RENAME TO aral_irip_weeks_old');
    await db.execute(v45);
    await db.execute('DROP TABLE aral_irip_weeks_old');
    await db.execute('PRAGMA user_version = 45');
    await LocalDatabase.close();
    db = await LocalDatabase.instance(dir);
    for (var w = 1; w <= 8; w++) {
      await week(e, w);
    }
    final ids = [for (final r in await db.query('aral_irip_weeks', orderBy: 'week_no')) r['id']];
    await db.execute('PRAGMA user_version = 45');
    await LocalDatabase.close();
    db = await LocalDatabase.instance(dir);

    expect((await db.rawQuery('PRAGMA user_version')).single.values.single as int, greaterThanOrEqualTo(46));
    final stored = (await db.rawQuery("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'aral_irip_weeks'"))
        .single['sql'] as String;
    expect(stored, contains('BETWEEN 1 AND 26'));
    expect([for (final r in await db.query('aral_irip_weeks', orderBy: 'week_no')) r['id']], ids);
    expect([for (final r in await db.rawQuery('PRAGMA table_info(aral_irip_weeks)')) r['name'] as String].join(', '), cols);
    expect(await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'aral_irip_weeks_enrollment'"),
        hasLength(1));
    // The device checks are back on the rebuilt table.
    await expectLater(week(e, 9), aborts('has 8 weeks'));
  });

  test('class max from the school setting', () async {
    await setting({'class_max_learners': 10});
    final c = await newClass();
    for (var i = 0; i < 10; i++) {
      await place(c);
    }
    await expectLater(place(c), aborts('at most 10'));
    await setting(null);
    final d = await newClass();
    for (var i = 0; i < 15; i++) {
      await place(d);
    }
    await expectLater(place(d), aborts('at most 15'));
    // The default row counts when the school has none; the school row wins over it.
    await setting(null, region: {'class_max_learners': 12});
    final r = await newClass();
    for (var i = 0; i < 12; i++) {
      await place(r);
    }
    await expectLater(place(r), aborts('at most 12'));
    await setting({'class_max_learners': 13}, region: {'class_max_learners': 12});
    await place(r);
  });

  test('over-max class still edits', () async {
    await setting(null);
    final c = await newClass();
    final ids = [for (var i = 0; i < 12; i++) await place(c)];
    await setting({'class_max_learners': 10});
    expect(await db.update('aral_enrollments', {'notes': 'still here'}, where: 'id = ?', whereArgs: [ids[0]]), 1);
    expect(
        await db.update('aral_enrollments', {'status': 'exited', 'exited_on': '2026-11-18', 'exit_reason': 'other'},
            where: 'id = ?', whereArgs: [ids[1]]),
        1);
    // A learner waiting for a class can't take a place in it.
    final waiting = await place(null);
    await expectLater(db.update('aral_enrollments', {'class_id': c}, where: 'id = ?', whereArgs: [waiting]),
        aborts('at most 10'));
  });

  test('weekday rule', () async {
    await setting({'sessions_weekdays_only': true});
    final c = await newClass();
    await expectLater(session(c, '2026-11-21'), aborts('Monday to Friday')); // Saturday
    await expectLater(session(c, '2026-11-22'), aborts('Monday to Friday')); // Sunday
    await expectLater(session(c, '2026-11-24', setup: 'weekend'), aborts('Monday to Friday'));
    await session(c, '2026-11-23');
    await expectLater(
        db.update('aral_sessions', {'held_on': '2026-11-28'}, where: 'class_id = ?', whereArgs: [c]),
        aborts('Monday to Friday'));
    expect(await db.update('aral_sessions', {'remarks': 'ok'}, where: 'class_id = ?', whereArgs: [c]), 1);
    await setting(null);
    await session(c, '2026-11-28', setup: 'weekend');
  });

  test('session max minutes', () async {
    await setting({'session_max_minutes': 60});
    final c = await newClass();
    await expectLater(session(c, '2026-11-16', minutes: 61), aborts('at most 60 minutes'));
    await session(c, '2026-11-16', minutes: 60);
    await expectLater(
        db.update('aral_sessions', {'minutes': 61}, where: 'class_id = ?', whereArgs: [c]), aborts('at most 60 minutes'));
    await setting(null);
    await session(c, '2026-11-17', minutes: 120);
  });

  test('IRIP weeks setting', () async {
    await setting({'irip_weeks': 6});
    final c = await newClass();
    final e = await place(c);
    for (var w = 1; w <= 6; w++) {
      await week(e, w);
    }
    await expectLater(week(e, 7), aborts('has 6 weeks'));
    await setting(null);
    await week(e, 7);
    await week(e, 8);
    await expectLater(week(e, 9), aborts('has 8 weeks'));
    await setting({'irip_weeks': 26});
    for (var w = 9; w <= 26; w++) {
      await week(e, w);
    }
    await expectLater(week(e, 27), aborts('has 26 weeks'));
  });
}
