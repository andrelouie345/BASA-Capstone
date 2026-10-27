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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group Screening Test')),
      body: PageBody(
        children: [
          SectionPicker(value: _section, onChanged: (s) => setState(() => _section = s), where: philIriGrade),
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
                final names = {for (final s in learners) s.id: studentLabel(s)};
                final colors = Theme.of(context).colorScheme;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: learners.isEmpty ? null : () => _record(learners),
                      icon: const Icon(Icons.add),
                      label: const Text('Record a score'),
                    ),
                    const SizedBox(height: 12),
                    if (results.isEmpty) const EmptyNote('No GST scores in this section yet.'),
                    for (final g in results)
                      Card(
                        child: ListTile(
                          title: Text(names[g.studentId] ?? 'Learner #${g.studentId}'),
                          subtitle: Text([
                            '${g.totalScore}/${g.maxScore} (${g.wholePercent}%) on ${g.takenAt}',
                            if (g.literalCorrect != null) 'L ${g.literalCorrect} · I ${g.inferentialCorrect ?? '-'} · C ${g.criticalCorrect ?? '-'}',
                          ].join('\n')),
                          trailing: Text(passed[g.id ?? 0] == true ? 'Passed' : 'Below',
                              style: TextStyle(color: passed[g.id ?? 0] == true ? colors.tertiary : colors.error)),
                        ),
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
