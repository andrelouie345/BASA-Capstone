// v47 (ARAL memo, people; spec docs/superpowers/specs/2026-11-18-aral-division-memo-design.md
// sections 3 and 6; cloud 20261118030000): sections.adviser_name /
// adviser_user_id, users.tutor_type, aral_classes.session_type on the device;
// the device triggers check the adviser rule (placement, class tutor change)
// and the daily tutor limits like the cloud (owner 2026-11-18: all three
// places). A section update keeps its adviser.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/data/local/aral_class_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/section_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/sync_local_writes.dart';
import 'package:basa_capstone/core/data/local/user_repository_sqlite.dart';
import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:basa_capstone/core/models/section.dart';
import 'package:basa_capstone/core/models/user.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/viewmodels/section_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/fake_online_auth.dart';

const _year = '2026-2027';
const _adviser = 'tutor-adviser';
const _other = 'tutor-other';
const _external = 'tutor-external';

void main() {
  late Database db;
  final dir = Directory.systemTemp.createTempSync('basa_v47_').path;
  var nextStudent = 4700;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ47A', 'school_name': 'ZZ v47 A'});
    for (final (id, name, type) in [
      (_adviser, 'Adviser', 'internal'),
      (_other, 'Other', null),
      (_external, 'External', 'external'),
    ]) {
      await db.insert('users', {'id': id, 'email': '$id@t', 'full_name': name, 'role': 'tutor', 'is_active': 1,
          'school_id': 1, 'tutor_type': type});
    }
    await db.insert('sections', {'id': 47, 'school_id': 1, 'school_year': _year, 'grade_level': '7',
        'section_name': 'ALUMINUM', 'adviser_name': 'Ms. Cruz', 'adviser_user_id': _adviser});
    await db.insert('sections', {'id': 48, 'school_id': 1, 'school_year': _year, 'grade_level': '7',
        'section_name': 'BORON'});
  });

  tearDownAll(LocalDatabase.close);

  Future<void> setting(Map<String, Object?>? school) async {
    await db.delete('aral_settings');
    if (school != null) await db.insert('aral_settings', {'id': 2, 'school_id': 1, 'settings': jsonEncode(school)});
  }

  Future<int> newClass({String? tutor}) async {
    final id = await nextLocalId(db);
    await db.insert('aral_classes', {'id': id, 'school_id': 1, 'school_year': _year, 'class_name': 'C$id',
        'grade_level': 7, 'program': 'ks3_basic', 'tutor_id': tutor});
    return id;
  }

  Future<int> place(int? classId, {int section = 47}) async {
    final student = nextStudent++;
    await db.insert('students',
        {'id': student, 'lrn': '99999900$student', 'last_name': 'Lopez', 'first_name': 'Ana$student', 'school_id': 1});
    await db.insert('enrollments', {'id': student, 'student_id': student, 'section_id': section, 'school_year': _year});
    final id = await nextLocalId(db);
    await db.insert('aral_enrollments', {'id': id, 'student_id': student, 'school_id': 1, 'section_id': section,
        'school_year': _year, 'key_stage': 'ks3', 'track': 'basic', 'class_id': classId, 'entered_on': '2026-11-02',
        'basis_source': 'manual'});
    return id;
  }

  Future<int> session(String tutor, int classId, String on, {int minutes = 45}) async {
    final id = await nextLocalId(db);
    await db.insert('aral_sessions', {'id': id, 'tutor_id': tutor, 'school_id': 1, 'school_year': _year,
        'held_on': on, 'minutes': minutes, 'setup': 'pull_out', 'class_id': classId});
    return id;
  }

  Matcher aborts(String text) =>
      throwsA(isA<DatabaseException>().having((e) => e.toString(), 'message', contains(text)));

  Future<Set<String>> columns(String table) async =>
      {for (final c in await db.rawQuery('PRAGMA table_info($table)')) c['name'] as String};

  test('a v46 database gains the three columns and keeps its rows', () async {
    // Put the tables back in their v46 shape: drop the new columns (and the
    // triggers that read them; the upgrade recreates them).
    final triggers = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'trigger' AND "
        "(sql LIKE '%adviser_user_id%' OR sql LIKE '%tutor_type%' OR sql LIKE '%session_type%' OR sql LIKE '%adviser_tutors_own_class%')");
    for (final t in triggers) {
      await db.execute('DROP TRIGGER ${t['name']}');
    }
    await db.execute('DROP INDEX IF EXISTS sections_adviser_user');
    for (final (table, column) in [
      ('sections', 'adviser_name'),
      ('sections', 'adviser_user_id'),
      ('users', 'tutor_type'),
      ('aral_classes', 'session_type'),
    ]) {
      await db.execute('ALTER TABLE $table DROP COLUMN $column');
    }
    final c = await newClass(tutor: _other);
    await db.execute('PRAGMA user_version = 46');
    await LocalDatabase.close();
    db = await LocalDatabase.instance(dir);

    expect((await db.rawQuery('PRAGMA user_version')).single.values.single as int, greaterThanOrEqualTo(47));
    expect(await columns('sections'), containsAll(['adviser_name', 'adviser_user_id']));
    expect(await columns('users'), contains('tutor_type'));
    expect(await columns('aral_classes'), contains('session_type'));
    expect(await db.query('sections'), hasLength(2));
    expect(await db.query('users'), hasLength(3));
    expect((await db.query('aral_classes', where: 'id = ?', whereArgs: [c])).single['tutor_id'], _other);
    // Put the fixture's values back.
    await db.update('sections', {'adviser_name': 'Ms. Cruz', 'adviser_user_id': _adviser}, where: 'id = 47');
    await db.update('users', {'tutor_type': 'internal'}, where: 'id = ?', whereArgs: [_adviser]);
    await db.update('users', {'tutor_type': 'external'}, where: 'id = ?', whereArgs: [_external]);
    // The device checks are back on.
    await setting({'adviser_tutors_own_class': false});
    final mine = await newClass(tutor: _adviser);
    await expectLater(place(mine), aborts('does not tutor their own learners'));
    await setting(null);
  });

  test('models round-trip through the SQLite repositories', () async {
    final sections = SectionRepositorySqlite(db);
    final s = await sections.getOrCreate(Section(schoolId: 1, schoolYear: _year, gradeLevel: '7', sectionName: 'COBALT',
        adviserName: 'Mr. Reyes', adviserUserId: _other));
    final back = (await sections.getById(s.id!))!;
    expect(back.adviserName, 'Mr. Reyes');
    expect(back.adviserUserId, _other);

    final users = UserRepositorySqlite(db);
    // Written as the pull writes it (UserRepositorySqlite.create is unused and
    // passes is_active as a bool, which sqflite refuses).
    final row = User(id: 'tutor-new', email: 'new@t', fullName: 'New', role: UserRole.tutor,
            createdAt: DateTime.utc(2026, 11, 19), schoolId: 1, tutorType: TutorType.external)
        .toMap();
    await db.insert('users', serverRowToLocal(row, await columns('users')));
    expect((await users.getById('tutor-new'))!.tutorType, TutorType.external);
    expect((await users.getById(_other))!.tutorType, isNull);
    expect(TutorType.fromValue('internal'), TutorType.internal);
    expect(TutorType.internal.value, 'internal');

    final classes = AralClassRepositorySqlite(db);
    final k = await classes.insert(AralClass(schoolId: 1, schoolYear: _year, className: 'ARAL-R-G7-01', gradeLevel: 7,
        sessionType: AralSessionType.pullOut));
    expect(k.sessionType, AralSessionType.pullOut);
    final changed = await classes.update(k.copyWith(sessionType: () => AralSessionType.beforeAfter));
    expect(changed.sessionType, AralSessionType.beforeAfter);
    expect(changed.toMap()['session_type'], 'before_after');
    final cleared = await classes.update(changed.copyWith(sessionType: () => null));
    expect(cleared.sessionType, isNull);
    expect(AralSessionType.beforeAfter.label, 'Before/after class');
  });

  test('pulled rows keep the new columns', () async {
    final pulled = serverRowToLocal({
      'id': 900, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'DUBNIUM',
      'adviser_name': 'Ms. Santos', 'adviser_user_id': _adviser,
    }, await columns('sections'));
    await SectionRepositorySqlite(db).upsertWithId(Section.fromMap(pulled));
    final s = (await SectionRepositorySqlite(db).getById(900))!;
    expect((s.adviserName, s.adviserUserId), ('Ms. Santos', _adviser));

    await AralClassRepositorySqlite(db).upsertWithId(AralClass.fromMap({
      'id': 901, 'school_id': 1, 'school_year': _year, 'class_name': 'Pulled', 'grade_level': 7,
      'session_type': 'before_after',
    }));
    expect((await AralClassRepositorySqlite(db).findById(901))!.sessionType, AralSessionType.beforeAfter);

    final user = User.fromMap({'id': 'u-pulled', 'email': 'p@t', 'full_name': 'P', 'role': 'tutor', 'school_id': 1,
        'is_active': true, 'created_at': '2026-11-19T00:00:00Z', 'tutor_type': 'internal'});
    expect(user.tutorType, TutorType.internal);
    expect(user.toMap()['tutor_type'], 'internal');
  });

  test('adviser rule: placement and class tutor change', () async {
    await setting(null);
    final mine = await newClass(tutor: _adviser);
    await place(mine); // allowed by default

    await setting({'adviser_tutors_own_class': false});
    await expectLater(place(mine), aborts('does not tutor their own learners'));
    await expectLater(place(mine), aborts('ALUMINUM'));
    await place(mine, section: 48); // another section
    final waiting = await place(null);
    await expectLater(db.update('aral_enrollments', {'class_id': mine}, where: 'id = ?', whereArgs: [waiting]),
        aborts('does not tutor their own learners'));
    final noTutor = await newClass();
    await place(noTutor);
    await expectLater(db.update('aral_classes', {'tutor_id': _adviser}, where: 'id = ?', whereArgs: [noTutor]),
        aborts('does not tutor their own learners'));
    final others = await newClass(tutor: _other);
    await place(others, section: 48);
    expect(await db.update('aral_classes', {'tutor_id': _adviser}, where: 'id = ?', whereArgs: [others]), 1);
    expect(await db.update('aral_classes', {'room': 'Library'}, where: 'id = ?', whereArgs: [mine]), 1);

    // A turned-off adviser still advises the section.
    await db.update('users', {'is_active': 0}, where: 'id = ?', whereArgs: [_adviser]);
    await expectLater(place(mine), aborts('does not tutor their own learners'));
    await db.update('users', {'is_active': 1}, where: 'id = ?', whereArgs: [_adviser]);

    await setting({'adviser_tutors_own_class': true});
    await place(mine);
    await setting(null);
  });

  test('daily tutor limits', () async {
    await setting({'internal_tutor_max_sessions_per_day': 2, 'external_tutor_max_minutes_per_day': 120});
    final a = await newClass(), b = await newClass(), c = await newClass();
    await session(_adviser, a, '2026-11-16');
    await session(_adviser, b, '2026-11-16');
    await expectLater(session(_adviser, c, '2026-11-16'), aborts('at most 2 ARAL sessions a day'));
    await expectLater(session(_adviser, c, '2026-11-16'), aborts('internal tutor'));
    final next = await session(_adviser, c, '2026-11-17');
    await expectLater(db.update('aral_sessions', {'held_on': '2026-11-16'}, where: 'id = ?', whereArgs: [next]),
        aborts('at most 2 ARAL sessions a day'));
    expect(await db.update('aral_sessions', {'remarks': 'ok'}, where: 'id = ?', whereArgs: [next]), 1);

    final e1 = await session(_external, a, '2026-11-18', minutes: 60);
    await session(_external, b, '2026-11-18', minutes: 60);
    await expectLater(session(_external, c, '2026-11-18', minutes: 1), aborts('at most 120 minutes'));
    await expectLater(session(_external, c, '2026-11-18', minutes: 1), aborts('external tutor'));
    await expectLater(db.update('aral_sessions', {'minutes': 61}, where: 'id = ?', whereArgs: [e1]),
        aborts('at most 120 minutes'));
    expect(await db.update('aral_sessions', {'minutes': 50}, where: 'id = ?', whereArgs: [e1]), 1);

    // No type: no limit.
    await session(_other, a, '2026-11-19', minutes: 120);
    await session(_other, b, '2026-11-19', minutes: 120);
    await session(_other, c, '2026-11-19', minutes: 120);
    // A type set later: the saved day stays editable, a new session is checked.
    await db.update('users', {'tutor_type': 'internal'}, where: 'id = ?', whereArgs: [_other]);
    expect(await db.update('aral_sessions', {'remarks': 'kept'}, where: "tutor_id = ? AND held_on = '2026-11-19'",
        whereArgs: [_other]), 3);
    final d = await newClass();
    await expectLater(session(_other, d, '2026-11-19'), aborts('at most 2 ARAL sessions a day'));
    await db.update('users', {'tutor_type': null}, where: 'id = ?', whereArgs: [_other]);

    await setting(null);
    await session(_adviser, d, '2026-11-16'); // no limit without the setting
  });

  test('a section update keeps its adviser', () async {
    final vm = SectionViewModel(auth: FakeOnlineAuth(UserRole.coordinator), repoFactory: (_) => SectionRepositorySqlite(db));
    final updated = await vm.update(id: 47, schoolYear: _year, gradeLevel: '7', sectionName: 'ALUMINUM 2');
    expect(updated.sectionName, 'ALUMINUM 2');
    final stored = (await SectionRepositorySqlite(db).getById(47))!;
    expect((stored.adviserName, stored.adviserUserId), ('Ms. Cruz', _adviser));
  });
}
