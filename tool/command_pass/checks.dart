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
/// F21): "failed: " followed on the same line by an exception type name, or
/// anywhere the text of a Dart error that prints no type name (review P1:
/// StateError "Bad state: ", casts, null checks, ArgumentError, a plain
/// Exception, a thrown non-exception object). Label null = group 1.
final _printedCrashes = <(RegExp, String?)>[
  (RegExp(r'failed: [^\n]*?\b([A-Z]\w*(?:Exception|Error))\b'), null),
  (RegExp(r'\b(RangeError|NoSuchMethodError|LateInitializationError|ConcurrentModificationError)\b'), null),
  (RegExp(r'Bad state: '), 'StateError'),
  (RegExp(r'Null check operator used on a null value'), 'TypeError (null check)'),
  (RegExp(r"is not a subtype of type '"), 'TypeError (cast)'),
  (RegExp(r'Invalid argument(\(s\)| \([^)]*\)): '), 'ArgumentError'),
  (RegExp(r'Unsupported operation: '), 'UnsupportedError'),
  (RegExp(r'(^|[\s:])Exception: '), 'Exception'),
  (RegExp(r"Instance of '"), 'thrown object'),
];

final _logLine = RegExp(r'^\s*\[[A-Za-z]+\]');

/// [expected]: the step's text or pattern; a step that names the type or
/// the crash text expects that crash on purpose.
StepOutcome? _crashed(CommandOutput o, String expected) {
  if (o.crashType != null) return StepOutcome(false, 'command crashed (${o.crashType})');
  // Log lines ("[AuthViewModel] ...") carry exception names on purpose; only
  // the answer counts.
  for (final line in o.text.split('\n').where((l) => !_logLine.hasMatch(l))) {
    for (final (pattern, label) in _printedCrashes) {
      final m = pattern.firstMatch(line);
      if (m == null) continue;
      final type = label ?? m.group(1)!;
      if (expected.contains(type) || expected.contains(m.group(0)!.trim())) continue;
      return StepOutcome(false, 'command crashed (printed as text: $type)');
    }
  }
  return null;
}

/// The crash check alone, for steps that read the output without checking
/// its text (capture, sql).
StepOutcome? crashOutcome(CommandOutput o, [String expected = '']) => _crashed(o, expected);

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
/// passes too. A usage answer passes only a step that expects it (review
/// P3: `refuse cloud` must not pass on `Usage: sign-in <cloud|lan> ...`).
StepOutcome checkRefuse(RefuseStep s, CommandOutput o) =>
    _crashed(o, s.text) ??
    (_isUsage(o.text) && !s.text.startsWith('Usage:') ? const StepOutcome(false, 'usage answer') : null) ??
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
/// [regex]: the line is a pattern, so the values are escaped (a Windows
/// path in {rundir} matches itself).
String substitute(String line, Map<String, String> captures, {bool regex = false}) =>
    line.replaceAllMapped(_placeholder, (m) {
      final key = m.group(1)!;
      final String v;
      if (key.startsWith('=')) {
        v = key.substring(1);
      } else {
        v = captures[key] ?? (throw MissingCaptureException(key));
      }
      return regex ? RegExp.escape(v) : v;
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
  // A bare number, or one passed as key=<n> / key:<n> (review P4); a key
  // starts with a letter, so a time like 08:00 is not an id.
  final bare = tokens.skip(1).where((t) => RegExp(r'^(\d+|[A-Za-z][\w-]*[=:]\d+)$').hasMatch(t)).toList();
  if (bare.isEmpty) return null;
  return 'bare number(s) ${bare.join(', ')} in a privileged step: use a capture {name} or a literal {=n}';
}
