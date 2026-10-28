// lib/ui/learners/learners_screen.dart
// Learners and roster CSV (docs/handoff/screens/admin.md): a section's
// learners from this device, a learner's details, and the section's roster
// saved as a CSV file.
import 'package:flutter/material.dart';

import '../../core/models/section.dart';
import '../../core/models/student.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';

class LearnersScreen extends StatefulWidget {
  /// Opens a learner's page in the admin build (Learner history); null in the tutor build.
  final void Function(BuildContext context, Student student)? onOpenLearner;
  const LearnersScreen({super.key, this.onOpenLearner});

  @override
  State<LearnersScreen> createState() => _LearnersScreenState();
}

class _LearnersScreenState extends State<LearnersScreen> {
  Section? _section;
  String _filter = '';

  Future<void> _exportCsv() async {
    final section = _section;
    if (section == null) return;
    final students = vmsOf(context).student;
    final path = await runAction(context, () async {
      final csv = await students.rosterCsv(section.id!);
      return saveTextExport('roster_${section.gradeLevel}_${section.sectionName}_${section.schoolYear}.csv', csv);
    }, where: 'LearnersScreen');
    if (path != null && mounted) await showSaved(context, path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Learners'),
        actions: [
          if (_section != null)
            IconButton(tooltip: 'Save roster as CSV', onPressed: _exportCsv, icon: const Icon(Icons.download)),
        ],
      ),
      body: PageBody(
        children: [
          FilterBar(children: [
            SectionPicker(value: _section, onChanged: (s) => setState(() => _section = s)),
            if (_section != null)
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search name or LRN'),
                onChanged: (v) => setState(() => _filter = v.toLowerCase()),
              ),
          ]),
          if (_section == null) const EmptyNote('Pick a section to see its learners.', icon: Icons.class_outlined),
          if (_section != null)
            LoadView<List<Student>>(
              where: 'LearnersScreen',
              reloadKey: _section!.id,
              load: (vms) => vms.student.localStudents(_section!.id!),
              builder: (context, items, _) {
                final shown = items
                    .where((s) => _filter.isEmpty || studentLabel(s).toLowerCase().contains(_filter) || s.lrn.contains(_filter))
                    .toList();
                if (items.isEmpty) return const EmptyNote('No learners in this section on this device.');
                int sex(String letter) => items.where((s) => (s.sex ?? '').toUpperCase().startsWith(letter)).length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatGrid(tileWidth: 160, tiles: [
                      StatTile(label: 'Learners', value: '${items.length}', icon: Icons.people_alt_outlined),
                      StatTile(label: 'Female', value: '${sex('F')}', icon: Icons.face_3_outlined),
                      StatTile(label: 'Male', value: '${sex('M')}', icon: Icons.face_outlined),
                      StatTile(label: 'Shown', value: '${shown.length}', icon: Icons.filter_list),
                    ]),
                    const SizedBox(height: 16),
                    if (shown.isEmpty)
                      const EmptyNote('No learners match.', icon: Icons.search_off)
                    else
                      ListCard(
                        title: '${shown.length} of ${items.length} learner(s)',
                        children: [
                          for (final s in shown)
                            ListRow(
                              leading: LetterBadge(initialOf(s.lastName.isNotEmpty ? s.lastName : s.firstName)),
                              title: [s.lastName, s.firstName].where((p) => p.isNotEmpty).join(', '),
                              subtitle: 'LRN ${s.lrn}',
                              trailing: [
                                if (s.sex != null && s.sex!.isNotEmpty) StatusChip(s.sex![0].toUpperCase()),
                                const Icon(Icons.chevron_right),
                              ],
                              onTap: () =>
                                  widget.onOpenLearner != null ? widget.onOpenLearner!(context, s) : _details(context, s),
                            ),
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

void _details(BuildContext context, Student s) => showTextDialog(
  context,
  title: studentLabel(s),
  text: [
    'LRN: ${s.lrn}',
    if (s.sex != null) 'Sex: ${s.sex}',
    if (s.birthDate != null) 'Birth date: ${s.birthDate}',
    if (s.motherTongue != null) 'Mother tongue: ${s.motherTongue}',
    if (s.learningModality != null) 'Learning modality: ${s.learningModality}',
    if (s.guardianName != null) 'Guardian: ${s.guardianName}${s.guardianRelationship == null ? '' : ' (${s.guardianRelationship})'}',
    if (s.contactNumber != null) 'Contact: ${s.contactNumber}',
    if ([s.barangay, s.municipality, s.province].any((x) => x != null))
      'Address: ${[s.addressStreet, s.barangay, s.municipality, s.province].whereType<String>().join(', ')}',
    if (s.remarks != null) 'Remarks: ${s.remarks}',
  ].join('\n'),
);
