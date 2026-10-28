// lib/ui/phil_iri/phil_iri_section_screen.dart
// Section Phil-IRI sessions (docs/handoff/screens/phil-iri.md): a section's
// sessions for a round, a new session for a learner, and a learner's
// results. A session opens the assessment session screen.
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_assessment.dart';
import '../../core/models/section.dart';
import '../../core/models/student.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import 'gst_screen.dart';
import 'learner_results_screen.dart';
import 'session_screen.dart';

/// "in progress", "completed", "finalized".
String philIriStatusLabel(PhilIriStatus s) => switch (s) {
  PhilIriStatus.inProgress => 'in progress',
  PhilIriStatus.completed => 'completed',
  PhilIriStatus.finalized => 'finalized',
};

/// A session's status as a chip: in progress = warn, completed = good, finalized = locked.
StatusChip philIriStatusChip(PhilIriStatus s) => switch (s) {
  PhilIriStatus.inProgress => StatusChip(philIriStatusLabel(s), tone: StatusTone.warn, icon: Icons.pending_outlined),
  PhilIriStatus.completed => StatusChip(philIriStatusLabel(s), tone: StatusTone.good, icon: Icons.check_circle_outline),
  PhilIriStatus.finalized => StatusChip(philIriStatusLabel(s), icon: Icons.lock_outline),
};

class PhilIriSectionScreen extends StatefulWidget {
  const PhilIriSectionScreen({super.key});

  @override
  State<PhilIriSectionScreen> createState() => _PhilIriSectionScreenState();
}

class _PhilIriSectionScreenState extends State<PhilIriSectionScreen> {
  Section? _section;
  PhilIriRound _round = PhilIriRound.values.first;
  int _reload = 0;

  /// The loaded section's learners, for the main action outside the loaded body.
  final _learners = ValueNotifier<List<Student>?>(null);

  @override
  void dispose() {
    _learners.dispose();
    super.dispose();
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhilIriSessionScreen(assessmentId: id)));
    if (mounted) setState(() => _reload++);
  }

  Future<void> _start(List<Student> learners) async {
    final section = _section!;
    final student = await pickOne<Student>(context, title: 'Start a session for', options: learners, label: studentLabel);
    if (student == null || !mounted) return;
    final vm = vmsOf(context).philIri;
    final a = await runAction(
      context,
      () => vm.startSession(studentId: student.id!, sectionId: section.id!, schoolYear: section.schoolYear, round: _round),
      where: 'PhilIriSection',
    );
    if (a?.id != null && mounted) await _open(a!.id!);
  }

  void _pickSection(Section? s) {
    _learners.value = null;
    setState(() => _section = s);
  }

  /// The main action, once the section's learners are loaded.
  Widget _mainAction({required bool fab}) => ValueListenableBuilder<List<Student>?>(
    valueListenable: _learners,
    builder: (context, learners, _) {
      if (_section == null || learners == null || learners.isEmpty) return const SizedBox.shrink();
      final label = 'Start a ${_round.label} session';
      void go() => _start(learners);
      return fab
          ? mainActionFab(onPressed: go, icon: Icons.play_arrow, label: label)
          : mainActionButton(onPressed: go, icon: Icons.play_arrow, label: label);
    },
  );

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Phil-IRI by section'), actions: [if (wide) _mainAction(fab: false)]),
      floatingActionButton: wide ? null : _mainAction(fab: true),
      body: PageBody(
        maxWidth: 1200,
        children: [
          FilterBar(children: [
            SectionPicker(value: _section, onChanged: _pickSection, where: philIriGrade),
            PhilIriRoundPicker(value: _round, onChanged: (r) => setState(() => _round = r ?? _round)),
          ]),
          if (_section == null)
            const EmptyNote('Pick a Grade 4–10 section to see its Phil-IRI sessions.', icon: Icons.class_outlined),
          if (_section != null)
            LoadView<(List<PhilIriAssessment>, List<Student>)>(
              where: 'PhilIriSection',
              reloadKey: '${_section!.id}-${_round.name}-$_reload',
              load: (vms) async {
                final s = _section!;
                await vms.philIri.loadForSection(s.id!, schoolYear: s.schoolYear, round: _round);
                return (List.of(vms.philIri.assessments), await vms.student.localStudents(s.id!));
              },
              builder: (context, data, _) {
                final (sessions, learners) = data;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _learners.value = learners;
                });
                final byStudent = <int, List<PhilIriAssessment>>{};
                for (final a in sessions) {
                  byStudent.putIfAbsent(a.studentId, () => []).add(a);
                }
                final done = sessions.where((a) => a.status != PhilIriStatus.inProgress).length;
                final cards = [
                  for (final s in learners)
                    ListCard(
                      children: [
                        ListRow(
                          leading: LetterBadge(initialOf(studentLabel(s))),
                          title: studentLabel(s),
                          subtitle: '${(byStudent[s.id] ?? const []).length} session(s) this round',
                          trailing: [
                            FilledButton.tonal(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => LearnerResultsScreen(student: s, section: _section!),
                              )),
                              child: const Text('Results'),
                            ),
                          ],
                        ),
                        for (final a in byStudent[s.id] ?? const <PhilIriAssessment>[])
                          ListRow(
                            leading: const IconBadge(Icons.menu_book_outlined, size: 36),
                            title: 'Session ${a.attemptNo ?? ''} · ${a.assessedAt}',
                            footer: philIriStatusChip(a.status),
                            trailing: const [Icon(Icons.chevron_right)],
                            onTap: () => _open(a.id!),
                          ),
                      ],
                    ),
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatGrid(tileWidth: 170, tiles: [
                      StatTile(label: 'Learners', value: '${learners.length}', icon: Icons.people_alt_outlined),
                      StatTile(label: 'Sessions', value: '${sessions.length}', icon: Icons.menu_book_outlined),
                      StatTile(label: 'Learners assessed', value: '${byStudent.length}', icon: Icons.how_to_reg_outlined),
                      StatTile(label: 'Completed', value: '$done', icon: Icons.task_alt),
                    ]),
                    const SizedBox(height: 16),
                    if (learners.isEmpty)
                      const EmptyNote('No learners in this section on this device.', icon: Icons.person_search_outlined),
                    LayoutBuilder(builder: (context, c) {
                      // Wide: the learner cards in two columns.
                      if (c.maxWidth < 1000) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 12), cards[i]],
                          ],
                        );
                      }
                      const gap = 12.0;
                      final w = (c.maxWidth - gap) / 2;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [for (final card in cards) SizedBox(width: w, child: card)],
                      );
                    }),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
