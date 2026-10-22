// lib/core/console/commands/section_commands.dart

/// Commands for sections
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/section_viewmodel.dart';

void registerSectionCommands(ConsoleRegistry registry, SectionViewModel vm) {

  registry.register(ConsoleCommand(
    name: 'section-list',
    description: 'section-list — list all sections visible to you',
    handler: (_) async {
      try {
        await vm.loadAll();
        if (vm.items.isEmpty) return '(no sections found)';
        return vm.items.map((s) => '${s.id} | $s').join('\n');
      } catch (e) {
        return 'List failed: $e';
      }
    },
  ));
}
