// lib/ui/crla/crla_entry_screen.dart
// Part 1 and Part 2 entry (docs/handoff/screens/crla.md): one attempt's
// Part 1 (standard for mother tongue / Filipino, English for English) and
// Part 2 (story, miscues, time, comprehension), then its reading profile.
// The profile is computed on saving; there is no preview before.
import 'package:flutter/material.dart';

import '../../core/models/crla_assessment.dart';
import '../../core/models/crla_result.dart';
import '../../core/models/crla_story.dart';
import '../../viewmodels/viewmodel_exception.dart';
import '../common/screen_kit.dart';
import 'crla_section_screen.dart';
import 'crla_story_help_screen.dart';

/// "1 · Bagyo sa Baryo (121 words)".
String crlaStoryLine(CrlaStory s) => '${s.storyNo} · ${s.title} (${s.wordCount} words)';

class CrlaEntryScreen extends StatefulWidget {
  final int assessmentId;
  const CrlaEntryScreen({super.key, required this.assessmentId});

  @override
  State<CrlaEntryScreen> createState() => _CrlaEntryScreenState();
}

class _CrlaEntryScreenState extends State<CrlaEntryScreen> {
  int _reload = 0;

  /// Asks Task 1 first, then only the Task 2 that its score calls for (the
  /// scoresheet's rule), so the wrong Task 2 can't be filled in.
  Future<void> _part1(CrlaAssessment a) async {
    final english = a.subjectVariant == 'eng';
    final title = english ? 'Part 1 (English)' : 'Part 1';
    final first = await askFields(context,
        title: title, fields: const [FieldSpec('t1', 'Task 1 score (0 to 10)', number: true)]);
    if (first == null || !mounted) return;
    final t1 = int.tryParse(first['t1']!);
    if (t1 == null) return showNote(context, 'Task 1 must be a whole number.');
    // English: Task 2 for a Task 1 of 1 or more. Standard: Task 2 low (rhymes
    // and words) for 0 to 6, Task 2 high (sentences) for 7 or more.
    final (String? key, String? label) = english
        ? (t1 >= 1 ? ('t2', 'Task 2 score (0 to 10)') : (null, null))
        : (t1 < 7 ? ('low', 'Task 2 low: rhymes and words (0 to 10)') : ('high', 'Task 2 high: sentences (0 to 10)'));
    int? t2;
    if (key != null) {
      if (!mounted) return;
      final second = await askFields(context,
          title: title,
          note: 'Task 1 is $t1, so enter ${english ? 'Task 2' : t1 < 7 ? 'Task 2 low' : 'Task 2 high'}.',
          fields: [FieldSpec(key, label!, number: true)]);
      if (second == null || !mounted) return;
      t2 = int.tryParse(second[key]!);
      if (t2 == null) return showNote(context, 'Task 2 must be a whole number.');
    }
    if (!mounted) return;
    final crla = vmsOf(context).crla;
    await runAction(
      context,
      () => english
          ? crla.savePart1English(assessmentId: a.id!, task1Score: t1, task2Score: t2)
          : crla.savePart1Standard(
              assessmentId: a.id!,
              task1Score: t1,
              task2LowScore: key == 'low' ? t2 : null,
              task2HighScore: key == 'high' ? t2 : null,
            ),
      done: 'Part 1 saved.',
      where: 'CrlaEntry',
    );
    setState(() => _reload++);
  }

