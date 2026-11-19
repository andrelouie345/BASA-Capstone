// lib/core/console/commands/section_admin_commands.dart
// Admin build only: the admin half of section-commands.dart (tutor build split, 2026-10-22).

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/section_viewmodel.dart';

void registerSectionAdminCommands(ConsoleRegistry registry, SectionViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'section-create',
    description:
        'section-create <schoolId> <schoolYear> <gradeLevel> <sectionName...> — create a section (admin/coordinator, own school only; superadmin any)',
    handler: (args) async {
      if (args.length < 4) return 'Usage: section-create <schoolId> <schoolYear> <gradeLevel> <sectionName...>';
      final schoolId = int.tryParse(args[0]);
      if (schoolId == null) return 'Invalid schoolId: "${args[0]}" (expected a number)';
      try {
        final result = await vm.create(
          schoolId: schoolId,
          schoolYear: args[1],
          gradeLevel: args[2],
          sectionName: args.sublist(3).join(' '),
        );
        return result.created
            ? 'OK: ${result.section.id} | ${result.section}'
            : 'Already exists (unchanged): ${result.section.id} | ${result.section}';
      } catch (e) {
        return 'Create failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'section-update',
    description:
        'section-update <id> <schoolYear> <gradeLevel> <sectionName...> — update a section (admin/coordinator, own school only; superadmin any)',
    handler: (args) async {
      if (args.length < 4) return 'Usage: section-update <id> <schoolYear> <gradeLevel> <sectionName...>';
      final id = int.tryParse(args[0]);
      if (id == null) return 'Invalid id: "${args[0]}" (expected a number)';
      try {
        final updated = await vm.update(
          id: id,
          schoolYear: args[1],
          gradeLevel: args[2],
          sectionName: args.sublist(3).join(' '),
        );
        return 'Updated: ${updated.id} | $updated';
      } catch (e) {
        return 'Update failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'section-adviser',
    description: 'section-adviser <sectionId> <"name"|-> [userId|-] — the section\'s adviser (ARAL Form 2): a typed '
        'name (an account is optional) and/or their BASA account of the school (left out = kept, - = removed; a '
        'linked adviser without a name gets the account\'s name); "-" as the name clears it (admin/coordinator, own '
        'school only; superadmin any)',
    handler: (args) async {
      const usage = 'Usage: section-adviser <sectionId> <"name"|-> [userId|-]';
      if (args.length < 2 || args.length > 3) return usage;
      final id = int.tryParse(args[0]);
      if (id == null) return 'Invalid sectionId: "${args[0]}" (expected a number)';
      try {
        final s = await vm.setAdviser(id,
            name: args[1] == '-' ? null : args[1],
            userId: args.length == 3 && args[2] != '-' ? args[2] : null,
            clearUser: args.length == 3 && args[2] == '-');
        final warn = vm.lastMirrorWarning;
        return 'Adviser of ${s.id} | $s: ${s.adviserName ?? '-'}'
            '${s.adviserUserId == null ? ' (no BASA account)' : ' (account ${s.adviserUserId})'}'
            '${warn == null ? '' : '\n$warn'}';
      } catch (e) {
        return 'Update failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'section-delete',
    description: 'section-delete <id> — delete a section (admin/coordinator, own school only; superadmin any)',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: section-delete <id>';
      final id = int.tryParse(args[0]);
      if (id == null) return 'Invalid id: "${args[0]}" (expected a number)';
      try {
        await vm.delete(id);
        return 'Deleted section $id.';
      } catch (e) {
        return 'Delete failed: $e';
      }
    },
  ));
}
