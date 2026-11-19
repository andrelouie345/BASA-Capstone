// lib/ui/admin/section_editing.dart
// The Sections screen's admin part: add, edit and delete a section (the
// grade must be a number) and set its adviser. Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/section.dart';
import '../../core/models/user.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import '../learners/sections_screen.dart';
import 'admin_scope.dart';

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

  @override
  Future<bool> adviser(BuildContext context, Section s) async {
    final vms = vmsOf(context);
    final users = AdminScope.of(context).users;
    final f = await askFields(context, title: 'Adviser of ${s.sectionName}', fields: [
      FieldSpec('name', "Adviser's name", initial: s.adviserName ?? '', optional: true,
          helper: "As the school writes it. Leave it empty to use the BASA account's name, or to clear the adviser."),
    ]);
    if (f == null || !context.mounted) return false;
    // The adviser's BASA account: optional; a user of the section's school.
    final loaded = await runAction(context, () async {
      await users.loadAll();
      return users.items.where((u) => u.schoolId == s.schoolId).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));
    }, where: 'SectionsScreen');
    if (loaded == null || !context.mounted) return false;
    const keep = '__keep', none = '__none';
    String nameOf(String id) => loaded.where((u) => u.id == id).map((u) => u.fullName).firstOrNull ?? 'the current account';
    final account = await pickOne<String>(
      context,
      title: "The adviser's BASA account",
      options: [if (s.adviserUserId != null) keep, none, for (final User u in loaded) u.id],
      label: (id) => switch (id) {
        keep => 'Keep ${nameOf(s.adviserUserId!)}',
        none => 'No BASA account',
        _ => '${nameOf(id)} (${loaded.firstWhere((u) => u.id == id).email})',
      },
    );
    if (account == null || !context.mounted) return false;
    final name = f['name']!.trim();
    final saved = await runAction(
      context,
      () => vms.section.setAdviser(s.id!,
          name: name.isEmpty ? null : name,
          userId: account == keep || account == none ? null : account,
          clearUser: account == none),
      done: 'Adviser saved.',
      where: 'SectionsScreen',
    );
    final warn = vms.section.lastMirrorWarning;
    if (saved != null && warn != null && context.mounted) showNote(context, warn);
    return saved != null;
  }
}
