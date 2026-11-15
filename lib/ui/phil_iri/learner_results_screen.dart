// lib/ui/phil_iri/learner_results_screen.dart
// Learner results (docs/handoff/screens/phil-iri.md): one learner's Phil-IRI
// results for the section's school year, round by round, with the GST and
// the end result.
import 'package:flutter/material.dart';

import '../../core/models/phil_iri_types.dart';
import '../../core/models/report_setting.dart' show PhilIriValues, philIriValuesLabel;
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
          // One kind of value, as the school's learner-pages switch says; a
          // tutor is never told which (showValues).
          final show = r.showValues;
          final rounds = [
            for (final x in r.rounds)
              () {
                final v = r.view(x.round);
                return SectionCard(
                  title: x.round.label,
                  icon: Icons.event_note_outlined,
                  trailing: roundViewChip(v, showValues: show),
                  children: roundViewRows(v, showValues: show),
                );
              }(),
          ];
          final end = r.endView();
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
                    if (end != null) StatTile(label: 'End result', value: end.profile?.label ?? '—', icon: Icons.flag_outlined),
                  ]),
                  if (end != null) ...[const SizedBox(height: 12), InfoRow('End result', roundViewText(end, showValues: show))],
                  if (show) ...[const SizedBox(height: 12), ValuesNote(philIriValuesLabel(r.values))],
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
  String _filter = '';

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
            if (_section != null)
              SearchField(label: 'Search name or LRN', onChanged: (v) => setState(() => _filter = v)),
          ]),
          if (_section == null)
            const EmptyNote('Pick a Grade 4–10 section, then a learner to see their results.', icon: Icons.class_outlined),
          if (_section != null)
            LoadView<List<Student>>(
              where: 'LearnerResults',
              reloadKey: _section!.id,
              load: (vms) => vms.student.localStudents(_section!.id!),
              builder: (context, learners, _) {
                final shown = learners.where((s) => matchesSearch(_filter, [studentLabel(s)])).toList();
                if (learners.isEmpty) {
                  return const EmptyNote('No learners in this section on this device.', icon: Icons.person_search_outlined);
                }
                if (shown.isEmpty) return const EmptyNote('No learners match.', icon: Icons.search_off);
                return ListCard(
                  title: 'Learners',
                  trailing: StatusChip('${shown.length} of ${learners.length}'),
                  children: [
                    for (final s in shown)
                      ListRow(
                        leading: LetterBadge(initialOf(studentLabel(s))),
                        title: studentLabel(s),
                        trailing: const [Icon(Icons.chevron_right)],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => LearnerResultsScreen(student: s, section: _section!)),
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

// [showValues] false = a tutor (PhilIriLearnerResults.showValues, owner/ma
// 2026-11-15): never say which values the page shows. A round without a
// reading is "No reading this round" under both values, and no carried note.
const _noReading = 'No reading this round';

bool _noReadingFor(PhilIriRoundView v) => v.notAssessedThisRound || v.notAssessed;

/// One line for a round as the learner pages show it (carried or actual,
/// [PhilIriLearnerResults.values]); also used by the learner history.
String roundViewText(PhilIriRoundView v, {bool showValues = true}) {
  if (!showValues && _noReadingFor(v)) return _noReading;
  if (v.notAssessedThisRound) return 'not assessed this round · ${v.adjustedLevelLabel} (${v.levelsDownLabel})';
  if (v.notAssessed) return 'not assessed';
  return [v.profile?.label ?? 'no profile', ?v.adjustedLevelLabel].join(' · ');
}

/// A round's profile as a chip ("not assessed" when it wasn't).
StatusChip roundViewChip(PhilIriRoundView v, {bool showValues = true}) => !showValues && _noReadingFor(v)
    ? const StatusChip(_noReading, icon: Icons.remove_circle_outline)
    : v.notAssessedThisRound
        ? const StatusChip('not assessed this round', icon: Icons.remove_circle_outline, tone: StatusTone.warn)
        : v.notAssessed
            ? const StatusChip('not assessed', icon: Icons.remove_circle_outline)
            : StatusChip(v.profile?.label ?? 'no profile', tone: philIriLevelTone(v.profile));

List<Widget> roundViewRows(PhilIriRoundView v, {bool showValues = true}) {
  if (!showValues && _noReadingFor(v)) return const [EmptyNote('$_noReading.', icon: Icons.event_busy_outlined)];
  if (v.notAssessedThisRound) {
    return [
      const EmptyNote('No reading of their own this round: counted as Struggling.', icon: Icons.event_busy_outlined),
      if (v.adjustedLevelLabel != null) InfoRow('Level', '${v.adjustedLevelLabel} (${v.levelsDownLabel ?? ''})'),
    ];
  }
  if (v.notAssessed) return const [EmptyNote('Not assessed.', icon: Icons.event_busy_outlined)];
  final wordReading = v.wordReadingAssumed
      ? 'not assessed (${v.wordReadingLevel?.label ?? 'Struggling'})'
      : v.wordReadingPercent == null
          ? '—'
          : '${v.wordReadingPercent}%${v.silentOnly ? ' (silent, not measured)' : ''} (${v.wordReadingLevel?.label ?? '—'})';
  return [
    InfoRow('Profile', v.profile?.label ?? '—'),
    InfoRow('Word reading', wordReading),
    InfoRow('Speed', v.wordsPerMinute == null ? '—' : '${v.wordsPerMinute!.toStringAsFixed(0)} wpm (${v.speed?.label ?? '—'})'),
    InfoRow('Comprehension', v.comprehensionPercent == null ? 'blank' : '${v.comprehensionPercent}% (${v.comprehensionLevel?.label ?? '—'})'),
    if (v.adjustedLevelLabel != null) InfoRow('Level', '${v.adjustedLevelLabel} (${v.levelsDownLabel ?? ''})'),
    // Monitoring status shows under carried only (as the console prints it), never to a tutor.
    if (showValues && v.values == PhilIriValues.carried && v.status == PhilIriRoundStatus.carriedOver)
      const InfoRow('Note', 'Carried from an earlier round'),
  ];
}
