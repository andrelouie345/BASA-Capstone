// SF1 leavers, final review I3 (owner 2026-11-13): `resolve-conflict <id>
// update` no longer moves a learner who already has an enrollment that
// school year at the conflict's school (active -> sf1-move, archived ->
// sf1-restore). I2 (D15): an enrollment that year at another school,
// archived or still active, goes to the server's sf1_transfer_in (also when
// the learner is hidden from this school: a transfer conflict); its result
// is copied to the device and the answer says where they came from. No
// enrollment still resolves by the upsert. SQLite repositories stand in for
// the cloud ones. Fixture names only.
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
import 'package:basa_capstone/core/services/sf1_importer.dart' show transferConflictReason, legacyTransferConflictReason, isTransferConflictReason;
import 'package:basa_capstone/viewmodels/import_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase/supabase.dart' show PostgrestException;

import '../helpers/fake_online_auth.dart';

const _year = '2026-2027';

/// The server's sf1_transfer_in: records the call, answers like the
/// function, or refuses with [refuse].
class _Leavers implements LearnerLeaverRepository {
  final calls = <int>[];
  String? refuse;

  @override
  Future<Map<String, dynamic>> transferIn(int conflictId) async {
    calls.add(conflictId);
    if (refuse != null) throw PostgrestException(message: refuse!);
    return {
      'enrollment': {'id': 1, 'section_id': 81},
      'student': {'id': 8104},
      'move': {'id': 9, 'source': 'transfer_in'},
      'from_school': {'id': 2, 'name': 'ZZ Resolve B'},
      'from_section': {'id': 84, 'name': 'G4-Other'},
      'exited_aral_enrollment_id': null,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final dir = Directory.systemTemp.createTempSync('basa_import_resolve_').path;
  late Database db;
  late ImportViewModel vm;
  late ImportConflictRepositorySqlite conflicts;
  final leavers = _Leavers();
  final mirrored = <Map<String, dynamic>>[];

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
          schools: schools, sections: sections, students: students, conflicts: conflicts, leavers: leavers),
      localSchools: schools,
      localSections: sections,
      localStudents: students,
      columnMap: await Sf1ColumnMap.load(dir),
      mirror: (r) async => mirrored.add(r),
    );
  });

  tearDownAll(LocalDatabase.close);

  /// A pending conflict for learner [studentId] raised for [sectionId].
  Future<int> conflictFor(int studentId, int sectionId, {String? reason}) async {
    await conflicts.log(ImportConflict(
      lrn: '9999990$studentId',
      sectionId: sectionId,
      reason: reason ?? 'LRN already exists (existing student id $studentId)',
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
            "sf1-move 8111 82 (this year's records follow), then close this conflict with resolve-conflict $id skip."));
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
            'resolve-conflict $id skip.'));
  });

  test('active in that very section: nothing to enroll', () async {
    final id = await conflictFor(8101, 81);
    await expectLater(
        vm.resolve(id, 'update'),
        refused('Refused: LRN 99999908101 is already active in G4-A (Grade 4) this school year: nothing to enroll; '
            'close this conflict with resolve-conflict $id skip.'));
  });

  test('archived at the school: refused, pointing to sf1-restore', () async {
    final into = await conflictFor(8102, 82);
    await expectLater(
        vm.resolve(into, 'update'),
        refused('Refused: LRN 99999908102 was archived on 2026-11-01 (dropped out) in G4-A (Grade 4) this school '
            "year. Restore them into this section with sf1-restore 8112 82 (this year's records follow), then close "
            'this conflict with resolve-conflict $into skip.'));
    final same = await conflictFor(8102, 81);
    await expectLater(
        vm.resolve(same, 'update'),
        refused('Refused: LRN 99999908102 was archived on 2026-11-01 (dropped out) in G4-A (Grade 4) this school '
            'year. Restore them with sf1-restore 8112, then close this conflict with resolve-conflict $same skip.'));
    final other = await conflictFor(8102, 83);
    await expectLater(
        vm.resolve(other, 'update'),
        refused('Refused: LRN 99999908102 was archived on 2026-11-01 (dropped out) in G4-A (Grade 4) this school '
            'year, and a restore into another section is same grade only: sf1-restore 8112 puts them back in G4-A, '
            'or decide by hand; then close this conflict with resolve-conflict $other skip.'));
    expect((await enrollment(8102))['status'], 'dropped_out');
  });

  test('archived at another school: transferred in by the server function (D15)', () async {
    leavers.calls.clear();
    mirrored.clear();
    final id = await conflictFor(8104, 81);
    final r = await vm.resolve(id, 'update');
    expect(leavers.calls, [id]);
    expect(r.action, 'update');
    expect(r.studentId, 8104);
    expect(r.enrolledIn?.id, 81);
    expect(r.transferredFrom, (schoolName: 'ZZ Resolve B', sectionName: 'G4-Other'));
    expect(r.deviceWarning, isNull);
    expect(mirrored.single['move'], {'id': 9, 'source': 'transfer_in'});
    // The device copy is the mirror's job: the VM wrote no enrollment itself.
    expect((await enrollment(8104))['section_id'], 84);
  });

  test('active at another school (q11) goes to the server function too', () async {
    leavers.calls.clear();
    final id = await conflictFor(8103, 81);
    await vm.resolve(id, 'update');
    expect(leavers.calls, [id]);
    expect((await enrollment(8103))['section_id'], 84);
    expect(await lastName(8103), 'ZZRes8103');
  });

  test('a transfer conflict of a learner this school cannot see goes to the server function', () async {
    leavers.calls.clear();
    final id = await conflictFor(8199, 81, reason: transferConflictReason);
    await vm.resolve(id, 'update');
    expect(leavers.calls, [id]);
  });

  test('a transfer conflict with the old stored reason text is still recognised', () async {
    leavers.calls.clear();
    expect(transferConflictReason, contains("this school's admin/coordinator when the other school archived the learner"));
    expect(isTransferConflictReason(legacyTransferConflictReason), isTrue);
    expect(isTransferConflictReason('LRN already exists (existing student id 1)'), isFalse);
    final id = await conflictFor(8198, 81, reason: legacyTransferConflictReason);
    await vm.resolve(id, 'update');
    expect(leavers.calls, [id]);
  });

  test("the server's refusal comes back as a readable message", () async {
    leavers.refuse = 'transfers are same grade only: G4-A is Grade 4, the learner is in Grade 5 at the other school';
    final id = await conflictFor(8104, 81);
    await expectLater(
        vm.resolve(id, 'update'),
        refused('The database refused it: transfers are same grade only: G4-A is Grade 4, the learner is in Grade 5 '
            'at the other school.'));
    leavers.refuse = null;
  });

  test('no enrollment this year still resolves by enrolling', () async {
    final fresh = await conflictFor(8105, 82);
    expect((await vm.resolve(fresh, 'update')).enrolledIn?.id, 82);
    expect((await enrollment(8105))['section_id'], 82);
    expect(await lastName(8105), 'ZZNew8105');
  });
}
