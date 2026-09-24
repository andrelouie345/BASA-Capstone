// lib/core/console/commands/tutor_section_commands.dart

/// Commands for tutor-section assignments
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../logger.dart';
import '../../models/user_role.dart';
import '../../models/tutor_section_assignment.dart';
import '../../data/remote/tutor_section_assignment_repository_supabase.dart';
import '../../../viewmodels/tutor_section_assignment_viewmodel.dart';
import '../../../viewmodels/auth_viewmodel.dart';

void registerTutorSectionCommands(ConsoleRegistry registry, AuthViewModel authVm, Logger? logger) {
  String? _forbiddenUnlessAdminOrCoordinator() {
    final role = authVm.currentUser?.role;
    if (role != UserRole.admin && role != UserRole.coordinator) {
      return 'Forbidden: admin or coordinator only.';
    }
    return null;
  }

  registry.register(ConsoleCommand(
    name: 'assign-section',
    description: 'assign-section <tutorId> <sectionId> — assign a tutor to a section (admin/coordinator only)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final forbidden = _forbiddenUnlessAdminOrCoordinator();
      if (forbidden != null) return forbidden;

      if (args.length < 2) return 'Usage: assign-section <tutorId> <sectionId>';
      final tutorId = args[0];
      final sectionId = int.tryParse(args[1]);
      if (sectionId == null) return 'Invalid sectionId: "${args[1]}" (expected a number)';

      final client = authVm.client!;
      final vm = TutorSectionAssignmentViewModel(repo: TutorSectionAssignmentRepositorySupabase(client), logger: logger);
      try {
        await vm.assign(TutorSectionAssignment(
          tutorId: tutorId,
          sectionId: sectionId,
          assignedBy: authVm.currentUser?.id,
          assignedAt: DateTime.now(),
        ));
        return 'Assigned tutor $tutorId to section $sectionId.';
      } catch (e) {
        return 'Assign failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'unassign-section',
    description: 'unassign-section <assignmentId> — remove a tutor-section assignment (admin/coordinator only)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final forbidden = _forbiddenUnlessAdminOrCoordinator();
      if (forbidden != null) return forbidden;

      if (args.isEmpty) return 'Usage: unassign-section <assignmentId>';
      final id = int.tryParse(args[0]);
      if (id == null) return 'Invalid assignmentId: "${args[0]}" (expected a number)';

      final client = authVm.client!;
      final vm = TutorSectionAssignmentViewModel(repo: TutorSectionAssignmentRepositorySupabase(client), logger: logger);
      try {
        await vm.unassign(id);
        return 'Unassigned assignment $id.';
      } catch (e) {
        return 'Unassign failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'list-tutor-sections',
    description: 'list-tutor-sections <tutorId> — list sections a tutor is assigned to (admin/coordinator only)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final forbidden = _forbiddenUnlessAdminOrCoordinator();
      if (forbidden != null) return forbidden;

      if (args.isEmpty) return 'Usage: list-tutor-sections <tutorId>';
      final client = authVm.client!;
      final vm = TutorSectionAssignmentViewModel(repo: TutorSectionAssignmentRepositorySupabase(client), logger: logger);
      try {
        await vm.loadForTutor(args[0]);
        if (vm.items.isEmpty) return '(no assignments found)';
        return vm.items.map((a) => '${a.id} | ${a.section?.toString() ?? "section ${a.sectionId}"} | assigned ${a.assignedAt}').join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'list-section-tutors',
    description: 'list-section-tutors <sectionId> — list tutors assigned to a section (admin/coordinator only)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;
      final forbidden = _forbiddenUnlessAdminOrCoordinator();
      if (forbidden != null) return forbidden;

      final sectionId = int.tryParse(args.isEmpty ? '' : args[0]);
      if (sectionId == null) return 'Usage: list-section-tutors <sectionId>';

      final client = authVm.client!;
      final vm = TutorSectionAssignmentViewModel(repo: TutorSectionAssignmentRepositorySupabase(client), logger: logger);
      try {
        await vm.loadForSection(sectionId);
        if (vm.items.isEmpty) return '(no assignments found)';
        return vm.items.map((a) => '${a.id} | ${a.tutorFullName ?? "tutor ${a.tutorId}"} (${a.tutorEmail ?? ""}) | assigned ${a.assignedAt}').join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));
}