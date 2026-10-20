// lib/core/console/commands/pull_commands.dart

/// pull-cloud: refresh the local copy from the server (SyncViewModel.pull, a
/// merge that keeps this device's unsent work).
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/sync_viewmodel.dart';
import '../../../viewmodels/viewmodel_exception.dart';

void registerPullCommands(ConsoleRegistry registry, SyncViewModel syncVm) {
  registry.register(ConsoleCommand(
    name: 'pull-cloud',
    description: 'pull-cloud yes [discard-local] — refresh the local copy with everything the signed-in user '
        'can read on the server, keeping this device\'s unsent work (discard-local deletes it first)',
    handler: (args) async {
      try {
        if (args.isEmpty || args[0] != 'yes') {
          final p = await syncVm.pullPreview();
          final out = StringBuffer()
            ..writeln('This refreshes the local copy (schools, users, sections, learners, enrollments, CRLA, '
                'Phil-IRI, ARAL, SRP) with everything ${p.currentEmail} can read on the server. '
                'Regions and login logs are kept.')
            ..writeln('Local data was last pulled by ${p.owner ?? "nobody (never pulled)"}.');
          final lines = p.localWork.map((l) => '  $l').join('\n');
          if (p.ownerSwitch && p.localTotal > 0) {
            out.writeln('This device holds work of ${p.owner!.email ?? p.owner!.userId} that is not on the server '
                'yet; the pull will refuse until they sync (or "pull-cloud yes discard-local" deletes it):\n$lines');
          } else if (p.ownerSwitch) {
            out.writeln('The pull replaces ${p.owner!.email ?? p.owner!.userId}\'s copy with yours.');
          } else if (p.localTotal > 0) {
            out.writeln('Kept on this device (not on the server yet):\n$lines');
          }
          out.write('Run "pull-cloud yes" to continue.');
          return out.toString();
        }

        final discardLocal = args.length > 1 && args[1] == 'discard-local';
        final r = await syncVm.pull(discardLocal: discardLocal);
        final m = r.merge;
        final out = StringBuffer();
        for (final e in m.serverRows.entries) {
          out.writeln('${e.key}: ${e.value} rows');
        }
        if (m.keptNew + m.keptChanged + m.keptPending > 0) {
          out.writeln('Kept on this device: ${m.keptNew} new, ${m.keptChanged} changed, '
              '${m.keptPending} waiting for approval.');
        }
        if (m.skippedUnderDeleted > 0) {
          out.writeln('${m.skippedUnderDeleted} server row(s) under records deleted on this device not written '
              '(they go away once the delete is uploaded).');
        }
        if (m.skippedNewClash > 0) {
          out.writeln('${m.skippedNewClash} server row(s) not written: a record made on this device has the same key '
              '(sorted out when it is uploaded).');
        }
        if (m.discarded + m.discardedChanges > 0) {
          out.writeln('Discarded this device\'s unsent work: ${m.discarded} new record(s), '
              '${m.discardedChanges} change(s) to server records.');
        }
        if (m.discardedPending > 0) {
          out.writeln('Dropped the lock on ${m.discardedPending} record(s) in pending uploads; those uploads are still '
              'on the server and come back with a later pull if they are approved.');
        }
        if (r.ownerChanged) out.writeln('Replaced the copy of ${r.previousOwnerEmail}.');
        out.write('Done. Local data now belongs to ${syncVm.currentEmail}.');
        if (r.unknownCalendarRounds.isNotEmpty) {
          out.write('\nWARNING: ${r.unknownCalendarRounds.length} calendar row(s) use a round this app version does '
              'not know (${r.unknownCalendarRounds.join(', ')}); they are ignored until the app is updated.');
        }
        return out.toString();
      } on ViewModelException catch (e) {
        return e.message;
      }
    },
  ));
}
