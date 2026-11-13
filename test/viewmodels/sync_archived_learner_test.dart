// SF1 leavers, final review I1 (owner 2026-11-13): a tutor's new records of
// a learner the coordinator archived while the tutor was offline. The
// preview lists them (the server would refuse the whole upload),
// `sync-resolve <table> <key> server` drops such a record and its items from
// the device, `mine` is refused, and the rest of the work uploads. Real
// device database, fake server. Fixture names only.
import 'dart:io';

import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/data/local/sync_local_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/sync_upload_local_sqlite.dart';
import 'package:basa_capstone/core/models/sync_upload.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/repositories/sync_download_source.dart';
import 'package:basa_capstone/core/repositories/sync_remote_repository.dart';
import 'package:basa_capstone/viewmodels/sync_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_online_auth.dart';

const _year = '2026-2027';

/// The server: which learners are archived, and what an upload sent.
class _FakeRemote implements SyncRemoteRepository {
  final archived = <SyncArchivedLearner>[];
  final asked = <List<SyncLearnerKey>>[];
  Map<String, Object?>? sentPayload;

  @override
  Future<List<SyncArchivedLearner>> archivedLearners(List<SyncLearnerKey> learners) async {
    asked.add(learners);
    return [
      for (final a in archived)
        if (learners.contains((a.studentId, a.schoolYear, a.schoolId))) a,
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> rowsWhere(String table, String column, List<Object> values,
          {String columns = '*'}) async =>
      const [];

  @override
  Future<List<SyncUploadRow>> myUploads({List<int>? ids, int limit = 20}) async => const [];

  @override
  Future<SyncUploadRow> insertUpload({
    required String clientUploadId,
    required int? schoolId,
    required String deviceId,
    required String release,
    required Map<String, Object?> payload,
    required Map<String, Object?> summary,
  }) async {
    sentPayload = payload;
    return SyncUploadRow.fromMap({'id': 77, 'status': 'pending', 'created_at': '2026-11-13T00:00:00Z'});
  }

  @override
  Future<bool> autoApprove(int? schoolId) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _NoDownload implements SyncDownloadSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final dir = Directory.systemTemp.createTempSync('basa_sync_archived_').path;
  late Database db;
  late _FakeRemote remote;
  late SyncViewModel vm;
  final auth = FakeOnlineAuth(UserRole.tutor, schoolId: 1);

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await LocalDatabase.instance(dir);
    await db.insert('schools', {'id': 1, 'school_id': 'ZZ71', 'school_name': 'ZZ Sync Archived', 'region_id': 13});
    await db.insert('sections', {'id': 71, 'school_id': 1, 'school_year': _year, 'grade_level': '7', 'section_name': 'G7-Z'});
    for (final i in [1, 2]) {
      await db.insert('students',
          {'id': 7100 + i, 'lrn': '99999907100$i', 'last_name': 'ZZArch$i', 'first_name': 'Lee', 'school_id': 1});
      // The device copy is from before the archive: both active here.
      await db.insert('enrollments',
          {'id': 7110 + i, 'student_id': 7100 + i, 'section_id': 71, 'school_year': _year, 'status': 'active'});
    }
    await db.insert('sync_meta', {'key': 'last_pull_user_id', 'value': auth.currentUser!.id});
    await db.insert('sync_meta', {'key': 'last_pull_at', 'value': '2026-11-01T00:00:00Z'});
    // Entered offline: a GST for each learner (-1 archived learner, -2 the
    // other one).
    for (final (id, student) in [(-1, 7101), (-2, 7102)]) {
      await db.insert('phil_iri_gst_results', {'id': id, 'student_id': student, 'school_id': 1, 'section_id': 71,
          'school_year': _year, 'max_score': 40, 'total_score': 20, 'taken_at': '2026-11-05', 'origin': 'local'});
    }
  });

  tearDownAll(LocalDatabase.close);

  setUp(() {
    remote = _FakeRemote();
    vm = SyncViewModel(
      auth: auth,
      local: SyncLocalRepositorySqlite(db),
      download: (_) => _NoDownload(),
      uploadLocal: SyncUploadLocalSqlite(db),
      remote: (_) => remote,
    );
  });

  Future<List<int>> gstIds() async =>
      [for (final r in await db.query('phil_iri_gst_results', orderBy: 'id')) r['id'] as int];

