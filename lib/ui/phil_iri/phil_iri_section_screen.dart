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

class PhilIriSectionScreen extends StatefulWidget {
  const PhilIriSectionScreen({super.key});

  @override
  State<PhilIriSectionScreen> createState() => _PhilIriSectionScreenState();
}

class _PhilIriSectionScreenState extends State<PhilIriSectionScreen> {
  Section? _section;
  PhilIriRound _round = PhilIriRound.values.first;
  int _reload = 0;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phil-IRI by section')),
      body: PageBody(
        children: [
          SectionPicker(value: _section, onChanged: (s) => setState(() => _section = s), where: philIriGrade),
          PhilIriRoundPicker(value: _round, onChanged: (r) => setState(() => _round = r ?? _round)),
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
                final byStudent = <int, List<PhilIriAssessment>>{};
                for (final a in sessions) {
                  byStudent.putIfAbsent(a.studentId, () => []).add(a);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: learners.isEmpty ? null : () => _start(learners),
                      icon: const Icon(Icons.play_arrow),
                      label: Text('Start a ${_round.label} session'),
                    ),
                    const SizedBox(height: 12),
                    for (final s in learners)
                      Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              title: Text(studentLabel(s)),
                              trailing: TextButton(
                                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => LearnerResultsScreen(student: s, section: _section!),
                                )),
                                child: const Text('Results'),
                              ),
                            ),
                            for (final a in byStudent[s.id] ?? const <PhilIriAssessment>[])
                              ListTile(
                                dense: true,
                                title: Text('Session ${a.attemptNo ?? ''} · ${a.assessedAt}'),
                                subtitle: Text(philIriStatusLabel(a.status)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _open(a.id!),
                              ),
                          ],
                        ),
                      ),
                    if (learners.isEmpty) const EmptyNote('No learners in this section on this device.'),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
