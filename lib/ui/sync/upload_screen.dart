// lib/ui/sync/upload_screen.dart
// Send my work (docs/handoff/screens/sync.md, Send my work): what is unsent,
// conflicts to settle (keep mine / take the server's), the upload itself,
// and the uploads sent so far (with withdraw while one waits).
import 'package:flutter/material.dart';

import '../../core/models/sync_pull.dart';
import '../../core/models/sync_upload.dart';
import '../common/screen_kit.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  int _reload = 0;
  bool _busy = false;
  String? _result;

  void _again() => setState(() => _reload++);

  Future<void> _send(SyncPreview p) async {
    if (!await confirm(
      context,
      title: 'Send your work?',
      body: '${p.package.rowCount} record(s) go to the server as one upload. Until it is approved they are '
          'read-only on this device.',
      action: 'Send',
    )) {
      return;
    }
    if (!mounted) return;
    final sync = vmsOf(context).sync;
    setState(() => _busy = true);
    final r = await runAction(context, sync.upload, where: 'UploadScreen');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) _result = r.toString();
      _reload++;
    });
  }

  Future<void> _resolve(SyncProblem problem, SyncChoice choice) async {
    final sync = vmsOf(context).sync;
    final r = await runAction(context, () => sync.resolve(problem.table, problem.key, choice), where: 'UploadScreen');
    if (r != null && mounted) {
      showNote(context, r.toString());
      _again();
    }
  }

  Future<void> _withdraw(SyncUploadRow u) async {
    if (!await confirm(context,
        title: 'Withdraw upload ${u.id}?', body: 'Its records can be changed again on this device.', action: 'Withdraw')) {
      return;
    }
    if (!mounted) return;
    final sync = vmsOf(context).sync;
    await runAction(context, () => sync.withdraw(u.id), done: 'Upload ${u.id} withdrawn.', where: 'UploadScreen');
    _again();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send my work'),
        actions: [IconButton(tooltip: 'Check again', onPressed: _again, icon: const Icon(Icons.refresh))],
      ),
      body: LoadView<(SyncPreview, List<SyncUploadRow>)>(
        where: 'UploadScreen',
        reloadKey: _reload,
        load: (vms) async => (await vms.sync.preview(), await vms.sync.uploads()),
        builder: (context, data, _) {
          final (p, uploads) = data;
          final colors = Theme.of(context).colorScheme;
          return PageBody(
            maxWidth: 760,
            children: [
              for (final o in p.settled)
                Card(
                  color: colors.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(o.toString(), style: TextStyle(color: colors.onSecondaryContainer)),
                  ),
                ),
              SectionCard(
                title: 'Not sent yet',
                children: p.package.isEmpty
                    ? [const Text('Nothing to send: all your work is on the server or waiting for approval.')]
                    : [for (final LocalWorkLine l in p.package.summary) Text('• $l')],
              ),
              if (p.problems.isNotEmpty)
                SectionCard(
                  title: 'Settle these first',
                  children: [
                    const Text('The server changed these records since your last download. Keep yours, or take '
                        "the server's copy."),
                    const SizedBox(height: 8),
                    for (final x in p.problems)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(x.toString()),
                            OutlinedButton(onPressed: () => _resolve(x, SyncChoice.mine), child: const Text('Keep mine')),
                            OutlinedButton(
                              onPressed: () => _resolve(x, SyncChoice.server),
                              child: const Text("Take the server's"),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              FilledButton.icon(
                onPressed: _busy || p.package.isEmpty || p.problems.isNotEmpty ? null : () => _send(p),
                icon: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload),
                label: const Text('Send my work'),
              ),
              if (_result != null) SectionCard(title: 'Last upload', children: [SelectableText(_result!)]),
              SectionCard(
                title: 'My uploads',
                children: uploads.isEmpty
                    ? [const Text('No uploads yet.')]
                    : [
                        for (final u in uploads.reversed)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(_statusIcon(u.status)),
                            title: Text('Upload ${u.id} · ${_statusLabel(u.status)}'),
                            subtitle: Text([
                              '${u.rows} record(s), sent ${isoDate(u.createdAt.toLocal())}',
                              if (u.reason != null) u.reason!,
                            ].join('\n')),
                            trailing: u.status == 'pending'
                                ? TextButton(onPressed: () => _withdraw(u), child: const Text('Withdraw'))
                                : null,
                          ),
                      ],
              ),
            ],
          );
        },
      ),
    );
  }
}

String _statusLabel(String s) => switch (s) {
  'pending' => 'waiting for approval',
  'applied' => 'approved',
  'rejected' => 'rejected',
  'withdrawn' => 'withdrawn',
  'conflict' => 'sent back (conflicts)',
  'error' => 'failed on the server',
  _ => s,
};

IconData _statusIcon(String s) => switch (s) {
  'pending' => Icons.hourglass_top,
  'applied' => Icons.check_circle_outline,
  'rejected' => Icons.block,
  'conflict' => Icons.call_split,
  'error' => Icons.error_outline,
  _ => Icons.undo,
};
