// lib/ui/crla/crla_entry_screen.dart
// Part 1 and Part 2 entry (docs/handoff/screens/crla.md): one attempt's
// Part 1 (standard for mother tongue / Filipino, English for English) and
// Part 2 (story, miscues, time, comprehension), then its reading profile.
// The profile is computed on saving; there is no preview before.
import 'package:flutter/material.dart';

import '../../core/models/crla_assessment.dart';
import '../../core/models/crla_result.dart';
import '../common/screen_kit.dart';
import 'crla_section_screen.dart';

class CrlaEntryScreen extends StatefulWidget {
  final int assessmentId;
  const CrlaEntryScreen({super.key, required this.assessmentId});

  @override
  State<CrlaEntryScreen> createState() => _CrlaEntryScreenState();
}

class _CrlaEntryScreenState extends State<CrlaEntryScreen> {
  int _reload = 0;

  Future<void> _part1(CrlaAssessment a) async {
    final english = a.subjectVariant == 'eng';
    final f = await askFields(
      context,
      title: english ? 'Part 1 (English)' : 'Part 1',
      note: english
          ? 'Task 2 only when task 1 is 1 to 10.'
          : 'Task 2 low (rhymes/words) when task 1 is below 7; task 2 high (sentences) when it is 7 or more.',
      fields: [
        const FieldSpec('t1', 'Task 1 score', number: true),
        if (english)
          const FieldSpec('t2', 'Task 2 score', number: true, optional: true)
        else ...[
          const FieldSpec('low', 'Task 2 low score', number: true, optional: true),
          const FieldSpec('high', 'Task 2 high score', number: true, optional: true),
        ],
      ],
    );
    if (f == null || !mounted) return;
    final t1 = int.tryParse(f['t1']!);
    if (t1 == null) return showNote(context, 'Task 1 must be a whole number.');
    final crla = vmsOf(context).crla;
    await runAction(
      context,
      () => english
          ? crla.savePart1English(assessmentId: a.id!, task1Score: t1, task2Score: int.tryParse(f['t2'] ?? ''))
          : crla.savePart1Standard(
              assessmentId: a.id!,
              task1Score: t1,
              task2LowScore: int.tryParse(f['low'] ?? ''),
              task2HighScore: int.tryParse(f['high'] ?? ''),
            ),
      done: 'Part 1 saved.',
      where: 'CrlaEntry',
    );
    setState(() => _reload++);
  }

  Future<void> _part2(CrlaAssessment a, CrlaResult? r) async {
    String v(num? x) => x == null ? '' : '$x';
    final f = await askFields(
      context,
      title: 'Part 2 (reading the story)',
      note: 'Words read is needed only where the region has no story list.',
      fields: [
        FieldSpec('story', 'Story number', initial: v(r?.storyNo), number: true),
        FieldSpec('miscues', 'Miscues', initial: v(r?.miscues), number: true),
        FieldSpec('words', 'Words read', initial: v(r?.wordsRead), number: true, optional: true),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CRLA attempt')),
      body: LoadView<(CrlaAssessment?, CrlaResult?)>(
        where: 'CrlaEntry',
        reloadKey: _reload,
        load: (vms) async =>
            (await vms.crla.getAssessment(widget.assessmentId), await vms.crla.getResult(widget.assessmentId)),
        builder: (context, data, _) {
          final (a, r) = data;
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
              const SizedBox(width: 8),
              enter(() => _part2(a, r), part2Done),
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
              InfoRow('Story', v(r?.storyNo)),
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
                          StatusChip('Attempt ${v(a.attemptNo)}', icon: Icons.replay),
                          StatusChip(a.assessedAt, icon: Icons.event_outlined),
                          if (a.administeredBy != null) StatusChip(a.administeredBy!, icon: Icons.person_outline),
                        ]),
                      ]),
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
