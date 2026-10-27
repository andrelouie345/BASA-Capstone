// lib/ui/admin/sync_review_screen.dart
// Review uploads (docs/handoff/screens/sync.md, Review uploads): the uploads
// waiting for an approver, each one's records, approve or reject with a
// reason, and the school's auto-approve switch. Admin build only.
import 'package:flutter/material.dart';

import '../../viewmodels/sync_review_viewmodel.dart';
import '../common/screen_kit.dart';
import 'admin_scope.dart';

class SyncReviewScreen extends StatefulWidget {
  const SyncReviewScreen({super.key});

  @override
  State<SyncReviewScreen> createState() => _SyncReviewScreenState();
}

class _SyncReviewScreenState extends State<SyncReviewScreen> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final review = AdminScope.of(context).syncReview;
    final schoolId = vmsOf(context).auth.currentUser?.schoolId;
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
          return PageBody(
            children: [
              Card(
                child: SwitchListTile(
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
              SectionCard(
                title: 'Waiting for approval (${list.pending.length})',
                children: list.pending.isEmpty
                    ? [const Text('No uploads are waiting.')]
                    : [for (final i in list.pending) _tile(context, i, reload)],
              ),
              if (list.sentBack.isNotEmpty)
                SectionCard(
                  title: 'Sent back for conflicts (${list.sentBack.length})',
                  children: [for (final i in list.sentBack) _tile(context, i, reload, canDecide: false)],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, SyncReviewItem i, VoidCallback reload, {bool canDecide = true}) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.inventory_2_outlined),
    title: Text('Upload ${i.upload.id} · ${i.uploader}'),
    subtitle: Text([
      '${i.upload.rows} record(s), sent ${isoDate(i.upload.createdAt.toLocal())}',
      ?i.school,
    ].join(' · ')),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _UploadDetailsScreen(id: i.upload.id, canDecide: canDecide)),
      );
      reload();
    },
  );
}

class _UploadDetailsScreen extends StatelessWidget {
  final int id;
  final bool canDecide;
  const _UploadDetailsScreen({required this.id, required this.canDecide});

  @override
  Widget build(BuildContext context) {
    final review = AdminScope.of(context).syncReview;
    return Scaffold(
      appBar: AppBar(title: Text('Upload $id')),
      body: LoadView<SyncUploadDetails>(
        where: 'SyncReviewScreen',
        load: (_) => review.details(id),
        builder: (context, d, _) => PageBody(
          children: [
            SectionCard(
              title: 'From ${d.item.uploader}${d.item.school == null ? '' : ' · ${d.item.school}'}',
              children: [for (final l in d.lines) SelectableText(l)],
            ),
            if (canDecide)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final r = await runAction(context, () => review.approve(id), where: 'SyncReviewScreen');
                      if (r == null || !context.mounted) return;
                      await showTextDialog(context, title: 'Upload $id', text: r.toString());
                      nav.pop();
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.block),
                    label: const Text('Reject'),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final f = await askFields(context,
                          title: 'Reject upload $id',
                          action: 'Reject',
                          fields: const [FieldSpec('reason', 'Reason (the tutor sees it)', multiline: true)]);
                      if (f == null || !context.mounted) return;
                      final r = await runAction(context, () => review.reject(id, f['reason']!), where: 'SyncReviewScreen');
                      if (r == null || !context.mounted) return;
                      showNote(context, r);
                      nav.pop();
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
