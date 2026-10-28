// lib/ui/admin/tutor_assignments_screen.dart
// Tutor assignments (docs/handoff/screens/admin.md): pick a tutor to see and
// change their sections, or a section to see its tutors. Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/section.dart';
import '../../core/models/tutor_section_assignment.dart';
import '../../core/models/user.dart';
import '../../core/models/user_role.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import 'admin_scope.dart';

class TutorAssignmentsScreen extends StatefulWidget {
  const TutorAssignmentsScreen({super.key});

  @override
  State<TutorAssignmentsScreen> createState() => _TutorAssignmentsScreenState();
}

class _TutorAssignmentsScreenState extends State<TutorAssignmentsScreen> {
  bool _byTutor = true;
  User? _tutor;
  Section? _section;
  int _reload = 0;

  Future<void> _assign() async {
    final admin = AdminScope.of(context);
    final vms = vmsOf(context);
    final sections = await runAction(context, vms.section.localSections, where: 'TutorAssignments');
    if (sections == null || !mounted) return;
    String? tutorId = _tutor?.id;
    int? sectionId = _section?.id;
    if (_byTutor) {
      final s = await pickOne<Section>(context, title: 'Assign a section', options: sections, label: (s) => '$s');
      sectionId = s?.id;
    } else {
      await admin.users.loadAll();
      if (!mounted) return;
      final tutors = admin.users.items.where((u) => u.role == UserRole.tutor && u.isActive).toList();
      final t = await pickOne<User>(context,
          title: 'Assign a tutor', options: tutors, label: (u) => u.fullName.isEmpty ? u.email : u.fullName);
      tutorId = t?.id;
    }
    if (tutorId == null || sectionId == null || !mounted) return;
    final tid = tutorId, sid = sectionId;
    final r = await runAction(context, () => admin.tutorSections.assign(tutorId: tid, sectionId: sid),
        done: 'Assigned.', where: 'TutorAssignments');
    if (r != null && admin.tutorSections.lastMirrorWarning != null && mounted) {
      showNote(context, admin.tutorSections.lastMirrorWarning!);
    }
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final ready = _byTutor ? _tutor != null : _section != null;
    final wide = isWideScreen(context);
    final actionLabel = _byTutor ? 'Assign a section' : 'Assign a tutor';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tutor assignments'),
        actions: [if (ready && wide) mainActionButton(onPressed: _assign, icon: Icons.add_link, label: actionLabel)],
      ),
      floatingActionButton:
          ready && !wide ? mainActionFab(onPressed: _assign, icon: Icons.add_link, label: actionLabel) : null,
      body: PageBody(
        children: [
          FilterBar(children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('By tutor'), icon: Icon(Icons.person)),
                ButtonSegment(value: false, label: Text('By section'), icon: Icon(Icons.class_)),
              ],
              selected: {_byTutor},
              onSelectionChanged: (s) => setState(() => _byTutor = s.first),
            ),
            if (_byTutor)
              AsyncPicker<User>(
                label: 'Tutor',
                load: (_) async {
                  await admin.users.loadAll();
                  return admin.users.items.where((u) => u.role == UserRole.tutor).toList();
                },
                value: _tutor,
                same: (a, b) => a.id == b.id,
                itemLabel: (u) => u.fullName.isEmpty ? u.email : '${u.fullName} (${u.email})',
                onChanged: (u) => setState(() => _tutor = u),
              )
            else
              SectionPicker(value: _section, onChanged: (s) => setState(() => _section = s)),
          ]),
          if (!ready)
            EmptyNote(
              _byTutor ? 'Pick a tutor to see their sections.' : 'Pick a section to see its tutors.',
              icon: _byTutor ? Icons.person_search_outlined : Icons.class_outlined,
            ),
          if (ready)
            LoadView<List<TutorSectionAssignment>>(
              where: 'TutorAssignments',
              reloadKey: '$_byTutor-${_tutor?.id}-${_section?.id}-$_reload',
              load: (_) async {
                if (_byTutor) {
                  await admin.tutorSections.loadForTutor(_tutor!.id);
                } else {
                  await admin.tutorSections.loadForSection(_section!.id!);
                }
                return List.of(admin.tutorSections.items);
              },
              builder: (context, items, reload) => items.isEmpty
                  ? const EmptyNote('No assignments yet.', icon: Icons.link_off)
                  : ListCard(
                      title: _byTutor ? 'Sections' : 'Tutors',
                      trailing: StatusChip('${items.length}'),
                      children: [
                        for (final a in items)
                          ListRow(
                            leading: _byTutor
                                ? const IconBadge(Icons.class_outlined)
                                : LetterBadge(initialOf(a.tutorFullName ?? a.tutorEmail ?? a.tutorId)),
                            title: _byTutor
                                ? (a.section?.toString() ?? 'Section #${a.sectionId}')
                                : (a.tutorFullName ?? a.tutorEmail ?? a.tutorId),
                            subtitle: _byTutor ? null : a.tutorEmail,
                            trailing: [
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.link_off),
                                onPressed: () async {
                                  if (!await confirm(context, title: 'Remove this assignment?', action: 'Remove')) return;
                                  if (!context.mounted) return;
                                  await runAction(context, () => admin.tutorSections.unassign(a.id!),
                                      done: 'Removed.', where: 'TutorAssignments');
                                  reload();
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
