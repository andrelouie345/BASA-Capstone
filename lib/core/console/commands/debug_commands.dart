// lib/core/console/commands/debug_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../console_session.dart';
import '../../viewmodels/viewmodel_registry.dart';

void registerDebugCommands(
  ConsoleRegistry registry,
  ConsoleSession session,
  ViewModelRegistry vmRegistry,
) {
  registry.register(ConsoleCommand(
    name: 'log-filter',
    description: 'log-filter <name|clear> — show logs from one view model only',
    handler: (args) async {
      if (args.isEmpty) {
        return session.currentFilter == null
            ? 'No filter active. Usage: log-filter <name> | log-filter clear'
            : 'Current filter: ${session.currentFilter}';
      }
      if (args.first == 'clear') {
        session.setLogFilter(null);
        return 'Filter cleared.';
      }
      session.setLogFilter(args.first);
      return 'Filtering logs to source: ${args.first}';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'list-viewmodels',
    description: 'list-viewmodels — list all registered view models',
    handler: (_) async {
      if (vmRegistry.names.isEmpty) return 'No view models registered.';
      return vmRegistry.names.join('\n');
    },
  ));
}