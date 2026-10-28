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

/// How a CRLA reading profile reads at a glance: Low Emerging = bad,
/// High Emerging / Developing = warn, at grade level = good, else neutral.
StatusTone crlaProfileTone(String? profile) {
  final p = (profile ?? '').toLowerCase();
  if (p.contains('low emerging')) return StatusTone.bad;
  if (p.contains('high emerging') || p.contains('developing')) return StatusTone.warn;
  if (p.contains('grade level')) return StatusTone.good;
  return StatusTone.neutral;
}

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
          FilterBar(children: [
            SectionPicker(
              value: _section,
              onChanged: (s) => setState(() => _section = s),
              where: (s) => const {'1', '2', '3'}.contains(s.gradeLevel),
            ),
          ]),
          if (_section == null)
            const EmptyNote('Pick a Grade 1–3 section to see its CRLA attempts.', icon: Icons.class_outlined),
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
                String? profileOf(CrlaAssessment a) => byId[a.id]?.readingProfile ?? a.readingProfile;
                final profiled = byStudent.values.where((l) => l.any((a) => profileOf(a) != null)).length;
                final theme = Theme.of(context);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatGrid(tileWidth: 160, tiles: [
                      StatTile(label: 'Learners', value: '${learners.length}', icon: Icons.people_alt_outlined),
                      StatTile(label: 'Attempts', value: '${assessments.length}', icon: Icons.fact_check_outlined),
                      StatTile(label: 'Learners assessed', value: '${byStudent.length}', icon: Icons.how_to_reg_outlined),
                      StatTile(label: 'With a profile', value: '$profiled', icon: Icons.auto_graph),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: Text('Attempts', style: theme.textTheme.titleMedium)),
                      FilledButton.icon(
                        onPressed: learners.isEmpty ? null : () => _start(learners),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start an attempt'),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (assessments.isEmpty)
                      const EmptyNote('No CRLA attempts in this section yet.', icon: Icons.record_voice_over_outlined),
                    for (final e in byStudent.entries) ...[
                      ListCard(
                        children: [
                          ListRow(
                            leading: LetterBadge(initialOf(names[e.key] ?? '?')),
                            title: names[e.key] ?? 'Learner #${e.key}',
                            trailing: [StatusChip('${e.value.length} attempt(s)')],
                          ),
                          for (final a in e.value)
                            ListRow(
                              leading: const IconBadge(Icons.edit_note, size: 36),
                              title:
                                  '${a.round.label} · ${crlaVariantLabel(a.subjectVariant)} (${a.language}) · attempt ${a.attemptNo ?? '-'}',
                              footer: StatusChip(profileOf(a) ?? 'No profile yet', tone: crlaProfileTone(profileOf(a))),
                              trailing: const [Icon(Icons.chevron_right)],
                              onTap: () => _open(a.id!),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
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
