// SF1 continuing learners (spec docs/superpowers/specs/2026-11-24-sf1-continuing-learners-design.md):
// a known LRN with no enrollment in the file's school year continues when its
// latest earlier enrollment is at this school, one grade lower or the same
// grade; a corrected name is updated and a blank birth date filled. Bigger
// jumps, lower grades and other schools stay conflicts.
//
// The "server" and the device copy are one SQLite file. Fixture names only.
import 'dart:io';

import 'package:basa_capstone/core/data/local/import_conflict_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/school_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/section_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/student_repository_sqlite.dart';
import 'package:basa_capstone/core/models/student.dart';
import 'package:basa_capstone/core/repositories/student_repository.dart';
import 'package:basa_capstone/core/services/sf1_column_map.dart';
import 'package:basa_capstone/core/services/sf1_importer.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _year = '2026-2027';
const _coord = '00000000-0000-0000-0000-00000000c080';

String _lrn(int id) => '99999980$id';

/// One SF1 row: LRN, last, first, middle, birth date (SF1 form MM-DD-YYYY).
typedef _Row = ({String lrn, String last, String first, String? middle, String? birth});

_Row _row(int id, {String? last, String first = 'Zed', String? middle, String? birth}) =>
    (lrn: _lrn(id), last: last ?? 'Fixture$id', first: first, middle: middle, birth: birth);

