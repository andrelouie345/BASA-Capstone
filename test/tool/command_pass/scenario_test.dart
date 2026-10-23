// Scenario parser of the command pass (tool/command_pass/scenario.dart).
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/command_pass/scenario.dart';

void main() {
  test('parses every step kind', () {
    final s = parseScenario('t1', '''
device phone tutor
as tutor1
run crla-start {sec} {lrn} bosy
expect Started CRLA
expect~ assessment \\d+
refuse Forbidden
capture crla1 = assessment (\\d+)
sql select count(*) from crla_assessments where id = {crla1} => 1
other-school run school-list
expect ZZTEST
''');
    expect(s.batch, 't1');
    final steps = s.steps;
    expect(steps, hasLength(10));

    final device = steps[0] as DeviceStep;
    expect(device.name, 'phone');
    expect(device.build, 'tutor');
    expect((steps[1] as AsStep).account, 'tutor1');
    final run = steps[2] as RunStep;
    expect(run.commandLine, 'crla-start {sec} {lrn} bosy');
    expect(run.otherSchool, isFalse);
    expect((steps[3] as ExpectStep).text, 'Started CRLA');
    expect((steps[4] as ExpectRegexStep).pattern.pattern, r'assessment \d+');
    expect((steps[5] as RefuseStep).text, 'Forbidden');
    final capture = steps[6] as CaptureStep;
    expect(capture.name, 'crla1');
    expect(capture.pattern.pattern, r'assessment (\d+)');
    final sql = steps[7] as SqlStep;
    expect(sql.query, 'select count(*) from crla_assessments where id = {crla1}');
    expect(sql.expected, '1');
    final other = steps[8] as RunStep;
    expect(other.commandLine, 'school-list');
    expect(other.otherSchool, isTrue);
    expect(steps.map((e) => e.line), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  });

  test('skips comments and blank lines', () {
    final s = parseScenario('x', '# heading\n\nrun whoami\n   \n# note\nexpect Signed in\n');
    expect(s.steps, hasLength(2));
    expect(s.steps[0].line, 3);
    expect(s.steps[1].line, 6);
  });

  test('strips CR from CRLF input', () {
    final s = parseScenario('x', 'run whoami\r\nexpect Signed in\r\n');
    expect((s.steps[1] as ExpectStep).text, 'Signed in');
    expect((s.steps[0] as RunStep).commandLine, 'whoami');
  });

  test('rejects a check before any run', () {
    expect(
      () => parseScenario('b0', 'expect x'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', startsWith('b0:1:'))),
    );
    // A device or account switch ends the run the checks belong to.
    expect(() => parseScenario('b0', 'run whoami\nas tutor1\nexpect x'), throwsFormatException);
  });

  test('rejects an unknown keyword and a bad device build', () {
    expect(() => parseScenario('x', 'launch whoami'), throwsA(isA<FormatException>()
        .having((e) => e.message, 'message', startsWith('x:1:'))));
    expect(() => parseScenario('x', 'device phone teacher'), throwsFormatException);
    expect(() => parseScenario('x', 'device phone'), throwsFormatException);
  });

  test('rejects a bad regex with its line number', () {
    expect(() => parseScenario('x', 'run whoami\nexpect~ (unclosed'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', startsWith('x:2:'))));
    expect(() => parseScenario('x', 'run whoami\ncapture id = [x'), throwsFormatException);
  });

  test('rejects malformed capture and sql lines', () {
    expect(() => parseScenario('x', 'run whoami\ncapture id'), throwsFormatException);
    expect(() => parseScenario('x', 'run whoami\nsql select 1'), throwsFormatException);
    expect(() => parseScenario('x', 'run'), throwsFormatException);
  });
}
