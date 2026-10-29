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
              builder: (context, classes, _) {
                final theme = Theme.of(context);
                final colors = theme.colorScheme;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The main action, top right of the page: it needs the
                    // school and year picked above.
                    if (canEdit) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () => _after(editor.schoolActions(context, schoolId, year)),
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('Candidates and classes'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (classes.isEmpty)
                      const EmptyNote('No SRP classes this school year.', icon: Icons.wb_sunny_outlined)
                    else ...[
                      StatGrid(tiles: [
                        StatTile(label: 'Classes', value: '${classes.length}', icon: Icons.class_outlined),
                        StatTile(
                            label: 'Learners',
                            value: '${classes.fold<int>(0, (n, c) => n + c.learners.length)}',
                            icon: Icons.groups_outlined),
                        StatTile(
                            label: 'Classes without a tutor',
                            value: '${classes.where((c) => c.tutor == null).length}',
                            icon: Icons.person_off_outlined),
                      ]),
                      const SizedBox(height: 16),
                    ],
                    for (final c in classes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            leading: LetterBadge(c.srpClass.className),
                            title: Text(c.srpClass.className, style: theme.textTheme.titleSmall),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  [
                                    'Grade ${c.srpClass.assessedGrade}',
                                    '${c.learners.length} learner(s)',
                                    if (c.tutor != null) c.tutor!.fullName.isEmpty ? c.tutor!.email : c.tutor!.fullName,
                                    ?c.srpClass.room,
                                    ?c.srpClass.schedule,
                                  ].join(' · '),
                                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                                ),
                                if (c.tutor == null) ...[
                                  const SizedBox(height: 6),
                                  const StatusChip('NO TUTOR', tone: StatusTone.warn, icon: Icons.person_off_outlined),
                                ],
                              ],
                            ),
                            trailing: canEdit
                                ? IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _after(editor.classActions(context, c, classes)))
                                : null,
                            children: [
                              for (var i = 0; i < c.learners.length; i++) ...[
                                const Divider(indent: 72),
                                ListRow(
                                  leading: const IconBadge(Icons.person_outline, size: 34),
                                  title: c.learners[i].student == null
                                      ? 'Learner #${c.learners[i].member.studentId}'
                                      : studentLabel(c.learners[i].student!),
                                  subtitle: c.learners[i].section == null ? null : '${c.learners[i].section}',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    if (classes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      CsvTableView(csv: srpClassesCsv(classes), fileName: 'SRP_classes_$year.csv', title: 'All classes'),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
