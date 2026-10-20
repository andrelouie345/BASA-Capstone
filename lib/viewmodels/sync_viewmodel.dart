// lib/viewmodels/sync_viewmodel.dart
//
// Sync (spec docs/superpowers/specs/2026-10-20-sync-design.md). S4: the pull,
// now a merge. Download everything the signed-in user can read, then
// refresh the local copy while keeping this device's work (new rows, edits
// and deletes of server records, records waiting in an upload).
//
// The device belongs to the last user who pulled. A different user's pull is
// refused while the owner has work that is not on the server yet; "discard
// local" deletes that work first. (S5: the upload methods join this class.)
import 'package:supabase/supabase.dart' show SupabaseClient;

import '../core/console/logger.dart';
import '../core/models/assessment_calendar.dart';
import '../core/models/sync_pull.dart';
import '../core/repositories/sync_download_source.dart';
import '../core/repositories/sync_local_repository.dart';
import '../core/services/calendar_rules.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

class SyncViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final SyncLocalRepository _local;
  final SyncDownloadSource Function(SupabaseClient client) _downloadFor;

  SyncViewModel({
    required AuthViewModel auth,
    required SyncLocalRepository local,
    required SyncDownloadSource Function(SupabaseClient client) download,
    Logger? logger,
  })  : _auth = auth,
        _local = local,
        _downloadFor = download,
        _log = ScopedLogger(logger, 'SyncViewModel');

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
