// ViewModel messages are read in the app and in the console: they say what to
// do in plain words and put the command name in brackets
// ("Download the latest data (pull-cloud)."), never "run pull-cloud"
// (frontend handoff, spec docs/superpowers/specs/2026-10-25-frontend-handoff-design.md, Q5).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no ViewModel message tells the reader to run a console command', () {
    final consoleWording = RegExp(r'\b[Rr]un [a-z]+(-[a-z]+)+');
    final hits = <String>[];
    for (final dir in ['lib/viewmodels', 'lib/core/viewmodels']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (consoleWording.hasMatch(line)) hits.add('${f.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
