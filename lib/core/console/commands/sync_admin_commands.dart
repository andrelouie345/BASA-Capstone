// lib/core/console/commands/sync_admin_commands.dart
// Admin build only: the admin half of sync_commands.dart (tutor build split, 2026-10-22).

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/sync_review_viewmodel.dart';
import '../../../viewmodels/viewmodel_exception.dart';
import 'sync_command_helpers.dart';

/// Approver commands (SyncReviewViewModel, S6): list, read, approve, reject.
/// `latest` = the newest upload waiting for this approver.
void registerSyncReviewCommands(ConsoleRegistry registry, SyncReviewViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on ViewModelException catch (e) {
          return e.message;
        }
      },
    ));
  }

  /// An upload id, or `latest`; null = nothing waiting.
  Future<int?> uploadId(String raw, String usage) async {
    if (raw == 'latest') return vm.latestPendingId();
    return int.tryParse(raw) ?? (throw ViewModelException(usage));
  }

  String item(SyncReviewItem i) => '  ${i.upload.id}  ${i.uploader}  ${syncWhen(i.upload.createdAt)}  '
      '${i.upload.rows} row(s)${i.school == null ? '' : '  ${i.school}'}';

  add('sync-pending',
      'sync-pending [schoolId] — uploads waiting for approval (oldest first) and those sent back on a conflict '
          '(the superadmin: every school, or one)', (args) async {
    if (args.length > 1) return 'Usage: sync-pending [schoolId]';
    final schoolId = args.isEmpty ? null : int.tryParse(args[0]);
    if (args.isNotEmpty && schoolId == null) return 'Usage: sync-pending [schoolId]';
    final list = await vm.pending(schoolId: schoolId);
    final out = StringBuffer();
    if (list.pending.isEmpty) {
      out.writeln('Nothing is waiting for approval.');
    } else {
      out.writeln('Waiting for approval (oldest first):');
      for (final i in list.pending) {
        out.writeln(item(i));
        for (final l in i.upload.summaryLines) {
          out.writeln('      $l');
        }
      }
    }
    if (list.sentBack.isNotEmpty) {
      out.writeln('Sent back (conflict), waiting for the uploader:');
      for (final i in list.sentBack) {
        out.writeln(item(i));
      }
    }
    out.write('${list.pending.length} upload(s) still pending.');
    return out.toString();
  });

  add('sync-show', 'sync-show <id>|latest — one upload, one line per record', (args) async {
    const usage = 'Usage: sync-show <upload id>|latest';
    if (args.length != 1) return usage;
    final id = await uploadId(args[0], usage);
    if (id == null) return 'Nothing is waiting for approval.';
    final d = await vm.details(id);
    final u = d.item.upload;
    return [
      'Upload ${u.id} by ${d.item.uploader}, ${syncWhen(u.createdAt)}, ${u.status}'
          '${u.reason == null ? '' : ': ${u.reason}'}${d.item.school == null ? '' : ' (${d.item.school})'}',
      for (final l in d.lines) '  $l',
    ].join('\n');
  });

  add('sync-approve', 'sync-approve <id>|latest — apply an upload on the server (as its uploader)', (args) async {
    const usage = 'Usage: sync-approve <upload id>|latest';
    if (args.length != 1) return usage;
    final id = await uploadId(args[0], usage);
    if (id == null) return 'Nothing is waiting for approval.';
    return '${await vm.approve(id)}';
  });

  add('sync-reject',
      'sync-reject <id>|latest <reason...> — send an upload back to its uploader (reason required, at most '
          '$maxRejectReasonLength characters)', (args) async {
    const usage = 'Usage: sync-reject <upload id>|latest <reason...>';
    if (args.length < 2) return usage;
    final id = await uploadId(args[0], usage);
    if (id == null) return 'Nothing is waiting for approval.';
    final reason = args.sublist(1).join(' ');
    final uploader = await vm.reject(id, reason);
    return 'Upload $id rejected and sent back to $uploader: ${reason.trim()}';
  });
}