void main() {
  late Database db;
  late Sf1Importer importer;
  late Sf1Importer refusingImporter;
  final dir = Directory.systemTemp.createTempSync('basa_sf1_continuing_').path;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ80', 'school_name': 'ZZ Continuing School', 'region_id': 13});
    await db.insert('schools', {'id': 2, 'school_id': 'ZZ81', 'school_name': 'ZZ Other School', 'region_id': 13});
    for (final (id, school, year, grade) in [
      (81, 1, '2024-2025', '3'), (82, 1, '2025-2026', '2'), (83, 1, '2025-2026', '3'), (84, 1, '2025-2026', '4'),
      (85, 1, '2025-2026', '5'), (86, 1, _year, '4'), (91, 2, '2025-2026', '3'), (92, 2, _year, '4'),
    ]) {
      await db.insert('sections', {'id': id, 'school_id': school, 'school_year': year, 'grade_level': grade, 'section_name': 'G$grade-$id'});
    }
    var enrollmentId = 1;
    Future<void> learner(int id, List<(int section, String year, String status)> enrollments,
        {String? middle, String? birthDate}) async {
      await db.insert('students', {
        'id': id, 'lrn': _lrn(id), 'last_name': 'Fixture$id', 'first_name': 'Zed', 'school_id': 1,
        'middle_name': ?middle, 'birth_date': ?birthDate,
      });
      for (final (section, year, status) in enrollments) {
        await db.insert('enrollments', {
          'id': enrollmentId++, 'student_id': id, 'section_id': section, 'school_year': year, 'status': status,
          if (status != 'active') 'left_on': '2026-02-01',
          if (status != 'active') 'left_by': _coord,
        });
      }
    }

    await learner(8001, [(83, '2025-2026', 'active')]); // one grade up
    await learner(8002, [(84, '2025-2026', 'active')]); // same grade
    await learner(8003, [(83, '2025-2026', 'dropped_out')]); // back after leaving
    await learner(8004, [(81, '2024-2025', 'active')]); // gap year
    await learner(8005, [(82, '2025-2026', 'active')]); // two grades up
    await learner(8006, [(85, '2025-2026', 'active')]); // lower grade
    await learner(8007, [(91, '2025-2026', 'active')]); // other school last year
    await learner(8008, [(83, '2025-2026', 'active'), (92, _year, 'active')]); // this year elsewhere
    await learner(8009, [(83, '2025-2026', 'active')]); // corrected name
    await learner(8010, [(83, '2025-2026', 'active')]); // middle name added
    await learner(8011, [(83, '2025-2026', 'active')]); // blank birth date
    await learner(8012, [(83, '2025-2026', 'active')], birthDate: '2016-02-01'); // stored birth date
    // import() tests (each its own learner: an import changes the next trial).
    await learner(8101, [(83, '2025-2026', 'active')]); // enrolled by the import
    await learner(8102, [(83, '2025-2026', 'active')]); // name corrected by the import
    await learner(8103, [(83, '2025-2026', 'active')]); // imported twice
    await learner(8104, [(83, '2025-2026', 'active')]); // name update refused

    final schools = SchoolRepositorySqlite(db);
    final sections = SectionRepositorySqlite(db);
    final students = StudentRepositorySqlite(db);
    importer = Sf1Importer(
      schoolRepo: schools,
      localSchoolRepo: schools,
      sectionRepo: sections,
      localSectionRepo: sections,
      studentRepo: students,
      localStudentRepo: students,
      conflictRepo: ImportConflictRepositorySqlite(db),
      columnMap: await Sf1ColumnMap.load(dir),
    );
    refusingImporter = Sf1Importer(
      schoolRepo: schools,
      localSchoolRepo: schools,
      sectionRepo: sections,
      localSectionRepo: sections,
      studentRepo: _RefusesUpdate(students),
      localStudentRepo: students,
      conflictRepo: ImportConflictRepositorySqlite(db),
      columnMap: await Sf1ColumnMap.load(dir),
    );
  });

  tearDownAll(LocalDatabase.close);

  /// A 2026-2027 Grade 4 SF1 of school 1 (default column map).
  String sf1(List<_Row> rows) {
    final excel = Excel.createExcel();
    final sheet = excel[excel.tables.keys.first];
    void put(int r, int c, String v) =>
        sheet.updateCell(CellIndex.indexByColumnRow(rowIndex: r, columnIndex: c), TextCellValue(v));
    final m = importer.columnMap;
    put(2, 5, 'ZZ80');
    put(2, 10, 'Region X');
    put(3, 5, 'ZZ Continuing School');
    put(3, 19, _year);
    put(3, 30, '4');
    put(3, 38, 'G4-86');
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      put(6 + i, m.lrn, r.lrn);
      put(6 + i, m.lastName, r.last);
      put(6 + i, m.firstName, r.first);
      if (r.middle != null) put(6 + i, m.middleName, r.middle!);
      put(6 + i, m.sex, 'M');
      if (r.birth != null) put(6 + i, m.birthDate, r.birth!);
    }
    final path = '$dir/sf1_${DateTime.now().microsecondsSinceEpoch}.xlsx';
    File(path).writeAsBytesSync(excel.save()!);
    return path;
  }

  Future<Sf1TrialRow> trialRow(_Row row) async =>
      (await importer.trial(sf1([row]))).rows.singleWhere((r) => r.lrn == row.lrn);

  test('one grade up continues', () async {
    final r = await trialRow(_row(8001));
    expect(r.outcome, 'continuing');
    expect(r.reason, 'moving up from Grade 3 (2025-2026)');
    expect(r.existingStudentId, 8001);
    expect(r.updatesName, isFalse);
  });

  test('same grade continues as repeating', () async {
    final r = await trialRow(_row(8002));
    expect(r.outcome, 'continuing');
    expect(r.reason, 'repeating Grade 4');
  });

  test('back after leaving', () async {
    final r = await trialRow(_row(8003));
    expect(r.outcome, 'continuing');
    expect(r.reason, 'moving up from Grade 3 (2025-2026), back after leaving (dropped out, 2025-2026)');
  });

  test('gap year', () async {
    final r = await trialRow(_row(8004));
    expect(r.outcome, 'continuing');
    expect(r.reason, 'moving up from Grade 3 (2024-2025), last here in 2024-2025');
  });

  test('two grades up is a conflict', () async {
    final r = await trialRow(_row(8005));
    expect(r.outcome, 'conflict');
    expect(r.reason, 'last enrolled here in Grade 2 (2025-2026): Grade 4 is not the next grade');
  });

  test('lower grade is a conflict', () async {
    final r = await trialRow(_row(8006));
    expect(r.outcome, 'conflict');
    expect(r.reason, 'last enrolled here in Grade 5 (2025-2026): Grade 4 is not the next grade');
  });

  test('other school stays the generic conflict', () async {
    final r = await trialRow(_row(8007));
    expect(r.outcome, 'conflict');
    expect(r.reason, startsWith('LRN already exists'));
  });

  test('this-year enrollment elsewhere wins', () async {
    final r = await trialRow(_row(8008));
    expect(r.outcome, 'conflict');
    expect(r.reason, startsWith('LRN already exists'));
  });

  test('corrected name', () async {
    final r = await trialRow(_row(8009, last: 'Fixtura8009'));
    expect(r.outcome, 'continuing');
    expect(r.updatesName, isTrue);
    expect(r.previousName, 'Fixture8009, Zed');
    expect(r.reason, 'moving up from Grade 3 (2025-2026), name corrected: Fixture8009, Zed -> Fixtura8009, Zed');
  });

  test('middle name added', () async {
    final r = await trialRow(_row(8010, middle: 'Q'));
    expect(r.updatesName, isTrue);
    expect(r.reason, endsWith('name corrected: Fixture8010, Zed -> Fixture8010, Zed Q'));
  });

  test('blank birth date filled, stored one kept', () async {
    expect((await trialRow(_row(8011, birth: '03-01-2016'))).fillsBirthDate, isTrue);
    expect((await trialRow(_row(8012, birth: '03-01-2016'))).fillsBirthDate, isFalse);
  });

  test('trial writes nothing', () async {
    Future<int> count(String t) async => (await db.rawQuery('SELECT COUNT(*) AS n FROM $t')).single['n'] as int;
    final before = (await count('enrollments'), await count('students'));
    final t = await importer.trial(sf1([_row(8001), _row(8009, last: 'Fixtura8009')]));
    expect(t.wouldContinue, 2);
    expect((await count('enrollments'), await count('students')), before);
    final stored = await db.query('students', where: 'id = 8009');
    expect(stored.single['last_name'], 'Fixture8009');
  });

  Future<List<Map<String, Object?>>> enrollmentsOf(int studentId) =>
      db.query('enrollments', where: 'student_id = ?', whereArgs: [studentId], orderBy: 'school_year');

  test('import enrolls continuing learners and logs no conflict', () async {
    final result = await importer.import(sf1([_row(8101)]));
    expect(result.continuing, 1);
    expect(result.conflicts, 0);
    expect(result.inserted, 0);
    final e = await enrollmentsOf(8101);
    expect(e.map((r) => (r['school_year'], r['section_id'], r['status'])),
        [('2025-2026', 83, 'active'), (_year, 86, 'active')]);
    expect(await db.query('import_conflicts', where: 'lrn = ?', whereArgs: [_lrn(8101)]), isEmpty);
  });

  test('import updates a corrected name', () async {
    final result = await importer.import(sf1([_row(8102, last: 'Fixtura8102', middle: 'Q')]));
    expect(result.continuing, 1);
    final s = (await db.query('students', where: 'id = 8102')).single;
    expect((s['last_name'], s['first_name'], s['middle_name']), ('Fixtura8102', 'Zed', 'Q'));
  });

  test('re-import of the same file gives already enrolled', () async {
    final path = sf1([_row(8103)]);
    expect((await importer.import(path)).continuing, 1);
    final again = await importer.import(path);
    expect(again.continuing, 0);
    expect(again.alreadyEnrolled, 1);
    expect(again.conflicts, 0);
    expect((await enrollmentsOf(8103)).where((r) => r['school_year'] == _year), hasLength(1));
  });

  test('refused name update: a warning, still enrolled', () async {
    final result = await refusingImporter.import(sf1([_row(8104, last: 'Fixtura8104')]));
    expect(result.continuing, 1);
    expect(result.rowWarnings, [contains("name not updated (this learner can't be changed)")]);
    expect((await db.query('students', where: 'id = 8104')).single['last_name'], 'Fixture8104');
    expect((await enrollmentsOf(8104)).last['school_year'], _year);
  });
}

/// The repository, except that the "server" refuses every learner update
/// (RLS, or the learner was anonymized meanwhile).
class _RefusesUpdate implements StudentRepository {
  final StudentRepository inner;
  _RefusesUpdate(this.inner);

  @override
  Future<void> update(Student student) async => throw Exception('refused by the server');

  @override
  dynamic noSuchMethod(Invocation invocation) => Function.apply(
        switch (invocation.memberName) {
          #findByLrn => inner.findByLrn,
          #insert => inner.insert,
          #fillBlankBirthDate => inner.fillBlankBirthDate,
          #getAll => inner.getAll,
          #getBySection => inner.getBySection,
          #activeSectionId => inner.activeSectionId,
          #enrollmentInYear => inner.enrollmentInYear,
          #latestEnrollmentBefore => inner.latestEnrollmentBefore,
          #enroll => inner.enroll,
          #upsertWithId => inner.upsertWithId,
          _ => throw UnimplementedError('${invocation.memberName}'),
        },
        invocation.positionalArguments,
        invocation.namedArguments,
      );
}
