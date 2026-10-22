// lib/core/console/commands/school_commands.dart

/// Commands for schools
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/school_viewmodel.dart';
import 'school_command_helpers.dart';

void registerSchoolCommands(ConsoleRegistry registry, SchoolViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'school-list',
    description: 'school-list — list the schools visible to you (superadmin: all; others: their own)',
    handler: (_) async {
      try {
        await vm.loadAll();
        if (vm.items.isEmpty) return '(no schools found)';
        return vm.items.map(schoolDescribe).join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));
}
