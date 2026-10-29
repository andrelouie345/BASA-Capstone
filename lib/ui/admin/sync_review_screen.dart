// lib/ui/admin/sync_review_screen.dart
// Review uploads (docs/handoff/screens/sync.md, Review uploads): the uploads
// waiting for an approver, each one's records, approve or reject with a
// reason, and the school's auto-approve switch. Admin build only.
// Wide screens show the list and the picked upload side by side.
import 'package:flutter/material.dart';

import '../../viewmodels/sync_review_viewmodel.dart';
import '../common/screen_kit.dart';
import 'admin_scope.dart';

/// From this width the list and the picked upload sit side by side.
const _twoPaneWidth = 1000.0;

class SyncReviewScreen extends StatefulWidget {
  const SyncReviewScreen({super.key});

  @override
  State<SyncReviewScreen> createState() => _SyncReviewScreenState();
}

class _SyncReviewScreenState extends State<SyncReviewScreen> {
  int _reload = 0;

  /// The upload shown in the right pane (wide screens).
  int? _selected;
  bool _selectedCanDecide = true;

  @override
  Widget build(BuildContext context) {
    final review = AdminScope.of(context).syncReview;
    final schoolId = vmsOf(context).auth.currentUser?.schoolId;
    final twoPane = MediaQuery.sizeOf(context).width >= _twoPaneWidth;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review uploads'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: () => setState(() => _reload++), icon: const Icon(Icons.refresh))],
      ),
      body: LoadView<(SyncPendingList, ({bool? region, bool? school, bool effective}))>(
        where: 'SyncReviewScreen',
        reloadKey: _reload,
        load: (vms) async =>
            (await review.pending(schoolId: schoolId), await vms.reportSettings.autoApproveLayers(schoolId)),
        builder: (context, data, reload) {
          final (list, auto) = data;
          final colors = Theme.of(context).colorScheme;
          final records = [...list.pending, ...list.sentBack].fold<int>(0, (n, i) => n + i.upload.rows);
          final listChildren = [
            Card(
              child: SwitchListTile(
                secondary: const IconBadge(Icons.bolt_outlined),
                title: Text(schoolId == null ? 'Approve automatically (region default)' : 'Approve automatically'),
                subtitle: const Text("Tutors' uploads are applied as soon as they are sent."),
                value: auto.effective,
                onChanged: (on) async {
                  final settings = vmsOf(context).reportSettings;
                  await runAction(context, () => settings.setAutoApprove(schoolId, on),
                      done: on ? 'Auto-approve is on.' : 'Auto-approve is off.', where: 'SyncReviewScreen');
                  reload();
                },
              ),
            ),
            StatGrid(tileWidth: 180, tiles: [
              StatTile(label: 'Uploads waiting', value: '${list.pending.length}', icon: Icons.hourglass_top),
              StatTile(label: 'Sent back', value: '${list.sentBack.length}', icon: Icons.call_split),
              StatTile(label: 'Records in them', value: '$records', icon: Icons.inventory_2_outlined),
            ]),
            ListCard(
              title: 'Waiting for approval (${list.pending.length})',
              children: list.pending.isEmpty
                  ? [const EmptyNote('No uploads are waiting.', icon: Icons.task_alt)]
                  : [for (final i in list.pending) _tile(context, i, reload, twoPane: twoPane)],
            ),
            if (list.sentBack.isNotEmpty)
              ListCard(
                title: 'Sent back for conflicts (${list.sentBack.length})',
                children: [for (final i in list.sentBack) _tile(context, i, reload, canDecide: false, twoPane: twoPane)],
              ),
          ];
          if (!twoPane) return PageBody(children: listChildren);
          // The picked upload may have been decided elsewhere since.
          final shown = [...list.pending, ...list.sentBack].any((i) => i.upload.id == _selected) ? _selected : null;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 2, child: PageBody(children: listChildren)),
              VerticalDivider(width: 1, color: colors.outlineVariant),
              Expanded(
                flex: 3,
                child: shown == null
                    ? const EmptyNote('Pick an upload on the left to see its records.', icon: Icons.inventory_2_outlined)
                    : _UploadDetails(
                        key: ValueKey(shown),
                        id: shown,
                        canDecide: _selectedCanDecide,
                        showTitle: true,
                        onDecided: () {
                          setState(() => _selected = null);
                          reload();
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, SyncReviewItem i, VoidCallback reload, {bool canDecide = true, required bool twoPane}) {
    final selected = twoPane && _selected == i.upload.id;
    return Material(
      color: selected ? Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5) : null,
      child: ListRow(
        leading: LetterBadge(i.uploader),
        title: 'Upload ${i.upload.id} · ${i.uploader}',
        subtitle: [
          '${i.upload.rows} record(s), sent ${isoDate(i.upload.createdAt.toLocal())}',
          ?i.school,
        ].join(' · '),
        trailing: [
          canDecide
              ? const StatusChip('PENDING', tone: StatusTone.warn)
              : const StatusChip('SENT BACK', tone: StatusTone.bad),
          const Icon(Icons.chevron_right),
        ],
        onTap: () async {
          if (twoPane) {
            setState(() {
              _selected = i.upload.id;
              _selectedCanDecide = canDecide;
            });
            return;
          }
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _UploadDetailsScreen(id: i.upload.id, canDecide: canDecide)),
          );
          reload();
        },
      ),
    );
  }
}

