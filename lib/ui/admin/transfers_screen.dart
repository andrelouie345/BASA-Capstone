// lib/ui/admin/transfers_screen.dart
// Cross-school transfers (docs/handoff/screens/sf1-leavers.md#cross-school-
// transfers-superadmin-only): the superadmin's list of every pending transfer
// conflict across schools (an SF1 listing a learner enrolled this school year
// at another school). Each card: the SF1 row and where it was imported, the
// stored learner and where they are this year, and whether the SF1 row
// matches them as the server checks it. Transfer in (resolve 'update';
// disabled when the identity differs: no override exists, fix it at the
// learner's school first) or Skip. Admin build; the home card is superadmin
// only.
import 'package:flutter/material.dart';

import '../../viewmodels/import_viewmodel.dart';
import '../common/screen_kit.dart';
import 'admin_scope.dart';

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  int _reload = 0;

  String _resultText(ConflictResolution r) {
    if (r.action == 'skip') return 'Skipped: the conflict is closed and nothing changed.';
    final t = r.transferredFrom;
    final school = t?.schoolName ?? 'another school';
    return [
      'Transferred in from $school${t?.sectionName == null ? '' : ' (${t!.sectionName})'}; '
          "this year's records stay at $school.",
      ?r.deviceWarning,
    ].join('\n');
  }

  Future<void> _resolve(TransferConflict t, String action) async {
    final sf1 = AdminScope.of(context).sf1Import;
    final p = t.current;
    final ok = action == 'skip'
        ? await confirm(context,
            title: 'Skip ${t.incomingName}?', body: 'The conflict is closed; nobody is moved.', action: 'Skip')
        : await confirm(
            context,
            title: 'Transfer ${t.incomingName} in?',
            body: [
              'Into ${t.section == null ? 'the section of the SF1' : 'Grade ${t.section!.gradeLevel} ${t.section!.sectionName}'}'
                  ' at ${t.schoolName ?? 'the receiving school'}.',
              if (t.activeElsewhere)
                'They are still active at ${p!.schoolName ?? 'the other school'}: they will be archived there as '
                    'transferred out first.',
              "This school year's records stay at the school that made them.",
            ].join('\n\n'),
            action: 'Transfer in',
          );
    if (!ok || !mounted) return;
    final r = await runAction(context, () => sf1.resolve(t.conflict.id!, action), where: 'Transfers');
    if (r != null && mounted) await showTextDialog(context, title: 'Done', text: _resultText(r));
    if (mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final sf1 = AdminScope.of(context).sf1Import;
    return Scaffold(
      appBar: AppBar(title: const Text('Cross-school transfers')),
      body: PageBody(
        maxWidth: 1100,
        children: [
          const Text('SF1 imports that list a learner enrolled this school year at another school. Only here can a '
              'learner still active at the other school be transferred.'),
          LoadView<List<TransferConflict>>(
            where: 'Transfers',
            reloadKey: _reload,
            load: (_) => sf1.transferConflicts(),
            builder: (context, items, _) => items.isEmpty
                ? const EmptyNote('No transfer conflicts waiting.', icon: Icons.task_alt)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final t in items) ...[_TransferCard(t: t, onResolve: _resolve), const SizedBox(height: 12)],
                  ]),
          ),
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  final TransferConflict t;
  final Future<void> Function(TransferConflict t, String action) onResolve;
  const _TransferCard({required this.t, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    final s = t.section;
    final st = t.stored;
    final p = t.current;
    final canTransfer = t.matches && p != null;
    return SectionCard(
      title: t.incomingName,
      icon: Icons.swap_horiz,
      trailing: st == null
          ? const StatusChip('no learner with this LRN', tone: StatusTone.bad, icon: Icons.help_outline)
          : t.matches
              ? const StatusChip('matches', tone: StatusTone.good, icon: Icons.check_circle_outline)
              : StatusChip('differs: ${t.differences.join(', ')}', tone: StatusTone.bad, icon: Icons.error_outline),
      children: [
        InfoRow('LRN', t.conflict.lrn),
        InfoRow('SF1 row', '${t.incomingName}, born ${t.incomingBirthDate ?? 'blank'}'),
        InfoRow('Imported into',
            '${s == null ? 'section not readable' : 'Grade ${s.gradeLevel} ${s.sectionName} (${s.schoolYear})'} · '
                '${t.schoolName ?? 'school not readable'}'),
        if (st != null) InfoRow('Stored learner', '${st.lastName}, ${st.firstName}, born ${st.birthDate ?? 'blank'}'),
        if (st != null)
          InfoRow(
            'This school year',
            p == null
                ? 'no enrollment: nothing to transfer'
                : '${p.schoolName ?? 'school ${p.schoolId}'} · Grade ${p.gradeLevel} ${p.sectionName} · '
                    '${p.status.replaceAll('_', ' ')}${p.leftOn == null ? '' : ' ${p.leftOn}'}',
          ),
        if (t.activeElsewhere) ...[
          const SizedBox(height: 8),
          StatusChip('still active at ${p!.schoolName ?? 'the other school'}', tone: StatusTone.warn, icon: Icons.warning_amber),
        ],
        if (st != null && !t.matches) ...[
          const SizedBox(height: 8),
          const NoticeBanner('The SF1 row does not match the stored learner. Fix the name or birth date at the '
              "learner's school first (or correct the SF1 and import again), then come back. There is no override."),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: canTransfer ? () => onResolve(t, 'update') : null,
            icon: const Icon(Icons.login),
            label: const Text('Transfer in'),
          ),
          OutlinedButton(onPressed: () => onResolve(t, 'skip'), child: const Text('Skip')),
        ]),
      ],
    );
  }
}
