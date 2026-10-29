// lib/ui/sync/pull_screen.dart
// Download the latest data (docs/handoff/screens/sync.md, Get the latest from
// the server): whose copy this device holds, the unsent work a download
// keeps, then the download itself. Deleting this device's unsent work is a
// separate, red action that asks first.
import 'package:flutter/material.dart';

import '../../core/models/sync_pull.dart';
import '../common/screen_kit.dart';

class PullScreen extends StatefulWidget {
  const PullScreen({super.key});

  @override
  State<PullScreen> createState() => _PullScreenState();
}

class _PullScreenState extends State<PullScreen> {
  int _reload = 0;
  bool _busy = false;
  String? _result;

  Future<void> _pull({required bool discard}) async {
    if (discard &&
        !await confirm(
          context,
          title: 'Delete unsent work and download?',
          body: "This device's work that is not on the server yet is deleted for good, then the latest data is "
              'downloaded.',
          action: 'Delete and download',
          destructive: true,
        )) {
      return;
    }
    if (!mounted) return;
    final sync = vmsOf(context).sync;
    setState(() => _busy = true);
    final r = await runAction(context, () => sync.pull(discardLocal: discard), where: 'PullScreen');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) _result = pullResultText(r);
      _reload++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Download the latest data')),
      body: LoadView<PullPreview>(
        where: 'PullScreen',
        reloadKey: _reload,
        load: (vms) => vms.sync.pullPreview(),
        builder: (context, p, _) {
          final colors = Theme.of(context).colorScheme;
          final blocked = p.ownerSwitch && p.localTotal > 0;
          final wide = isWideScreen(context);
          final onDownload = blocked ? null : () => _pull(discard: false);
          const actionLabel = 'Download the latest data';
          // The page's own Scaffold: the main action needs the preview.
          return Scaffold(
            backgroundColor: colors.surface.withValues(alpha: 0),
            floatingActionButton: wide
                ? null
                : mainActionFab(onPressed: onDownload, icon: Icons.cloud_download, label: actionLabel, busy: _busy),
            body: PageBody(
              maxWidth: 760,
              children: [
                if (wide)
                  Align(
                    alignment: Alignment.centerRight,
                    child: mainActionButton(onPressed: onDownload, icon: Icons.cloud_download, label: actionLabel, busy: _busy),
                  ),
                StatGrid(tiles: [
                  StatTile(label: 'Unsent records', value: '${p.localTotal}', icon: Icons.cloud_off_outlined),
                  StatTile(
                    label: 'Owner of this device',
                    value: p.owner == null ? 'Nobody yet' : p.ownerSwitch ? 'Another user' : 'You',
                    icon: Icons.phone_android,
                  ),
                ]),
                SectionCard(
                  title: 'This device',
                  icon: Icons.devices_outlined,
                  trailing: p.localTotal > 0
                      ? PopupMenuButton<void>(
                          tooltip: 'More',
                          enabled: !_busy,
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              onTap: () => _pull(discard: true),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.delete_forever_outlined, color: colors.error),
                                title: Text('Delete unsent work and download', style: TextStyle(color: colors.error)),
                              ),
                            ),
                          ],
                        )
                      : null,
                  children: [
                    InfoRow('Signed in as', p.currentEmail ?? '—'),
                    InfoRow('Last downloaded by', p.owner?.toString() ?? 'Nobody yet'),
                    InfoRow('Unsent work', p.localTotal == 0 ? 'None' : '${p.localTotal} record(s)'),
                  ],
                ),
                if (p.localWork.isNotEmpty)
                  ListCard(
                    children: [
                      for (final l in p.localWork)
                        ListRow(leading: const IconBadge(Icons.edit_note), title: '$l'),
                    ],
                  ),
                if (blocked)
                  NoticeBanner(
                    'This device holds work of ${p.owner!.email ?? 'another user'} that is not on the server yet. '
                    'They should send it first. Downloading as you deletes it.',
                    icon: Icons.warning_amber,
                    tone: StatusTone.bad,
                  )
                else
                  NoticeBanner(
                    p.localTotal == 0
                        ? 'Downloading replaces this device\'s copy with the latest from the server.'
                        : 'Your unsent work is kept; everything else is refreshed from the server.',
                    tone: StatusTone.neutral,
                  ),
                if (_result != null)
                  SectionCard(title: 'Last download', icon: Icons.cloud_done_outlined, children: [SelectableText(_result!)]),
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

/// What a download did, in plain lines.
String pullResultText(PullResult r) {
  final m = r.merge;
  final total = m.serverRows.values.fold(0, (a, b) => a + b);
  return [
    'Downloaded $total record(s) from the server.',
    if (r.ownerChanged) 'This device now belongs to you (was ${r.previousOwnerEmail ?? 'another user'}).',
    if (m.keptNew + m.keptChanged + m.keptPending > 0)
      'Kept on this device: ${m.keptNew} new, ${m.keptChanged} changed, ${m.keptPending} waiting for approval.',
    if (m.discarded + m.discardedChanges + m.discardedPending > 0)
      'Deleted unsent work: ${m.discarded + m.discardedChanges + m.discardedPending} record(s).',
    if (m.skippedUnderDeleted + m.skippedNewClash > 0)
      'Skipped ${m.skippedUnderDeleted + m.skippedNewClash} record(s) that clash with the server.',
    if (r.unknownCalendarRounds.isNotEmpty)
      'Round calendar entries this app does not know (shown as invalid): ${r.unknownCalendarRounds.join(', ')}.',
  ].join('\n');
}
