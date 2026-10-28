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
import '../common/signed_in_user.dart';
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
    final canAdd = canEdit && schoolId != null && _year != null;
    final wide = isWideScreen(context);
    void add() => _after(editor!.addClass(context, schoolId!, _year!));
    return Scaffold(
      appBar: AppBar(
        title: const Text('ARAL classes'),
        actions: [if (canAdd && wide) mainActionButton(onPressed: add, icon: Icons.add, label: 'New class')],
      ),
      floatingActionButton: canAdd && !wide ? mainActionFab(onPressed: add, icon: Icons.add, label: 'New class') : null,
      body: schoolId == null
          ? const NeedsSchoolNote()
          : PageBody(
              children: [
                FilterBar(children: [SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y))]),
                if (_year != null)
                  LoadView<List<AralClassSummary>>(
                    where: 'AralClasses',
                    reloadKey: '$_year-$_reload',
                    load: (vms) async {
                      final classes = await vms.aralClass.classes(schoolId: schoolId, schoolYear: _year);
                      return [for (final c in classes) await vms.aralSession.classSummary(c.id!)];
                    },
                    builder: (context, list, _) {
                      if (list.isEmpty) {
                        return EmptyNote(
                          'No ARAL classes this school year yet.${canEdit ? ' Add one with New class.' : ''}',
                          icon: Icons.class_outlined,
                        );
                      }
                      final cap = vmsOf(context).aralClass.classCap;
                      final learners = list.fold<int>(0, (n, s) => n + s.activeLearners);
                      final sessions = list.fold<int>(0, (n, s) => n + s.sessions);
                      final present = list.fold<int>(0, (n, s) => n + s.attendance.present);
                      final counted = list.fold<int>(0, (n, s) => n + s.attendance.present + s.attendance.absent);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StatGrid(tiles: [
                            StatTile(label: 'Classes', value: '${list.length}', icon: Icons.class_outlined),
                            StatTile(label: 'Active learners', value: '$learners', icon: Icons.groups_outlined),
                            StatTile(label: 'Sessions held', value: '$sessions', icon: Icons.event_note_outlined),
                            StatTile(
                              label: 'Attendance rate',
                              value: counted == 0 ? '—' : '${(present * 100 / counted).round()}%',
                              icon: Icons.fact_check_outlined,
                            ),
                          ]),
                          const SizedBox(height: 16),
                          ListCard(
                            children: [
                              for (final s in list)
                                ListRow(
                                  leading: LetterBadge('${s.aralClass.gradeLevel}'),
                                  title: s.aralClass.className,
                                  subtitle: [
                                    'Grade ${s.aralClass.gradeLevel} · ${s.aralClass.program?.label ?? 'mixed programs'}',
                                    '${s.activeLearners}/$cap active · ${s.sessions} session(s) · attendance ${s.attendance.label}',
                                  ].join('\n'),
                                  footer: s.nextCheckInAfter == null && s.aralClass.room == null && s.aralClass.schedule == null
                                      ? null
                                      : Wrap(spacing: 8, runSpacing: 6, children: [
                                          if (s.aralClass.room != null || s.aralClass.schedule != null)
                                            Text(
                                              [s.aralClass.room, s.aralClass.schedule].whereType<String>().join(' · '),
                                              style: Theme.of(context).textTheme.bodySmall
                                                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                            ),
                                          if (s.nextCheckInAfter != null)
                                            StatusChip('Check-in after session ${s.nextCheckInAfter}',
                                                tone: StatusTone.warn, icon: Icons.assignment_outlined),
                                        ]),
                                  trailing: [
                                    StatusChip(
                                      '${s.activeLearners}/$cap',
                                      tone: s.activeLearners >= cap ? StatusTone.warn : StatusTone.neutral,
                                      icon: Icons.person_outline,
                                    ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                  onTap: () async {
                                    await Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => AralClassScreen(classId: s.aralClass.id!, editor: canEdit ? editor : null),
                                    ));
                                    if (mounted) setState(() => _reload++);
                                  },
                                ),
                            ],
                          ),
                          if (canAdd && !wide) const SizedBox(height: 72),
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
    final wide = isWideScreen(context);
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
        final active = roster.where((e) => e.status == AralStatus.active).length;
        final cap = vmsOf(context).aralClass.classCap;
        void place() => _after(editor!.place(context, c));
        return Scaffold(
          appBar: AppBar(
            title: Text(c.className),
            actions: [
              if (editor != null && wide) mainActionButton(onPressed: place, icon: Icons.person_add, label: 'Place a learner'),
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
          floatingActionButton: editor != null && !wide
              ? mainActionFab(onPressed: place, icon: Icons.person_add, label: 'Place a learner')
              : null,
          body: PageBody(
            children: [
              StatGrid(tiles: [
                StatTile(label: 'Active learners', value: '$active/$cap', icon: Icons.groups_outlined),
                StatTile(label: 'Exited', value: '${roster.length - active}', icon: Icons.logout),
                StatTile(label: 'Grade', value: '${c.gradeLevel}', icon: Icons.school_outlined),
                StatTile(label: 'Program', value: c.program?.label ?? 'Mixed', icon: Icons.auto_stories_outlined),
              ]),
              if (c.room != null || c.schedule != null || c.notes != null)
                SectionCard(title: 'Details', icon: Icons.info_outline, children: [
                  if (c.room != null) InfoRow('Room', c.room!),
                  if (c.schedule != null) InfoRow('Schedule', c.schedule!),
                  if (c.notes != null) InfoRow('Notes', c.notes!),
                ]),
              const SizedBox(height: 4),
              if (roster.isEmpty)
                EmptyNote(
                  'No learners placed yet.${editor != null ? ' Add one with Place a learner.' : ''}',
                  icon: Icons.person_add_alt_outlined,
                )
              else
                ListCard(
                  title: 'Learners ($active active)',
                  children: [
                    for (final e in roster)
                      ListRow(
                        leading: LetterBadge(initialOf(names[e.studentId] ?? '')),
                        title: names[e.studentId] ?? 'Learner #${e.studentId}',
                        subtitle: aralProgramLabel(e),
                        trailing: [
                          aralStatusChip(e),
                          editor == null
                              ? const Icon(Icons.chevron_right)
                              : IconButton(
                                  tooltip: 'Take out of the class',
                                  icon: const Icon(Icons.person_remove_outlined),
                                  onPressed: () => _after(editor.unplace(context, e)),
                                ),
                        ],
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => LearnerAralScreen(enrollmentId: e.id!, name: names[e.studentId] ?? 'Learner'),
                        )),
                      ),
                  ],
                ),
              if (editor != null && !wide) const SizedBox(height: 72),
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
                FilterBar(children: [SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y))]),
                if (_year != null)
                  LoadView<List<({User tutor, int classes, int activeLearners})>>(
                    where: 'AralTutors',
                    reloadKey: _year,
                    load: (vms) => vms.aral.tutors(schoolId: schoolId, schoolYear: _year!),
                    builder: (context, list, _) {
                      if (list.isEmpty) return const EmptyNote('No tutors at this school.', icon: Icons.badge_outlined);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StatGrid(tiles: [
                            StatTile(label: 'Tutors', value: '${list.length}', icon: Icons.badge_outlined),
                            StatTile(
                              label: 'Classes',
                              value: '${list.fold<int>(0, (n, t) => n + t.classes)}',
                              icon: Icons.class_outlined,
                            ),
                            StatTile(
                              label: 'Active learners',
                              value: '${list.fold<int>(0, (n, t) => n + t.activeLearners)}',
                              icon: Icons.groups_outlined,
                            ),
                          ]),
                          const SizedBox(height: 16),
                          ListCard(children: [
                            for (final t in list)
                              ListRow(
                                leading: UserAvatar(user: t.tutor),
                                title: t.tutor.fullName.isEmpty ? t.tutor.email : t.tutor.fullName,
                                subtitle: '${t.classes} class(es) · ${t.activeLearners} active learner(s)',
                                trailing: [
                                  StatusChip(
                                    t.classes == 0 ? 'no class' : 'teaching',
                                    tone: t.classes == 0 ? StatusTone.neutral : StatusTone.good,
                                  ),
                                ],
                              ),
                          ]),
                        ],
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
