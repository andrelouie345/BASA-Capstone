// SF1 leavers, the import trial (spec docs/superpowers/specs/2026-11-12-sf1-leavers-design.md,
// section 2; D6-D8): a row whose learner is active in another section of the
// same school and grade is "moving", another grade stays a conflict, an
// archived learner of the school is "returning", an anonymized learner never
// matches (their LRN changed), and the learners active in the file's section
// but not on the file are listed as missing. import() never applies moving
// or returning rows and never logs them as conflicts.
//
// Both the "server" and the device copy are one SQLite file here: the
// importer only needs the repository interfaces. Fixture names only.
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
const _coord = '00000000-0000-0000-0000-00000000c045';

String _lrn(int id) => '99999910$id';

void main() {
  late Database db;
  late Sf1Importer importer;
  final dir = Directory.systemTemp.createTempSync('basa_sf1_leavers_').path;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ45', 'school_name': 'ZZ Leavers School', 'region_id': 13});
    await db.insert('schools', {'id': 2, 'school_id': 'ZZ46', 'school_name': 'ZZ Other School', 'region_id': 13});
    for (final (id, school, grade, name) in [
      (41, 1, '4', 'G4-A'), (42, 1, '4', 'G4-B'), (43, 1, '4', 'G4-Fill'), (51, 1, '5', 'G5-A'), (61, 2, '4', 'G4-Other'),
    ]) {
      await db.insert('sections', {'id': id, 'school_id': school, 'school_year': _year, 'grade_level': grade, 'section_name': name});
    }
    Future<void> learner(int id, int section,
        {String status = 'active', String? lrn, bool anonymized = false, int school = 1}) async {
      await db.insert('students', {
        'id': id, 'lrn': lrn ?? _lrn(id), 'last_name': anonymized ? 'Anonymized' : 'Fixture$id',
        'first_name': anonymized ? '—' : 'Zed', 'school_id': school,
        if (anonymized) 'anonymized_at': '2027-08-01T00:00:00Z',
      });
      await db.insert('enrollments', {
        'id': id, 'student_id': id, 'section_id': section, 'school_year': _year, 'status': status,
        if (status != 'active') 'left_on': '2026-10-01',
        if (status != 'active') 'left_by': _coord,
      });
    }

    await learner(4501, 42); // G4-B, same grade -> moving
    await learner(4502, 51); // G5-A, other grade -> conflict
    await learner(4503, 42, status: 'dropped_out'); // archived -> returning
    await learner(4504, 42, status: 'transferred_out', lrn: 'ANON-4504', anonymized: true); // old LRN on the file -> insert
    await learner(4505, 41); // on the file, already here -> enrolled
    await learner(4506, 41); // not on the file -> missing
    await learner(4507, 41, status: 'dropped_out'); // archived here: not missing; on the file -> returning
    await learner(4508, 51, status: 'dropped_out'); // archived, other grade -> conflict (can't restore)
    await learner(4509, 61, school: 2); // active at another school, same grade -> generic conflict
    // Birth date fill (owner 2026-11-16, option A): enrolled in G4-Fill.
    await learner(4701, 43); // blank -> filled from the file
    await learner(4702, 43); // stored date -> never changed
    await db.update('students', {'birth_date': '2012-01-01'}, where: 'id = 4702');
    await learner(4703, 43); // blank, unreadable on the file -> stays blank
    await learner(4704, 43); // blank, the server refuses the fill -> warning

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
  });

  tearDownAll(LocalDatabase.close);

  /// An SF1 of G4-A (default column map) with the given LRNs, one row each.
  String sf1(List<String> lrns, {String section = 'G4-A', String grade = '4', Map<int, String> birthDates = const {}}) {
    final excel = Excel.createExcel();
    final sheet = excel[excel.tables.keys.first];
    void put(int r, int c, String v) =>
        sheet.updateCell(CellIndex.indexByColumnRow(rowIndex: r, columnIndex: c), TextCellValue(v));
    put(2, 5, 'ZZ45');
    put(2, 10, 'Region X');
    put(3, 5, 'ZZ Leavers School');
    put(3, 19, _year);
    put(3, 30, grade);
    put(3, 38, section);
    for (var i = 0; i < lrns.length; i++) {
      put(6 + i, 0, lrns[i]);
      put(6 + i, 2, 'Filerow$i');
      put(6 + i, 3, 'Zed');
      put(6 + i, 6, 'M');
      final b = birthDates[i];
      if (b != null) put(6 + i, importer.columnMap.birthDate, b);
    }
    final path = '$dir/sf1_${DateTime.now().microsecondsSinceEpoch}.xlsx';
    File(path).writeAsBytesSync(excel.save()!);
    return path;
  }

  Sf1TrialRow rowFor(Sf1TrialResult t, String lrn) => t.rows.singleWhere((r) => r.lrn == lrn);

  test('moving row for same grade', () async {
    final t = await importer.trial(sf1([_lrn(4501)]));
    final r = rowFor(t, _lrn(4501));
    expect(r.outcome, 'moving');
    expect(r.fromSectionId, 42);
    expect(r.fromSectionName, 'G4-B');
    expect(r.enrollmentId, 4501);
    expect(r.existingStudentId, 4501);
    expect(r.reason, 'moving from G4-B');
  });

  test('other grade stays a conflict', () async {
    final t = await importer.trial(sf1([_lrn(4502)]));
    final r = rowFor(t, _lrn(4502));
    expect(r.outcome, 'conflict');
    expect(r.reason, "active in G5-A (Grade 5): other grade, can't move");
    expect(r.existingStudentId, 4502);
    expect(r.enrollmentId, isNull);
  });

  test('returning row for archived learner', () async {
    final t = await importer.trial(sf1([_lrn(4503)]));
    final r = rowFor(t, _lrn(4503));
    expect(r.outcome, 'returning');
    expect(r.enrollmentId, 4503);
    expect(r.leftOn, '2026-10-01');
    expect(r.leftReason, 'dropped_out');
    expect(r.reason, 'archived on 2026-10-01, dropped out');
    expect(r.fromSectionId, 42); // archived in G4-B, on G4-A's file
    expect(r.fromSectionName, 'G4-B');
  });

  test('archived learner of another grade is a conflict', () async {
    final t = await importer.trial(sf1([_lrn(4508)]));
    final r = rowFor(t, _lrn(4508));
    expect(r.outcome, 'conflict');
    expect(r.reason, "archived in G5-A (Grade 5): other grade, can't restore");
    expect(r.existingStudentId, 4508);
    expect(r.enrollmentId, isNull);
  });

  test('learner active at another school keeps the generic conflict', () async {
    final t = await importer.trial(sf1([_lrn(4509)]));
    final r = rowFor(t, _lrn(4509));
    expect(r.outcome, 'conflict');
    expect(r.reason, 'LRN already exists (existing student id 4509)');
    expect(r.existingStudentId, 4509);
    expect(r.enrollmentId, isNull);
    expect(r.fromSectionId, isNull);
  });

  test("learner archived in the file's own section is returning", () async {
    final t = await importer.trial(sf1([_lrn(4507)]));
    final r = rowFor(t, _lrn(4507));
    expect(r.outcome, 'returning');
    expect(r.enrollmentId, 4507);
    expect(r.leftOn, '2026-10-01');
    expect(r.leftReason, 'dropped_out');
    expect(r.reason, 'archived on 2026-10-01, dropped out');
    expect(r.fromSectionName, 'G4-A');
  });

  test('anonymized learner is a plain insert', () async {
    final t = await importer.trial(sf1([_lrn(4504)]));
    final r = rowFor(t, _lrn(4504));
    expect(r.outcome, 'insert');
    expect(r.existingStudentId, isNull);
    expect(r.enrollmentId, isNull);
  });

  test('missing lists active learners not in the file', () async {
    final t = await importer.trial(sf1([_lrn(4505)]));
    expect(rowFor(t, _lrn(4505)).outcome, 'enrolled');
    expect(t.missing.map((m) => (m.enrollmentId, m.studentId, m.lrn, m.name)).toList(),
        [(4506, 4506, _lrn(4506), 'Fixture4506, Zed')]);
    // A section the school doesn't hold yet has nobody missing.
    expect((await importer.trial(sf1([_lrn(4505)], section: 'G4-New'))).missing, isEmpty);
  });

  // The file's section id: what "Move here" / "Restore here" take (row 61).
  test('trial gives the file section id, null for a new section', () async {
    expect((await importer.trial(sf1([_lrn(4505)]))).sectionId, 41);
    expect((await importer.trial(sf1([_lrn(4505)], section: 'G4-New'))).sectionId, isNull);
  });

  // Owner 2026-11-15, option i: a birth date that can't be read is left
  // blank with a row warning; the learner is still imported (the old code
  // turned "2013-03-15" into "15-2013-03" and the server refused the import
  // after the section was made).
  test('birth dates: SF1 and ISO forms read; an unreadable one is left blank with a warning', () async {
    final lrns = [_lrn(4601), _lrn(4602), _lrn(4603)];
    final path = sf1(lrns, birthDates: {0: '03-15-2013', 1: '2013-03-16 00:00:00', 2: '15/13/2013'});
    final t = await importer.trial(path);
    expect(t.parsedStudents.values.map((s) => s.birthDate).toList(), ['2013-03-15', '2013-03-16', null]);
    expect(rowFor(t, _lrn(4603)).warning, 'birth date "15/13/2013" can\'t be read: left blank');
    expect(t.rowWarnings, ['Row 9 Filerow2, Zed: birth date "15/13/2013" can\'t be read: left blank']);
    expect(rowFor(t, _lrn(4601)).warning, isNull);

    final result = await importer.import(path);
    expect(result.inserted, 3);
    expect(result.rowWarnings, t.rowWarnings);
    final stored = {
      for (final r in await db.query('students', where: "lrn IN ('${lrns.join("','")}')")) r['lrn']: r['birth_date'],
    };
    expect(stored, {_lrn(4601): '2013-03-15', _lrn(4602): '2013-03-16', _lrn(4603): null});
  });

  // Owner 2026-11-16, option A: a re-import fills a blank birth date of a
  // learner already enrolled in the section; a stored one is never changed.
  test('birth date fill: trial reports it and writes nothing', () async {
    final path = sf1([_lrn(4701), _lrn(4702), _lrn(4703)],
        birthDates: {0: '03-15-2013', 1: '03-16-2013', 2: '15/13/2013'}, section: 'G4-Fill');
    final t = await importer.trial(path);
    final fill = rowFor(t, _lrn(4701));
    expect((fill.outcome, fill.fillsBirthDate, fill.reason, fill.existingStudentId),
        ('enrolled', true, sf1FillsBirthDateReason, 4701));
    expect(rowFor(t, _lrn(4702)).fillsBirthDate, isFalse); // stored date
    expect(rowFor(t, _lrn(4702)).reason, 'already enrolled in this section');
    expect(rowFor(t, _lrn(4703)).fillsBirthDate, isFalse); // unreadable
    expect(t.wouldFillBirthDate, 1);
    final stored = await db.query('students', columns: ['birth_date'], where: 'id = 4701');
    expect(stored.single['birth_date'], isNull);
  });

  test('birth date fill: import fills only the blank, readable one', () async {
    final path = sf1([_lrn(4701), _lrn(4702), _lrn(4703)],
        birthDates: {0: '03-15-2013', 1: '03-16-2013', 2: '15/13/2013'}, section: 'G4-Fill');
    final result = await importer.import(path);
    expect((result.alreadyEnrolled, result.birthDatesFilled, result.inserted), (3, 1, 0));
    final stored = {
      for (final r in await db.query('students', where: 'id IN (4701, 4702, 4703)')) r['id']: r['birth_date'],
    };
    expect(stored, {4701: '2013-03-15', 4702: '2012-01-01', 4703: null});
    // Once filled, a second import has nothing to fill.
    expect((await importer.trial(path)).wouldFillBirthDate, 0);
  });

  test('birth date fill refused: a warning, the import goes on', () async {
    final students = StudentRepositorySqlite(db);
    final refusing = Sf1Importer(
      schoolRepo: importer.schoolRepo,
      localSchoolRepo: importer.localSchoolRepo,
      sectionRepo: importer.sectionRepo,
      localSectionRepo: importer.localSectionRepo,
      studentRepo: _RefusesFill(students),
      localStudentRepo: students,
      conflictRepo: importer.conflictRepo,
      columnMap: importer.columnMap,
    );
    final result = await refusing.import(sf1([_lrn(4704), _lrn(4801)], birthDates: {0: '03-17-2013'}, section: 'G4-Fill'));
    expect((result.alreadyEnrolled, result.birthDatesFilled, result.inserted), (1, 0, 1));
    expect(result.rowWarnings,
        ["Row 7 Filerow0, Zed: birth date not filled (already set, or this learner can't be changed)"]);
    final stored = await db.query('students', columns: ['birth_date'], where: 'id = 4704');
    expect(stored.single['birth_date'], isNull);
  });

  test('import skips moving and returning rows and logs no conflict', () async {
    final path = sf1([_lrn(4501), _lrn(4502), _lrn(4503), _lrn(4504), _lrn(4505)]);
    final result = await importer.import(path);
    expect(result.waiting, 2);
    expect(result.inserted, 1);
    expect(result.conflicts, 1);
    expect(result.alreadyEnrolled, 1);

    final conflicts = await db.query('import_conflicts');
    expect(conflicts.map((c) => c['lrn']), [_lrn(4502)]);
    // The waiting learners keep their enrollments as they were.
    final e = {for (final r in await db.query('enrollments', where: 'id IN (4501, 4503)')) r['id']: r};
    expect((e[4501]!['section_id'], e[4501]!['status']), (42, 'active'));
    expect((e[4503]!['section_id'], e[4503]!['status']), (42, 'dropped_out'));
  });
}

/// The device's repository, except that the "server" refuses every birth
/// date fill (RLS, or filled meanwhile: both come back as no row).
class _RefusesFill implements StudentRepository {
  final StudentRepository inner;
  _RefusesFill(this.inner);

  @override
  Future<Student?> fillBlankBirthDate(int studentId, String birthDate) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => Function.apply(
        switch (invocation.memberName) {
          #findByLrn => inner.findByLrn,
          #insert => inner.insert,
          #update => inner.update,
          #getAll => inner.getAll,
          #getBySection => inner.getBySection,
          #activeSectionId => inner.activeSectionId,
          #enrollmentInYear => inner.enrollmentInYear,
          #enroll => inner.enroll,
          #upsertWithId => inner.upsertWithId,
          _ => throw UnimplementedError('${invocation.memberName}'),
        },
        invocation.positionalArguments,
        invocation.namedArguments,
      );
}