  Future<void> _part2(CrlaAssessment a, CrlaResult? r, List<CrlaStory> stories) async {
    String v(num? x) => x == null ? '' : '$x';
    const ask = 'Not sure which story? Ask your coordinator.';
    final f = await askFields(
      context,
      title: 'Part 2 (reading the story)',
      onHelp: () => CrlaStoryHelpScreen.open(context),
      helpTooltip: 'Story number and words read',
      fields: [
        FieldSpec('story', 'Story number', initial: v(r?.storyNo), number: true,
            helper: stories.isEmpty
                ? 'No story list for this region, language and grade. $ask'
                : [...stories.map(crlaStoryLine), ask].join('\n')),
        FieldSpec('miscues', 'Miscues', initial: v(r?.miscues), number: true),
        FieldSpec('words', 'Words read', initial: v(r?.wordsRead), number: true, optional: true,
            helper: stories.isEmpty
                ? "Needed here: the story's total words minus the miscues."
                : 'Leave blank: BASA works it out (story words minus miscues).'),
        const FieldSpec('min', 'Time: minutes', number: true),
        const FieldSpec('sec', 'Time: seconds', number: true),
        FieldSpec('comp', 'Comprehension: correct answers', initial: v(r?.comprehensionCorrect), number: true),
        FieldSpec('exp', 'Learner experience rating', initial: v(r?.learnerExperienceRating), number: true, optional: true),
        FieldSpec('obs', 'Observation level', initial: v(r?.observationLevel), number: true, optional: true),
        FieldSpec('remarks', 'Remarks', initial: r?.remarks ?? '', optional: true, multiline: true),
      ],
    );
    if (f == null || !mounted) return;
    int? n(String k) => int.tryParse(f[k] ?? '');
    final required = [n('story'), n('miscues'), n('min'), n('sec'), n('comp')];
    if (required.contains(null)) return showNote(context, 'Story, miscues, time and comprehension must be whole numbers.');
    final crla = vmsOf(context).crla;
    await runAction(
      context,
      () => crla.savePart2Fluency(
        assessmentId: a.id!,
        storyNo: n('story')!,
        miscues: n('miscues')!,
        wordsRead: n('words'),
        timeMinutes: n('min')!,
        timeSeconds: n('sec')!,
        comprehensionCorrect: n('comp')!,
        learnerExperienceRating: n('exp'),
        observationLevel: n('obs'),
        remarks: (f['remarks'] ?? '').isEmpty ? null : f['remarks'],
      ),
      done: 'Part 2 saved.',
      where: 'CrlaEntry',
    );
    setState(() => _reload++);
  }

