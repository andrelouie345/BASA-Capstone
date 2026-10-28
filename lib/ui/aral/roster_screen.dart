// lib/ui/aral/roster_screen.dart
// ARAL roster (docs/handoff/screens/aral.md, Roster): who is in ARAL, by
// section, by school or the tutor's own, with program, class and status.
// Changing the roster (propose, enroll, refer, placement, exit, ...) is
// admin-only: the admin build passes an [AralRosterEditor] (lib/ui/admin/).
import 'package:flutter/material.dart';

import '../../core/models/aral_enrollment.dart';
import '../../core/models/section.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import 'aral_common.dart';
import 'learner_aral_screen.dart';

/// The admin build's roster changes. Each returns true when something changed.
abstract class AralRosterEditor {
  const AralRosterEditor();
  bool canEdit(BuildContext context);

  /// Propose, enroll or refer learners of [section]; apply new results.
  Future<bool> sectionActions(BuildContext context, Section section);

  /// Placement, move, exit, reactivate, notes, remove.
  Future<bool> enrollmentActions(BuildContext context, AralEnrollment e);
}

enum _View { section, school, mine }

class AralRosterScreen extends StatefulWidget {
  final AralRosterEditor? editor;
  const AralRosterScreen({super.key, this.editor});

  @override
  State<AralRosterScreen> createState() => _AralRosterScreenState();
}

class _AralRosterScreenState extends State<AralRosterScreen> {
  late _View _view = _View.section;
  Section? _section;
  String? _year;
  int _reload = 0;

  Future<void> _after(Future<bool> change) async {
    if (await change && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    final tutor = me != null && !isAdminOrCoordinator(me);
    final schoolId = me?.schoolId;
    final editor = widget.editor;
    final canEdit = editor != null && editor.canEdit(context);
    final ready = switch (_view) {
      _View.section => _section != null,
      _View.school => schoolId != null && _year != null,
      _View.mine => _year != null,
    };
    final canEnroll = canEdit && _view == _View.section && _section != null;
    final wide = isWideScreen(context);
    void enroll() => _after(editor!.sectionActions(context, _section!));
    return Scaffold(
      appBar: AppBar(
        title: const Text('ARAL roster'),
        actions: [
          if (canEnroll && wide) mainActionButton(onPressed: enroll, icon: Icons.group_add_outlined, label: 'Enroll and update'),
        ],
      ),
      floatingActionButton:
          canEnroll && !wide ? mainActionFab(onPressed: enroll, icon: Icons.group_add_outlined, label: 'Enroll and update') : null,
      body: PageBody(
        children: [
          FilterBar(children: [
            SegmentedButton<_View>(
              segments: [
                const ButtonSegment(value: _View.section, label: Text('Section')),
                if (schoolId != null) const ButtonSegment(value: _View.school, label: Text('School')),
                if (tutor) const ButtonSegment(value: _View.mine, label: Text('My classes')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            if (_view == _View.section)
              SectionPicker(value: _section, onChanged: (s) => setState(() => _section = s))
            else
              SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y)),
          ]),
          if (!ready && _view == _View.section)
            const EmptyNote('Pick a section to see its ARAL learners.', icon: Icons.groups_outlined),
          if (ready)
            LoadView<(List<AralEnrollment>, Map<int, String>, Map<int, String>)>(
              where: 'AralRoster',
              reloadKey: '$_view-${_section?.id}-$_year-$_reload',
              load: (vms) async {
                final aral = vms.aral;
                final list = switch (_view) {
                  _View.section => await aral.roster(sectionId: _section!.id!, schoolYear: _section!.schoolYear),
                  _View.school => await aral.schoolRoster(schoolId: schoolId!, schoolYear: _year),
                  _View.mine => await aral.tutorRoster(tutorId: me?.id, schoolYear: _year),
                };
                final names = await vms.aralSession.learnerNames(list);
                final classes = schoolId == null ? <int, String>{} : await aral.classNames(schoolId);
                return (list, names, classes);
              },
              builder: (context, data, reload) {
                final (list, names, classes) = data;
                if (list.isEmpty) {
                  return EmptyNote(
                    'No ARAL learners here yet.${canEnroll ? ' Add some with Enroll and update.' : ''}',
                    icon: Icons.groups_outlined,
                  );
                }
                final active = list.where((e) => e.status == AralStatus.active).length;
                bool referred(AralEnrollment e) => e.basisSource == AralBasisSource.manual && e.referredBy != null;
                bool waiting(AralEnrollment e) => e.classId == null && e.status == AralStatus.active;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatGrid(tileWidth: 180, tiles: [
                      StatTile(label: 'Active', value: '$active', icon: Icons.how_to_reg_outlined),
                      StatTile(label: 'Exited', value: '${list.length - active}', icon: Icons.logout),
                      StatTile(label: 'Waiting for a class', value: '${list.where(waiting).length}', icon: Icons.hourglass_empty),
                      StatTile(label: 'Referred', value: '${list.where(referred).length}', icon: Icons.forward_to_inbox_outlined),
                    ]),
                    const SizedBox(height: 16),
                    ListCard(
                      title: '$active active · ${list.length - active} exited',
                      children: [
                        for (final e in list)
                          ListRow(
                            leading: LetterBadge(initialOf(names[e.studentId] ?? '')),
                            title: names[e.studentId] ?? 'Learner #${e.studentId}',
                            subtitle: [
                              aralProgramLabel(e),
                              e.classId == null ? 'waiting for a class' : (classes[e.classId] ?? 'class #${e.classId}'),
                            ].join(' · '),
                            footer: Wrap(spacing: 8, runSpacing: 6, children: [
                              aralStatusChip(e),
                              if (waiting(e)) const StatusChip('waiting', tone: StatusTone.warn, icon: Icons.hourglass_empty),
                              if (referred(e)) const StatusChip('referred', icon: Icons.forward_to_inbox_outlined),
                            ]),
                            trailing: [
                              canEdit
                                  ? IconButton(
                                      tooltip: 'Change',
                                      icon: const Icon(Icons.more_vert),
                                      onPressed: () => _after(editor.enrollmentActions(context, e)),
                                    )
                                  : const Icon(Icons.chevron_right),
                            ],
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => LearnerAralScreen(enrollmentId: e.id!, name: names[e.studentId] ?? 'Learner'),
                            )),
                          ),
                      ],
                    ),
                    if (canEnroll && !wide) const SizedBox(height: 72),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
