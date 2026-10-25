// Learner history reads on the device (learner_history_repository_sqlite.dart):
// one learner's section enrollments, ARAL entries and SRP classes across all
// school years, and the learner by id or LRN.
import 'dart:io';

import 'package:basa_capstone/core/data/local/learner_history_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LearnerHistoryRepositorySqlite repo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await LocalDatabase.instance(Directory.systemTemp.createTempSync('basa_learner_history_').path);
    repo = LearnerHistoryRepositorySqlite(db);
    await db.insert('schools', {'id': 9801, 'school_id': 'ZZH1', 'school_name': 'ZZ History'});
    for (final id in [9801, 9802]) {
      await db.insert('students', {'id': id, 'lrn': '9999999${id}00', 'last_name': 'ZZH', 'first_name': 'L$id',
          'school_id': 9801});
    }
    await db.insert('sections', {'id': 9801, 'school_id': 9801, 'school_year': '2025-2026', 'grade_level': '3',
        'section_name': 'S3'});
    await db.insert('sections', {'id': 9802, 'school_id': 9801, 'school_year': '2026-2027', 'grade_level': '4',
        'section_name': 'S4'});
    for (final (student, section, year) in [
      (9801, 9801, '2025-2026'),
      (9801, 9802, '2026-2027'),
      (9802, 9802, '2026-2027'),
    ]) {
      await db.insert('enrollments', {'student_id': student, 'section_id': section, 'school_year': year, 'status': 'active'});
    }
    for (final (id, student) in [(9801, 9801), (9802, 9802)]) {
      await db.insert('aral_enrollments', {
        'id': id, 'student_id': student, 'school_id': 9801, 'section_id': 9802, 'school_year': '2026-2027',
        'key_stage': 'ks2', 'track': 'basic', 'entered_on': '2026-08-01', 'basis_source': 'manual', 'origin': 'cloud', 'row_version': 1, // a pulled row
      });
    }
    await db.insert('srp_classes', {'id': 9801, 'school_id': 9801, 'school_year': '2025-2026', 'assessed_grade': 3,
        'class_name': 'Summer A'});
    await db.insert('srp_classes', {'id': 9802, 'school_id': 9801, 'school_year': '2026-2027', 'assessed_grade': 4,
        'class_name': 'Summer B'});
    await db.insert('srp_class_members', {'class_id': 9801, 'student_id': 9801, 'school_year': '2025-2026'});
    await db.insert('srp_class_members', {'class_id': 9802, 'student_id': 9802, 'school_year': '2026-2027'});
  });

  tearDownAll(LocalDatabase.close);

  test('sectionEnrollments returns both years latest first with section and school names', () async {
    final rows = await repo.sectionEnrollments(9801);
    expect(rows.map((r) => r.schoolYear), ['2026-2027', '2025-2026']);
    expect(rows.first.gradeLevel, '4');
    expect(rows.first.sectionName, 'S4');
    expect(rows.first.sectionId, 9802);
    expect(rows.first.schoolId, 9801);
    expect(rows.first.schoolName, 'ZZ History');
    expect(rows.first.status, 'active');
  });

  test("aralEntries returns only this learner's entries", () async {
    final rows = await repo.aralEntries(9801);
    expect(rows, hasLength(1));
    expect(rows.single.studentId, 9801);
  });

  test("srpClasses returns the learner's classes", () async {
    final rows = await repo.srpClasses(9801);
    expect(rows, hasLength(1));
    expect(rows.single.schoolYear, '2025-2026');
    expect(rows.single.className, 'Summer A');
  });

  test('student and studentByLrn find the learner; unknown gives null', () async {
    expect((await repo.student(9801))!.lrn, '9999999980100');
    expect((await repo.studentByLrn('9999999980100'))!.id, 9801);
    expect(await repo.student(1), isNull);
    expect(await repo.studentByLrn('000'), isNull);
  });
}
