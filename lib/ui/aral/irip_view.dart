// lib/ui/aral/irip_view.dart
// IRIP (docs/handoff/screens/aral.md): a learner's intervention plan: the
// current cycle's strands with their latest week and suggested next target,
// every week with its rating, and the class tutor's actions (start a cycle,
// next week, rate, notes, change target, delete).
import 'package:flutter/material.dart';

import '../../core/models/aral_irip.dart';
import '../../viewmodels/aral_irip_viewmodel.dart';
import '../common/screen_kit.dart';

class IripView extends StatefulWidget {
  final int enrollmentId;
  const IripView({super.key, required this.enrollmentId});

  @override
  State<IripView> createState() => _IripViewState();
}

class _IripViewState extends State<IripView> {
  int _reload = 0;
  void _again() => setState(() => _reload++);

  Future<void> _start() async {
    final vm = vmsOf(context).aralIrip;
    await runAction(context, () => vm.startCycle(widget.enrollmentId), done: 'Cycle started.', where: 'Irip');
    _again();
  }

  Future<void> _next(AralIripPlan plan, AralIripStrandState s) async {
    final vm = vmsOf(context).aralIrip;
    int? targetId = s.suggestion?.id;
    if (targetId == null || s.listDone) {
      final options = plan.targets.where((t) => t.strand == s.strand).toList();
      final t = await pickOne<AralIripTarget>(context, title: 'Target for next week', options: options, label: (t) => t.label);
      if (t == null || !mounted) return;
      targetId = t.id;
    }
    final id = targetId;
    await runAction(context, () => vm.nextWeek(widget.enrollmentId, strand: s.strand, targetId: id), done: 'Week added.', where: 'Irip');
    _again();
  }

  Future<void> _week(AralIripPlan plan, AralIripWeek w) async {
    final vm = vmsOf(context).aralIrip;
    final a = await pickOne<String>(
      context,
      title: 'Cycle ${w.cycleNo}, week ${w.weekNo}',
      options: [...AralIripStatus.values.map((s) => s.value), if (w.isRated) 'clear', 'notes', 'target', 'delete'],
      label: (a) => switch (a) {
        'clear' => 'Clear the rating',
        'notes' => 'Notes',
        'target' => 'Change the target',
        'delete' => 'Delete this week',
        _ => () {
          final s = AralIripStatus.values.firstWhere((s) => s.value == a);
          return '${s.symbol} ${s.meaning}';
        }(),
      },
    );
    if (a == null || !mounted) return;
    switch (a) {
      case 'clear':
        await runAction(context, () => vm.clearRating(w.id!), where: 'Irip');
      case 'notes':
        final f = await askFields(context, title: 'Notes', fields: [FieldSpec('n', 'Notes', initial: w.notes ?? '', optional: true, multiline: true)]);
        if (f == null || !mounted) return;
        await runAction(context, () => vm.setNotes(w.id!, f['n']!.isEmpty ? null : f['n']), where: 'Irip');
      case 'target':
        final t = await pickOne<AralIripTarget>(context,
            title: 'Target', options: plan.targets.where((t) => t.strand == w.strand).toList(), label: (t) => t.label);
        if (t == null || !mounted) return;
        await runAction(context, () => vm.changeTarget(w.id!, t.id), where: 'Irip');
      case 'delete':
        if (!await confirm(context, title: 'Delete this week?', action: 'Delete', destructive: true) || !mounted) return;
        await runStep(context, () => vm.deleteWeek(w.id!), where: 'Irip');
      default:
        final status = AralIripStatus.values.firstWhere((s) => s.value == a);
        await runAction(context, () => vm.rate(w.id!, status), done: 'Rated.', where: 'Irip');
    }
    _again();
  }

  @override
  Widget build(BuildContext context) {
    return LoadView<AralIripPlan>(
      where: 'Irip',
      reloadKey: _reload,
      load: (vms) => vms.aralIrip.plan(widget.enrollmentId),
      builder: (context, plan, _) {
        if (plan.program == null) return const EmptyNote('No IRIP for this learner\'s program.');
        String strand(AralIripStrand s) => s.label.isEmpty ? 'Targets' : s.label;
        return PageBody(
          children: [
            SectionCard(
              title: '${plan.program!.label} · ${plan.currentCycle == 0 ? 'not started' : 'cycle ${plan.currentCycle}'}',
              trailing: TextButton(onPressed: _start, child: Text(plan.currentCycle == 0 ? 'Start' : 'New cycle')),
              children: [
                for (final s in plan.strands)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strand(s.strand)),
                    subtitle: Text([
                      if (s.latestTarget != null) 'Latest: ${s.latestTarget!.label}${s.latest?.status == null ? '' : ' ${s.latest!.status!.symbol}'}',
                      if (s.suggestion != null) 'Next: ${s.suggestion!.label}',
                      if (s.listDone) 'List done: pick a target to review',
                    ].join('\n')),
                    trailing: plan.currentCycle == 0 ? null : TextButton(onPressed: () => _next(plan, s), child: const Text('Next week')),
                  ),
              ],
            ),
            SectionCard(
              title: 'Weeks',
              children: [
                if (plan.weeks.isEmpty) const Text('No weeks yet.'),
                for (final w in plan.weeks.reversed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text(w.status?.symbol ?? '·', style: Theme.of(context).textTheme.titleLarge),
                    title: Text('Cycle ${w.cycleNo}, week ${w.weekNo} · ${strand(w.strand)}'),
                    subtitle: Text([plan.targetById[w.targetId]?.label ?? 'target #${w.targetId}', ?w.notes].join('\n')),
                    onTap: () => _week(plan, w),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
