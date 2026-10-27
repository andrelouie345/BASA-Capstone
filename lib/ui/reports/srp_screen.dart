// lib/ui/reports/srp_screen.dart
// SRP, the Summer Remediation Program (docs/handoff/screens/reports.md): a
// school year's SRP classes with tutor, room, schedule and learners (an SRP
// tutor sees their own). Ranking candidates and building or changing
// classes are admin-only: the admin build passes an [SrpEditor] (lib/ui/admin/).
import 'package:flutter/material.dart';

import '../../viewmodels/srp_viewmodel.dart';
import '../common/csv_table.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../common/school_year_scope.dart';

/// The admin build's SRP work. Each returns true when something changed.
abstract class SrpEditor {
  const SrpEditor();
  bool canEdit(BuildContext context);

  /// Ranked candidates, build classes, clear classes.
  Future<bool> schoolActions(BuildContext context, int schoolId, String year);
  Future<bool> classActions(BuildContext context, SrpClassView c, List<SrpClassView> all);
}

class SrpScreen extends StatefulWidget {
  final SrpEditor? editor;
  const SrpScreen({super.key, this.editor});

  @override
  State<SrpScreen> createState() => _SrpScreenState();
}

class _SrpScreenState extends State<SrpScreen> {
  int _reload = 0;

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final canEdit = editor != null && editor.canEdit(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Summer Remediation')),
      body: PageBody(
        maxWidth: 1100,
        children: [
          SchoolYearScope(
            builder: (context, schoolId, year) => LoadView<List<SrpClassView>>(
              where: 'Srp',
              reloadKey: '$schoolId-$year-$_reload',
              load: (vms) => vms.srp.classes(schoolId: schoolId, schoolYear: year),
              builder: (context, classes, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (canEdit)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _after(editor.schoolActions(context, schoolId, year)),
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('Candidates and classes'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (classes.isEmpty) const EmptyNote('No SRP classes this school year.'),
                  for (final c in classes)
                    Card(
                      child: ExpansionTile(
                        title: Text(c.srpClass.className),
                        subtitle: Text([
                          'Grade ${c.srpClass.assessedGrade}',
                          '${c.learners.length} learner(s)',
                          if (c.tutor != null) c.tutor!.fullName.isEmpty ? c.tutor!.email : c.tutor!.fullName,
                          ?c.srpClass.room,
                          ?c.srpClass.schedule,
                        ].join(' · ')),
                        trailing: canEdit
                            ? IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _after(editor.classActions(context, c, classes)))
                            : null,
                        children: [
                          for (final l in c.learners)
                            ListTile(
                              dense: true,
                              title: Text(l.student == null ? 'Learner #${l.member.studentId}' : studentLabel(l.student!)),
                              subtitle: l.section == null ? null : Text('${l.section}'),
                            ),
                        ],
                      ),
                    ),
                  if (classes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    CsvTableView(csv: srpClassesCsv(classes), fileName: 'SRP_classes_$year.csv', title: 'All classes'),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
