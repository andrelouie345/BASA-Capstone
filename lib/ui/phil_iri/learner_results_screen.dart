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
import 'session_screen.dart';

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
        builder: (context, r, _) {
          final rounds = [
            for (final x in r.rounds)
              SectionCard(title: x.round.label, icon: Icons.event_note_outlined, trailing: roundResultChip(x), children: roundResultRows(x)),
          ];
          return PageBody(
            maxWidth: 1200,
            children: [
              SectionCard(
                title: 'Grade ${r.learnerGrade} · ${r.schoolYear}',
                icon: Icons.person_outline,
                children: [
                  StatGrid(tileWidth: 200, tiles: [
                    StatTile(
                      label: 'GST',
                      value: r.gst == null ? 'not taken' : '${r.gst!.totalScore}/${r.gst!.maxScore} (${r.gst!.wholePercent}%)',
                      icon: Icons.quiz_outlined,
                    ),
                    StatTile(label: 'Rounds assessed', value: '${r.rounds.where((x) => !x.notAssessed).length}/${r.rounds.length}', icon: Icons.event_available_outlined),
                    if (r.end != null) StatTile(label: 'End result', value: r.end!.profile?.label ?? '—', icon: Icons.flag_outlined),
                  ]),
                  if (r.end != null) ...[const SizedBox(height: 12), InfoRow('End result', roundResultText(r.end!))],
                ],
              ),
              if (rounds.isEmpty) const EmptyNote('No Phil-IRI rounds for this learner yet.', icon: Icons.menu_book_outlined),
              LayoutBuilder(builder: (context, c) {
                // Wide: the round cards in two columns.
                final columns = c.maxWidth >= 1000 ? 2 : 1;
                const gap = 12.0;
                final w = (c.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(spacing: gap, runSpacing: gap, children: [for (final card in rounds) SizedBox(width: w, child: card)]);
              }),
            ],
          );
        },
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
          FilterBar(children: [
            SectionPicker(
              value: _section,
              onChanged: (s) => setState(() => _section = s),
              where: (s) => (int.tryParse(s.gradeLevel) ?? 0) >= 4,
            ),
          ]),
          if (_section == null)
            const EmptyNote('Pick a Grade 4–10 section, then a learner to see their results.', icon: Icons.class_outlined),
          if (_section != null)
            LoadView<List<Student>>(
              where: 'LearnerResults',
              reloadKey: _section!.id,
              load: (vms) => vms.student.localStudents(_section!.id!),
              builder: (context, learners, _) => learners.isEmpty
                  ? const EmptyNote('No learners in this section on this device.', icon: Icons.person_search_outlined)
                  : ListCard(
                      title: 'Learners',
                      trailing: StatusChip('${learners.length}'),
                      children: [
                        for (final s in learners)
                          ListRow(
                            leading: LetterBadge(initialOf(studentLabel(s))),
                            title: studentLabel(s),
                            trailing: const [Icon(Icons.chevron_right)],
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => LearnerResultsScreen(student: s, section: _section!)),
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

/// One line for a round's result.
String roundResultText(PhilIriRoundResult x) => x.notAssessed
    ? 'not assessed'
    : [x.profile?.label ?? 'no profile', ?x.adjustedLevelLabel].join(' · ');

/// A round's profile as a chip ("not assessed" when it wasn't).
StatusChip roundResultChip(PhilIriRoundResult x) => x.notAssessed
    ? const StatusChip('not assessed', icon: Icons.remove_circle_outline)
    : StatusChip(x.profile?.label ?? 'no profile', tone: philIriLevelTone(x.profile));

List<Widget> roundResultRows(PhilIriRoundResult x) {
  if (x.notAssessed) return const [EmptyNote('Not assessed.', icon: Icons.event_busy_outlined)];
  return [
    InfoRow('Profile', x.profile?.label ?? '—'),
    InfoRow('Word reading', x.wordReadingPercent == null ? '—' : '${x.wordReadingPercent}% (${x.wordReadingLevel?.label ?? '—'})'),
    InfoRow('Speed', x.wordsPerMinute == null ? '—' : '${x.wordsPerMinute!.toStringAsFixed(0)} wpm (${x.speed?.label ?? '—'})'),
    InfoRow('Comprehension', x.comprehensionPercent == null ? 'blank' : '${x.comprehensionPercent}% (${x.comprehensionLevel?.label ?? '—'})'),
    if (x.adjustedLevelLabel != null) InfoRow('Level', '${x.adjustedLevelLabel} (${x.levelsDownLabel ?? ''})'),
    if (x.actualAdjustedLevelLabel != null) InfoRow('This round alone', '${x.actualAdjustedLevelLabel} (${x.actualLevelsDownLabel ?? ''})'),
    if (!x.given) const InfoRow('Note', 'Carried from an earlier round'),
  ];
}
