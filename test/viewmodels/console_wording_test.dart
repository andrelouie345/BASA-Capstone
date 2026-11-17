// ViewModel and model messages are read on screens by tutors and coordinators
// who read English as a second language (owner 2026-11-17, replacing the
// 2026-10-25 handoff rule Q5 that kept the command name in brackets): they
// say what to do in plain words and name the screen to use ("Download the
// latest data", "(Send my work)"), never a console command, neither
// "run pull-cloud" nor "(pull-cloud)". The console has its own help.
// Models are checked too: a screen may show their text (their toString() is
// the console's and is left out).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Adjacent string literals ('… run ' then 'pull-cloud.') are joined first,
  // so a message split over two lines is caught too (joined with a space, so
  // a word after an escaped newline still starts a word).
  final literalJoin = RegExp(r'''(['"])\s*\n\s*(['"])''');

  /// Every source line outside comments, with split literals joined, per file.
  Map<String, String> sources() => {
        for (final dir in ['lib/viewmodels', 'lib/core/viewmodels', 'lib/core/models'])
          for (final f in Directory(dir).listSync(recursive: true).whereType<File>())
            if (f.path.endsWith('.dart'))
              f.path: f
                  .readAsLinesSync()
                  .where((l) => !l.trimLeft().startsWith('//'))
                  .join('\n')
                  .replaceAllMapped(literalJoin, (m) => m[1] == m[2] ? ' ' : m[0]!),
      };

  String lineAt(String code, int i) {
    final start = code.lastIndexOf('\n', i) + 1;
    final end = code.indexOf('\n', i);
    return code.substring(start, end < 0 ? code.length : end).trim();
  }

  test('no ViewModel or model message tells the reader to run a console command', () {
    // "run pull-cloud", "Run \"pull-cloud yes\"", "run `sync-status`".
    final consoleWording = RegExp(r'''\b[Rr]un ["'`]?[a-z]+(-[a-z]+)+''');
    final hits = [
      for (final e in sources().entries)
        for (final m in consoleWording.allMatches(e.value)) '${e.key}: ${lineAt(e.value, m.start)}',
    ];
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('no ViewModel or model message names a console command in brackets', () {
    // The real command names of both builds (the pinned lists), multi-word
    // ones only: "(pull-cloud)", "(sync-upload)", "(aral-class-place)".
    final commands = {
      for (final f in ['test/core/wiring/admin_commands.txt', 'test/core/wiring/tutor_commands.txt'])
        ...File(f).readAsLinesSync().map((l) => l.trim()).where((l) => l.contains('-')),
    };
    final inBrackets = RegExp(r'\(([a-z]+(?:-[a-z]+)+)');
    final hits = <String>[];
    for (final e in sources().entries) {
      for (final m in inBrackets.allMatches(e.value)) {
        if (!commands.contains(m[1])) continue;
        final line = lineAt(e.value, m.start);
        // toString() is the console's own text: skip a match inside one (the
        // nearest member above it is a toString(), not a plain message).
        final above = e.value.substring(0, m.start);
        if (above.lastIndexOf('toString()') > above.lastIndexOf('get message')) continue;
        hits.add('${e.key}: $line');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
