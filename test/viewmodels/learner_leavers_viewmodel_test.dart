// SF1 leavers (spec docs/superpowers/specs/2026-11-12-sf1-leavers-design.md,
// sections 3 and 5): LearnerLeaversViewModel with a fake repository. Who may
// act (tutors refused, an online sign-in needed), archive / move / restore
// call the server function and mirror its result, anonymize needs the
// preview's code, the undecided list comes from the last import's LRNs
// (ImportViewModel saves them), and the archive_keep_months setting.
// Fixture names only.
import 'dart:io';

import 'package:basa_capstone/core/data/local/import_conflict_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/learner_leaver_local_writes.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/school_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/section_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/student_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/sync_local_writes.dart';
import 'package:basa_capstone/core/models/enrollment.dart';
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:basa_capstone/core/models/student.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/repositories/learner_leaver_repository.dart';
import 'package:basa_capstone/core/repositories/report_setting_repository.dart';
import 'package:basa_capstone/core/services/auth_messages.dart';
import 'package:basa_capstone/core/services/sf1_column_map.dart';
import 'package:basa_capstone/viewmodels/import_viewmodel.dart';
import 'package:basa_capstone/viewmodels/learner_leavers_viewmodel.dart';
import 'package:basa_capstone/viewmodels/report_settings_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase/supabase.dart' show PostgrestException, SupabaseClient;

import '../helpers/fake_online_auth.dart';

const _year = '2026-2027';

Matcher _refused(String message) =>
    throwsA(isA<ViewModelException>().having((e) => e.message, 'message', message));

/// Signed in, but offline: no server session.
class _OfflineAuth extends FakeOnlineAuth {
  _OfflineAuth() : super(UserRole.coordinator);
  @override
  SupabaseClient? get client => null;
  @override
  String? requireOnlineSession({bool allowPendingPasswordChange = false}) => needsOnlineSignInMessage;
}

class _FakeLeavers implements LearnerLeaverRepository {
  final calls = <String>[];
  List<Map<String, dynamic>> eligible = [];

  /// Thrown by archive() when set (server and network errors).
  Object? archiveError;

  /// Section id -> the last import's LRNs (sf1_last_imports).
  final lastImports = <int, ({int schoolId, String schoolYear, List<String> lrns})>{};

  /// Active learners per section, as the server holds them.
  final active = <int, List<Map<String, dynamic>>>{};

  @override
  Future<Map<String, dynamic>> archive(int enrollmentId, String reason, String? note) async {
    calls.add('archive($enrollmentId, $reason, $note)');
    if (archiveError != null) throw archiveError!;
    return {
      'enrollment': {'id': enrollmentId, 'student_id': 7, 'section_id': 41, 'school_year': _year, 'status': reason,
          'left_on': '2026-11-13', 'left_by': 'u', 'left_note': note},
      'aral_enrollment': {'id': 3, 'status': 'exited'},
    };
  }

  @override
  Future<Map<String, dynamic>> move(int enrollmentId, int toSectionId, String source) async {
    calls.add('move($enrollmentId, $toSectionId, $source)');
    return {
      'enrollment': {'id': enrollmentId, 'student_id': 7, 'section_id': toSectionId, 'school_year': _year,
          'status': 'active'},
      'moved': {
        'crla_assessments': [{'id': 1, 'section_id': toSectionId, 'attempt_no': 2}],
        'phil_iri_assessments': [5, 6],
        'phil_iri_gst_results': <int>[],
      },
      'aral_enrollment': null,
      'move': {'id': 9, 'enrollment_id': enrollmentId, 'student_id': 7, 'school_id': 1, 'school_year': _year,
          'from_section_id': 41, 'to_section_id': toSectionId, 'moved_on': '2026-11-13', 'moved_by': 'u',
          'source': source},
    };
  }

  @override
  Future<Map<String, dynamic>> restore(int enrollmentId, int? toSectionId) async {
    calls.add('restore($enrollmentId, $toSectionId)');
    return {
      'enrollment': {'id': enrollmentId, 'student_id': 7, 'section_id': toSectionId ?? 41, 'school_year': _year,
          'status': 'active'},
    };
  }

