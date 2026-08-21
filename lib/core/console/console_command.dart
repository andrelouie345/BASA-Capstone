// lib/core/console/console_command.dart
typedef CommandHandler = Future<String> Function(List<String> args);

class ConsoleCommand {
  final String name;
  final String description;
  final CommandHandler handler;

  const ConsoleCommand({
    required this.name,
    required this.description,
    required this.handler,
  });
}