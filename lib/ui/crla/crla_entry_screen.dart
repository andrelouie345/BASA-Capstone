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
          return PageBody(
            maxWidth: 720,
            children: [
              SectionCard(
                title: '${a.round.label} · ${crlaVariantLabel(a.subjectVariant)} (${a.language})',
                children: [
                  InfoRow('Attempt', v(a.attemptNo)),
                  InfoRow('Assessed', a.assessedAt),
                  if (a.administeredBy != null) InfoRow('By', a.administeredBy!),
                ],
              ),
              SectionCard(
                title: 'Part 1',
                trailing: TextButton(onPressed: () => _part1(a), child: Text(r?.part1TotalScore == null ? 'Enter' : 'Change')),
                children: [
                  InfoRow('Total score', v(r?.part1TotalScore)),
                  InfoRow('Reading level', v(r?.part1ReadingLevel)),
                ],
              ),
              SectionCard(
                title: 'Part 2',
                trailing: TextButton(onPressed: () => _part2(a, r), child: Text(r?.storyNo == null ? 'Enter' : 'Change')),
                children: [
                  InfoRow('Story', v(r?.storyNo)),
                  InfoRow('Words read', v(r?.wordsRead)),
                  InfoRow('Miscues', v(r?.miscues)),
                  InfoRow('Words per minute', r?.wpm == null ? '—' : r!.wpm!.toStringAsFixed(1)),
                  InfoRow('Correct words', r?.pctCorrectWordsRead == null ? '—' : '${r!.pctCorrectWordsRead!.toStringAsFixed(1)}%'),
                  InfoRow('Comprehension', v(r?.comprehensionCorrect)),
                ],
              ),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.auto_graph),
                  title: const Text('Reading profile'),
                  subtitle: Text(r?.readingProfile ?? a.readingProfile ?? 'Not yet: enter Part 1 and Part 2.'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