  test('nothing archived: no problem, and a new record has nothing to resolve', () async {
    final p = await vm.preview();
    expect(p.problems, isEmpty);
    expect(remote.asked.single.toSet(), {(7101, _year, 1), (7102, _year, 1)});
    await expectLater(vm.resolve('phil_iri_gst_results', '-1', SyncChoice.server),
        throwsA(isA<ViewModelException>().having((e) => e.message, 'message', 'Nothing to resolve for phil_iri_gst_results -1.')));
    expect(await gstIds(), [-2, -1]);
  });

  test('an archived learner: listed, mine refused, server drops it, the rest uploads', () async {
    remote.archived.add(
        (studentId: 7101, schoolYear: _year, schoolId: 1, status: 'dropped_out', leftOn: '2026-11-10', name: 'ZZArch1, L.',
            transferredOn: null));

    final p = await vm.preview();
    expect(p.problems.map((x) => '$x'), [
      'phil_iri_gst_results -1: a new record of ZZArch1, L. (archived on 2026-11-10, dropped out); the server refuses it. '
          'Ask the coordinator to restore the learner, or drop it with sync-resolve phil_iri_gst_results -1 server',
    ]);
    expect(p.problems.single.kind, learnerArchivedKind);

    // The upload refuses before sending anything.
    await expectLater(vm.upload(), throwsA(isA<ViewModelException>().having((e) => e.message, 'message',
        startsWith('Resolve these first (sync-resolve <table> <key> mine|server):'))));
    expect(remote.sentPayload, isNull);

    await expectLater(
        vm.resolve('phil_iri_gst_results', '-1', SyncChoice.mine),
        throwsA(isA<ViewModelException>().having((e) => e.message, 'message',
            'Refused: phil_iri_gst_results -1 is a new record of ZZArch1, L. (archived on 2026-11-10, dropped out), '
                'and the server refuses new records of an archived learner, so yours cannot be kept. '
                'Ask the coordinator to restore the learner, then upload; '
                'or drop it with sync-resolve phil_iri_gst_results -1 server.')));
    expect(await gstIds(), [-2, -1]);

    // The other learner's record is not archived: nothing to resolve.
    await expectLater(vm.resolve('phil_iri_gst_results', '-2', SyncChoice.server), throwsA(isA<ViewModelException>()));

    final r = await vm.resolve('phil_iri_gst_results', '-1', SyncChoice.server);
    expect(r.droppedNew, isTrue);
    expect('$r', 'Dropped phil_iri_gst_results -1 and its items from this device: the server refuses new records '
        'of an archived learner. The rest of your work can be uploaded.');
    expect(await gstIds(), [-2]);
    expect(await db.query('sync_changes', where: "table_name = 'phil_iri_gst_results' AND row_key = '-1'"), isEmpty);

    expect((await vm.preview()).problems, isEmpty);
    final sent = await vm.upload();
    expect(sent.uploadId, 77);
    final records = (remote.sentPayload!['records'] as List).cast<Map<String, Object?>>();
    expect(records.map((x) => '${x['table']} ${(x['key'] as Map).values.single}'), ['phil_iri_gst_results -2']);
  });

  test('a learner transferred to another school (D15): listed, mine refused without "restore", server drops it',
      () async {
    await db.insert('phil_iri_gst_results', {'id': -9, 'student_id': 7102, 'school_id': 1, 'section_id': 71,
        'school_year': _year, 'max_score': 40, 'total_score': 21, 'taken_at': '2026-11-06', 'origin': 'local'});
    remote.archived.add((studentId: 7102, schoolYear: _year, schoolId: 1, status: 'transferred_out',
        leftOn: '2026-11-10', name: 'ZZArch2, L.', transferredOn: '2026-11-12'));
    final p = await vm.preview();
    final problem = p.problems.singleWhere((x) => x.key == '-9');
    expect(problem.transferred, isTrue);
    expect('$problem', 'phil_iri_gst_results -9: a new record of ZZArch2, L. (transferred to another school on '
        '2026-11-12); the server refuses it. Drop it with sync-resolve phil_iri_gst_results -9 server');
    await expectLater(
        vm.resolve('phil_iri_gst_results', '-9', SyncChoice.mine),
        throwsA(isA<ViewModelException>().having((e) => e.message, 'message',
            'Refused: phil_iri_gst_results -9 is a new record of ZZArch2, L. (transferred to another school on '
                '2026-11-12), and the server refuses new records of a learner who left this school, so yours cannot '
                'be kept: drop it with sync-resolve phil_iri_gst_results -9 server.')));
    expect((await vm.resolve('phil_iri_gst_results', '-9', SyncChoice.server)).droppedNew, isTrue);
    expect(await db.query('phil_iri_gst_results', where: 'id = -9'), isEmpty);
  });
}
