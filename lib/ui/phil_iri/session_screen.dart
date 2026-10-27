// lib/ui/phil_iri/session_screen.dart
// Assessment session (docs/handoff/screens/phil-iri.md): one learner's
// session: its readings (a passage each: whole text, one minute or silent),
// the rubric, and complete / reopen / discard. A reading opens the reading
// screen (timing, miscues on the passage's words, observations, answers).
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_assessment.dart';
import '../../core/models/phil_iri_collection.dart';
import '../../core/models/phil_iri_passage.dart';
import '../../core/models/phil_iri_reading.dart';
import '../../core/models/phil_iri_rubric_score.dart';
import '../../core/models/phil_iri_types.dart';
import '../common/screen_kit.dart';
import 'phil_iri_section_screen.dart';
import 'reading_screen.dart';

String readingMethodLabel(PhilIriReadingMethod m) => switch (m) {
  PhilIriReadingMethod.wholeText => 'Whole text (timed)',
  PhilIriReadingMethod.oneMinute => 'One minute',
  PhilIriReadingMethod.silent => 'Silent',
};

class PhilIriSessionScreen extends StatefulWidget {
  final int assessmentId;
  const PhilIriSessionScreen({super.key, required this.assessmentId});

  @override
  State<PhilIriSessionScreen> createState() => _PhilIriSessionScreenState();
}

class _SessionData {
  final PhilIriAssessment session;
  final List<(PhilIriReading, PhilIriPassage?, PhilIriPassageResult?)> readings;
  final List<PhilIriRubricCriterion> criteria;
  final List<PhilIriRubricScore> scores;
  const _SessionData(this.session, this.readings, this.criteria, this.scores);
}

class _PhilIriSessionScreenState extends State<PhilIriSessionScreen> {
  int _reload = 0;
  void _again() => setState(() => _reload++);

  Future<void> _openReading(int readingId) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PhilIriReadingScreen(assessmentId: widget.assessmentId, readingId: readingId),
    ));
    if (mounted) _again();
  }

  Future<void> _addReading() async {
    final vm = vmsOf(context).philIri;
    final method = await pickOne<PhilIriReadingMethod>(
      context,
      title: 'How is the passage read?',
      options: PhilIriReadingMethod.values,
      label: readingMethodLabel,
    );
    if (method == null || !mounted) return;
    final passages = await runAction(context, () => vm.availablePassages(widget.assessmentId, method: method), where: 'PhilIriSession');
    if (passages == null || !mounted) return;
    if (passages.isEmpty) return showNote(context, 'No passage is left for this learner and round.');
    final p = await pickOne<PhilIriPassage>(
      context,
      title: 'Passage',
      options: passages,
      label: (p) => '${p.title}${p.level == null ? '' : ' · Grade ${p.level}'}${p.setCode == null ? '' : ' · Set ${p.setCode}'}',
    );
    if (p == null || !mounted) return;
    final r = await runAction(context, () => vm.startReading(assessmentId: widget.assessmentId, passageId: p.id!, method: method),
        where: 'PhilIriSession');
    if (r?.id != null && mounted) await _openReading(r!.id!);
  }

  Future<void> _status(String action) async {
    final vm = vmsOf(context).philIri;
    final id = widget.assessmentId;
    if (action == 'discard' &&
        !await confirm(context, title: 'Discard this session?', body: 'Its readings and answers are deleted.', action: 'Discard', destructive: true)) {
      return;
    }
    if (!mounted) return;
    switch (action) {
      case 'complete':
        await runAction(context, () => vm.complete(id), done: 'Session completed.', where: 'PhilIriSession');
      case 'reopen':
        await runAction(context, () => vm.reopen(id), done: 'Session reopened.', where: 'PhilIriSession');
      default:
        if (await runStep(context, () => vm.discard(id), done: 'Session discarded.', where: 'PhilIriSession') && mounted) {
          return Navigator.of(context).pop();
        }
    }
    _again();
  }

  Future<void> _score(PhilIriRubricCriterion c, PhilIriRubricScore? current) async {
    final f = await askFields(context,
        title: c.name,
        fields: [FieldSpec('s', 'Score (${c.scaleMin} to ${c.scaleMax})', initial: current == null ? '' : '${current.score}', number: true)]);
    final s = int.tryParse(f?['s'] ?? '');
    if (s == null || !mounted) return;
    final vm = vmsOf(context).philIri;
    await runAction(context, () => vm.scoreRubric(assessmentId: widget.assessmentId, criterionId: c.id!, score: s),
        done: 'Rubric saved.', where: 'PhilIriSession');
    _again();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phil-IRI session')),
      body: LoadView<_SessionData?>(
        where: 'PhilIriSession',
        reloadKey: _reload,
        load: (vms) async {
          final vm = vms.philIri;
          final session = await vm.getSession(widget.assessmentId);
          if (session == null) return null;
          final readings = <(PhilIriReading, PhilIriPassage?, PhilIriPassageResult?)>[];
          int? collectionId;
          for (final r in await vm.readings(widget.assessmentId)) {
            final p = await vm.passage(r.passageId);
            collectionId ??= p?.collectionId;
            PhilIriPassageResult? score;
            if (r.isTimed) {
              try {
                score = await vm.scoreReading(r.id!);
              } catch (e) {
                debugPrint('PhilIriSession: score ${r.id}: $e');
              }
            }
            readings.add((r, p, score));
          }
          final criteria = collectionId == null ? <PhilIriRubricCriterion>[] : await vm.rubricCriteria(collectionId);
          return _SessionData(session, readings, criteria, await vm.rubricScores(widget.assessmentId));
        },
        builder: (context, d, _) {
          if (d == null) return const EmptyNote('This session is not on this device.');
          final s = d.session;
          final open = s.status == PhilIriStatus.inProgress;
          return PageBody(
            children: [
              SectionCard(
                title: '${s.round.label} · ${s.assessedAt}',
                children: [
                  InfoRow('Status', philIriStatusLabel(s.status)),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (open) FilledButton(onPressed: () => _status('complete'), child: const Text('Complete')),
                    if (s.status == PhilIriStatus.completed) OutlinedButton(onPressed: () => _status('reopen'), child: const Text('Reopen')),
                    if (!s.isFinalized) TextButton(onPressed: () => _status('discard'), child: const Text('Discard')),
                  ]),
                ],
              ),
              SectionCard(
                title: 'Readings',
                trailing: open ? TextButton.icon(onPressed: _addReading, icon: const Icon(Icons.add), label: const Text('Add')) : null,
                children: [
                  if (d.readings.isEmpty) const Text('No passage read yet.'),
                  for (final (r, p, score) in d.readings)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Text('${r.sequenceNo}')),
                      title: Text(p?.title ?? 'Passage #${r.passageId}'),
                      subtitle: Text([
                        readingMethodLabel(r.method),
                        if (!r.isTimed) 'not timed yet',
                        if (score != null) score.profile.label,
                      ].join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openReading(r.id!),
                    ),
                ],
              ),
              if (d.criteria.isNotEmpty)
                SectionCard(
                  title: 'Rubric',
                  children: [
                    for (final c in d.criteria)
                      Builder(builder: (context) {
                        final score = d.scores.where((x) => x.criterionId == c.id).firstOrNull;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.name),
                          subtitle: Text('${c.scaleMin} to ${c.scaleMax}'),
                          trailing: Text(score == null ? '—' : '${score.score}', style: Theme.of(context).textTheme.titleMedium),
                          onTap: open ? () => _score(c, score) : null,
                        );
                      }),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
