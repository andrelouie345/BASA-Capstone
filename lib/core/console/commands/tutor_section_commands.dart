// lib/core/console/commands/tutor_section_commands.dart

/// Commands for tutor-section assignments
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/tutor_section_assignment_viewmodel.dart';

void registerTutorSectionCommands(ConsoleRegistry registry, TutorSectionAssignmentViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'assign-section',
    description: 'assign-section <tutorId> <sectionId> — assign a tutor to a section (admin/coordinator only)',
    handler: (args) async {
      if (args.length < 2) return 'Usage: assign-section <tutorId> <sectionId>';
      final sectionId = int.tryParse(args[1]);
      if (sectionId == null) return 'Invalid sectionId: "${args[1]}" (expected a number)';
      try {
        final a = await vm.assign(tutorId: args[0], sectionId: sectionId);
        return 'Assigned tutor ${a.tutorId} to section ${a.sectionId} (assignment ${a.id}).'
            '${vm.lastMirrorWarning == null ? '' : '\n${vm.lastMirrorWarning}'}';
      } catch (e) {
        return 'Assign failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'unassign-section',
    description: 'unassign-section <assignmentId> — remove a tutor-section assignment (admin/coordinator only)',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: unassign-section <assignmentId>';
      final id = int.tryParse(args[0]);
      if (id == null) return 'Invalid assignmentId: "${args[0]}" (expected a number)';
      try {
        await vm.unassign(id);
        return 'Unassigned assignment $id.${vm.lastMirrorWarning == null ? '' : '\n${vm.lastMirrorWarning}'}';
      } catch (e) {
        return 'Unassign failed: $e';
      }
    },
  ));

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

  registry.register(ConsoleCommand(
    name: 'list-section-tutors',
    description: 'list-section-tutors <sectionId> — list tutors assigned to a section (admin/coordinator only)',
    handler: (args) async {
      final sectionId = int.tryParse(args.isEmpty ? '' : args[0]);
      if (sectionId == null) return 'Usage: list-section-tutors <sectionId>';
      try {
        await vm.loadForSection(sectionId);
        if (vm.items.isEmpty) return '(no assignments found)';
        return vm.items
            .map((a) => '${a.id} | ${a.tutorFullName ?? "tutor ${a.tutorId}"} (${a.tutorEmail ?? ""}) | assigned ${a.assignedAt?.toLocal()}')
            .join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));
}
