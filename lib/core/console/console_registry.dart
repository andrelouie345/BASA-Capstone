// lib/core/console/console_registry.dart
import 'console_command.dart';

class ConsoleRegistry {
  final Map<String, ConsoleCommand> _commands = {};

  void register(ConsoleCommand command) {
    _commands[command.name] = command;
  }

  List<ConsoleCommand> get all => _commands.values.toList();

  Future<String> execute(String input) async {
    final parts = tokenize(input);
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

  /// Splits on whitespace, except inside double quotes:
  /// `section-create 6 "2025 - 2026" 7 "St. Jude"` -> 5 tokens, quotes
  /// dropped. `""` is an empty argument. A quote that doesn't start a token
  /// (abc"def) or is never closed is kept as a literal character.
  static List<String> tokenize(String input) => RegExp(r'"([^"]*)"(?=\s|$)|\S+')
      .allMatches(input)
      .map((m) => m.group(1) ?? m.group(0)!)
      .toList();
}