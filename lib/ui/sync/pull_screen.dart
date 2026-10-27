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
          return PageBody(
            maxWidth: 720,
            children: [
              SectionCard(
                title: 'This device',
                children: [
                  InfoRow('Signed in as', p.currentEmail ?? '—'),
                  InfoRow('Last downloaded by', p.owner?.toString() ?? 'Nobody yet'),
                  InfoRow('Unsent work', p.localTotal == 0 ? 'None' : '${p.localTotal} record(s)'),
                  for (final l in p.localWork) Padding(padding: const EdgeInsets.only(left: 16), child: Text('• $l')),
                ],
              ),
              if (blocked)
                Card(
                  color: colors.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'This device holds work of ${p.owner!.email ?? 'another user'} that is not on the server yet. '
                      'They should send it first. Downloading as you deletes it.',
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                  ),
                )
              else
                Text(
                  p.localTotal == 0
                      ? 'Downloading replaces this device\'s copy with the latest from the server.'
                      : 'Your unsent work is kept; everything else is refreshed from the server.',
                ),
              FilledButton.icon(
                onPressed: _busy || blocked ? null : () => _pull(discard: false),
                icon: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_download),
                label: const Text('Download the latest data'),
              ),
              if (p.localTotal > 0)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: colors.error),
                  onPressed: _busy ? null : () => _pull(discard: true),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete unsent work and download'),
                ),
              if (_result != null) SectionCard(title: 'Last download', children: [SelectableText(_result!)]),
            ],
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
