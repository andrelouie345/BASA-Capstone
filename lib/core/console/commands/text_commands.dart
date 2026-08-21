// lib/core/console/commands/text_commands.dart
import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/text_viewmodel.dart';

void registerTextCommands(ConsoleRegistry registry, TextViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'set-text',
    description: 'set-text <value> — replace the current text',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: set-text <value>';
      vm.setText(args.join(' '));
      return 'OK: "${vm.value}"';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'get-text',
    description: 'get-text — show the current text',
    handler: (_) async => 'Text: "${vm.value}"',
  ));

  registry.register(ConsoleCommand(
    name: 'append-text',
    description: 'append-text <value> — append to current text',
    handler: (args) async {
      if (args.isEmpty) return 'Usage: append-text <value>';
      vm.append(args.join(' '));
      return 'OK: "${vm.value}"';
    },
  ));

  registry.register(ConsoleCommand(
    name: 'clear-text',
    description: 'clear-text — reset to empty string',
    handler: (_) async {
      vm.clear();
      return 'Cleared.';
    },
  ));
}