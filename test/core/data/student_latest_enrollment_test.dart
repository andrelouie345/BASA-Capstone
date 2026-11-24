// StudentRepository.latestEnrollmentBefore (SF1 continuing learners, spec
// docs/superpowers/specs/2026-11-24-sf1-continuing-learners-design.md): the
// learner's enrollment with the greatest school year strictly before the
// asked one, any school, any status. Fixture names only.
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/student_repository_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late StudentRepositorySqlite repo;
  final dir = Directory.systemTemp.createTempSync('basa_latest_enrollment_').path;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    repo = StudentRepositorySqlite(db);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ70', 'school_name': 'ZZ Latest School', 'region_id': 13});
    for (final (id, year, grade) in [(71, '2024-2025', '2'), (72, '2025-2026', '3'), (73, '2026-2027', '4')]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': year, 'grade_level': grade, 'section_name': 'G$grade-A'});
    }
    for (final id in [1, 2, 3, 4]) {
      await db.insert('students', {'id': id, 'lrn': '9999997000$id', 'last_name': 'Fixture$id', 'first_name': 'Zed', 'school_id': 1});
    }
    Future<void> enroll(int id, int student, int section, String year, {String status = 'active'}) => db.insert('enrollments', {
          'id': id, 'student_id': student, 'section_id': section, 'school_year': year, 'status': status,
          if (status != 'active') 'left_on': '2026-02-01',
          if (status != 'active') 'left_by': '00000000-0000-0000-0000-00000000c070',
        });
    // 1: two earlier years. 2: only the asked year. 3: archived last year. 4: none.
    await enroll(1, 1, 71, '2024-2025');
    await enroll(2, 1, 72, '2025-2026');
    await enroll(3, 2, 73, '2026-2027');
    await enroll(4, 3, 72, '2025-2026', status: 'dropped_out');
  });

  tearDownAll(() async {
    await LocalDatabase.close();
    Directory(dir).deleteSync(recursive: true);
  });

  test('none before', () async {
    expect(await repo.latestEnrollmentBefore(4, '2026-2027'), isNull);
  });

  test('latest of two earlier years wins', () async {
    final e = await repo.latestEnrollmentBefore(1, '2026-2027');
    expect(e, isNotNull);
    expect(e!.schoolYear, '2025-2026');
    expect(e.gradeLevel, '3');
    expect(e.sectionId, 72);
    expect(e.schoolId, 1);
  });

  test('the asked year itself is not "before"', () async {
    expect(await repo.latestEnrollmentBefore(2, '2026-2027'), isNull);
  });

  test('archived counts', () async {
    final e = await repo.latestEnrollmentBefore(3, '2026-2027');
    expect(e!.status, 'dropped_out');
    expect(e.leftOn, '2026-02-01');
  });
}
