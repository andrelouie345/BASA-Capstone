// lib/ui/crla/crla_marking_screen.dart
// Digitized CRLA (docs/handoff/screens/crla.md, "Digitized CRLA"; spec
// docs/superpowers/specs/2026-11-28-digitized-assessment-screens-design.md):
// the assessor marks Part 1 items, the story words and the questions while
// the learner reads from the printed copy, and BASA works out the totals,
// words read and the profile. The screen is the assessor's only: there is no
// learner side (reading coordinator, 2026-11-28).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/crla_assessment.dart';
import '../../core/models/crla_form.dart';
import '../../core/models/crla_result.dart';
import '../../viewmodels/crla_viewmodel.dart';
import '../../viewmodels/viewmodel_exception.dart';
import '../common/screen_kit.dart';
import 'crla_section_screen.dart';

/// The refusal that asks to confirm a Task 1 change (handoff: ask, then repeat
/// with confirm: true).
const _switchTask2 = 'This changes which Task 2 is given; confirm to clear its marks.';

String crlaTaskLabel(CrlaTask t) => switch (t) {
      CrlaTask.task1 => 'Task 1',
      CrlaTask.task2Low => 'Task 2 low',
      CrlaTask.task2High => 'Task 2 high',
      CrlaTask.task2 => 'Task 2',
    };

class CrlaMarkingScreen extends StatefulWidget {
  final int assessmentId;
  const CrlaMarkingScreen({super.key, required this.assessmentId});

  @override
  State<CrlaMarkingScreen> createState() => _CrlaMarkingScreenState();
}

class _MarkData {
  final CrlaAssessment? attempt;
  final CrlaForm form;
  final CrlaDigitizedState state;
  final CrlaResult? result;
  const _MarkData(this.attempt, this.form, this.state, this.result);
}

enum _ItemMark { right, wrong, self }

class _CrlaMarkingScreenState extends State<CrlaMarkingScreen> {
  int _reload = 0;
  int? _pickedStory;
  void _again() => setState(() => _reload++);

  int get _id => widget.assessmentId;

  /// Runs a marking call; the Task 2 switch is confirmed, then repeated.
  Future<void> _mark(Future<CrlaDigitizedState> Function(CrlaViewModel vm, bool confirmed) call) async {
    final crla = vmsOf(context).crla;
    try {
      await call(crla, false);
    } on ViewModelException catch (e) {
      if (!mounted) return;
      if (e.message == _switchTask2) {
        if (await confirm(context, title: 'Change Task 2?', body: e.message, action: 'Confirm') && mounted) {
          await runAction(context, () => call(crla, true), where: 'CrlaMarking');
        }
      } else {
        await runAction(context, () => Future<void>.error(e), where: 'CrlaMarking');
      }
    } catch (e) {
      if (mounted) await runAction(context, () => Future<void>.error(e), where: 'CrlaMarking');
    }
    if (mounted) _again();
  }

  Future<void> _item(CrlaTask task, int itemNo, _ItemMark? current, _ItemMark tapped) => _mark((vm, ok) => current == tapped
      ? vm.unmarkItem(_id, task, itemNo, confirm: ok)
      : vm.markItem(_id, task, itemNo,
          correct: tapped != _ItemMark.wrong, selfCorrected: tapped == _ItemMark.self, confirm: ok));

