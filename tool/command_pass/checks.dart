// Step checks of the command pass: expect/refuse rules, captures,
// substitution, password masking and the id guard (plan Task 2, D1, D5).
import 'dart:io';

import 'package:basa_capstone/core/console/console_registry.dart';

import 'scenario.dart';

class StepOutcome {
  final bool passed;
  final String message;
  const StepOutcome(this.passed, [this.message = '']);
}

/// What a command produced. [refused]: it threw a ViewModelException (a
/// normal refusal). [crashType]: it threw anything else (always a failure).
class CommandOutput {
  final String text;
  final bool refused;
  final String? crashType;
  const CommandOutput(this.text, {this.refused = false, this.crashType});
}

class MissingCaptureException implements Exception {
  final String name;
  const MissingCaptureException(this.name);
  @override
  String toString() => 'no capture named "$name"';
}

bool _isUsage(String text) => text.trimLeft().startsWith('Usage:');

/// A crash a command file's catch-all printed as text ('<name> failed: <e>',
/// F21): "failed: " followed on the same line by an exception type name.
final _printedCrash = RegExp(r'failed: [^\n]*?\b([A-Z]\w*(?:Exception|Error))\b');

final _logLine = RegExp(r'^\s*\[[A-Za-z]+\]');

/// [expected]: the step's text or pattern; a step that names the type
/// expects that crash text on purpose.
StepOutcome? _crashed(CommandOutput o, String expected) {
  if (o.crashType != null) return StepOutcome(false, 'command crashed (${o.crashType})');
  // Log lines ("[AuthViewModel] ...") carry exception names on purpose; only
  // the answer counts.
  final type = o.text
      .split('\n')
      .where((l) => !_logLine.hasMatch(l))
      .map((l) => _printedCrash.firstMatch(l)?.group(1))
      .firstWhere((t) => t != null, orElse: () => null);
  if (type == null || expected.contains(type)) return null;
  return StepOutcome(false, 'command crashed (printed as text: $type)');
}

StepOutcome? _notASuccess(CommandOutput o) {
  if (o.refused) return const StepOutcome(false, 'command was refused');
  if (_isUsage(o.text)) return const StepOutcome(false, 'usage answer');
  return null;
}

StepOutcome checkExpect(ExpectStep s, CommandOutput o) =>
    _crashed(o, s.text) ??
    _notASuccess(o) ??
    (o.text.contains(s.text) ? const StepOutcome(true) : StepOutcome(false, 'expected "${s.text}"'));

StepOutcome checkExpectRegex(ExpectRegexStep s, CommandOutput o) =>
    _crashed(o, s.pattern.pattern) ??
    _notASuccess(o) ??
    (s.pattern.hasMatch(o.text) ? const StepOutcome(true) : StepOutcome(false, 'expected /${s.pattern.pattern}/'));

/// Many commands return refusals as text, so a plain answer with the text
/// passes too.
StepOutcome checkRefuse(RefuseStep s, CommandOutput o) =>
    _crashed(o, s.text) ??
    (o.text.contains(s.text) ? const StepOutcome(true) : StepOutcome(false, 'expected a refusal with "${s.text}"'));

/// Group 1 of the match, or null when nothing (or nothing usable) matched.
String? capture(CaptureStep s, CommandOutput o) {
  if (o.crashType != null || o.refused) return null;
  final m = s.pattern.firstMatch(o.text);
  if (m == null || m.groupCount < 1) return null;
  final v = m.group(1);
  return (v == null || v.isEmpty) ? null : v;
}

final _placeholder = RegExp(r'\{(=[^}]*|[A-Za-z_][A-Za-z0-9_]*)\}');

/// Replaces `{name}` with its capture and `{=literal}` with the literal.
String substitute(String line, Map<String, String> captures) => line.replaceAllMapped(_placeholder, (m) {
      final key = m.group(1)!;
      if (key.startsWith('=')) return key.substring(1);
      final v = captures[key];
      if (v == null) throw MissingCaptureException(key);
      return v;
    });

final _tempPassword = RegExp(r'(Temporary password: )\S+');

String mask(String text, Iterable<String> secrets) {
  var t = text.replaceAllMapped(_tempPassword, (m) => '${m.group(1)}***');
  for (final s in secrets) {
    if (s.isNotEmpty) t = t.replaceAll(s, '***');
  }
  return t;
}

/// Commands that never write to the server (an `other-school` step may only
/// use these; a command missing from the list counts as a write). Path is
/// relative to the repo root.
Set<String> loadReadOnlyCommands([String path = 'tool/command_pass/readonly_commands.txt']) =>
    File(path).readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty).toSet();

/// The refusal reason, or null when the step may run. Checked on the
/// unsubstituted line.
String? guardIds(RunStep s, {required bool privileged, required Set<String> readOnlyCommands}) {
  final tokens = ConsoleRegistry.tokenize(s.commandLine);
  final command = tokens.isEmpty ? '' : tokens.first;
  if (s.otherSchool) {
    return readOnlyCommands.contains(command)
        ? null
        : 'other-school is for read-only commands; "$command" is not in tool/command_pass/readonly_commands.txt';
  }
  if (!privileged) return null;
  final bare = tokens.skip(1).where((t) => RegExp(r'^\d+$').hasMatch(t)).toList();
  if (bare.isEmpty) return null;
  return 'bare number(s) ${bare.join(', ')} in a privileged step: use a capture {name} or a literal {=n}';
}
