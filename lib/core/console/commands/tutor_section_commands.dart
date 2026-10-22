// lib/core/console/commands/tutor_section_commands.dart

/// Commands for tutor-section assignments
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/tutor_section_assignment_viewmodel.dart';

void registerTutorSectionCommands(ConsoleRegistry registry, TutorSectionAssignmentViewModel vm) {

  registry.register(ConsoleCommand(
    name: 'list-tutor-sections',
    description: 'list-tutor-sections <tutorId> — list sections a tutor is assigned to (admin/coordinator only)',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: list-tutor-sections <tutorId>';
      try {
        await vm.loadForTutor(args[0]);
        if (vm.items.isEmpty) return '(no assignments found)';
        return vm.items
            .map((a) => '${a.id} | ${a.section?.toString() ?? "section ${a.sectionId}"} | assigned ${a.assignedAt?.toLocal()}')
            .join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));
}