  Future<void> _observation(CrlaResult? r) async {
    String v(num? x) => x == null ? '' : '$x';
    final f = await askFields(context, title: 'Observation', fields: [
      FieldSpec('exp', 'Learner experience rating', initial: v(r?.learnerExperienceRating), number: true, optional: true),
      FieldSpec('obs', 'Observation level', initial: v(r?.observationLevel), number: true, optional: true),
      FieldSpec('remarks', 'Remarks', initial: r?.remarks ?? '', optional: true, multiline: true),
    ]);
    if (f == null || !mounted) return;
    final crla = vmsOf(context).crla;
    await runAction(
      context,
      () => crla.saveObservation(_id,
          learnerExperienceRating: int.tryParse(f['exp'] ?? ''),
          observationLevel: int.tryParse(f['obs'] ?? ''),
          remarks: (f['remarks'] ?? '').trim().isEmpty ? null : f['remarks']!.trim()),
      done: 'Observation saved.',
      where: 'CrlaMarking',
    );
    _again();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mark CRLA')),
      body: LoadView<_MarkData?>(
        where: 'CrlaMarking',
        reloadKey: _reload,
        load: (vms) async {
          final crla = vms.crla;
          final form = await crla.form(_id);
          return _MarkData(await crla.getAssessment(_id), form, await crla.storyTimer(_id), await crla.getResult(_id));
        },
        builder: (context, d, _) {
          if (d == null) return const EmptyNote('This attempt is not on this device.');
          final s = d.state;
          final theme = Theme.of(context);
          final a = d.attempt;
          final header = Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  a == null ? 'CRLA attempt' : '${a.round.label} · ${crlaVariantLabel(a.subjectVariant)} (${a.language}) · Grade ${d.form.grade}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (s.isDigitized) StatusChip(s.label, icon: Icons.edit_note, shrink: true),
                  StatusChip('Profile: ${d.result?.readingProfile ?? 'not yet'}',
                      tone: crlaProfileTone(d.result?.readingProfile), icon: Icons.auto_graph, shrink: true),
                ]),
              ]),
            ),
          );
          final part1 = _part1(context, d);
          final part2 = _part2(context, d);
          return PageBody(maxWidth: 1200, children: [
            header,
            LayoutBuilder(
              builder: (context, c) => c.maxWidth >= 840
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: part1),
                      const SizedBox(width: 12),
                      Expanded(child: part2),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [part1, const SizedBox(height: 12), part2]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _part1(BuildContext context, _MarkData d) {
    final s = d.state;
    final marks = {for (final m in s.evidence.part1) (m.task, m.itemNo): m};
    Widget task(CrlaTask t, int? score, {required bool done}) {
      final items = d.form.items[t] ?? const <CrlaPart1Item>[];
      return SectionCard(
        title: '${crlaTaskLabel(t)} · ${score ?? 0}/${items.length}',
        icon: Icons.abc,
        children: [
          for (final item in items)
            _ItemRow(
              task: t,
              item: item,
              mark: switch (marks[(t, item.itemNo)]) {
                null => null,
                final m when m.selfCorrected => _ItemMark.self,
                final m => m.correct ? _ItemMark.right : _ItemMark.wrong,
              },
              onTap: (current, tapped) => _item(t, item.itemNo, current, tapped),
            ),
          if (!done) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => _mark((vm, _) => vm.closeTask(_id, t)),
                child: Text('Done with ${t == CrlaTask.task1 ? 'Task 1' : 'Task 2'}'),
              ),
            ),
          ],
        ],
      );
    }

    final t2 = s.task2;
    final t2Items = t2 == null ? 0 : (d.form.items[t2]?.length ?? 0);
    final t2Marked = t2 == null ? 0 : s.evidence.part1.where((m) => m.task == t2).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      task(CrlaTask.task1, s.task1Score, done: s.task1Done),
      if (s.task1Done) ...[
        const SizedBox(height: 12),
        if (t2 == null)
          const EmptyNote('No Task 2: the test ends at Task 1.', icon: Icons.flag_outlined)
        else
          task(t2, s.task2Score, done: t2Marked >= t2Items),
      ],
    ]);
  }

  Widget _part2(BuildContext context, _MarkData d) {
    final s = d.state;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final stories = d.form.stories;
    final storyNo = s.storyNo ?? _pickedStory ?? (stories.isEmpty ? null : stories.first.storyNo);
    final story = stories.where((x) => x.storyNo == storyNo).firstOrNull;
    if (story == null) return const EmptyNote('No story in this form.');
    final words = {for (final w in s.evidence.words) if (w.storyNo == story.storyNo) w.wordIndex: w.kind};
    final answers = {for (final x in s.evidence.answers) if (x.storyNo == story.storyNo) x.questionNo: x.mark};
    final timed = s.timerStatus == TimerStatus.stopped;
    return SectionCard(
      title: 'Part 2 · ${story.title}',
      icon: Icons.menu_book_outlined,
      children: [
        if (s.storyNo == null && stories.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 6, children: [
              for (final x in stories)
                ChoiceChip(
                  label: Text('Story ${x.storyNo}'),
                  selected: x.storyNo == story.storyNo,
                  onSelected: (_) => setState(() => _pickedStory = x.storyNo),
                ),
            ]),
          ),
        _StoryClock(assessmentId: _id, state: s, storyNo: story.storyNo, onChanged: _again, run: _mark),
        if (s.lastWordNeeded)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: colors.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.touch_app_outlined, color: colors.onTertiaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Tap the last word the learner reached',
                    style: theme.textTheme.titleSmall?.copyWith(color: colors.onTertiaryContainer)),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        Text('Tap a word for a miscue (again to remove it); hold it for a self-correction.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < story.words.length; i++)
            _StoryWord(
              word: story.words[i],
              kind: words[i],
              afterLast: s.lastWordReached != null && i > s.lastWordReached!,
              onTap: () => s.lastWordNeeded
                  ? _mark((vm, _) => vm.setLastWordReached(_id, i))
                  : _mark((vm, _) => vm.toggleWord(_id, i)),
              onLongPress: () => _mark((vm, _) => vm.toggleWord(_id, i, kind: CrlaWordMarkKind.selfCorrected)),
            ),
        ]),
        const SizedBox(height: 12),
        StatGrid(tileWidth: 120, tiles: [
          StatTile(label: 'Miscues', value: '${s.miscues}', icon: Icons.spellcheck),
          StatTile(label: 'Words read', value: s.wordsRead?.toString() ?? '—', icon: Icons.format_list_numbered),
          StatTile(label: 'Comprehension', value: '${s.comprehension}', icon: Icons.quiz_outlined),
        ]),
        if (timed) ...[
          const SizedBox(height: 12),
          for (final q in story.questions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${q.questionNo}. ${q.question}', style: theme.textTheme.titleSmall),
                Text('Accepted: ${q.acceptedAnswers}', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: [
                  for (final (m, label) in [
                    (CrlaAnswerMark.correct, 'Correct'),
                    (CrlaAnswerMark.incorrect, 'Wrong'),
                    (CrlaAnswerMark.notAsked, 'Not asked'),
                  ])
                    ChoiceChip(
                      key: Key('q-${q.questionNo}-${switch (m) {
                        CrlaAnswerMark.correct => 'correct',
                        CrlaAnswerMark.incorrect => 'wrong',
                        CrlaAnswerMark.notAsked => 'notasked',
                      }}'),
                      label: Text(label),
                      selected: answers[q.questionNo] == m,
                      onSelected: (_) => _mark((vm, _) => vm.answerQuestion(_id, q.questionNo, m)),
                    ),
                ]),
              ]),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => _observation(d.result),
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Observation'),
            ),
          ),
        ],
      ],
    );
  }
}

