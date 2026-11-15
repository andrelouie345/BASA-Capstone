// SF1 leavers row 64 (2026-11-15): ImportViewModel.transferConflicts, the
// superadmin's list of pending transfer conflicts across schools. Each row
// has the SF1 row, the receiving section and school, the learner with the
// LRN and where they are this school year, and whether the SF1 row matches
// them as sf1_transfer_in checks it (names with accents/case/spaces folded;
// the birth date when the stored learner has one). Other conflicts are not
// listed; anyone but the superadmin is refused. SQLite repositories stand in
// for the cloud ones. Fixture names only.
import 'dart:convert';
import 'dart:io';

import 'package:basa_capstone/core/data/local/import_conflict_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/school_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/section_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/student_repository_sqlite.dart';
import 'package:basa_capstone/core/models/import_conflict.dart';
import 'package:basa_capstone/core/models/student.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/repositories/learner_leaver_repository.dart';
import 'package:basa_capstone/core/services/sf1_column_map.dart';
import 'package:basa_capstone/core/services/sf1_importer.dart';
import 'package:basa_capstone/viewmodels/import_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_online_auth.dart';

const _year = '2026-2027';

class _NoLeavers implements LearnerLeaverRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('not used here');
}

void main() {
  group('sf1TransferIdentityDifferences (the server rule)', () {
    final stored = Student(lrn: '1', lastName: 'Dela Cruz', firstName: 'José', sex: 'M', birthDate: '2013-03-15');
    test('names fold accents, case and spaces', () {
      expect(sf1NormName('  DELA   CRUZ '), 'dela cruz');
      expect(sf1NormName('Jose'), sf1NormName('JOSÉ'));
      expect(sf1NormName('   '), isNull);
      expect(sf1TransferIdentityDifferences(
          {'last_name': 'DELA  CRUZ', 'first_name': 'JOSE', 'birth_date': '2013-03-15'}, stored), isEmpty);
    });
    test('each difference named; a blank SF1 birth date differs when one is stored', () {
      expect(sf1TransferIdentityDifferences(
          {'last_name': 'Santos', 'first_name': 'Ana', 'birth_date': '2013-03-16'}, stored),
          ['last name', 'first name', 'birth date']);
      expect(sf1TransferIdentityDifferences({'last_name': 'Dela Cruz', 'first_name': 'Jose'}, stored),
          ['birth date (blank on the SF1)']);
    });
    test('no stored birth date: names only', () {
      final noBirth = Student(lrn: '1', lastName: 'Dela Cruz', firstName: 'Jose', sex: 'M');
      expect(sf1TransferIdentityDifferences(
          {'last_name': 'Dela Cruz', 'first_name': 'Jose', 'birth_date': '2013-01-01'}, noBirth), isEmpty);
    });
  });

  group('transferConflicts', () {
    final dir = Directory.systemTemp.createTempSync('basa_transfer_conflicts_').path;
    late Database db;
    late ImportConflictRepositorySqlite conflicts;
    late ImportViewModel Function(FakeOnlineAuth auth) vmAs;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      db = await LocalDatabase.instance(dir);
      await db.insert('schools', {'id': 1, 'school_id': 'ZZ91', 'school_name': 'ZZ Receiving', 'region_id': 13});
      await db.insert('schools', {'id': 2, 'school_id': 'ZZ92', 'school_name': 'ZZ Sending', 'region_id': 13});
      await db.insert('sections', {'id': 91, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'G7-In'});
      await db.insert('sections', {'id': 92, 'school_id': 2, 'school_year': _year, 'grade_level': '7', 'section_name': 'G7-Out'});
      // 9101 archived at school 2 (transferred out); 9102 still active there.
      for (final (id, last, first, birth) in [(9101, 'Dela Cruz', 'José', '2013-03-15'), (9102, 'Reyes', 'Ana', '2013-04-01')]) {
        await db.insert('students', {'id': id, 'lrn': '99999991$id', 'last_name': last, 'first_name': first,
            'sex': 'M', 'school_id': 2, 'birth_date': birth});
      }
      await db.insert('enrollments', {'id': 9111, 'student_id': 9101, 'section_id': 92, 'school_year': _year,
          'status': 'transferred_out', 'left_on': '2026-11-02', 'left_by': 'u'});
      await db.insert('enrollments', {'id': 9112, 'student_id': 9102, 'section_id': 92, 'school_year': _year, 'status': 'active'});

      conflicts = ImportConflictRepositorySqlite(db);
      Future<void> conflict(String lrn, Map<String, Object?> data, {String reason = transferConflictReason}) =>
          conflicts.log(ImportConflict(lrn: lrn, sectionId: 91, reason: reason, incomingDataJson: jsonEncode(data)));
      await conflict('999999919101', {'last_name': 'DELA CRUZ', 'first_name': 'Jose', 'birth_date': '2013-03-15'});
      await conflict('999999919102', {'last_name': 'Reyes', 'first_name': 'Ana', 'birth_date': '2013-04-02'});
      await conflict('999999919199', {'last_name': 'Nobody', 'first_name': 'Here'});
      await conflict('999999919101', {'last_name': 'X', 'first_name': 'Y'}, reason: 'LRN already exists (existing student id 9101)');

      final schools = SchoolRepositorySqlite(db);
      final sections = SectionRepositorySqlite(db);
      final students = StudentRepositorySqlite(db);
      final map = await Sf1ColumnMap.load(dir);
      vmAs = (auth) => ImportViewModel(
            auth: auth,
            cloudFactory: (_) => ImportCloudRepos(
                schools: schools, sections: sections, students: students, conflicts: conflicts, leavers: _NoLeavers()),
            localSchools: schools,
            localSections: sections,
            localStudents: students,
            columnMap: map,
          );
    });

    tearDownAll(LocalDatabase.close);

    Matcher refused(String m) => throwsA(isA<ViewModelException>().having((e) => e.message, 'message', m));

    test('anyone but the superadmin is refused', () async {
      await expectLater(vmAs(FakeOnlineAuth(UserRole.coordinator)).transferConflicts(), refused(transferConflictsForbiddenMessage));
      await expectLater(vmAs(FakeOnlineAuth(UserRole.admin, schoolId: 1)).transferConflicts(), refused(transferConflictsForbiddenMessage));
    });

    test('the superadmin gets every transfer conflict with the learner, the place and the identity hint', () async {
      final list = await vmAs(FakeOnlineAuth(UserRole.admin, schoolId: null)).transferConflicts();
      // The plain "LRN already exists" conflict is not a transfer.
      expect(list.map((t) => t.conflict.lrn).toList(), ['999999919101', '999999919102', '999999919199']);

      final archived = list[0];
      expect((archived.section?.sectionName, archived.schoolName), ('G7-In', 'ZZ Receiving'));
      expect((archived.incomingName, archived.incomingBirthDate), ('DELA CRUZ, Jose', '2013-03-15'));
      expect(archived.stored?.id, 9101);
      expect(archived.current, (
        schoolName: 'ZZ Sending', schoolId: 2, sectionName: 'G7-Out', gradeLevel: '7',
        status: 'transferred_out', leftOn: '2026-11-02',
      ));
      expect(archived.matches, isTrue);
      expect(archived.activeElsewhere, isFalse);

      final active = list[1];
      expect(active.activeElsewhere, isTrue);
      expect(active.differences, ['birth date']);
      expect(active.matches, isFalse);

      final unknown = list[2];
      expect(unknown.stored, isNull);
      expect(unknown.current, isNull);
      expect(unknown.matches, isFalse);
      expect(unknown.incomingBirthDate, isNull);
    });
  });
}
