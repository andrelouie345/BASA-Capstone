// lib/ui/admin/section_editing.dart
// The Sections screen's admin part: add, edit and delete a section (the
// grade must be a number). Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/section.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import '../learners/sections_screen.dart';

class AdminSectionsEditor extends SectionsEditor {
  const AdminSectionsEditor();

  @override
  bool canEdit(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    return me != null && isAdminOrCoordinator(me);
  }

  @override
  Future<bool> add(BuildContext context) => _save(context, null);

  @override
  Future<bool> edit(BuildContext context, Section section) => _save(context, section);

  Future<bool> _save(BuildContext context, Section? s) async {
    final vms = vmsOf(context);
    final f = await askFields(
      context,
      title: s == null ? 'Add section' : 'Edit section',
      fields: [
        FieldSpec('year', 'School year', initial: s?.schoolYear ?? '', hint: 'e.g. 2026-2027'),
        FieldSpec('grade', 'Grade', initial: s?.gradeLevel ?? '', hint: '1 to 10', number: true),
        FieldSpec('name', 'Section name', initial: s?.sectionName ?? ''),
        if (s == null && vms.auth.currentUser?.schoolId == null) const FieldSpec('school', 'School number (id)', number: true),
      ],
    );
    if (f == null || !context.mounted) return false;
    if (s == null) {
      final schoolId = vms.auth.currentUser?.schoolId ?? int.tryParse(f['school'] ?? '');
      if (schoolId == null) {
        showNote(context, 'Enter the school number.');
        return false;
      }
      final r = await runAction(
        context,
        () => vms.section.create(schoolId: schoolId, schoolYear: f['year']!, gradeLevel: f['grade']!, sectionName: f['name']!),
        where: 'SectionsScreen',
      );
      if (r != null && context.mounted) showNote(context, r.created ? 'Section added.' : 'That section was already there.');
      return r != null;
    }
    return await runAction(
          context,
          () => vms.section.update(id: s.id!, schoolYear: f['year']!, gradeLevel: f['grade']!, sectionName: f['name']!),
          done: 'Section saved.',
          where: 'SectionsScreen',
        ) !=
        null;
  }

  @override
  Future<bool> delete(BuildContext context, Section s) async {
    if (!await confirm(context, title: 'Delete $s?', action: 'Delete', destructive: true)) return false;
    if (!context.mounted) return false;
    final sections = vmsOf(context).section;
    return runStep(context, () => sections.delete(s.id!), done: 'Section deleted.', where: 'SectionsScreen');
  }
}