/// One Part 1 item: its text and Right / Wrong / Self-corrected (tap the
/// chosen one again to clear it).
class _ItemRow extends StatelessWidget {
  final CrlaTask task;
  final CrlaPart1Item item;
  final _ItemMark? mark;
  final void Function(_ItemMark? current, _ItemMark tapped) onTap;
  const _ItemRow({required this.task, required this.item, required this.mark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget choice(_ItemMark m, String label, String key) => ChoiceChip(
          key: Key('item-${task.value}-${item.itemNo}-$key'),
          label: Text(label),
          selected: mark == m,
          onSelected: (_) => onTap(mark, m),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 150,
          child: Text('${item.itemNo}. ${item.text}${item.answerKey == null ? '' : ' (${item.answerKey})'}',
              style: theme.textTheme.bodyLarge),
        ),
        choice(_ItemMark.right, 'Right', 'right'),
        choice(_ItemMark.wrong, 'Wrong', 'wrong'),
        choice(_ItemMark.self, 'Self-corrected', 'self'),
      ]),
    );
  }
}

/// One story word: tap = miscue on/off, hold = self-corrected.
class _StoryWord extends StatelessWidget {
  final String word;
  final CrlaWordMarkKind? kind;
  final bool afterLast;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _StoryWord({required this.word, required this.kind, required this.afterLast, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (bg, fg, border) = switch (kind) {
      null => (colors.surfaceContainerLowest, afterLast ? colors.outline : colors.onSurface, colors.outlineVariant),
      CrlaWordMarkKind.selfCorrected => (colors.tertiaryContainer, colors.onTertiaryContainer, colors.tertiary),
      CrlaWordMarkKind.miscue => (colors.errorContainer, colors.onErrorContainer, colors.error),
    };
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: border)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(word,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: fg,
                  fontWeight: kind == null ? null : FontWeight.w600,
                  decoration: kind == CrlaWordMarkKind.miscue ? TextDecoration.lineThrough : null,
                  decorationColor: fg,
                )),
          ),
        ),
      ),
    );
  }
}

