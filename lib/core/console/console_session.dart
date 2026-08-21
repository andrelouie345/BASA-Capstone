// lib/core/console/console_session.dart
import 'console_registry.dart';
import 'console_command.dart';
import 'logger.dart';

enum ConsoleEntryType { input, result, log }

class ConsoleEntry {
  final ConsoleEntryType type;
  final String message;
  final String? source;
  ConsoleEntry({required this.type, required this.message, this.source});
}

class ConsoleSession implements Logger {
  final ConsoleRegistry registry;
  final List<ConsoleEntry> entries = [];
  final List<void Function()> _listeners = [];
  String? _logFilter;

  ConsoleSession(this.registry) {
    registry.register(ConsoleCommand(
      name: 'help',
      description: 'List all commands',
      handler: (_) async =>
          registry.all.map((c) => '${c.name} — ${c.description}').join('\n'),
    ));
  }

  String? get currentFilter => _logFilter;

  void setLogFilter(String? source) {
    _logFilter = source;
    _notify();
  }

  List<ConsoleEntry> get visibleEntries => entries.where((e) {
        if (e.type != ConsoleEntryType.log) return true;
        if (_logFilter == null) return true;
        return e.source?.toLowerCase() == _logFilter!.toLowerCase();
      }).toList();

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void _notify() {
    for (final l in _listeners) {
      l();
    }
  }

  Future<void> run(String input) async {
    entries.add(ConsoleEntry(type: ConsoleEntryType.input, message: '> $input'));
    final result = await registry.execute(input);
    if (result.isNotEmpty) {
      entries.add(ConsoleEntry(type: ConsoleEntryType.result, message: result));
    }
    _notify();
  }

  @override
  void log(String source, String message) {
    entries.add(ConsoleEntry(type: ConsoleEntryType.log, message: message, source: source));
    _notify();
  }
}