  /// An attempt started by mistake (wrong learner, test, language or round):
  /// only on this device alone (negative id); the ViewModel also checks it is
  /// the learner's latest.
  Future<void> _remove(CrlaAssessment a) async {
    final ok = await confirm(
      context,
      title: 'Remove this attempt?',
      body: 'Attempt ${a.attemptNo} (${a.round.label}, ${crlaVariantLabel(a.subjectVariant)}) and its Part 1 and '
          'Part 2 are removed from this device.\n\n$removeUnsentWarning',
      action: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final crla = vmsOf(context).crla;
    final navigator = Navigator.of(context);
    if (await runStep(context, () => crla.removeAttempt(a.id!), done: 'Attempt removed.', where: 'CrlaEntry')) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CRLA attempt')),
      body: LoadView<(CrlaAssessment?, CrlaResult?, List<CrlaStory>)>(
        where: 'CrlaEntry',
        reloadKey: _reload,
        load: (vms) async {
          final a = await vms.crla.getAssessment(widget.assessmentId);
          final r = await vms.crla.getResult(widget.assessmentId);
          var stories = const <CrlaStory>[];
          if (a != null) {
            try {
              stories = await vms.crla.storiesForAttempt(widget.assessmentId);
            } on ViewModelException catch (e) {
              debugPrint('CrlaEntry: no story list: ${e.message}');
            }
          }
          return (a, r, stories);
        },
        builder: (context, data, _) {
          final (a, r, stories) = data;
          if (a == null) return const EmptyNote('This attempt is not on this device.');
          String v(Object? x) => x == null ? '—' : '$x';
          final theme = Theme.of(context);
          final profile = r?.readingProfile ?? a.readingProfile;
          final part1Done = r?.part1TotalScore != null;
          final part2Done = r?.storyNo != null;
          Widget doneChip(bool done) =>
              StatusChip(done ? 'Done' : 'To do', tone: done ? StatusTone.good : StatusTone.warn);
          Widget enter(VoidCallback onPressed, bool done) => OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
            child: Text(done ? 'Change' : 'Enter'),
          );
          final part1 = SectionCard(
            title: 'Part 1',
            icon: Icons.abc,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              doneChip(part1Done),
              const SizedBox(width: 8),
              enter(() => _part1(a), part1Done),
            ]),
            children: [
              InfoRow('Total score', v(r?.part1TotalScore)),
              InfoRow('Reading level', v(r?.part1ReadingLevel)),
            ],
          );
          final part2 = SectionCard(
            title: 'Part 2',
            icon: Icons.menu_book_outlined,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              doneChip(part2Done),
              TextButton.icon(
                icon: const Icon(Icons.help_outline),
                label: const Text('Help'),
                onPressed: () => CrlaStoryHelpScreen.open(context),
              ),
              const SizedBox(width: 4),
              enter(() => _part2(a, r, stories), part2Done),
            ]),
            children: [
              StatGrid(tileWidth: 140, tiles: [
                StatTile(label: 'Words per minute', value: r?.wpm == null ? '—' : r!.wpm!.toStringAsFixed(1)),
                StatTile(
                  label: 'Correct words',
                  value: r?.pctCorrectWordsRead == null ? '—' : '${r!.pctCorrectWordsRead!.toStringAsFixed(1)}%',
                ),
                StatTile(label: 'Comprehension', value: v(r?.comprehensionCorrect)),
                StatTile(label: 'Miscues', value: v(r?.miscues)),
              ]),
              const SizedBox(height: 8),
              InfoRow('Story', switch (stories.where((s) => s.storyNo == r?.storyNo).firstOrNull) {
                final s? => crlaStoryLine(s),
                null => v(r?.storyNo),
              }),
              InfoRow('Words read', v(r?.wordsRead)),
            ],
          );
          return PageBody(
            maxWidth: 1100,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    const IconBadge(Icons.record_voice_over_outlined, size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '${a.round.label} · ${crlaVariantLabel(a.subjectVariant)} (${a.language})',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          if ((a.id ?? 0) < 0) const StatusChip('Not uploaded yet', icon: Icons.cloud_off_outlined),
                          StatusChip('Attempt ${v(a.attemptNo)}', icon: Icons.replay),
                          StatusChip(a.assessedAt, icon: Icons.event_outlined),
                          if (a.administeredBy != null && a.administeredBy == vmsOf(context).auth.currentUser?.id)
                            const StatusChip('By you', icon: Icons.person_outline),
                        ]),
                      ]),
                    ),
                    if ((a.id ?? 0) < 0)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove'),
                        onPressed: () => _remove(a),
                      ),
                  ]),
                ),
              ),
              _ProfileCard(profile: profile),
              LayoutBuilder(
                builder: (context, c) => c.maxWidth >= 1000
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: part1),
                        const SizedBox(width: 12),
                        Expanded(child: part2),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        part1,
                        const SizedBox(height: 12),
                        part2,
                      ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The attempt's reading profile, tinted by how it reads (crlaProfileTone).
class _ProfileCard extends StatelessWidget {
  final String? profile;
  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = switch (crlaProfileTone(profile)) {
      StatusTone.good => colors.tertiary,
      StatusTone.warn => colors.secondary,
      StatusTone.bad => colors.error,
      StatusTone.neutral => colors.primary,
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Color.alphaBlend(accent.withValues(alpha: 0.10), colors.surfaceContainerLowest),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        IconBadge(Icons.auto_graph, size: 48, background: accent.withValues(alpha: 0.16), foreground: accent),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reading profile', style: theme.textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(
              profile ?? 'Not yet: enter Part 1 and Part 2.',
              style: profile == null
                  ? theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant)
                  : theme.textTheme.titleLarge?.copyWith(color: accent),
            ),
          ]),
        ),
      ]),
    );
  }
}
