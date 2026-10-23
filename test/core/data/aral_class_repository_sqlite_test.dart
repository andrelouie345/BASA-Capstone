// ARAL classes on the device (aral_classes, aral_local_schema.dart): negative
// ids, the name rule and the local checks for rows made here.
import 'dart:io';

import 'package:basa_capstone/core/data/local/aral_class_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/models/aral_class.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late AralClassRepositorySqlite repo;
  const t1 = '00000000-0000-0000-0000-0000000093a1';
  const t2 = '00000000-0000-0000-0000-0000000093a2';
  const tb = '00000000-0000-0000-0000-0000000093b1';
  const coord = '00000000-0000-0000-0000-0000000093c1';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_classes_').path);
    repo = AralClassRepositorySqlite(db);
    await db.insert('schools', {'id': 9301, 'school_id': 'ZZK1', 'school_name': 'ZZ Classes A'});
    await db.insert('schools', {'id': 9302, 'school_id': 'ZZK2', 'school_name': 'ZZ Classes B'});
    for (final (id, role, school, active) in [
      (t1, 'tutor', 9301, 1),
      (t2, 'tutor', 9301, 1),
      (tb, 'tutor', 9302, 1),
      (coord, 'coordinator', 9301, 1),
      ('00000000-0000-0000-0000-0000000093a9', 'tutor', 9301, 0),
    ]) {
      await db.insert('users', {'id': id, 'email': '$id@zz', 'full_name': id, 'role': role, 'school_id': school, 'is_active': active});
    }
  });

  tearDownAll(LocalDatabase.close);

  AralClass cls(String name,
          {String year = '2026-2027',
          AralClassProgram program = AralClassProgram.ks3Basic,
          AralGradeBand band = AralGradeBand.g7to10,
          String? tutor,
          int school = 9301}) =>
      AralClass(schoolId: school, schoolYear: year, className: name, program: program, gradeBand: band, tutorId: tutor);

  test('a new class gets a negative id and its stamps', () async {
    final c = await repo.insert(cls('7-Rose', tutor: t1));
    expect(c.id, isNegative);
    expect(c.createdAt, isNotNull);
    expect((await repo.findById(c.id!))!.className, '7-Rose');
  });

  test('the name is unique per school and year, ignoring case and outer spaces', () async {
    await expectLater(repo.insert(cls(' 7-rose ')), throwsA(isA<DatabaseException>()));
    expect((await repo.insert(cls('7-Rose', year: '2027-2028'))).id, isNegative);
    expect((await repo.insert(cls('7-Rose', school: 9302))).id, isNegative);
  });

  test('getByTutor and getBySchool', () async {
    await repo.insert(cls('7-Lily', tutor: t2));
    await repo.insert(cls('2-Sun', program: AralClassProgram.ks1, band: AralGradeBand.g1to3, tutor: t1));
    expect((await repo.getByTutor(t1, schoolYear: '2026-2027')).map((c) => c.className), ['2-Sun', '7-Rose']);
    expect((await repo.getByTutor(t2)).map((c) => c.className), ['7-Lily']);
    expect((await repo.getBySchool(9301, schoolYear: '2026-2027')).map((c) => c.className), ['2-Sun', '7-Lily', '7-Rose']);
    expect((await repo.getBySchool(9301)).length, 4);
  });

  test('update saves the changeable fields; delete removes the class', () async {
    final c = (await repo.getBySchool(9301, schoolYear: '2026-2027')).firstWhere((c) => c.className == '7-Lily');
    final saved = await repo.update(c.copyWith(className: '7-Lilac', tutorId: () => null, room: () => 'Rm 2'));
    expect(saved.className, '7-Lilac');
    expect(saved.tutorId, isNull);
    expect(saved.room, 'Rm 2');
    await repo.delete(c.id!);
    expect(await repo.findById(c.id!), isNull);
  });

  test('unknown program or band is refused', () async {
    Future<void> raw(String program, String band) => db.insert('aral_classes', {
          'id': -900, 'school_id': 9301, 'school_year': '2026-2027', 'class_name': 'Bad', 'program': program,
          'grade_band': band, 'created_at': 'x', 'updated_at': 'x'});
    await expectLater(raw('ks2', '4-6'), throwsA(isA<DatabaseException>()));
    await expectLater(raw('ks1', '1-2'), throwsA(isA<DatabaseException>()));
    await expectLater(raw('ks1', '1-3').then((_) => db.delete('aral_classes', where: 'id = -900')), completes);
  });

  test('a blank name or a bad school year is refused', () async {
    await expectLater(repo.insert(cls('   ')), throwsA(isA<DatabaseException>()));
    await expectLater(repo.insert(cls('Q', year: '2026-2028')), throwsA(isA<DatabaseException>()));
  });

  test('the local trigger checks the tutor of a class made here', () async {
    for (final bad in [tb, coord, '00000000-0000-0000-0000-0000000093a9']) {
      await expectLater(repo.insert(cls('7-X', tutor: bad)),
          throwsA(predicate((e) => '$e'.contains("The ARAL class tutor must be an active tutor of the class's school"))),
          reason: bad);
    }
    final c = await repo.insert(cls('7-Y'));
    await expectLater(repo.update(c.copyWith(tutorId: () => tb)),
        throwsA(predicate((e) => '$e'.contains("The ARAL class tutor must be an active tutor"))));
  });

  test('a class keeps its school and year', () async {
    final c = await repo.insert(cls('7-Z'));
    await expectLater(db.update('aral_classes', {'school_year': '2027-2028'}, where: 'id = ?', whereArgs: [c.id]),
        throwsA(predicate((e) => '$e'.contains('An ARAL class keeps its school and school year'))));
  });

  test('a mirrored class keeps its cloud id and is not re-checked', () async {
    final m = await repo.upsertWithId(
        const AralClass(id: 812, schoolId: 9302, schoolYear: '2026-2027', className: 'B-1', program: AralClassProgram.ks1,
            gradeBand: AralGradeBand.g1to3, tutorId: '00000000-0000-0000-0000-0000000093a9'));
    expect(m.id, 812);
    final row = (await db.query('aral_classes', where: 'id = 812')).single;
    expect(row['origin'], 'cloud');
  });
}
