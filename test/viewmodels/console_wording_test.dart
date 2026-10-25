// ViewModel messages are read in the app and in the console: they say what to
// do in plain words and put the command name in brackets
// ("Download the latest data (pull-cloud)."), never "run pull-cloud"
// (frontend handoff, spec docs/superpowers/specs/2026-10-25-frontend-handoff-design.md, Q5).
// Models are checked too: a screen may show their text (e.g. toString()).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no ViewModel or model message tells the reader to run a console command', () {
    // "run pull-cloud", "Run \"pull-cloud yes\"", "run `sync-status`".
    final consoleWording = RegExp(r'''\b[Rr]un ["'`]?[a-z]+(-[a-z]+)+''');
    // Adjacent string literals ('… run ' then 'pull-cloud.') are joined first,
    // so a message split over two lines is caught too (joined with a space, so
    // a word after an escaped newline still starts a word).
    final literalJoin = RegExp(r'''(['"])\s*\n\s*(['"])''');
    final hits = <String>[];
    for (final dir in ['lib/viewmodels', 'lib/core/viewmodels', 'lib/core/models']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final code = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n')
            .replaceAllMapped(literalJoin, (m) => m[1] == m[2] ? ' ' : m[0]!);
        for (final m in consoleWording.allMatches(code)) {
          final start = code.lastIndexOf('\n', m.start) + 1;
          final end = code.indexOf('\n', m.end);
          hits.add('${f.path}: ${code.substring(start, end < 0 ? code.length : end).trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
