// lib/ui/aral/classes_screen.dart
// ARAL classes (docs/handoff/screens/aral.md, Classes) and Tutors: a school
// year's classes (at most 15 active learners each) with tutor and summary,
// each class's roster, and the school's tutors. Creating, editing, deleting
// classes and placing learners are admin-only: the admin build passes an
// [AralClassEditor] (lib/ui/admin/).
import 'package:flutter/material.dart';

import '../../core/models/aral_class.dart';
import '../../core/models/aral_enrollment.dart';
import '../../core/models/user.dart';
import '../../viewmodels/aral_session_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import 'aral_common.dart';
import 'learner_aral_screen.dart';

/// The admin build's class changes. Each returns true when something changed.
abstract class AralClassEditor {
  const AralClassEditor();
  bool canEdit(BuildContext context);
  Future<bool> addClass(BuildContext context, int schoolId, String schoolYear);
  Future<bool> classActions(BuildContext context, AralClass c);

  /// Place a waiting learner in [c].
  Future<bool> place(BuildContext context, AralClass c);
  Future<bool> unplace(BuildContext context, AralEnrollment e);
}

class AralClassesScreen extends StatefulWidget {
  final AralClassEditor? editor;
  const AralClassesScreen({super.key, this.editor});

  @override
  State<AralClassesScreen> createState() => _AralClassesScreenState();
}

class _AralClassesScreenState extends State<AralClassesScreen> {
  String? _year;
  int _reload = 0;

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final schoolId = mySchoolId(context);
    final editor = widget.editor;
    final canEdit = editor != null && editor.canEdit(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ARAL classes')),
      floatingActionButton: canEdit && schoolId != null && _year != null
          ? FloatingActionButton.extended(
              onPressed: () => _after(editor.addClass(context, schoolId, _year!)),
              icon: const Icon(Icons.add),
              label: const Text('New class'),
            )
          : null,
      body: schoolId == null
          ? const NeedsSchoolNote()
          : PageBody(
              children: [
                SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y)),
                if (_year != null)
                  LoadView<List<AralClassSummary>>(
                    where: 'AralClasses',
                    reloadKey: '$_year-$_reload',
                    load: (vms) async {
                      final classes = await vms.aralClass.classes(schoolId: schoolId, schoolYear: _year);
                      return [for (final c in classes) await vms.aralSession.classSummary(c.id!)];
                    },
                    builder: (context, list, _) {
                      if (list.isEmpty) return const EmptyNote('No ARAL classes this school year yet.');
                      final cap = vmsOf(context).aralClass.classCap;
                      return Column(
                        children: [
                          for (final s in list)
                            Card(
                              child: ListTile(
                                title: Text(s.aralClass.className),
                                subtitle: Text([
                                  'Grade ${s.aralClass.gradeLevel} · ${s.aralClass.program?.label ?? 'mixed programs'}',
                                  '${s.activeLearners}/$cap active · ${s.sessions} session(s) · attendance ${s.attendance.label}',
                                  if (s.nextCheckInAfter != null) 'Check-in after session ${s.nextCheckInAfter}',
                                  if (s.aralClass.room != null || s.aralClass.schedule != null)
                                    [s.aralClass.room, s.aralClass.schedule].whereType<String>().join(' · '),
                                ].join('\n')),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  await Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => AralClassScreen(classId: s.aralClass.id!, editor: canEdit ? editor : null),
                                  ));
                                  if (mounted) setState(() => _reload++);
                                },
                              ),
                            ),
                          const SizedBox(height: 72),
                        ],
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

class AralClassScreen extends StatefulWidget {
  final int classId;
  final AralClassEditor? editor;
  const AralClassScreen({super.key, required this.classId, this.editor});

  @override
  State<AralClassScreen> createState() => _AralClassScreenState();
}

class _AralClassScreenState extends State<AralClassScreen> {
  int _reload = 0;

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    return LoadView<(AralClass, List<AralEnrollment>, Map<int, String>)>(
      where: 'AralClass',
      reloadKey: _reload,
      load: (vms) async {
        final c = await vms.aralClass.getClass(widget.classId);
        final roster = await vms.aralClass.classRoster(widget.classId);
        return (c, roster, await vms.aralSession.learnerNames(roster));
      },
      builder: (context, data, _) {
        final (c, roster, names) = data;
        return Scaffold(
          appBar: AppBar(
            title: Text(c.className),
            actions: [
              if (editor != null)
                IconButton(
                  tooltip: 'Class actions',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    final before = await editor.classActions(context, c);
                    if (before) nav.pop();
                  },
                ),
            ],
          ),
          floatingActionButton: editor == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _after(editor.place(context, c)),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Place a learner'),
                ),
          body: PageBody(
            children: [
              SectionCard(title: 'Learners (${roster.where((e) => e.status == AralStatus.active).length} active)', children: [
                if (roster.isEmpty) const Text('No learners placed yet.'),
                for (final e in roster)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(names[e.studentId] ?? 'Learner #${e.studentId}'),
                    subtitle: Text('${aralProgramLabel(e)} · ${aralStatusLabel(e)}'),
                    trailing: editor == null
                        ? const Icon(Icons.chevron_right)
                        : IconButton(
                            tooltip: 'Take out of the class',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: () => _after(editor.unplace(context, e)),
                          ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LearnerAralScreen(enrollmentId: e.id!, name: names[e.studentId] ?? 'Learner'),
                    )),
                  ),
              ]),
              const SizedBox(height: 72),
            ],
          ),
        );
      },
    );
  }
}

/// Tutors (docs/handoff/screens/aral.md): the school's tutors with their
/// classes and active learners.
class AralTutorsScreen extends StatefulWidget {
  const AralTutorsScreen({super.key});

  @override
  State<AralTutorsScreen> createState() => _AralTutorsScreenState();
}

class _AralTutorsScreenState extends State<AralTutorsScreen> {
  String? _year;

  @override
  Widget build(BuildContext context) {
    final schoolId = mySchoolId(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ARAL tutors')),
      body: schoolId == null
          ? const NeedsSchoolNote()
          : PageBody(
              children: [
                SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y)),
                if (_year != null)
                  LoadView<List<({User tutor, int classes, int activeLearners})>>(
                    where: 'AralTutors',
                    reloadKey: _year,
                    load: (vms) => vms.aral.tutors(schoolId: schoolId, schoolYear: _year!),
                    builder: (context, list, _) => Column(children: [
                      if (list.isEmpty) const EmptyNote('No tutors at this school.'),
                      for (final t in list)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.badge_outlined),
                            title: Text(t.tutor.fullName.isEmpty ? t.tutor.email : t.tutor.fullName),
                            subtitle: Text('${t.classes} class(es) · ${t.activeLearners} active learner(s)'),
                          ),
                        ),
                    ]),
                  ),
              ],
            ),
    );
  }
}
