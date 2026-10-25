// lib/viewmodels/sync_review_viewmodel.dart
//
// Sync S6, the approver's side (spec docs/superpowers/specs/2026-10-20-sync-design.md
// section 5.2): list the uploads waiting for a decision, read one as plain
// lines, approve it (the server's sync_apply, which writes as the uploader)
// or reject it with a reason.
//
// Approvers: an admin or coordinator for their own school; the superadmin for
// every school (or one). Online only. Names come from this device's copy; a
// row it doesn't hold prints its id. Approving never changes this device:
// the approver pulls to see the applied work.
import 'package:supabase/supabase.dart' show PostgrestException, SupabaseClient;

import '../core/console/logger.dart';
import '../core/data/pull_tables.dart' show syncedTables;
import '../core/models/sync_upload.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/sync_remote_repository.dart';
import '../core/repositories/sync_review_local_repository.dart';
import '../core/services/sync_review_lines.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// Longest reject reason the device accepts (S6 decision 7).
const maxRejectReasonLength = 500;

/// An upload as the approver sees it in a listing.
class SyncReviewItem {
  final SyncUploadRow upload;

  /// Full name, else email, else the uuid.
  final String uploader;

  /// "school 3 ZZTEST HIGH" for the superadmin's listing; null otherwise.
  final String? school;

  const SyncReviewItem({required this.upload, required this.uploader, this.school});
}

/// Uploads waiting for the approver, and those sent back on a conflict that
/// wait for their uploader. Both oldest first.
class SyncPendingList {
  final List<SyncReviewItem> pending;
  final List<SyncReviewItem> sentBack;
  const SyncPendingList({required this.pending, required this.sentBack});
}

/// One upload and its records as plain lines.
class SyncUploadDetails {
  final SyncReviewItem item;
  final List<String> lines;
  const SyncUploadDetails({required this.item, required this.lines});
}

/// What approving did.
class SyncApproveResult {
  final int uploadId;

  /// applied | conflict | error | release (made by an older BASA release)
  final String status;
  final String? reason;
  final List<SyncProblem> conflicts;
  final String uploader;

  const SyncApproveResult(
      {required this.uploadId, required this.status, required this.uploader, this.reason, this.conflicts = const []});

  @override
  String toString() => switch (status) {
        'applied' => 'Upload $uploadId applied. Download the latest data to see it on this device (pull-cloud).',
        'conflict' => 'Upload $uploadId stopped on ${conflicts.length} conflict(s), sent back to $uploader:\n'
            '${conflicts.map((c) => '  $c').join('\n')}',
        'release' => 'Upload $uploadId was made by an older BASA release: reject it so $uploader updates BASA '
            'and syncs again.',
        _ => 'Upload $uploadId failed on the server: ${reason ?? 'unknown error'}',
      };
}

class SyncReviewViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final SyncReviewLocalRepository _local;
  final SyncRemoteRepository Function(SupabaseClient client) _remoteFor;

  SyncReviewViewModel({
    required AuthViewModel auth,
    required SyncReviewLocalRepository local,
    required SyncRemoteRepository Function(SupabaseClient client) remote,
    Logger? logger,
  })  : _auth = auth,
        _local = local,
        _remoteFor = remote,
        _log = ScopedLogger(logger, 'SyncReviewViewModel');

  /// Pending uploads of [schoolId] (the superadmin: null = every school; an
  /// admin/coordinator: their own school), plus those sent back.
  Future<SyncPendingList> pending({int? schoolId}) async {
    _log('pending(schoolId: $schoolId)');
    final me = _approver();
    final superadmin = _isSuperadmin(me);
    final scope = superadmin ? schoolId : _ownSchool(me, schoolId);
    final remote = _remoteFor(_auth.client!);
    final rows = await _server('read the uploads',
        () => remote.schoolUploads(schoolId: scope, statuses: const ['pending', 'conflict']));
    final items = await _items(rows, withSchool: superadmin);
    return SyncPendingList(
      pending: [for (final i in items) if (i.upload.status == 'pending') i],
      sentBack: [for (final i in items) if (i.upload.status == 'conflict') i],
    );
  }

  /// The newest pending upload the approver may decide (null when none).
  Future<int?> latestPendingId({int? schoolId}) async =>
      (await pending(schoolId: schoolId)).pending.lastOrNull?.upload.id;

  /// Upload [id] with one line per record.
  Future<SyncUploadDetails> details(int id) async {
    _log('details($id)');
    final me = _approver();
    final remote = _remoteFor(_auth.client!);
    final row = await _server('read upload $id', () => remote.uploadById(id, withPayload: true));
    if (row == null) throw ViewModelException('Upload $id not found (or not one you can review).');
    final item = (await _items([row], withSchool: _isSuperadmin(me))).single;
    // Nothing checks a package's shape before it is applied, so it may hold
    // anything: refuse plainly instead of failing on a cast.
    final List<String> lines;
    try {
      final records = row.records;
      lines = describeUpload(records, await _context(records));
    } catch (e) {
      throw ViewModelException('Upload $id has a package this device cannot read ($e). '
          'Reject it so the uploader syncs again.');
    }
    return SyncUploadDetails(item: item, lines: lines);
  }

  /// Applies upload [id] on the server (as its uploader). A conflict sends it
  /// back to the uploader; an error leaves the reason on the upload.
  Future<SyncApproveResult> approve(int id) async {
    _log('approve($id)');
    _approver();
    final remote = _remoteFor(_auth.client!);
    final row = await _server('read upload $id', () => remote.uploadById(id));
    if (row == null) throw ViewModelException('Upload $id not found (or not one you can review).');
    final uploader = await _uploaderLabel(row.uploaderId);
    final SyncApplyResult r;
    try {
      r = await remote.apply(id);
    } on PostgrestException catch (e) {
      if (e.message.contains('older BASA release')) {
        return SyncApproveResult(uploadId: id, status: 'release', uploader: uploader, reason: e.message);
      }
      throw ViewModelException(e.message);
    } catch (e) {
      throw ViewModelException('Could not approve upload $id, nothing was changed: $e');
    }
    _log('upload $id: ${r.status}');
    return SyncApproveResult(
        uploadId: id, status: r.status, uploader: uploader, reason: r.reason, conflicts: r.conflicts);
  }

  /// Sends upload [id] back with [reason]; returns the uploader's label.
  Future<String> reject(int id, String reason) async {
    _log('reject($id)');
    _approver();
    final text = reason.trim();
    if (text.isEmpty) throw const ViewModelException('A reason is required to reject an upload.');
    if (text.length > maxRejectReasonLength) {
      throw ViewModelException(
          'The reason is ${text.length} characters; keep it to $maxRejectReasonLength.');
    }
    final remote = _remoteFor(_auth.client!);
    final row = await _server('read upload $id', () => remote.uploadById(id));
    if (row == null) throw ViewModelException('Upload $id not found (or not one you can review).');
    await _server('reject upload $id', () => remote.reject(id, text));
    return _uploaderLabel(row.uploaderId);
  }

  // ---- Helpers ----

  /// The signed-in approver (online). Tutors are refused.
  User _approver() {
    final error = _auth.requireOnlineSession();
    if (error != null) throw ViewModelException(error);
    final me = _auth.currentUser!;
    if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
      throw const ViewModelException('Forbidden: only an admin or coordinator reviews uploads.');
    }
    return me;
  }

  /// The regional admin (no school); a coordinator never is.
  bool _isSuperadmin(User me) => me.role == UserRole.admin && me.schoolId == null;

  int _ownSchool(User me, int? schoolId) {
    if (me.schoolId == null) {
      throw const ViewModelException('Forbidden: your account has no school, so it reviews no uploads.');
    }
    if (schoolId != null && schoolId != me.schoolId) {
      throw const ViewModelException("Forbidden: you can only review your own school's uploads.");
    }
    return me.schoolId!;
  }

  Future<List<SyncReviewItem>> _items(List<SyncUploadRow> rows, {required bool withSchool}) async {
    final users = await _byKey('users', 'id', {for (final r in rows) ?r.uploaderId});
    final schools = withSchool ? await _byKey('schools', 'id', {for (final r in rows) ?r.schoolId}) : null;
    return [
      for (final r in rows)
        SyncReviewItem(
          upload: r,
          uploader: _userLabel(users[r.uploaderId], r.uploaderId),
          school: schools == null
              ? null
              : r.schoolId == null
                  ? 'region'
                  : 'school ${r.schoolId} ${schools['${r.schoolId}']?['school_name'] ?? ''}'.trim(),
        ),
    ];
  }

  Future<String> _uploaderLabel(String? id) async =>
      _userLabel(id == null ? null : (await _byKey('users', 'id', {id}))[id], id);

  String _userLabel(Map<String, Object?>? u, String? id) {
    final name = u?['full_name'] as String?;
    if (name != null && name.trim().isNotEmpty) return name;
    return (u?['email'] as String?) ?? id ?? 'unknown uploader';
  }

  Future<Map<String, Map<String, Object?>>> _byKey(String table, String column, Set<Object> keys) async {
    if (keys.isEmpty) return const {};
    return {for (final r in await _local.rowsWhere(table, column, keys.toList())) '${r[column]}': r};
  }

  /// This device's rows the records' lines need. A found row can name
  /// another (a deleted mark names its session), so ask until nothing new.
  Future<SyncReviewContext> _context(List<Map<String, Object?>> records) async {
    final rows = <String, Map<String, Map<String, Object?>>>{};
    final asked = <String>{};
    while (true) {
      final ctx = SyncReviewContext(rows);
      final misses = referencedKeys(records, ctx);
      var askedSomething = false;
      for (final e in misses.entries) {
        final fresh = [for (final k in e.value) if (asked.add('${e.key} $k')) k];
        if (fresh.isEmpty) continue;
        askedSomething = true;
        final column = syncedTables[e.key] ?? 'id';
        final values = <Object>[for (final k in fresh) column == 'tutor_id' || e.key == 'users' ? k : int.parse(k)];
        for (final r in await _local.rowsWhere(e.key, column, values)) {
          (rows[e.key] ??= {})['${r[column]}'] = r;
        }
      }
      if (!askedSomething) return ctx;
    }
  }

  /// Runs a server step; a network or server error becomes a plain refusal.
  Future<T> _server<T>(String what, Future<T> Function() body) async {
    try {
      return await body();
    } on ViewModelException {
      rethrow;
    } on PostgrestException catch (e) {
      throw ViewModelException('Could not $what: ${e.message}');
    } catch (e) {
      throw ViewModelException('Could not $what, nothing was changed: $e');
    }
  }
}
