// Step checks of the command pass (tool/command_pass/checks.dart).
import 'dart:io';

import 'package:basa_capstone/core/console/console_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/command_pass/checks.dart';
import '../../../tool/command_pass/scenario.dart';

CommandOutput out(String text, {bool refused = false, String? crash}) =>
    CommandOutput(text, refused: refused, crashType: crash);

void main() {
  group('crash rule', () {
    test('every check fails on a crashed command, even when the text matches', () {
      final crashed = out('Started CRLA assessment 5', crash: 'StateError');
      expect(checkExpect(const ExpectStep(1, 'Started'), crashed).passed, isFalse);
      expect(checkExpectRegex(ExpectRegexStep(1, RegExp('assessment')), crashed).passed, isFalse);
      expect(checkRefuse(const RefuseStep(1, 'Started'), crashed).passed, isFalse);
      expect(checkExpect(const ExpectStep(1, 'Started'), crashed).message, contains('StateError'));
    });

    // F21: catch-alls in command files print '<name> failed: <e>'.
    test('a crash printed as "... failed: <Type>" fails every check', () {
      final printed = out("aral-update failed: type 'Null' is not a subtype of type 'int' (TypeError)");
      expect(checkExpect(const ExpectStep(1, 'aral-update'), printed).passed, isFalse);
      expect(checkRefuse(const RefuseStep(1, 'failed'), printed).passed, isFalse);
      expect(checkRefuse(const RefuseStep(1, 'failed'), printed).message, contains('TypeError'));
      final pg = out('report-settings-set failed: PostgrestException(message: boom, code: 42P01)');
      expect(checkExpectRegex(ExpectRegexStep(1, RegExp('failed')), pg).passed, isFalse);
    });

    test('a step that names the type, or a plain failure text, still passes', () {
      final pg = out('x failed: PostgrestException(message: boom)');
      expect(checkRefuse(const RefuseStep(1, 'PostgrestException'), pg).passed, isTrue);
      expect(checkRefuse(const RefuseStep(1, 'Sign-in failed'), out('Sign-in failed: Invalid login credentials')).passed,
          isTrue);
      expect(checkExpect(const ExpectStep(1, 'Error rate'), out('Import failed: 0 rows. Error rate 0%')).passed,
          isTrue);
    });

    // Review P1: the commonest Dart errors print no type name.
    String textOf(void Function() f) {
      try {
        f();
      } catch (e) {
        return '$e';
      }
      throw StateError('no error');
    }

    test('real error texts without a type name fail every check (P1)', () {
      String? nothing;
      final texts = [
        'aral-update failed: ${StateError('No element')}',
        'aral-update failed: ${textOf(() => (nothing as dynamic) as int)}',
        'aral-update failed: ${textOf(() => nothing!.length)}',
        'aral-update failed: ${ArgumentError.value(3, 'id')}',
        'aral-update failed: ${Exception('boom')}',
        'Could not read the file: ${StateError('closed')}',
      ];
      for (final t in texts) {
        expect(checkExpect(const ExpectStep(1, 'aral-update'), out(t)).passed, isFalse, reason: t);
        expect(checkRefuse(const RefuseStep(1, 'failed'), out(t)).passed, isFalse, reason: t);
        expect(crashOutcome(out(t)), isNotNull, reason: t);
      }
    });

    test('a step that names the crash text expects it on purpose', () {
      expect(checkRefuse(const RefuseStep(1, 'Bad state: closed'), out('x failed: Bad state: closed')).passed, isTrue);
    });

    test('an ordinary answer is not a crash', () {
      expect(crashOutcome(out('Exited: 3 learners. Invalid rows: 0. State: done')), isNull);
    });

    test('a ViewModel log line naming the type is not the answer', () {
      final logged = out('Sign-in failed: Invalid login credentials\n'
          '[AuthViewModel] sign-in failed: AuthApiException(message: Invalid login credentials)');
      expect(checkRefuse(const RefuseStep(1, 'Invalid login credentials'), logged).passed, isTrue);
    });
  });

  group('expect', () {
    test('passes when the text is present', () {
      expect(checkExpect(const ExpectStep(1, 'Started'), out('Started CRLA')).passed, isTrue);
    });

    test('fails when the text is absent', () {
      expect(checkExpect(const ExpectStep(1, 'Started'), out('Nothing')).passed, isFalse);
    });

    test('fails on a usage answer that echoes the word', () {
      final r = checkExpect(const ExpectStep(1, 'Started'), out('Usage: crla-start Started <sectionId>'));
      expect(r.passed, isFalse);
      expect(r.message, contains('usage answer'));
      expect(checkExpectRegex(ExpectRegexStep(1, RegExp('Started')), out('  Usage: x Started')).passed, isFalse);
    });

    test('fails on a refusal', () {
      final refused = out('Forbidden: Started', refused: true);
      expect(checkExpect(const ExpectStep(1, 'Started'), refused).passed, isFalse);
      expect(checkExpectRegex(ExpectRegexStep(1, RegExp('Started')), refused).passed, isFalse);
    });

    test('expect~ matches a regex', () {
      expect(checkExpectRegex(ExpectRegexStep(1, RegExp(r'id \d+')), out('created id 42')).passed, isTrue);
      expect(checkExpectRegex(ExpectRegexStep(1, RegExp(r'id \d+')), out('created id x')).passed, isFalse);
    });
  });

  group('refuse', () {
    test('passes on a ViewModelException with the text', () {
      expect(checkRefuse(const RefuseStep(1, 'Forbidden'), out('Forbidden: superadmin only.', refused: true)).passed,
          isTrue);
    });

    test('passes on a refusal returned as plain text', () {
      expect(checkRefuse(const RefuseStep(1, 'Usage:'), out('Usage: crla-start <sectionId>')).passed, isTrue);
    });

    test('fails on a usage answer unless the step expects the usage line (P3)', () {
      final usage = out('Usage: sign-in <cloud|lan> <email> <password>');
      final r = checkRefuse(const RefuseStep(1, 'cloud'), usage);
      expect(r.passed, isFalse);
      expect(r.message, contains('usage answer'));
      expect(checkRefuse(const RefuseStep(1, 'Usage: sign-in'), usage).passed, isTrue);
    });

    test('fails when the text is absent', () {
      expect(checkRefuse(const RefuseStep(1, 'Forbidden'), out('Created school 5', refused: false)).passed, isFalse);
      expect(checkRefuse(const RefuseStep(1, 'Forbidden'), out('Not allowed', refused: true)).passed, isFalse);
    });
  });

  group('capture', () {
    test('returns group 1', () {
      expect(capture(CaptureStep(1, 'id', RegExp(r'assessment (\d+)')), out('Started assessment 77.')), '77');
    });

    test('returns null when nothing matches or the group is empty', () {
      expect(capture(CaptureStep(1, 'id', RegExp(r'assessment (\d+)')), out('Usage: crla-start')), isNull);
      expect(capture(CaptureStep(1, 'id', RegExp(r'id=(\d*)')), out('id=')), isNull);
    });

    test('returns null on a crashed or refused command', () {
      expect(capture(CaptureStep(1, 'id', RegExp(r'(\d+)')), out('5', crash: 'TypeError')), isNull);
      expect(capture(CaptureStep(1, 'id', RegExp(r'(\d+)')), out('Forbidden 5', refused: true)), isNull);
    });
  });

  group('substitute', () {
    test('fills captures', () {
      expect(substitute('crla-start {sec} {lrn} bosy', {'sec': '41', 'lrn': '999000070001'}),
          'crla-start 41 999000070001 bosy');
    });

    test('fills literals', () {
      expect(substitute('aral-idle-days-set {school} {=10}', {'school': '9'}), 'aral-idle-days-set 9 10');
    });

    test('throws on a missing capture', () {
      expect(() => substitute('crla-start {sec} {lrn}', {'sec': '41'}),
          throwsA(isA<MissingCaptureException>().having((e) => e.name, 'name', 'lrn')));
    });

    test('regex mode escapes the filled values, not the pattern', () {
      final pattern = substitute(r'saved to {dir}\\\S+ \((\d+) rows\)', {'dir': r'D:\x\r7 (b)'}, regex: true);
      final m = RegExp(pattern).firstMatch(r'saved to D:\x\r7 (b)\out.csv (12 rows)');
      expect(m?.group(1), '12');
    });

    test('keeps quoted Windows paths as one argument', () {
      final line = substitute(r'import-students "{dir}\sf1 g2.xlsx"', {'dir': r'D:\x\r7'});
      expect(line, r'import-students "D:\x\r7\sf1 g2.xlsx"');
      expect(ConsoleRegistry.tokenize(line), ['import-students', r'D:\x\r7\sf1 g2.xlsx']);
    });
  });

  group('mask', () {
    test('masks a temporary password', () {
      expect(mask(r'Temporary password: Ab3$xyz (shown once)', ['secret1']), 'Temporary password: *** (shown once)');
    });

    test('masks known secrets anywhere', () {
      expect(mask('sign-in cloud a@b.c secret1 ok secret1', ['secret1', '']), 'sign-in cloud a@b.c *** ok ***');
    });
  });

  group('guardIds', () {
    const reads = {'section-list', 'school-list'};

    test('refuses a bare integer in a privileged step', () {
      expect(guardIds(const RunStep(1, 'section-delete 28'), privileged: true, readOnlyCommands: reads), isNotNull);
    });

    test('allows captures and explicit literals', () {
      expect(guardIds(const RunStep(1, 'section-delete {sec_g7}'), privileged: true, readOnlyCommands: reads), isNull);
      expect(guardIds(const RunStep(1, 'aral-idle-days-set {school} {=10}'), privileged: true, readOnlyCommands: reads),
          isNull);
    });

    test('ignores tokens that only contain digits', () {
      expect(
          guardIds(const RunStep(1, 'calendar-set {school} 2026-10-23 0.85 r7 "Grade 7"'),
              privileged: true, readOnlyCommands: reads),
          isNull);
    });

    test('refuses an id passed as key=<n> or key:<n> (P4)', () {
      for (final line in ['aral-enroll {s} class=123', 'aral-material-set material=7 x', 'dashboard school:6']) {
        expect(guardIds(RunStep(1, line), privileged: true, readOnlyCommands: reads), isNotNull, reason: line);
      }
      for (final line in ['aral-enroll {s} class={c}', 'srp-add x time=08:00', 'progress done={=0.9} asof=2026-10-23']) {
        expect(guardIds(RunStep(1, line), privileged: true, readOnlyCommands: reads), isNull, reason: line);
      }
    });

    test('does not guard non-privileged steps', () {
      expect(guardIds(const RunStep(1, 'section-delete 28'), privileged: false, readOnlyCommands: reads), isNull);
    });

    test('refuses other-school on any command not known to be read-only, for every account', () {
      expect(guardIds(const RunStep(1, 'section-delete 28', otherSchool: true), privileged: true, readOnlyCommands: reads),
          isNotNull);
      expect(guardIds(const RunStep(1, 'section-delete 28', otherSchool: true), privileged: false, readOnlyCommands: reads),
          isNotNull);
      // A write whose name has no write keyword is still refused.
      expect(guardIds(const RunStep(1, 'sync-upload', otherSchool: true), privileged: false, readOnlyCommands: reads),
          isNotNull);
    });

    test('allows other-school on a read command, numbers included', () {
      expect(guardIds(const RunStep(1, 'section-list 6', otherSchool: true), privileged: true, readOnlyCommands: reads),
          isNull);
    });
  });

  test('the read-only list names only real, sorted commands', () {
    final all = File('test/core/wiring/admin_commands.txt').readAsLinesSync().where((l) => l.isNotEmpty).toSet();
    final reads = loadReadOnlyCommands();
    expect(reads, isNotEmpty);
    expect(reads.difference(all), isEmpty);
    final lines = File('tool/command_pass/readonly_commands.txt').readAsLinesSync().where((l) => l.isNotEmpty).toList();
    expect(lines, [...lines]..sort());
    for (final w in ['sync-upload', 'crla-part1', 'phil-iri-answer', 'aral-log', 'section-delete']) {
      expect(reads, isNot(contains(w)));
    }
  });
}
