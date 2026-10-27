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
    return Scaffold(
      appBar: AppBar(
        title: const Text('ARAL roster'),
        actions: [
          if (canEdit && _view == _View.section && _section != null)
            IconButton(
              tooltip: 'Enroll and update',
              icon: const Icon(Icons.group_add_outlined),
              onPressed: () => _after(editor.sectionActions(context, _section!)),
            ),
        ],
      ),
      body: PageBody(
        children: [
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
                if (list.isEmpty) return const EmptyNote('No ARAL learners here yet.');
                final active = list.where((e) => e.status == AralStatus.active).length;
                return SectionCard(
                  title: '$active active · ${list.length - active} exited',
                  children: [
                    for (final e in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(names[e.studentId] ?? 'Learner #${e.studentId}'),
                        subtitle: Text([
                          aralProgramLabel(e),
                          e.classId == null ? 'waiting for a class' : (classes[e.classId] ?? 'class #${e.classId}'),
                          aralStatusLabel(e),
                          if (e.basisSource == AralBasisSource.manual && e.referredBy != null) 'referred',
                        ].join(' · ')),
                        trailing: canEdit
                            ? IconButton(
                                tooltip: 'Change',
                                icon: const Icon(Icons.more_vert),
                                onPressed: () => _after(editor.enrollmentActions(context, e)),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => LearnerAralScreen(enrollmentId: e.id!, name: names[e.studentId] ?? 'Learner'),
                        )),
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
