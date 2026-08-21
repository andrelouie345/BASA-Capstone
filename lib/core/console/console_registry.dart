// lib/core/console/console_registry.dart
import 'console_command.dart';

class ConsoleRegistry {
  final Map<String, ConsoleCommand> _commands = {};

  void register(ConsoleCommand command) {
    _commands[command.name] = command;
  }

  List<ConsoleCommand> get all => _commands.values.toList();

  Future<String> execute(String input) async {
    final parts = input.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '';
    final name = parts.first;
    final args = parts.skip(1).toList();

    final command = _commands[name];
    if (command == null) {
      return 'Unknown command: $name (try "help")';
    }
    try {
      return await command.handler(args);
    } catch (e) {
      return 'Error running $name: $e';
    }
  }
}