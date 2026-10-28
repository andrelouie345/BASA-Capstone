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

/// How a Phil-IRI level reads at a glance: independent = good,
/// instructional = warn, frustration / non-reader = bad.
StatusTone philIriLevelTone(PhilIriLevel? l) => switch (l) {
  PhilIriLevel.independent => StatusTone.good,
  PhilIriLevel.instructional => StatusTone.warn,
  PhilIriLevel.frustration || PhilIriLevel.nonReader => StatusTone.bad,
  null => StatusTone.neutral,
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

  /// The loaded session, for the app bar and the floating button.
  final _session = ValueNotifier<PhilIriAssessment?>(null);

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

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

  /// "Add" (a reading) while the session is open: app bar on wide screens, floating on phones.
  Widget _mainAction({required bool fab}) => ValueListenableBuilder<PhilIriAssessment?>(
    valueListenable: _session,
    builder: (context, s, _) {
      if (s == null || s.status != PhilIriStatus.inProgress) return const SizedBox.shrink();
      return fab
          ? mainActionFab(onPressed: _addReading, icon: Icons.add, label: 'Add')
          : mainActionButton(onPressed: _addReading, icon: Icons.add, label: 'Add');
    },
  );

  Widget _overflow() => ValueListenableBuilder<PhilIriAssessment?>(
    valueListenable: _session,
    builder: (context, s, _) {
      if (s == null || s.isFinalized) return const SizedBox.shrink();
      return PopupMenuButton<String>(
        onSelected: _status,
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'discard', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Discard'))),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Phil-IRI session'), actions: [if (wide) _mainAction(fab: false), _overflow()]),
      floatingActionButton: wide ? null : _mainAction(fab: true),
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _session.value = d?.session;
          });
          if (d == null) return const EmptyNote('This session is not on this device.', icon: Icons.cloud_off_outlined);
          final s = d.session;
          final open = s.status == PhilIriStatus.inProgress;
          final theme = Theme.of(context);
          final scored = d.criteria.where((c) => d.scores.any((x) => x.criterionId == c.id)).length;
          final header = SectionCard(
            title: '${s.round.label} · ${s.assessedAt}',
            icon: Icons.assignment_outlined,
            trailing: philIriStatusChip(s.status),
            children: [
              StatGrid(tileWidth: 160, tiles: [
                StatTile(label: 'Readings', value: '${d.readings.length}', icon: Icons.menu_book_outlined),
                StatTile(label: 'Timed', value: '${d.readings.where((x) => x.$1.isTimed).length}', icon: Icons.timer_outlined),
                if (d.criteria.isNotEmpty)
                  StatTile(label: 'Rubric scored', value: '$scored/${d.criteria.length}', icon: Icons.rule),
              ]),
              const SizedBox(height: 12),
              InfoRow('Status', philIriStatusLabel(s.status)),
              if (open || s.status == PhilIriStatus.completed) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (open)
                    FilledButton.icon(onPressed: () => _status('complete'), icon: const Icon(Icons.task_alt), label: const Text('Complete')),
                  if (s.status == PhilIriStatus.completed)
                    OutlinedButton.icon(onPressed: () => _status('reopen'), icon: const Icon(Icons.lock_open), label: const Text('Reopen')),
                ]),
              ],
            ],
          );
          final readings = d.readings.isEmpty
              ? SectionCard(
                  title: 'Readings',
                  icon: Icons.menu_book_outlined,
                  children: [
                    const EmptyNote('No passage read yet.', icon: Icons.auto_stories_outlined),
                    if (open)
                      Text(
                        'Tap Add to pick a passage.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                )
              : ListCard(
                  title: 'Readings',
                  children: [
                    for (final (r, p, score) in d.readings)
                      ListRow(
                        leading: LetterBadge('${r.sequenceNo}', size: 36),
                        title: p?.title ?? 'Passage #${r.passageId}',
                        subtitle: readingMethodLabel(r.method),
                        footer: !r.isTimed
                            ? const StatusChip('not timed yet', tone: StatusTone.warn, icon: Icons.timer_off_outlined)
                            : score != null
                            ? StatusChip(score.profile.label, tone: philIriLevelTone(score.profile))
                            : null,
                        trailing: const [Icon(Icons.chevron_right)],
                        onTap: () => _openReading(r.id!),
                      ),
                  ],
                );
          final rubric = d.criteria.isEmpty
              ? null
              : ListCard(
                  title: 'Rubric',
                  children: [
                    for (final c in d.criteria)
                      Builder(builder: (context) {
                        final score = d.scores.where((x) => x.criterionId == c.id).firstOrNull;
                        return ListRow(
                          leading: const IconBadge(Icons.rule, size: 36),
                          title: c.name,
                          subtitle: '${c.scaleMin} to ${c.scaleMax}',
                          trailing: [
                            score == null
                                ? Text('—', style: theme.textTheme.titleMedium)
                                : LetterBadge(
                                    '${score.score}',
                                    size: 36,
                                    background: theme.colorScheme.secondaryContainer,
                                    foreground: theme.colorScheme.onSecondaryContainer,
                                  ),
                            if (open) const Icon(Icons.edit_outlined, size: 18),
                          ],
                          onTap: open ? () => _score(c, score) : null,
                        );
                      }),
                  ],
                );
          return LayoutBuilder(builder: (context, c) {
            // Wide: readings left, status and rubric right.
            if (c.maxWidth >= 1000) {
              return PageBody(
                maxWidth: 1200,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: readings),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        header,
                        if (rubric != null) ...[const SizedBox(height: 16), rubric],
                      ]),
                    ),
                  ]),
                ],
              );
            }
            return PageBody(children: [header, readings, ?rubric]);
          });
        },
      ),
    );
  }
}
