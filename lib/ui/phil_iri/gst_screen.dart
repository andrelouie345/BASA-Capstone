// lib/ui/phil_iri/gst_screen.dart
// GST, the Group Screening Test (docs/handoff/screens/phil-iri.md): a
// section's GST scores for its school year, and a learner's new score
// (total, or literal / inferential / critical).
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_gst_result.dart';
import '../../core/models/section.dart';
import '../../core/models/student.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';

/// Grades 4 to 10 (Phil-IRI English).
bool philIriGrade(Section s) => (int.tryParse(s.gradeLevel) ?? 0) >= 4;

class GstScreen extends StatefulWidget {
  const GstScreen({super.key});

  @override
  State<GstScreen> createState() => _GstScreenState();
}

class _GstScreenState extends State<GstScreen> {
  Section? _section;
  int _reload = 0;

  /// The loaded section's learners, for the main action outside the loaded body.
  final _learners = ValueNotifier<List<Student>?>(null);

  @override
  void dispose() {
    _learners.dispose();
    super.dispose();
  }

  Future<void> _record(List<Student> learners) async {
    final section = _section!;
    final student = await pickOne<Student>(context, title: 'Learner', options: learners, label: studentLabel);
    if (student == null || !mounted) return;
    final f = await askFields(
      context,
      title: 'GST score: ${studentLabel(student)}',
      note: 'Out of 20 (Grades 4–6) or 40 (Grades 7–10). The breakdown is optional.',
      fields: const [
        FieldSpec('total', 'Total score', number: true),
        FieldSpec('l', 'Literal correct', number: true, optional: true),
        FieldSpec('i', 'Inferential correct', number: true, optional: true),
        FieldSpec('c', 'Critical correct', number: true, optional: true),
      ],
    );
    if (f == null || !mounted) return;
    final total = int.tryParse(f['total']!);
    if (total == null) return showNote(context, 'The total must be a whole number.');
    final vm = vmsOf(context).philIri;
    await runAction(
      context,
      () => vm.recordGst(
        studentId: student.id!,
        sectionId: section.id!,
        schoolYear: section.schoolYear,
        totalScore: total,
        literalCorrect: int.tryParse(f['l'] ?? ''),
        inferentialCorrect: int.tryParse(f['i'] ?? ''),
        criticalCorrect: int.tryParse(f['c'] ?? ''),
      ),
      done: 'GST score saved.',
      where: 'GstScreen',
    );
    setState(() => _reload++);
  }

  void _pickSection(Section? s) {
    _learners.value = null;
    setState(() => _section = s);
  }

  /// "Record a score", once the section's learners are loaded.
  Widget _mainAction({required bool fab}) => ValueListenableBuilder<List<Student>?>(
    valueListenable: _learners,
    builder: (context, learners, _) {
      if (_section == null || learners == null || learners.isEmpty) return const SizedBox.shrink();
      void go() => _record(learners);
      return fab
          ? mainActionFab(onPressed: go, icon: Icons.add, label: 'Record a score')
          : mainActionButton(onPressed: go, icon: Icons.add, label: 'Record a score');
    },
  );

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Group Screening Test'), actions: [if (wide) _mainAction(fab: false)]),
      floatingActionButton: wide ? null : _mainAction(fab: true),
      body: PageBody(
        children: [
          FilterBar(children: [
            SectionPicker(value: _section, onChanged: _pickSection, where: philIriGrade),
          ]),
          if (_section == null)
            const EmptyNote('Pick a Grade 4–10 section to see its GST scores.', icon: Icons.class_outlined),
          if (_section != null)
            LoadView<(List<PhilIriGstResult>, List<Student>, Map<int, bool>)>(
              where: 'GstScreen',
              reloadKey: '${_section!.id}-$_reload',
              load: (vms) async {
                final s = _section!;
                final results = await vms.philIri.gstForSection(s.id!, schoolYear: s.schoolYear);
                final passed = {for (final g in results) g.id ?? 0: await vms.philIri.gstPassed(g)};
                return (results, await vms.student.localStudents(s.id!), passed);
              },
              builder: (context, data, _) {
                final (results, learners, passed) = data;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _learners.value = learners;
                });
                final names = {for (final s in learners) s.id: studentLabel(s)};
                final passCount = results.where((g) => passed[g.id ?? 0] == true).length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatGrid(tileWidth: 160, tiles: [
                      StatTile(label: 'Learners', value: '${learners.length}', icon: Icons.people_alt_outlined),
                      StatTile(label: 'Scores recorded', value: '${results.length}', icon: Icons.fact_check_outlined),
                      StatTile(label: 'Passed', value: '$passCount', icon: Icons.verified_outlined),
                      StatTile(label: 'Below', value: '${results.length - passCount}', icon: Icons.trending_down),
                    ]),
                    const SizedBox(height: 16),
                    if (results.isEmpty)
                      const EmptyNote('No GST scores in this section yet.', icon: Icons.quiz_outlined),
                    if (results.isNotEmpty)
                      ListCard(
                        title: 'Scores',
                        children: [
                          for (final g in results)
                            Builder(builder: (context) {
                              final name = names[g.studentId] ?? 'Learner #${g.studentId}';
                              final ok = passed[g.id ?? 0] == true;
                              return ListRow(
                                leading: LetterBadge(initialOf(name)),
                                title: name,
                                subtitle: [
                                  '${g.totalScore}/${g.maxScore} (${g.wholePercent}%) on ${g.takenAt}',
                                  if (g.literalCorrect != null) 'L ${g.literalCorrect} · I ${g.inferentialCorrect ?? '-'} · C ${g.criticalCorrect ?? '-'}',
                                ].join('\n'),
                                trailing: [
                                  StatusChip(
                                    ok ? 'Passed' : 'Below',
                                    tone: ok ? StatusTone.good : StatusTone.bad,
                                    icon: ok ? Icons.check : Icons.arrow_downward,
                                  ),
                                ],
                              );
                            }),
                        ],
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
