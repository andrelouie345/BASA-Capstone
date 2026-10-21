// lib/viewmodels/sync_viewmodel.dart
//
// Sync (spec docs/superpowers/specs/2026-10-20-sync-design.md). S4: the pull,
// now a merge. Download everything the signed-in user can read, then
// refresh the local copy while keeping this device's work (new rows, edits
// and deletes of server records, records waiting in an upload).
//
// The device belongs to the last user who pulled. A different user's pull is
// refused while the owner has work that is not on the server yet; "discard
// local" deletes that work first.
//
// S5, the upload: preview (what would go, and what stops it: records the
// server changed or deleted since the pull, a new tutor setting the server
// already has), resolve (keep mine / take the server's), upload, refresh
// (take in the server's decisions), withdraw.
import 'dart:convert';

import 'package:supabase/supabase.dart' show PostgrestException, SupabaseClient;

import '../core/console/logger.dart';
import '../core/models/assessment_calendar.dart';
import '../core/data/pull_tables.dart';
import '../core/models/sync_pull.dart';
import '../core/models/sync_upload.dart';
import '../core/models/user_role.dart';
import '../core/release.dart';
import '../core/repositories/sync_download_source.dart';
import '../core/repositories/sync_local_repository.dart';
import '../core/repositories/sync_remote_repository.dart';
import '../core/repositories/sync_upload_local_repository.dart';
import '../core/services/sync_upload_rules.dart';
import '../core/services/calendar_rules.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

class SyncViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final SyncLocalRepository _local;
  final SyncDownloadSource Function(SupabaseClient client) _downloadFor;
  final SyncUploadLocalRepository _uploadLocal;
  final SyncRemoteRepository Function(SupabaseClient client) _remoteFor;

  SyncViewModel({
    required AuthViewModel auth,
    required SyncLocalRepository local,
    required SyncDownloadSource Function(SupabaseClient client) download,
    required SyncUploadLocalRepository uploadLocal,
    required SyncRemoteRepository Function(SupabaseClient client) remote,
    Logger? logger,
  })  : _auth = auth,
        _local = local,
        _downloadFor = download,
        _uploadLocal = uploadLocal,
        _remoteFor = remote,
        _log = ScopedLogger(logger, 'SyncViewModel');

  /// Only after [_guard].
  SyncRemoteRepository get _remote => _remoteFor(_auth.client!);

  /// The release this build was made for: the newest migration it knows.
  static String get release => basaMigrations.keys.last;

  /// The signed-in user's email (the owner after a pull).
  String? get currentEmail => _auth.currentUser?.email;

  /// Who owns the device, who is signed in, and the work a pull keeps.
  Future<PullPreview> pullPreview() async {
    _guard();
    final user = _auth.currentUser;
    return PullPreview(
      owner: await _local.owner(),
      currentUserId: user?.id,
      currentEmail: user?.email,
      localWork: await _local.localWork(),
    );
  }

  /// Refreshes the local copy from the server, keeping this device's work
  /// (or deleting it first with [discardLocal]). All or nothing: any refusal
  /// or error leaves the local copy as it was. Throws [ViewModelException].
  Future<PullResult> pull({bool discardLocal = false}) async {
    _log('pull(discardLocal: $discardLocal)');
    // Applied uploads first, or their device copies would stay next to the
    // server's (S4 review I3).
    await refreshStatus();
    final preview = await pullPreview();
    if (preview.ownerSwitch && preview.localTotal > 0 && !discardLocal) {
      throw ViewModelException('Refused: this device holds work of ${preview.owner!.email ?? preview.owner!.userId} '
          'that is not on the server yet:\n${_lines(preview.localWork)}\n'
          'They must sync first, or run "pull-cloud yes discard-local" to delete it.');
    }

    final Map<String, List<Map<String, dynamic>>> fetched;
    try {
      fetched = await _downloadFor(_auth.client!).downloadAll();
    } catch (e) {
      throw ViewModelException('Pull stopped while downloading, nothing was changed: $e');
    }

    final PullMerge merge;
    try {
      merge = await _local.mergePull(fetched,
          userId: preview.currentUserId!, email: preview.currentEmail, discardLocal: discardLocal);
    } on PullOrphansException catch (e) {
      throw ViewModelException('Refused, nothing was changed: ${e.orphans.length} record(s) on this device point at '
          'data the server no longer gives you:\n${e.orphans.map((o) => '  $o').join('\n')}\n'
          'Run "pull-cloud yes discard-local" to delete this device\'s unsent work.');
    } catch (e) {
      throw ViewModelException('Pull stopped, nothing was changed (rolled back): $e');
    }
    _log('pull done: kept ${merge.keptNew} new, ${merge.keptChanged} changed, ${merge.keptPending} pending');
    return PullResult(
      merge: merge,
      ownerChanged: preview.ownerSwitch,
      previousOwnerEmail: preview.owner?.email,
      unknownCalendarRounds: _unknownCalendarRounds(fetched['assessment_calendar'] ?? const []),
    );
  }

  /// What an upload would send now and what stops it. Takes in the
  /// server's decisions on earlier uploads first. Throws [ViewModelException].
  Future<SyncPreview> preview() async {
    _guard();
    final settled = await refreshStatus();
    final package = await _uploadLocal.buildPackage(release: release);
    final problems = await _server('check the records against the server', () => _problems(package));
    return SyncPreview(package: package, problems: problems, settled: settled);
  }

  /// Settles one problem of [preview]: [SyncChoice.mine] keeps this device's
  /// change (overwriting the server's newer version), [SyncChoice.server]
  /// drops it and takes the server's copy of the record and its items.
  Future<SyncResolution> resolve(String table, String key, SyncChoice choice) async {
    _log('resolve($table, $key, ${choice.name})');
    _guard();
    if (await _uploadLocal.isPending(table, key)) throw ViewModelException(pendingLockMessage);
    final package = await _uploadLocal.buildPackage(release: release);
    final r = package.records
        .where((r) =>
            r.table == table && r.rowKey == key && !r.isFollowUp && (r.op != 'insert' || table == 'aral_tutor_settings'))
        .firstOrNull;
    if (r == null) throw ViewModelException('Nothing to resolve for $table $key.');
    final remote = _remote;
    final server = await _server('read $table $key from the server',
        () async => (await remote.rowsWhere(table, r.keyColumn, [r.key])).firstOrNull);
    final version = (server?['row_version'] as num?)?.toInt();

    if (r.op == 'insert') {
      // A new tutor setting: only a problem when the server has one.
      if (version == null) throw ViewModelException('Nothing to resolve for $table $key.');
      if (choice == SyncChoice.mine) {
        await _uploadLocal.adoptServerSetting(key, version);
      } else {
        await _uploadLocal.restoreServerCopy(table, key, {table: [server!]});
      }
    } else {
      if (version == r.baseVersion) throw ViewModelException('Nothing to resolve for $table $key.');
      if (choice == SyncChoice.mine) {
        if (version != null) {
          await _uploadLocal.setBaseVersion(table, key, version);
        } else if (r.op == 'delete') {
          await _uploadLocal.dropJournalLine(table, key);
        } else {
          throw ViewModelException('The server no longer has $table $key for you, so your change cannot be kept. '
              'Use "server" to drop it.');
        }
      } else {
        final rows = server == null
            ? const <String, List<Map<String, dynamic>>>{}
            : await _server('read $table $key from the server', () => _serverTree(remote, table, server));
        await _uploadLocal.restoreServerCopy(table, key, rows);
      }
    }
    return SyncResolution(table: table, key: key, choice: choice, serverVersion: version);
  }

  /// Takes in the server's decisions on this device's uploads: an applied
  /// upload's records become server copies with their real ids; a rejected,
  /// failed, withdrawn or conflicting one is unlocked. Settles an upload
  /// whose answer never came first. Only for the device owner (another
  /// user cannot see the owner's uploads): returns nothing for anyone else.
  Future<List<SyncOutcome>> refreshStatus() async {
    _guard();
    if (!await _isOwner()) return const [];
    final remote = _remote;
    await _settleInFlight(remote);
    final ids = await _uploadLocal.pendingUploadIds();
    if (ids.isEmpty) return const [];
    final rows = await _server('read your uploads', () => remote.myUploads(ids: ids));
    final byId = {for (final r in rows) r.id: r};
    final out = <SyncOutcome>[];
    for (final id in ids) {
      final records = (await _uploadLocal.pendingRecords(id)).length;
      final row = byId[id];
      if (row == null) {
        out.add(SyncOutcome(uploadId: id, status: 'unknown', records: records));
        continue;
      }
      switch (row.status) {
        case 'pending':
          continue;
        case 'applied':
          await _takeIn(remote, row);
        default:
          await _uploadLocal.releaseUpload(id);
      }
      _log('upload $id: ${row.status}');
      out.add(SyncOutcome(uploadId: id, status: row.status, records: records, reason: row.reason, conflicts: row.conflicts));
    }
    return out;
  }

  /// Sends everything [preview] lists as one upload. The device owner only;
  /// refused while a problem is unresolved. Applied at once when the school
  /// auto-approves or the uploader is an admin/coordinator.
  Future<SyncUploadResult> upload() async {
    _log('upload()');
    _guard();
    await _requireOwner();
    final p = await preview();
    if (p.package.isEmpty) throw ViewModelException('Nothing to upload.');
    if (p.problems.isNotEmpty) {
      throw ViewModelException('Resolve these first (sync-resolve <table> <key> mine|server):\n'
          '${p.problems.map((x) => '  $x').join('\n')}');
    }
    final payload = p.package.toJson();
    final bytes = utf8.encode(jsonEncode(payload)).length;
    if (bytes > maxPackageBytes) {
      throw ViewModelException('Too much unsynced work for one upload (${bytes ~/ 1024} KB, the limit is '
          '${maxPackageBytes ~/ 1024} KB); sync more often:\n${_lines(p.package.summary)}');
    }

    final clientId = newUuidV4();
    try {
      await _uploadLocal.beginUpload(clientId, p.package);
    } on StateError catch (e) {
      throw ViewModelException(e.message);
    }
    final remote = _remote;
    SyncUploadRow row;
    try {
      row = await remote.insertUpload(
        clientUploadId: clientId,
        schoolId: _auth.currentUser!.schoolId,
        deviceId: p.package.deviceId,
        release: release,
        payload: payload,
        summary: p.package.summaryJson(),
      );
    } catch (e) {
      // The answer may be lost while the row got there: ask once.
      final SyncUploadRow? found;
      try {
        found = await remote.uploadByClientId(clientId);
      } catch (_) {
        throw ViewModelException('Upload state unknown (the server did not answer): ${_plain(e)}\n'
            'Its rows stay locked; run sync-status when online.');
      }
      if (found == null) {
        await _uploadLocal.abandonUpload();
        throw ViewModelException('Upload refused, nothing was sent: ${_plain(e)}');
      }
      row = found;
    }
    await _uploadLocal.confirmUpload(row.id);
    _log('upload ${row.id} sent (${p.package.records.length} records)');

    final user = _auth.currentUser!;
    String? applyError;
    var applyNow = user.role == UserRole.admin || user.role == UserRole.coordinator;
    try {
      applyNow = applyNow || await remote.autoApprove(user.schoolId);
      if (applyNow) await remote.apply(row.id);
    } catch (e) {
      applyError = _plain(e);
    }
    final outcomes = applyNow ? await refreshStatus() : const <SyncOutcome>[];
    return SyncUploadResult(
      uploadId: row.id,
      records: p.package.rowCount,
      outcome: outcomes.where((o) => o.uploadId == row.id).firstOrNull,
      applyError: applyError,
    );
  }

  /// Takes back a pending upload (or one stopped on a conflict) so its
  /// records can be changed and sent again.
  Future<void> withdraw(int uploadId) async {
    _log('withdraw($uploadId)');
    _guard();
    await _requireOwner();
    final remote = _remote;
    await _server('withdraw upload $uploadId', () => remote.withdraw(uploadId));
    await _uploadLocal.releaseUpload(uploadId);
  }

  /// The signed-in user's latest uploads (newest first).
  Future<List<SyncUploadRow>> uploads() async {
    _guard();
    final remote = _remote;
    return _server('read your uploads', () => remote.myUploads());
  }

  /// How many of this device's records are locked, per upload (0 = being sent).
  Future<Map<int, int>> lockedCounts() async => {
        for (final id in [if (await _uploadLocal.inFlight() != null) 0, ...await _uploadLocal.pendingUploadIds()])
          id: (await _uploadLocal.pendingRecords(id)).length,
      };

  /// The future sync button: refresh, preview, upload if [confirm] agrees
  /// and nothing stops it, then pull.
  Future<SyncRunResult> sync({required Future<bool> Function(SyncPreview preview) confirm}) async {
    _log('sync()');
    final p = await preview();
    SyncUploadResult? sent;
    if (!p.package.isEmpty && p.problems.isEmpty && await confirm(p)) sent = await upload();
    final pulled = await pull();
    return SyncRunResult(preview: p, upload: sent, pull: pulled);
  }

  /// An upload whose answer never came: adopted if the server has it,
  /// unlocked if not. Refuses (records stay locked) when the server can't say.
  Future<void> _settleInFlight(SyncRemoteRepository remote) async {
    final f = await _uploadLocal.inFlight();
    if (f == null) return;
    final SyncUploadRow? found;
    try {
      found = await remote.uploadByClientId(f.clientUploadId);
    } catch (e) {
      throw ViewModelException('Upload state unknown (the server did not answer): ${_plain(e)}\n'
          'Its ${f.recordCount} row(s) stay locked; run sync-status when online.');
    }
    if (found == null) {
      await _uploadLocal.abandonUpload();
      _log('in-flight upload never arrived; unlocked');
    } else {
      await _uploadLocal.confirmUpload(found.id);
      _log('in-flight upload found as ${found.id}');
    }
  }

  /// Reads the applied records back from the server under their new keys and
  /// takes them in.
  Future<void> _takeIn(SyncRemoteRepository remote, SyncUploadRow row) async {
    final idMap = {
      for (final t in row.idMap.entries) t.key: {for (final e in t.value.entries) int.parse(e.key): e.value},
    };
    final flat = {for (final m in idMap.values) ...m};
    final keys = <String, List<Object>>{};
    for (final (table, key) in await _uploadLocal.pendingRecords(row.id)) {
      final keyColumn = syncedTables[table]!;
      (keys[table] ??= []).add(keyColumn == 'tutor_id' ? key : flat[int.parse(key)] ?? int.parse(key));
    }
    final serverRows = <String, List<Map<String, dynamic>>>{};
    await _server('read upload ${row.id} back from the server', () async {
      for (final e in keys.entries) {
        serverRows[e.key] = await remote.rowsWhere(e.key, syncedTables[e.key]!, e.value);
      }
    });
    await _uploadLocal.takeInApplied(row.id, idMap, serverRows);
  }

  Future<bool> _isOwner() async => (await _local.owner())?.userId == _auth.currentUser?.id;

  /// Only the device owner (the last puller) uploads this device's work.
  Future<void> _requireOwner() async {
    final owner = await _local.owner();
    if (owner == null) throw ViewModelException('This device was never pulled. Run "pull-cloud yes" first.');
    if (owner.userId != _auth.currentUser?.id) {
      throw ViewModelException('This device\'s work belongs to ${owner.email ?? owner.userId}; only they can sync it.');
    }
  }

  /// The server's own message where there is one.
  String _plain(Object e) => e is PostgrestException ? e.message : '$e';

  /// Version conflicts, records the server no longer gives this user, and
  /// new tutor settings the server already has (spec 5.1, plan decision 4).
  Future<List<SyncProblem>> _problems(SyncPackage p) async {
    final byTable = <String, List<SyncRecord>>{};
    for (final r in p.records) {
      if (r.isFollowUp) continue; // checked through the record it follows
      if (r.op != 'insert' || r.table == 'aral_tutor_settings') byTable.putIfAbsent(r.table, () => []).add(r);
    }
    final remote = _remote;
    final out = <SyncProblem>[];
    for (final e in byTable.entries) {
      final keyColumn = e.value.first.keyColumn;
      final rows = await remote.rowsWhere(e.key, keyColumn, [for (final r in e.value) r.key],
          columns: '$keyColumn, row_version');
      final server = {for (final row in rows) '${row[keyColumn]}': (row['row_version'] as num).toInt()};
      for (final r in e.value) {
        final v = server[r.rowKey];
        if (r.op == 'insert') {
          if (v != null) out.add(SyncProblem(table: r.table, key: r.rowKey, kind: 'clash', serverVersion: v));
        } else if (v == null) {
          out.add(SyncProblem(table: r.table, key: r.rowKey, kind: 'server_deleted', baseVersion: r.baseVersion));
        } else if (v != r.baseVersion) {
          out.add(SyncProblem(
              table: r.table, key: r.rowKey, kind: 'conflict', baseVersion: r.baseVersion, serverVersion: v));
        }
      }
    }
    return out;
  }

  /// [row] of [table] and its items on the server, any depth.
  Future<Map<String, List<Map<String, dynamic>>>> _serverTree(
      SyncRemoteRepository remote, String table, Map<String, dynamic> row) async {
    final out = <String, List<Map<String, dynamic>>>{table: [row]};
    final queue = [table];
    while (queue.isNotEmpty) {
      final parent = queue.removeAt(0);
      for (final e in syncedParents.entries.where((e) => e.value.$1 == parent)) {
        final keys = [for (final r in out[parent]!) r[syncedTables[parent]] as Object];
        out[e.key] = keys.isEmpty ? [] : await remote.rowsWhere(e.key, e.value.$2, keys);
        queue.add(e.key);
      }
    }
    return out;
  }

  /// Runs a server step; a network or server error becomes a plain refusal.
  Future<T> _server<T>(String what, Future<T> Function() body) async {
    try {
      return await body();
    } on ViewModelException {
      rethrow;
    } catch (e) {
      throw ViewModelException('Could not $what, nothing was changed: $e');
    }
  }


  void _guard() {
    final error = _auth.requireOnlineSession();
    if (error != null) throw ViewModelException(error);
  }
}

String _lines(List<LocalWorkLine> work) => work.map((l) => '  $l').join('\n');

/// "CRLA mosy2 (row 12)" for each pulled calendar row whose round this app
/// version does not know for its instrument (the server holds a newer round
/// list than this app).
List<String> _unknownCalendarRounds(List<Map<String, dynamic>> rows) => [
      for (final r in rows)
        if (!isCalendarRound(CalendarInstrument.parse(r['instrument'] as String), r['round'] as String))
          '${CalendarInstrument.parse(r['instrument'] as String).label} ${r['round']} (row ${r['id']})',
    ];