class _UploadDetailsScreen extends StatelessWidget {
  final int id;
  final bool canDecide;
  const _UploadDetailsScreen({required this.id, required this.canDecide});

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Upload $id')),
      body: _UploadDetails(id: id, canDecide: canDecide, onDecided: nav.pop),
    );
  }
}

/// One upload's records and the approve / reject buttons; [onDecided] runs
/// after a decision (closes the page, or clears the right pane).
class _UploadDetails extends StatelessWidget {
  final int id;
  final bool canDecide;
  final bool showTitle;
  final VoidCallback onDecided;
  const _UploadDetails({super.key, required this.id, required this.canDecide, required this.onDecided, this.showTitle = false});

  @override
  Widget build(BuildContext context) {
    final review = AdminScope.of(context).syncReview;
    return LoadView<SyncUploadDetails>(
      where: 'SyncReviewScreen',
      load: (_) => review.details(id),
      builder: (context, d, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        return PageBody(
          children: [
            if (showTitle) Text('Upload $id', style: theme.textTheme.titleLarge),
            StatGrid(tileWidth: 200, tiles: [
              StatTile(label: 'Records', value: '${d.item.upload.rows}', icon: Icons.inventory_2_outlined),
              StatTile(label: 'Sent', value: isoDate(d.item.upload.createdAt.toLocal()), icon: Icons.event),
            ]),
            if (canDecide)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('Approve'),
                        onPressed: () async {
                          final r = await runAction(context, () => review.approve(id), where: 'SyncReviewScreen');
                          if (r == null || !context.mounted) return;
                          await showTextDialog(context, title: 'Upload $id', text: r.toString());
                          onDecided();
                        },
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: colors.error),
                        icon: const Icon(Icons.block),
                        label: const Text('Reject'),
                        onPressed: () async {
                          final f = await askFields(context,
                              title: 'Reject upload $id',
                              action: 'Reject',
                              fields: const [FieldSpec('reason', 'Reason (the tutor sees it)', multiline: true)]);
                          if (f == null || !context.mounted) return;
                          final r = await runAction(context, () => review.reject(id, f['reason']!), where: 'SyncReviewScreen');
                          if (r == null || !context.mounted) return;
                          showNote(context, r);
                          onDecided();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            SectionCard(
              title: 'From ${d.item.uploader}${d.item.school == null ? '' : ' · ${d.item.school}'}',
              icon: Icons.person_outline,
              children: [
                for (var n = 0; n < d.lines.length; n++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: n.isEven ? colors.surfaceContainerLowest : colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(d.lines[n]),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