/// The story timer: the clock against the grade's limit and the buttons for
/// its state. While it runs it asks the ViewModel once a second; at the limit
/// the timer stops itself and the screen reloads (then: tap the last word).
class _StoryClock extends StatefulWidget {
  final int assessmentId;
  final CrlaDigitizedState state;
  final int storyNo;
  final VoidCallback onChanged;
  final Future<void> Function(Future<CrlaDigitizedState> Function(CrlaViewModel vm, bool confirmed) call) run;
  const _StoryClock({required this.assessmentId, required this.state, required this.storyNo, required this.onChanged, required this.run});

  @override
  State<_StoryClock> createState() => _StoryClockState();
}

class _StoryClockState extends State<_StoryClock> {
  late CrlaDigitizedState _s = widget.state;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_StoryClock old) {
    super.didUpdateWidget(old);
    _s = widget.state;
    _sync();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _sync() {
    _tick?.cancel();
    _tick = _s.timerStatus == TimerStatus.running ? Timer.periodic(const Duration(seconds: 1), (_) => _refresh()) : null;
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final crla = vmsOf(context).crla;
    try {
      final s = await crla.storyTimer(widget.assessmentId);
      if (!mounted) return;
      if (s.timerStatus != TimerStatus.running) {
        _tick?.cancel();
        widget.onChanged();
      } else {
        setState(() => _s = s);
      }
    } catch (e) {
      debugPrint('CrlaMarking timer: $e');
    }
  }

  Future<void> _restart() async {
    if (!await confirm(context, title: 'Time this story again?', body: 'The first timing stays in the record.', action: 'Restart')) {
      return;
    }
    await widget.run((vm, _) => vm.resetStoryTimer(widget.assessmentId));
  }

  static String _clock(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final id = widget.assessmentId;
    final limit = Duration(seconds: _s.timeLimitSeconds);
    final buttons = switch (_s.timerStatus) {
      TimerStatus.none => [
          FilledButton.icon(
              onPressed: () => widget.run((vm, _) => vm.startStoryTimer(id, widget.storyNo)),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start')),
        ],
      TimerStatus.running => [
          FilledButton.tonalIcon(
              onPressed: () => widget.run((vm, _) => vm.pauseStoryTimer(id)), icon: const Icon(Icons.pause), label: const Text('Pause')),
          FilledButton.icon(onPressed: () => widget.run((vm, _) => vm.stopStoryTimer(id)), icon: const Icon(Icons.stop), label: const Text('Stop')),
        ],
      TimerStatus.paused => [
          FilledButton.tonalIcon(
              onPressed: () => widget.run((vm, _) => vm.resumeStoryTimer(id)), icon: const Icon(Icons.play_arrow), label: const Text('Resume')),
          FilledButton.icon(onPressed: () => widget.run((vm, _) => vm.stopStoryTimer(id)), icon: const Icon(Icons.stop), label: const Text('Stop')),
        ],
      TimerStatus.stopped => [
          OutlinedButton.icon(onPressed: _restart, icon: const Icon(Icons.replay), label: const Text('Restart')),
        ],
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
      child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${_clock(_s.elapsed)} / ${_clock(limit)}',
            style: theme.textTheme.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ...buttons,
      ]),
    );
  }
}