  @override
  Future<Map<String, dynamic>> anonymize(int studentId) async {
    calls.add('anonymize($studentId)');
    return {
      'student': {'id': studentId, 'lrn': 'ANON-$studentId', 'last_name': 'Anonymized', 'first_name': '—'},
    };
  }

  @override
  Future<List<Map<String, dynamic>>> anonymizeEligible(int schoolId) async {
    calls.add('anonymizeEligible($schoolId)');
    return eligible;
  }

  /// Enrollment id -> its section and school (enrollmentPlace).
  final places = <int, ({int sectionId, int schoolId})>{};

  @override
  Future<({int sectionId, int schoolId})?> enrollmentPlace(int enrollmentId) async {
    calls.add('enrollmentPlace($enrollmentId)');
    return places[enrollmentId];
  }

  @override
  Future<List<Map<String, dynamic>>> missing(int schoolId, {int? sectionId}) async {
    calls.add('missing($schoolId, $sectionId)');
    // As sf1_missing: active learners of sections with a last import whose
    // LRN isn't in it.
    return [
      for (final e in lastImports.entries)
        if (sectionId == null || e.key == sectionId)
          for (final l in active[e.key] ?? const <Map<String, dynamic>>[])
            if (!e.value.lrns.contains(l['lrn'])) {...l, 'section_id': e.key, 'section_name': 'G4-A'},
    ];
  }

  @override
  Future<void> saveLastImport(int sectionId, int schoolId, String schoolYear, List<String> lrns) async {
    calls.add('saveLastImport($sectionId, $schoolId, $schoolYear)');
    lastImports[sectionId] = (schoolId: schoolId, schoolYear: schoolYear, lrns: lrns);
  }
}

class _Settings implements ReportSettingRepository {
  ReportSetting? region;
  final schools = <int, ReportSetting>{};
  @override
  Future<ReportSetting?> getRegion() async => region;
  @override
  Future<ReportSetting?> getForSchool(int schoolId) async => schools[schoolId];
  @override
  Future<ReportSetting> save(int? schoolId, Map<String, Object?> settings) async {
    final s = ReportSetting(id: schoolId ?? 0, schoolId: schoolId, settings: settings);
    schoolId == null ? region = s : schools[schoolId] = s;
    return s;
  }

  @override
  Future<ReportSetting> upsertWithId(ReportSetting setting) async =>
      save(setting.schoolId, setting.settings);
  @override
  Future<void> deleteForSchool(int schoolId) async => schools.remove(schoolId);
  @override
  Future<void> removeMirroredForSchool(int schoolId) async => schools.remove(schoolId);
}

