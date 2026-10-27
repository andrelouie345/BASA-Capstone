// lib/ui/admin/school_editing.dart
// The Schools screen's admin part: add, edit and delete a school
// (superadmin). Admin build only; lib/ui/learners/schools_screen.dart shows
// the list in both builds.
import 'package:flutter/material.dart';

import '../../core/models/region.dart';
import '../../core/models/school.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import '../learners/schools_screen.dart';

class AdminSchoolsEditor extends SchoolsEditor {
  const AdminSchoolsEditor();

  @override
  bool canEdit(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    return me != null && isSuperadmin(me);
  }

  @override
  Future<bool> add(BuildContext context) => _save(context, null);

  @override
  Future<bool> edit(BuildContext context, School school) => _save(context, school);

  Future<bool> _save(BuildContext context, School? s) async {
    final schools = vmsOf(context).school;
    final r = await showDialog<School>(context: context, builder: (_) => _SchoolDialog(school: s));
    if (r == null || !context.mounted) return false;
    if (s == null) {
      final made = await runAction(
        context,
        () => schools.create(schoolCode: r.schoolId, schoolName: r.schoolName, regionId: r.regionId, division: r.division),
        where: 'SchoolsScreen',
      );
      if (made != null && context.mounted) {
        showNote(context, made.created ? 'School added.' : 'That school was already there.');
      }
      return made != null;
    }
    return await runAction(context, () => schools.update(r), done: 'School saved.', where: 'SchoolsScreen') != null;
  }

  @override
  Future<bool> delete(BuildContext context, School s) async {
    if (!await confirm(context,
        title: 'Delete ${s.schoolName}?', body: 'This cannot be undone.', action: 'Delete', destructive: true)) {
      return false;
    }
    if (!context.mounted) return false;
    final schools = vmsOf(context).school;
    return runStep(context, () => schools.delete(s.id!), done: 'School deleted.', where: 'SchoolsScreen');
  }
}

class _SchoolDialog extends StatefulWidget {
  final School? school;
  const _SchoolDialog({this.school});

  @override
  State<_SchoolDialog> createState() => _SchoolDialogState();
}

class _SchoolDialogState extends State<_SchoolDialog> {
  late final _code = TextEditingController(text: widget.school?.schoolId ?? '');
  late final _name = TextEditingController(text: widget.school?.schoolName ?? '');
  late final _division = TextEditingController(text: widget.school?.division ?? '');
  late Region? _region = widget.school?.regionId == null ? null : Region.byId(widget.school!.regionId!);

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _division.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.school == null ? 'Add school' : 'Edit school'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _code, decoration: const InputDecoration(labelText: 'School ID (DepEd)')),
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'School name')),
              const SizedBox(height: 12),
              RegionPicker(value: _region, onChanged: (r) => setState(() => _region = r)),
              const SizedBox(height: 12),
              TextField(controller: _division, decoration: const InputDecoration(labelText: 'Division (optional)')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) return;
            Navigator.of(context).pop(School(
              id: widget.school?.id,
              schoolId: _code.text.trim(),
              schoolName: _name.text.trim(),
              regionId: _region?.id,
              division: _division.text.trim().isEmpty ? null : _division.text.trim(),
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
