// lib/ui/crla/crla_section_screen.dart
// Section CRLA list and Start a CRLA attempt (docs/handoff/screens/crla.md):
// a section's attempts for its school year, per learner with the reading
// profile, and a new attempt (variant, language, round). An attempt opens
// the Part 1 / Part 2 entry.
import 'package:flutter/material.dart';

import '../../core/models/crla_assessment.dart';
import '../../core/models/crla_result.dart';
import '../../core/models/crla_variant.dart';
import '../../core/models/section.dart';
import '../../core/models/student.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import 'crla_entry_screen.dart';

/// "Mother tongue", "Filipino", "English".
String crlaVariantLabel(String v) => switch (v) {
  'mt' => 'Mother tongue',
  'fil' => 'Filipino',
  'eng' => 'English',
  _ => v,
};

class CrlaSectionScreen extends StatefulWidget {
  const CrlaSectionScreen({super.key});

  @override
  State<CrlaSectionScreen> createState() => _CrlaSectionScreenState();
}

class _CrlaSectionScreenState extends State<CrlaSectionScreen> {
  Section? _section;
  int _reload = 0;

  Future<void> _open(int assessmentId) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CrlaEntryScreen(assessmentId: assessmentId)));
    if (mounted) setState(() => _reload++);
  }

  Future<void> _start(List<Student> learners) async {
    final section = _section!;
    final r = await showDialog<_Start>(context: context, builder: (_) => _StartDialog(learners: learners));
    if (r == null || !mounted) return;
    final crla = vmsOf(context).crla;
    final me = vmsOf(context).auth.currentUser;
    final a = await runAction(
      context,
      () => crla.startAssessment(
        studentId: r.student.id!,
        sectionId: section.id!,
        schoolYear: section.schoolYear,
        subjectVariant: r.variant,
        language: r.language,
        round: r.round,
        administeredBy: me?.fullName,
      ),
      where: 'CrlaSection',
    );
    if (a?.id != null && mounted) await _open(a!.id!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CRLA by section')),
      body: PageBody(
        children: [
          SectionPicker(
            value: _section,
            onChanged: (s) => setState(() => _section = s),
            where: (s) => const {'1', '2', '3'}.contains(s.gradeLevel),
          ),
          if (_section != null)
            LoadView<(List<CrlaAssessment>, List<CrlaResult>, List<Student>)>(
              where: 'CrlaSection',
              reloadKey: '${_section!.id}-$_reload',
              load: (vms) async {
                final s = _section!;
                await vms.crla.loadForSection(s.id!, schoolYear: s.schoolYear);
                final assessments = List.of(vms.crla.assessments);
                await vms.crla.loadResultsForSection(s.id!, schoolYear: s.schoolYear);
                return (assessments, List.of(vms.crla.results), await vms.student.localStudents(s.id!));
              },
              builder: (context, data, _) {
                final (assessments, results, learners) = data;
                final byId = {for (final r in results) r.assessmentId: r};
                final names = {for (final s in learners) s.id: studentLabel(s)};
                final byStudent = <int, List<CrlaAssessment>>{};
                for (final a in assessments) {
                  byStudent.putIfAbsent(a.studentId, () => []).add(a);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: learners.isEmpty ? null : () => _start(learners),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start an attempt'),
                    ),
                    const SizedBox(height: 12),
                    if (assessments.isEmpty) const EmptyNote('No CRLA attempts in this section yet.'),
                    for (final e in byStudent.entries)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ListTile(title: Text(names[e.key] ?? 'Learner #${e.key}')),
                              for (final a in e.value)
                                ListTile(
                                  dense: true,
                                  title: Text('${a.round.label} · ${crlaVariantLabel(a.subjectVariant)} (${a.language}) · attempt ${a.attemptNo ?? '-'}'),
                                  subtitle: Text(byId[a.id]?.readingProfile ?? a.readingProfile ?? 'No profile yet'),
                                  trailing: const Icon(Icons.edit_note),
                                  onTap: () => _open(a.id!),
                                ),
                            ],
                          ),
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

class _Start {
  final Student student;
  final String variant;
  final String? language;
  final CrlaRound round;
  const _Start(this.student, this.variant, this.language, this.round);
}

class _StartDialog extends StatefulWidget {
  final List<Student> learners;
  const _StartDialog({required this.learners});

  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  Student? _student;
  String _variant = 'mt';
  CrlaRound _round = CrlaRound.values.first;
  final _language = TextEditingController();

  @override
  void dispose() {
    _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultLanguage = crlaDefaultLanguage(_variant);
    return AlertDialog(
      title: const Text('Start a CRLA attempt'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BasaDropdown<Student>(
                label: 'Learner',
                items: widget.learners,
                value: _student,
                itemLabel: studentLabel,
                onChanged: (s) => setState(() => _student = s),
              ),
              const SizedBox(height: 12),
              BasaDropdown<String>(
                label: 'Test',
                items: crlaSubjectVariants,
                value: _variant,
                itemLabel: crlaVariantLabel,
                onChanged: (v) => setState(() => _variant = v ?? _variant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _language,
                decoration: InputDecoration(
                  labelText: 'Language',
                  hintText: defaultLanguage ?? 'e.g. Cebuano',
                  helperText: defaultLanguage == null ? 'Needed for the mother tongue test.' : 'Empty = $defaultLanguage',
                ),
              ),
              const SizedBox(height: 12),
              CrlaRoundPicker(value: _round, onChanged: (r) => setState(() => _round = r ?? _round)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _student == null
              ? null
              : () => Navigator.of(context).pop(_Start(
                    _student!,
                    _variant,
                    _language.text.trim().isEmpty ? null : _language.text.trim(),
                    _round,
                  )),
          child: const Text('Start'),
        ),
      ],
    );
  }
}