void main() {
  late _FakeLeavers repo;
  late List<Map<String, dynamic>> mirrored;
  late FakeOnlineAuth auth;

  LearnerLeaversViewModel vmFor(FakeOnlineAuth a,
          {Map<int, Student>? students, Future<int> Function(int enrollmentId)? unsent}) =>
      LearnerLeaversViewModel(
        auth: a,
        cloud: (_) => repo,
        mirror: (r) async => mirrored.add(r),
        localStudent: (id) async => students?[id],
        unsentRecords: unsent ?? (_) async => 0,
      );

  setUp(() {
    repo = _FakeLeavers();
    mirrored = [];
    auth = FakeOnlineAuth(UserRole.coordinator, schoolId: 1);
  });

  group('who may act', () {
    test('a tutor is refused everything', () async {
      final vm = vmFor(FakeOnlineAuth(UserRole.tutor, schoolId: 1));
      const forbidden = 'Forbidden: only an admin or coordinator archives, moves or restores learners.';
      final calls = <String, Future<Object?> Function()>{
        'missing': () => vm.missing(),
        'archive': () => vm.archive(1, EnrollmentStatus.droppedOut),
        'move': () => vm.move(1, 42, source: 'sf1_missing'),
        'restore': () => vm.restore(1),
        'anonymizePreview': () => vm.anonymizePreview(),
        'anonymize': () => vm.anonymize('abc'),
      };
      for (final e in calls.entries) {
        await expectLater(e.value(), _refused(forbidden), reason: e.key);
      }
      expect(repo.calls, isEmpty);
    });

    test('offline (no server session) is refused everything', () async {
      final vm = vmFor(_OfflineAuth());
      final calls = <String, Future<Object?> Function()>{
        'missing': () => vm.missing(),
        'archive': () => vm.archive(1, EnrollmentStatus.droppedOut),
        'move': () => vm.move(1, 42, source: 'sf1_missing'),
        'restore': () => vm.restore(1),
        'anonymizePreview': () => vm.anonymizePreview(),
        'anonymize': () => vm.anonymize('abc'),
      };
      for (final e in calls.entries) {
        await expectLater(e.value(), _refused(needsOnlineSignInMessage), reason: e.key);
      }
      expect(repo.calls, isEmpty);
    });

    test('signed out is refused', () async {
      await expectLater(vmFor(FakeOnlineAuth.signedOut()).archive(1, EnrollmentStatus.droppedOut),
          _refused(notSignedInMessage));
    });

    test('the superadmin names the school; a school-bound user only their own', () async {
      final superadmin = vmFor(FakeOnlineAuth(UserRole.admin, schoolId: null));
      await expectLater(superadmin.missing(),
          _refused('Give the school: the superadmin has no school of their own.'));
      await superadmin.missing(schoolId: 2);
      expect(repo.calls.last, 'missing(2, null)');
      await expectLater(vmFor(auth).anonymizePreview(schoolId: 2),
          _refused("Forbidden: you can only manage your own school's learners."));
    });
  });

  group('archive, move, restore', () {
    test('archive calls the server function and mirrors its result', () async {
      final vm = vmFor(auth);
      final out = await vm.archive(11, EnrollmentStatus.transferredOut, note: 'to another town');
      expect(repo.calls, ['archive(11, transferred_out, to another town)']);
      expect(mirrored.single['enrollment']['status'], 'transferred_out');
      expect(out.enrollment!.status, EnrollmentStatus.transferredOut);
      expect(out.message, contains('saved on the server; pull to refresh this device'));
      expect(out.message, contains('ARAL'));
      expect(vm.lastMessage, out.message);
    });

    test('server and network errors come back as short messages', () async {
      final vm = vmFor(auth);
      repo.archiveError = const PostgrestException(message: 'boom', code: 'XX000');
      await expectLater(vm.archive(11, EnrollmentStatus.droppedOut), _refused('The database refused it: boom.'));
      repo.archiveError = const SocketException('no route');
      await expectLater(vm.archive(11, EnrollmentStatus.droppedOut), _refused(leaverUnreachableMessage));
      repo.archiveError = ClientException('Connection closed');
      await expectLater(vm.archive(11, EnrollmentStatus.droppedOut), _refused(leaverUnreachableMessage));
      repo.archiveError = StateError('a bug');
      await expectLater(vm.archive(11, EnrollmentStatus.droppedOut), throwsStateError);
    });

    test('archive refuses active as a reason', () async {
      await expectLater(vmFor(auth).archive(11, EnrollmentStatus.active),
          _refused('The reason must be transferred out or dropped out.'));
      expect(repo.calls, isEmpty);
    });

    test('move calls the server function and mirrors its result', () async {
      final out = await vmFor(auth).move(11, 42, source: 'sf1_incoming');
      expect(repo.calls, ['move(11, 42, sf1_incoming)']);
      expect(mirrored.single['move']['to_section_id'], 42);
      expect(out.enrollment!.sectionId, 42);
      expect(out.move!.toSectionId, 42);
      expect(out.message, contains('1 CRLA, 2 Phil-IRI, 0 GST'));
      expect(out.message, contains('saved on the server; pull to refresh this device'));
    });

    test("move decides the source from the learner's own enrollment", () async {
      repo.places[11] = (sectionId: 41, schoolId: 1);
      repo.places[12] = (sectionId: 41, schoolId: 1);
      repo.lastImports[41] = (schoolId: 1, schoolYear: _year, lrns: ['999999000012']);
      repo.active[41] = [
        {'enrollment_id': 11, 'student_id': 7, 'lrn': '999999000011', 'last_name': 'Fixture', 'first_name': 'Eleven'},
        {'enrollment_id': 12, 'student_id': 8, 'lrn': '999999000012', 'last_name': 'Fixture', 'first_name': 'Twelve'},
      ];
      final vm = vmFor(auth);
      await vm.move(11, 42); // left off section 41's last SF1
      await vm.move(12, 42); // on it: confirmed from the new section's file
      expect(repo.calls.where((c) => c.startsWith('move(')), ['move(11, 42, sf1_missing)', 'move(12, 42, sf1_incoming)']);
      expect(repo.calls, contains('missing(1, 41)'));
    });

    test('the superadmin moves without a school; a wrong school is refused', () async {
      repo.places[11] = (sectionId: 41, schoolId: 1);
      final superVm = vmFor(FakeOnlineAuth(UserRole.admin));
      await superVm.move(11, 42);
      expect(repo.calls.last, 'move(11, 42, sf1_incoming)');
      await expectLater(superVm.move(11, 42, schoolId: 5), _refused('Enrollment 11 is at school 1, not school 5.'));
      await expectLater(superVm.move(99, 42), _refused('Enrollment 99 not found (or not one you can manage).'));
    });

    test("archive, move and restore into another section wait for this device's unsent work", () async {
      final vm = vmFor(auth, unsent: (id) async => id == 11 ? 2 : 0);
      final upload = leaverUploadFirstMessage(2);
      expect(upload, "This device has 2 records of this learner that are not on the server yet: upload this "
          "device's work first (sync-upload), then try again.");
      await expectLater(vm.archive(11, EnrollmentStatus.droppedOut), _refused(upload));
      await expectLater(vm.move(11, 42, source: 'sf1_incoming'), _refused(upload));
      await expectLater(vm.restore(11, toSectionId: 42), _refused(upload));
      expect(repo.calls, isEmpty);
      // Into their own section only the enrollment changes: not blocked.
      await vm.restore(11);
      // Another learner's unsent work doesn't block this one.
      await vm.archive(12, EnrollmentStatus.droppedOut);
      expect(repo.calls, ['restore(11, null)', 'archive(12, dropped_out, null)']);
    });

    test('move refuses another source', () async {
      await expectLater(vmFor(auth).move(11, 42, source: 'return'),
          _refused('The move source must be sf1_missing or sf1_incoming.'));
      expect(repo.calls, isEmpty);
    });

    test('restore calls the server function and mirrors its result', () async {
      final vm = vmFor(auth);
      final out = await vm.restore(11, toSectionId: 42);
      expect(repo.calls, ['restore(11, 42)']);
      expect(mirrored.single['enrollment']['status'], 'active');
      expect(out.enrollment!.status, EnrollmentStatus.active);
      expect(out.message, contains('ARAL is not restored'));
      expect(out.message, contains('saved on the server; pull to refresh this device'));
      await vm.restore(12);
      expect(repo.calls.last, 'restore(12, null)');
    });

    test('a failed device copy still reports the server change', () async {
      final vm = LearnerLeaversViewModel(
          auth: auth,
          cloud: (_) => repo,
          mirror: (_) async => throw StateError('disk'),
          localStudent: (_) async => null,
          unsentRecords: (_) async => 0);
      final out = await vm.archive(11, EnrollmentStatus.droppedOut);
      expect(out.mirrored, isFalse);
      expect(out.message, contains("saved on the server, but this device's copy was not updated"));
    });
  });

  group('anonymize', () {
    test('a stale code is refused; the preview code anonymizes everyone listed', () async {
      repo.eligible = [
        {'student_id': 21, 'left_on': '2025-01-10', 'school_year': '2024-2025'},
        {'student_id': 22, 'left_on': '2025-02-10', 'school_year': '2024-2025'},
      ];
      final vm = vmFor(auth, students: {
        21: Student(id: 21, lrn: '999999002101', lastName: 'Fixture21', firstName: 'Zed', schoolId: 1),
      });
      final preview = await vm.anonymizePreview();
      expect(preview.learners.map((l) => l.studentId), [21, 22]);
      expect(preview.learners.first.name, 'Fixture21, Zed');
      expect(preview.learners.last.name, isNull); // not on this device
      expect(preview.code, isNotEmpty);

      repo.eligible = [...repo.eligible, {'student_id': 23, 'left_on': '2025-03-10', 'school_year': '2024-2025'}];
      await expectLater(vm.anonymize(preview.code),
          _refused('The list changed since the preview: preview again (learner-anonymize-preview).'));
      expect(repo.calls.where((c) => c.startsWith('anonymize(')), isEmpty);

      final again = await vm.anonymizePreview();
      expect(await vm.anonymize(again.code), 3);
      expect(repo.calls.where((c) => c.startsWith('anonymize(')), ['anonymize(21)', 'anonymize(22)', 'anonymize(23)']);
      expect(mirrored, hasLength(3));
      expect(vm.lastMessage, contains('pull to finish clearing'));
    });

    test('an empty list anonymizes nobody', () async {
      final vm = vmFor(auth);
      final preview = await vm.anonymizePreview();
      expect(preview.learners, isEmpty);
      expect(await vm.anonymize(preview.code), 0);
      expect(repo.calls.where((c) => c.startsWith('anonymize(')), isEmpty);
    });
  });

  group('missing (the last import)', () {
    final dir = Directory.systemTemp.createTempSync('basa_leavers_vm_').path;
    late Database db;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      db = await LocalDatabase.instance(dir);
      await db.insert('schools', {'id': 1, 'school_id': 'ZZ55', 'school_name': 'ZZ Leavers VM', 'region_id': 13});
    });

    tearDownAll(LocalDatabase.close);

    String sf1(List<String> lrns) {
      final excel = Excel.createExcel();
      final sheet = excel[excel.tables.keys.first];
      void put(int r, int c, String v) =>
          sheet.updateCell(CellIndex.indexByColumnRow(rowIndex: r, columnIndex: c), TextCellValue(v));
      put(2, 5, 'ZZ55');
      put(2, 10, 'Region X');
      put(3, 5, 'ZZ Leavers VM');
      put(3, 19, _year);
      put(3, 30, '4');
      put(3, 38, 'G4-A');
      for (var i = 0; i < lrns.length; i++) {
        put(6 + i, 0, lrns[i]);
        put(6 + i, 2, 'Filerow$i');
        put(6 + i, 3, 'Zed');
        put(6 + i, 6, 'M');
      }
      final path = '$dir/sf1_${DateTime.now().microsecondsSinceEpoch}.xlsx';
      File(path).writeAsBytesSync(excel.save()!);
      return path;
    }

    test('unsent work blocks only its own learner (device copy)', () async {
      await db.insert('sections', {'id': 61, 'school_id': 1, 'school_year': _year, 'grade_level': '4', 'section_name': 'G4-U'});
      for (final i in [1, 2, 3]) {
        await db.insert('students', {'id': 6100 + i, 'lrn': '99999906100$i', 'last_name': 'ZZU', 'first_name': 'L$i',
            'school_id': 1});
        await db.insert('enrollments',
            {'id': 6110 + i, 'student_id': 6100 + i, 'section_id': 61, 'school_year': _year, 'status': 'active'});
      }
      Map<String, Object?> gst(int id, int student, String origin) => {'id': id, 'student_id': student, 'school_id': 1,
          'section_id': 61, 'school_year': _year, 'attempt_no': 1, 'max_score': 40, 'total_score': 20,
          'taken_at': '2026-10-01', 'origin': origin, 'row_version': origin == 'cloud' ? 1 : null};
      await db.transaction((txn) => withSyncBypass(txn, () async {
            // Learner 1: a pulled GST with an edit journaled (unsent edit).
            await txn.insert('phil_iri_gst_results', gst(5001, 6101, 'cloud'));
            await txn.insert('sync_changes',
                {'table_name': 'phil_iri_gst_results', 'row_key': '5001', 'op': 'update', 'base_version': 1});
            // Learner 2: a pulled GST waiting in an upload.
            await txn.insert('phil_iri_gst_results', gst(5002, 6102, 'cloud'));
            await txn.insert('sync_pending', {'table_name': 'phil_iri_gst_results', 'row_key': '5002', 'upload_id': 9});
            // Learner 3: only a pulled, unchanged GST.
            await txn.insert('phil_iri_gst_results', gst(5003, 6103, 'cloud'));
          }));
      expect(await leaverUnsentRecords(db, 6111), 1);
      expect(await leaverUnsentRecords(db, 6112), 1);
      expect(await leaverUnsentRecords(db, 6113), 0);
      expect(await leaverUnsentRecords(db, 999), 0); // not on this device
      final vm = vmFor(auth, unsent: (id) => leaverUnsentRecords(db, id));
      await expectLater(vm.archive(6111, EnrollmentStatus.droppedOut), _refused(leaverUploadFirstMessage(1)));
      await expectLater(vm.move(6112, 62, source: 'sf1_incoming'), _refused(leaverUploadFirstMessage(1)));
      await vm.archive(6113, EnrollmentStatus.droppedOut);
      expect(repo.calls, ['archive(6113, dropped_out, null)']);
    });

    test('import saves the file LRNs; missing lists the active learners not in them', () async {
      final schools = SchoolRepositorySqlite(db);
      final sections = SectionRepositorySqlite(db);
      final students = StudentRepositorySqlite(db);
      final importVm = ImportViewModel(
        auth: auth,
        cloudFactory: (_) => ImportCloudRepos(
          schools: schools,
          sections: sections,
          students: students,
          conflicts: ImportConflictRepositorySqlite(db),
          leavers: repo,
        ),
        localSchools: schools,
        localSections: sections,
        localStudents: students,
        columnMap: await Sf1ColumnMap.load(dir),
      );
      await importVm.import(sf1(['999999005501', '999999005502']));
      final section = (await db.query('sections', where: 'section_name = ?', whereArgs: ['G4-A'])).single;
      final sectionId = section['id'] as int;
      expect(repo.calls, ['saveLastImport($sectionId, 1, $_year)']);
      expect(repo.lastImports[sectionId]!.lrns, ['999999005501', '999999005502']);

      repo.active[sectionId] = [
        {'enrollment_id': 1, 'student_id': 1, 'lrn': '999999005501', 'last_name': 'Filerow0', 'first_name': 'Zed'},
        {'enrollment_id': 3, 'student_id': 3, 'lrn': '999999005503', 'last_name': 'Fixture3', 'first_name': 'Zed'},
      ];
      final missing = await vmFor(auth).missing(sectionId: sectionId);
      expect(repo.calls.last, 'missing(1, $sectionId)');
      expect(missing.single.enrollmentId, 3);
      expect(missing.single.lrn, '999999005503');
      expect(missing.single.name, 'Fixture3, Zed');
      expect(missing.single.sectionId, sectionId);
      expect(missing.single.sectionName, 'G4-A');
    });
  });

  group('archive_keep_months', () {
    test('defaults to 6; a school sets a whole number 1 to 120', () async {
      final local = _Settings(), cloud = _Settings();
      final vm = ReportSettingsViewModel(auth: auth, local: local, cloud: (_) => cloud);
      expect(const ReportSettings().archiveKeepMonths, 6);
      final before = await vm.archiveKeepMonthsLayers(1);
      expect((before.region, before.school, before.effective), (null, null, 6));

      for (final bad in [0, 121]) {
        await expectLater(vm.setArchiveKeepMonths(1, bad),
            _refused('Archived learners are kept 1 to 120 months, not $bad.'));
      }
      await vm.setArchiveKeepMonths(1, 12);
      final after = await vm.archiveKeepMonthsLayers(1);
      expect((after.region, after.school, after.effective), (null, 12, 12));
      expect(cloud.schools[1]!.settings[ReportSettings.archiveKeepMonthsKey], 12);
    });
  });
}
