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
          final wide = isWideScreen(context);
          final onSend = p.package.isEmpty || p.problems.isNotEmpty ? null : () => _send(p);
          const actionLabel = 'Send my work';
          // The page's own Scaffold: the main action needs the preview.
          return Scaffold(
            backgroundColor: colors.surface.withValues(alpha: 0),
            floatingActionButton:
                wide ? null : mainActionFab(onPressed: onSend, icon: Icons.cloud_upload, label: actionLabel, busy: _busy),
            body: PageBody(
              maxWidth: 760,
              children: [
                if (wide)
                  Align(
                    alignment: Alignment.centerRight,
                    child: mainActionButton(onPressed: onSend, icon: Icons.cloud_upload, label: actionLabel, busy: _busy),
                  ),
                for (final o in p.settled)
                  NoticeBanner(o.toString(), icon: _statusIcon(o.status), tone: _statusTone(o.status)),
                StatGrid(tiles: [
                  StatTile(label: 'Records to send', value: '${p.package.rowCount}', icon: Icons.cloud_upload_outlined),
                  StatTile(label: 'Conflicts', value: '${p.problems.length}', icon: Icons.call_split),
                  StatTile(
                    label: 'Waiting for approval',
                    value: '${uploads.where((u) => u.status == 'pending').length}',
                    icon: Icons.hourglass_top,
                  ),
                ]),
                ListCard(
                  title: 'Not sent yet',
                  children: p.package.isEmpty
                      ? [
                          const EmptyNote('Nothing to send: all your work is on the server or waiting for approval.',
                              icon: Icons.cloud_done_outlined),
                        ]
                      : [
                          for (final LocalWorkLine l in p.package.summary)
                            ListRow(leading: const IconBadge(Icons.edit_note), title: '$l'),
                        ],
                ),
                if (p.problems.isNotEmpty)
                  SectionCard(
                    title: 'Settle these first',
                    icon: Icons.warning_amber,
                    trailing: StatusChip('${p.problems.length}', tone: StatusTone.bad),
                    children: [
                      Text(
                        'The server changed these records since your last download. Keep yours, or take '
                        "the server's copy.",
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      for (final x in p.problems)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              IconBadge(Icons.call_split,
                                  size: 32, background: colors.errorContainer, foreground: colors.onErrorContainer),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(x.toString())),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        OutlinedButton(
                                            onPressed: () => _resolve(x, SyncChoice.mine), child: const Text('Keep mine')),
                                        OutlinedButton(
                                          onPressed: () => _resolve(x, SyncChoice.server),
                                          child: const Text("Take the server's"),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ]),
                          ),
                        ),
                    ],
                  ),
                if (_result != null)
                  SectionCard(title: 'Last upload', icon: Icons.cloud_done_outlined, children: [SelectableText(_result!)]),
                ListCard(
                  title: 'My uploads',
                  children: uploads.isEmpty
                      ? [const EmptyNote('No uploads yet.', icon: Icons.cloud_queue)]
                      : [
                          for (final u in uploads.reversed)
                            ListRow(
                              leading: IconBadge(
                                _statusIcon(u.status),
                                background: _badgeColors(colors, u.status).$1,
                                foreground: _badgeColors(colors, u.status).$2,
                              ),
                              title: 'Upload ${u.id}',
                              subtitle: '${u.rows} record(s), sent ${isoDate(u.createdAt.toLocal())}',
                              // The reason in full (the subtitle is cut at two lines).
                              footer: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  StatusChip(_statusLabel(u.status), tone: _statusTone(u.status)),
                                  if (u.reason != null) ...[const SizedBox(height: 6), Text(u.reason!)],
                                ],
                              ),
                              trailing: [
                                if (u.status == 'pending')
                                  TextButton(onPressed: () => _withdraw(u), child: const Text('Withdraw')),
                              ],
                            ),
                        ],
                ),
                // Room for the floating button.
                if (!wide) const SizedBox(height: 72),
              ],
            ),
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

StatusTone _statusTone(String s) => switch (s) {
  'pending' => StatusTone.warn,
  'applied' => StatusTone.good,
  'rejected' || 'conflict' || 'error' => StatusTone.bad,
  _ => StatusTone.neutral,
};

/// Badge background and icon colour for an upload's status.
(Color, Color) _badgeColors(ColorScheme c, String s) => switch (_statusTone(s)) {
  StatusTone.good => (c.tertiaryContainer, c.onTertiaryContainer),
  StatusTone.warn => (c.secondaryContainer, c.onSecondaryContainer),
  StatusTone.bad => (c.errorContainer, c.onErrorContainer),
  StatusTone.neutral => (c.surfaceContainerHigh, c.onSurfaceVariant),
};
