// lib/core/console/commands/sync_commands.dart

/// Tutor-side sync commands (SyncViewModel, sync spec section 5.3): preview,
/// resolve, upload, status, withdraw. Approver commands (S6) below.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../models/sync_upload.dart';
import '../../../viewmodels/sync_viewmodel.dart';
import '../../../viewmodels/viewmodel_exception.dart';
import 'sync_command_helpers.dart';

void registerSyncCommands(ConsoleRegistry registry, SyncViewModel syncVm) {
  registry.register(ConsoleCommand(
    name: 'sync-preview',
    description: 'sync-preview — what an upload would send now, and what must be resolved first',
    handler: (args) async {
      try {
        return _previewText(await syncVm.preview());
      } on ViewModelException catch (e) {
        return e.message;
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'sync-resolve',
    description: 'sync-resolve <table> <key> mine|server — keep this device\'s change (overwrite the server\'s) '
        'or take the server\'s copy',
    handler: (args) async {
      if (args.length != 3 || !const ['mine', 'server'].contains(args[2])) {
        return 'Usage: sync-resolve <table> <key> mine|server';
      }
      try {
        return '${await syncVm.resolve(args[0], args[1], SyncChoice.values.byName(args[2]))}';
      } on ViewModelException catch (e) {
        return e.message;
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'sync-upload',
    description: 'sync-upload yes — send this device\'s unsent work as one upload (without "yes": show it first)',
    handler: (args) async {
      try {
        if (args.isEmpty || args[0] != 'yes') {
          final p = await syncVm.preview();
          final text = _previewText(p);
          return p.package.isEmpty || p.problems.isNotEmpty ? text : '$text\nRun "sync-upload yes" to send.';
        }
        return '${await syncVm.upload()}';
      } on ViewModelException catch (e) {
        return e.message;
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'sync-status',
    description: 'sync-status — your uploads and their decisions; takes in decided ones',
    handler: (args) async {
      try {
        final settled = await syncVm.refreshStatus();
        final uploads = await syncVm.uploads();
        final locked = await syncVm.lockedCounts();
        final out = StringBuffer();
        for (final o in settled) {
          out.writeln(o);
        }
        if (uploads.isEmpty) {
          out.writeln('You have no uploads.');
        } else {
          out.writeln('Your uploads (newest first):');
          for (final u in uploads) {
            out.writeln('  ${u.id}  ${u.status.padRight(9)}  ${syncWhen(u.createdAt)}  ${u.rows} row(s)'
                '${u.reason == null ? '' : '  ${u.reason}'}');
            for (final c in u.conflicts) {
              out.writeln('      $c');
            }
          }
        }
        if (locked.isEmpty) {
          out.write('Nothing on this device is waiting for approval.');
        } else {
          out.write([
            for (final e in locked.entries)
              e.key == 0
                  ? 'Locked on this device: ${e.value} row(s) in an upload whose answer never came '
                      '(run sync-status again when online).'
                  : 'Locked on this device: ${e.value} row(s) in upload ${e.key}.',
          ].join('\n'));
        }
        return out.toString();
      } on ViewModelException catch (e) {
        return e.message;
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'sync-withdraw',
    description: 'sync-withdraw <id>|latest — take back a pending upload so its records can be changed again '
        '(latest = this device\'s newest upload waiting for approval)',
    handler: (args) async {
      if (args.length != 1) return 'Usage: sync-withdraw <upload id>|latest';
      try {
        final int? id;
        if (args[0] == 'latest') {
          final ids = (await syncVm.lockedCounts()).keys.where((k) => k > 0);
          if (ids.isEmpty) return 'Nothing on this device is waiting for approval.';
          id = ids.reduce((a, b) => a > b ? a : b);
        } else {
          id = int.tryParse(args[0]);
          if (id == null) return 'Usage: sync-withdraw <upload id>|latest';
        }
        await syncVm.withdraw(id);
        return 'Upload $id withdrawn; its records can be changed again.';
      } on ViewModelException catch (e) {
        return e.message;
      }
    },
  ));
}

String _previewText(SyncPreview p) {
  final out = StringBuffer();
  for (final o in p.settled) {
    out.writeln(o);
  }
  if (p.package.isEmpty) {
    out.write('Nothing to upload.');
    return out.toString();
  }
  out.writeln('Would upload ${p.package.rowCount} row(s):');
  for (final l in p.package.summary) {
    out.writeln('  $l');
  }
  if (p.problems.isEmpty) {
    out.write('Ready: run "sync-upload yes".');
  } else {
    out.writeln('Problems (resolve with sync-resolve <table> <key> mine|server):');
    out.write(p.problems.map((x) => '  $x').join('\n'));
  }
  return out.toString();
}
