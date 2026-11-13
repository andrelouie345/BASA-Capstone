// SF1 leavers, final review I3 (owner 2026-11-13): `import-resolve <id>
// update` no longer moves a learner who already has an enrollment that
// school year at the conflict's school (active -> sf1-move, archived ->
// sf1-restore); an archived enrollment at another school gets a named
// refusal (review I2, until the transfer path is decided). No enrollment, or
// active at another school (the superadmin's transfer), still resolves.
// SQLite repositories stand in for the cloud ones. Fixture names only.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/data/local/import_conflict_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/school_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/section_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/student_repository_sqlite.dart';
import 'package:basa_capstone/core/models/import_conflict.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/repositories/learner_leaver_repository.dart';
import 'package:basa_capstone/core/services/sf1_column_map.dart';
import 'package:basa_capstone/viewmodels/import_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_online_auth.dart';

const _year = '2026-2027';

class _NoLeavers implements LearnerLeaverRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final dir = Directory.systemTemp.createTempSync('basa_import_resolve_').path;
  late Database db;
  late ImportViewModel vm;
  late ImportConflictRepositorySqlite conflicts;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ81', 'school_name': 'ZZ Resolve A', 'region_id': 13});
    await db.insert('schools', {'id': 2, 'school_id': 'ZZ82', 'school_name': 'ZZ Resolve B', 'region_id': 13});
    for (final (id, school, grade, name) in [
      (81, 1, '4', 'G4-A'),
      (82, 1, '4', 'G4-B'),
      (83, 1, '5', 'G5-A'),
      (84, 2, '4', 'G4-Other'),
    ]) {
      await db.insert('sections',
          {'id': id, 'school_id': school, 'school_year': _year, 'grade_level': grade, 'section_name': name});
    }
    // 8101 active in G4-A; 8102 archived in G4-A; 8103 active at school 2;
    // 8104 archived at school 2; 8105 no enrollment this year.
    for (final (id, school) in [(8101, 1), (8102, 1), (8103, 2), (8104, 2), (8105, 1)]) {
      await db.insert('students',
          {'id': id, 'lrn': '9999990$id', 'last_name': 'ZZRes$id', 'first_name': 'Kim', 'sex': 'F', 'school_id': school});
    }
    await db.insert('enrollments', {'id': 8111, 'student_id': 8101, 'section_id': 81, 'school_year': _year, 'status': 'active'});
    await db.insert('enrollments', {'id': 8112, 'student_id': 8102, 'section_id': 81, 'school_year': _year,
        'status': 'dropped_out', 'left_on': '2026-11-01', 'left_by': 'u'});
    await db.insert('enrollments', {'id': 8113, 'student_id': 8103, 'section_id': 84, 'school_year': _year, 'status': 'active'});
    await db.insert('enrollments', {'id': 8114, 'student_id': 8104, 'section_id': 84, 'school_year': _year,
        'status': 'transferred_out', 'left_on': '2026-11-02', 'left_by': 'u'});

    final schools = SchoolRepositorySqlite(db);
    final sections = SectionRepositorySqlite(db);
    final students = StudentRepositorySqlite(db);
    conflicts = ImportConflictRepositorySqlite(db);
    vm = ImportViewModel(
      auth: FakeOnlineAuth(UserRole.admin, schoolId: null),
      cloudFactory: (_) => ImportCloudRepos(
          schools: schools, sections: sections, students: students, conflicts: conflicts, leavers: _NoLeavers()),
      localSchools: schools,
      localSections: sections,
      localStudents: students,
      columnMap: await Sf1ColumnMap.load(dir),
    );
  });

  tearDownAll(LocalDatabase.close);

  /// A pending conflict for learner [studentId] raised for [sectionId].
  Future<int> conflictFor(int studentId, int sectionId) async {
    await conflicts.log(ImportConflict(
      lrn: '9999990$studentId',
      sectionId: sectionId,
      reason: 'LRN already exists (existing student id $studentId)',
      incomingDataJson: jsonEncode({'lrn': '9999990$studentId', 'last_name': 'ZZNew$studentId', 'first_name': 'Kim'}),
      existingStudentId: studentId,
    ));
    return (await db.query('import_conflicts', orderBy: 'id DESC', limit: 1)).single['id'] as int;
  }

  Future<Map<String, Object?>> enrollment(int studentId) async =>
      (await db.query('enrollments', where: 'student_id = ? AND school_year = ?', whereArgs: [studentId, _year])).single;
  Future<String> lastName(int studentId) async =>
      (await db.query('students', where: 'id = ?', whereArgs: [studentId])).single['last_name'] as String;

  Matcher refused(String message) => throwsA(isA<ViewModelException>().having((e) => e.message, 'message', message));

  test('active at the school, same grade: refused, pointing to sf1-move; nothing changes', () async {
    final id = await conflictFor(8101, 82);
    await expectLater(
        vm.resolve(id, 'update'),
        refused('Refused: LRN 99999908101 is already active in G4-A (Grade 4) this school year. Move them with '
            "sf1-move 8111 82 (this year's records follow), then close this conflict with import-resolve $id skip."));
    expect((await enrollment(8101))['section_id'], 81);
    expect(await lastName(8101), 'ZZRes8101');
    expect((await conflicts.getById(id))!.status, 'pending');
    // skip still closes it.
    expect((await vm.resolve(id, 'skip')).action, 'skip');
  });

  test('active at the school, another grade: a decision by hand', () async {
    final id = await conflictFor(8101, 83);
    await expectLater(
        vm.resolve(id, 'update'),
        refused('Refused: LRN 99999908101 is active in G4-A (Grade 4) this school year, and moves are same grade '
            'only, so this is a decision by hand (e.g. archive them there); then close this conflict with '
            'import-resolve $id skip.'));
  });

  test('active in that very section: nothing to enroll', () async {
    final id = await conflictFor(8101, 81);
    await expectLater(
        vm.resolve(id, 'update'),
        refused('Refused: LRN 99999908101 is already active in G4-A (Grade 4) this school year: nothing to enroll; '
            'close this conflict with import-resolve $id skip.'));
  });

  test('archived at the school: refused, pointing to sf1-restore', () async {
    final into = await conflictFor(8102, 82);
    await expectLater(
        vm.resolve(into, 'update'),
        refused('Refused: LRN 99999908102 was archived on 2026-11-01 (dropped out) in G4-A (Grade 4) this school '
            "year. Restore them into this section with sf1-restore 8112 82 (this year's records follow), then close "
            'this conflict with import-resolve $into skip.'));
    final same = await conflictFor(8102, 81);
    await expectLater(
        vm.resolve(same, 'update'),
        refused('Refused: LRN 99999908102 was archived on 2026-11-01 (dropped out) in G4-A (Grade 4) this school '
            'year. Restore them with sf1-restore 8112, then close this conflict with import-resolve $same skip.'));
    final other = await conflictFor(8102, 83);
    await expectLater(
        vm.resolve(other, 'update'),
        refused('Refused: LRN 99999908102 was archived on 2026-11-01 (dropped out) in G4-A (Grade 4) this school '
            'year, and a restore into another section is same grade only: sf1-restore 8112 puts them back in G4-A, '
            'or decide by hand; then close this conflict with import-resolve $other skip.'));
    expect((await enrollment(8102))['status'], 'dropped_out');
  });

  test('archived at another school: a named refusal (review I2)', () async {
    final id = await conflictFor(8104, 81);
    await expectLater(
        vm.resolve(id, 'update'),
        refused('Refused: LRN 99999908104 was archived on 2026-11-02 (transferred out) at another school this school '
            'year, in G4-Other (Grade 4), so they cannot be enrolled here this year by resolving the conflict. '
            "For now: that school restores them (sf1-restore 8114), then resolve again; this year's records stay "
            'under that school.'));
    expect((await enrollment(8104))['section_id'], 84);
  });

  test('active at another school (the transfer) and no enrollment still resolve', () async {
    final transfer = await conflictFor(8103, 81);
    final r = await vm.resolve(transfer, 'update');
    expect(r.enrolledIn?.id, 81);
    expect((await enrollment(8103))['section_id'], 81);
    expect(await lastName(8103), 'ZZNew8103');

    final fresh = await conflictFor(8105, 82);
    expect((await vm.resolve(fresh, 'update')).enrolledIn?.id, 82);
    expect((await enrollment(8105))['section_id'], 82);
  });
}
