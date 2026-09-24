// lib/core/console/commands/section_commands.dart

/// Commands for sections
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../logger.dart';
import '../../models/user_role.dart';
import '../../models/section.dart';
import '../../data/remote/section_repository_supabase.dart';
import '../../../viewmodels/auth_viewmodel.dart';

void registerSectionCommands(ConsoleRegistry registry, AuthViewModel authVm, Logger? logger) {
  String? _forbiddenUnlessScoped(int? targetSchoolId) {
    final actingUser = authVm.currentUser;
    final isSuperadmin = actingUser?.role == UserRole.admin && actingUser?.schoolId == null;
    if (isSuperadmin) return null;
    if (actingUser?.role != UserRole.admin && actingUser?.role != UserRole.coordinator) {
      return 'Forbidden: admin or coordinator only.';
    }
    if (targetSchoolId != null && actingUser?.schoolId != targetSchoolId) {
      return 'Forbidden: can only manage sections for your own school.';
    }
    return null;
  }

  registry.register(ConsoleCommand(
    name: 'section-create',
    description:
        'section-create <schoolId> <schoolYear> <gradeLevel> <sectionName...> — create a section (admin/coordinator, own school only; superadmin any)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      if (args.length < 4) return 'Usage: section-create <schoolId> <schoolYear> <gradeLevel> <sectionName...>';

      final schoolId = int.tryParse(args[0]);
      if (schoolId == null) return 'Invalid schoolId: "${args[0]}" (expected a number)';

      final forbidden = _forbiddenUnlessScoped(schoolId);
      if (forbidden != null) return forbidden;

      final client = authVm.client!;
      final repo = SectionRepositorySupabase(client);
      try {
        final section = await repo.getOrCreate(Section(
          schoolId: schoolId,
          schoolYear: args[1],
          gradeLevel: args[2],
          sectionName: args.sublist(3).join(' '),
        ));
        return 'OK: ${section.id} | $section';
      } catch (e) {
        return 'Create failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'section-list',
    description: 'section-list — list all sections visible to you',
    handler: (_) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final client = authVm.client!;
      final repo = SectionRepositorySupabase(client);
      try {
        final sections = await repo.getAll();
        if (sections.isEmpty) return '(no sections found)';
        return sections.map((s) => '${s.id} | $s').join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'section-update',
    description:
        'section-update <id> <schoolYear> <gradeLevel> <sectionName...> — update a section (admin/coordinator, own school only; superadmin any)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      if (args.length < 4) return 'Usage: section-update <id> <schoolYear> <gradeLevel> <sectionName...>';

      final id = int.tryParse(args[0]);
      if (id == null) return 'Invalid id: "${args[0]}" (expected a number)';

      final client = authVm.client!;
      final repo = SectionRepositorySupabase(client);
      final existing = await repo.getById(id);
      if (existing == null) return 'No section found with id $id.';

      final forbidden = _forbiddenUnlessScoped(existing.schoolId);
      if (forbidden != null) return forbidden;

      try {
        final updated = await repo.update(Section(
          id: id,
          schoolId: existing.schoolId,
          schoolYear: args[1],
          gradeLevel: args[2],
          sectionName: args.sublist(3).join(' '),
        ));
        return 'Updated: ${updated.id} | $updated';
      } catch (e) {
        return 'Update failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'section-delete',
    description: 'section-delete <id> — delete a section (admin/coordinator, own school only; superadmin any)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      if (args.isEmpty) return 'Usage: section-delete <id>';

      final id = int.tryParse(args[0]);
      if (id == null) return 'Invalid id: "${args[0]}" (expected a number)';

      final client = authVm.client!;
      final repo = SectionRepositorySupabase(client);
      final existing = await repo.getById(id);
      if (existing == null) return 'No section found with id $id.';

      final forbidden = _forbiddenUnlessScoped(existing.schoolId);
      if (forbidden != null) return forbidden;

      try {
        await repo.delete(id);
        return 'Deleted section $id.';
      } catch (e) {
        return 'Delete failed: $e';
      }
    },
  ));
}