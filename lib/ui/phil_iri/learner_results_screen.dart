// lib/ui/phil_iri/learner_results_screen.dart
// Learner results (docs/handoff/screens/phil-iri.md): one learner's Phil-IRI
// results for the section's school year, round by round, with the GST and
// the end result.
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_types.dart';
import '../../core/models/section.dart';
import '../../core/models/student.dart';
import '../../viewmodels/phil_iri_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';

class LearnerResultsScreen extends StatelessWidget {
  final Student student;
  final Section section;
  const LearnerResultsScreen({super.key, required this.student, required this.section});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(studentLabel(student))),
      body: LoadView<PhilIriLearnerResults>(
        where: 'LearnerResults',
        load: (vms) => vms.philIri.learnerResults(studentId: student.id!, sectionId: section.id!, schoolYear: section.schoolYear),
        builder: (context, r, _) => PageBody(
          children: [
            SectionCard(
              title: 'Grade ${r.learnerGrade} · ${r.schoolYear}',
              children: [
                InfoRow('GST', r.gst == null ? 'not taken' : '${r.gst!.totalScore}/${r.gst!.maxScore} (${r.gst!.wholePercent}%)'),
                if (r.end != null) InfoRow('End result', roundResultText(r.end!)),
              ],
            ),
            for (final x in r.rounds) SectionCard(title: x.round.label, children: roundResultRows(x)),
          ],
        ),
      ),
    );
  }
}

/// Pick a section and a learner, then open their results.
class LearnerResultsPickScreen extends StatefulWidget {
  const LearnerResultsPickScreen({super.key});

  @override
  State<LearnerResultsPickScreen> createState() => _LearnerResultsPickScreenState();
}

class _LearnerResultsPickScreenState extends State<LearnerResultsPickScreen> {
  Section? _section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Learner results')),
      body: PageBody(
        children: [
          SectionPicker(
            value: _section,
            onChanged: (s) => setState(() => _section = s),
            where: (s) => (int.tryParse(s.gradeLevel) ?? 0) >= 4,
          ),
          if (_section != null)
            LoadView<List<Student>>(
              where: 'LearnerResults',
              reloadKey: _section!.id,
              load: (vms) => vms.student.localStudents(_section!.id!),
              builder: (context, learners, _) => Column(children: [
                if (learners.isEmpty) const EmptyNote('No learners in this section on this device.'),
                for (final s in learners)
                  Card(
                    child: ListTile(
                      title: Text(studentLabel(s)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => LearnerResultsScreen(student: s, section: _section!)),
                      ),
                    ),
                  ),
              ]),
            ),
        ],
      ),
    );
  }
}

/// One line for a round's result.
String roundResultText(PhilIriRoundResult x) => x.notAssessed
    ? 'not assessed'
    : [x.profile?.label ?? 'no profile', ?x.adjustedLevelLabel, if (x.isStrugglingReader) 'struggling reader'].join(' · ');

List<Widget> roundResultRows(PhilIriRoundResult x) {
  if (x.notAssessed) return const [Text('Not assessed.')];
  return [
    InfoRow('Profile', x.profile?.label ?? '—'),
    InfoRow('Word reading', x.wordReadingPercent == null ? '—' : '${x.wordReadingPercent}% (${x.wordReadingLevel?.label ?? '—'})'),
    InfoRow('Speed', x.wordsPerMinute == null ? '—' : '${x.wordsPerMinute!.toStringAsFixed(0)} wpm (${x.speed?.label ?? '—'})'),
    InfoRow('Comprehension', x.comprehensionPercent == null ? 'blank' : '${x.comprehensionPercent}% (${x.comprehensionLevel?.label ?? '—'})'),
    if (x.adjustedLevelLabel != null) InfoRow('Level', '${x.adjustedLevelLabel} (${x.levelsDownLabel ?? ''})'),
    if (x.actualAdjustedLevelLabel != null) InfoRow('This round alone', '${x.actualAdjustedLevelLabel} (${x.actualLevelsDownLabel ?? ''})'),
    if (x.isStrugglingReader) const InfoRow('Note', 'Struggling reader'),
    if (!x.given) const InfoRow('Note', 'Carried from an earlier round'),
  ];
}
