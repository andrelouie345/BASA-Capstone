// lib/ui/aral/checkin_view.dart
// Check-ins (docs/handoff/screens/aral.md): a learner's 16th / 32nd-session
// check-ins with their result (Met / Not met at the cut-off), a new one,
// and answering its items (letters, or right / wrong for open items).
import 'package:flutter/material.dart';

import '../../core/models/aral_checkin.dart';
import '../../viewmodels/aral_checkin_viewmodel.dart';
import '../common/screen_kit.dart';

class CheckinView extends StatefulWidget {
  final int enrollmentId;
  const CheckinView({super.key, required this.enrollmentId});

  @override
  State<CheckinView> createState() => _CheckinViewState();
}

class _CheckinViewState extends State<CheckinView> {
  int _reload = 0;

  Future<void> _start(int checkpoint) async {
    final vm = vmsOf(context).aralCheckin;
    final c = await runAction(context, () => vm.startCheckin(widget.enrollmentId, checkpoint), where: 'Checkin');
    if (c?.id != null && mounted) await _open(c!.id!);
  }

  Future<void> _open(int checkinId) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CheckinScreen(checkinId: checkinId)));
    if (mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    return LoadView<AralLearnerCheckins>(
      where: 'Checkin',
      reloadKey: _reload,
      load: (vms) => vms.aralCheckin.learnerCheckins(widget.enrollmentId),
      builder: (context, l, _) {
        if (l.toolsByCheckpoint.isEmpty) return const EmptyNote('No check-ins for this learner\'s program.');
        final colors = Theme.of(context).colorScheme;
        return PageBody(
          children: [
            for (final e in l.toolsByCheckpoint.entries)
              SectionCard(
                title: 'After session ${e.key}: ${e.value.title}',
                trailing: TextButton(onPressed: () => _start(e.key), child: const Text('Start')),
                children: [
                  for (final r in l.results.where((r) => r.tool.id == e.value.id))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Attempt ${r.checkin.attemptNo} · ${r.checkin.takenOn}'),
                      subtitle: Text('${r.score.correct}/${r.score.total} (${r.score.wholePercent}%), cut-off ${r.passPct}%'
                          '${r.complete ? '' : ' · not finished'}'),
                      trailing: Text(r.passed ? 'Met' : 'Not met', style: TextStyle(color: r.passed ? colors.tertiary : colors.error)),
                      onTap: () => _open(r.checkin.id!),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class CheckinScreen extends StatefulWidget {
  final int checkinId;
  const CheckinScreen({super.key, required this.checkinId});

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  int _reload = 0;
  void _again() => setState(() => _reload++);

  Future<void> _choice(AralCheckinItem i, String? letter) async {
    final vm = vmsOf(context).aralCheckin;
    await runAction(context, () => vm.answerChoices(widget.checkinId, i.itemNo, [letter]), where: 'Checkin');
    _again();
  }

  Future<void> _open(AralCheckinItem i, bool correct) async {
    final vm = vmsOf(context).aralCheckin;
    await runAction(context, () => vm.markOpen(widget.checkinId, i.itemNo, correct), where: 'Checkin');
    _again();
  }

  Future<void> _clear(AralCheckinItem i) async {
    final vm = vmsOf(context).aralCheckin;
    await runStep(context, () => vm.clearAnswer(widget.checkinId, i.itemNo), where: 'Checkin');
    _again();
  }

  Future<void> _delete() async {
    if (!await confirm(context, title: 'Delete this check-in?', action: 'Delete', destructive: true) || !mounted) return;
    final vm = vmsOf(context).aralCheckin;
    final nav = Navigator.of(context);
    if (await runStep(context, () => vm.deleteCheckin(widget.checkinId), done: 'Check-in deleted.', where: 'Checkin')) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-in'),
        actions: [IconButton(tooltip: 'Delete', onPressed: _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: LoadView<AralCheckinResult>(
        where: 'Checkin',
        reloadKey: _reload,
        load: (vms) => vms.aralCheckin.result(widget.checkinId),
        builder: (context, r, _) {
          final colors = Theme.of(context).colorScheme;
          String? part;
          final rows = <Widget>[];
          for (final i in r.items) {
            if (i.section != null && i.section != part) {
              part = i.section;
              rows.add(Padding(padding: const EdgeInsets.only(top: 12), child: Text(part!, style: Theme.of(context).textTheme.titleSmall)));
            }
            final a = r.answerByItem[i.id];
            rows.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i.displayNo}. ${i.prompt}'),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (i.kind == AralCheckinItemKind.choice)
                    for (final l in const ['A', 'B', 'C', 'D', 'E'])
                      ChoiceChip(label: Text(l), selected: a?.response?.toUpperCase() == l, onSelected: (_) => _choice(i, l))
                  else ...[
                    ChoiceChip(label: const Text('Right'), selected: a != null && a.isCorrect, onSelected: (_) => _open(i, true)),
                    ChoiceChip(label: const Text('Wrong'), selected: a != null && !a.isCorrect, onSelected: (_) => _open(i, false)),
                  ],
                  if (a != null) ...[
                    Icon(a.isCorrect ? Icons.check : Icons.close, size: 18, color: a.isCorrect ? colors.tertiary : colors.error),
                    TextButton(onPressed: () => _clear(i), child: const Text('Clear')),
                  ],
                ]),
              ]),
            ));
          }
          return PageBody(
            children: [
              Card(
                color: r.passed ? colors.tertiaryContainer : colors.errorContainer,
                child: ListTile(
                  title: Text('${r.tool.label} · ${r.passed ? 'Met' : 'Not met'}'),
                  subtitle: Text('${r.score.correct}/${r.score.total} correct (${r.score.wholePercent}%), '
                      'cut-off ${r.passPct}%${r.complete ? '' : ' · ${r.score.total - r.score.answered} item(s) left'}'),
                ),
              ),
              SectionCard(title: 'Items', children: rows),
            ],
          );
        },
      ),
    );
  }
}
