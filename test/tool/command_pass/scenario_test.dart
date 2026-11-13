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

  test('parses device ... fresh', () {
    final s = parseScenario('x', 'device phone tutor fresh\ndevice pc admin');
    expect((s.steps[0] as DeviceStep).fresh, isTrue);
    expect((s.steps[1] as DeviceStep).fresh, isFalse);
    expect(() => parseScenario('x', 'device phone tutor stale'), throwsFormatException);
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

  test('parses make-sf1', () {
    final s = parseScenario('x', 'device pc admin\nmake-sf1 sf1_g7 b 7 ZZTEST-G7 4');
    final m = s.steps[1] as MakeSf1Step;
    expect(m.name, 'sf1_g7');
    expect(m.schoolB, isTrue);
    expect(m.grade, 7);
    expect(m.section, 'ZZTEST-G7');
    expect(m.count, 4);
    expect(m.first, 1);
    final f = parseScenario('x', 'device pc admin\nmake-sf1 sf1_g7c a 7 ZZTEST-G7C 16 from=101').steps[1] as MakeSf1Step;
    expect(f.count, 16);
    expect(f.first, 101);
    expect(() => parseScenario('x', 'make-sf1 f a 7 S 4 from=0'), throwsFormatException);
    expect(() => parseScenario('x', 'make-sf1 f a 7 S 4 101'), throwsFormatException);
    expect(() => parseScenario('x', 'make-sf1 f c 7 S 4'), throwsFormatException);
    expect(() => parseScenario('x', 'make-sf1 f a seven S 4'), throwsFormatException);
    expect(() => parseScenario('x', 'make-sf1 f a 7 S'), throwsFormatException);
  });

  test('parses make-sf1 from=last with an offset', () {
    MakeSf1Step one(String from) => parseScenario('x', 'make-sf1 f a 7 S 2 $from').steps.single as MakeSf1Step;
    expect(one('from=last').lastOffset, 0);
    expect(one('from=last+3').lastOffset, 3);
    expect(one('from=last-4').lastOffset, -4);
    expect(one('from=stamp').lastOffset, isNull);
    expect(() => parseScenario('x', 'make-sf1 f b 7 S 2 from=last'), throwsFormatException);
    expect(() => parseScenario('x', 'make-sf1 f a 7 S 2 from=last*2'), throwsFormatException);
  });

  test('parses make-sf1 lrns=a (school a learners in school b file)', () {
    MakeSf1Step one(String tail) => parseScenario('x', 'make-sf1 f b 7 S 1 $tail').steps.single as MakeSf1Step;
    final t = one('from=last+1 lrns=a');
    expect([t.schoolB, t.aLearners, t.lastOffset], [true, true, 1]);
    expect(one('from=last-4 lrns=a as=7').learnerGrade, 7);
    expect(one('from=3').aLearners, isFalse);
    expect(() => parseScenario('x', 'make-sf1 f a 7 S 1 from=last lrns=a'), throwsFormatException);
    expect(() => parseScenario('x', 'make-sf1 f b 7 S 1 from=last lrns=b'), throwsFormatException);
    expect(() => parseScenario('x', 'make-sf1 f b 7 S 1 from=last lrns=a lrns=a'), throwsFormatException);
  });

  test('parses make-sf1 as=<grade>', () {
    MakeSf1Step one(String tail) => parseScenario('x', 'make-sf1 f a 8 S 2 $tail').steps.single as MakeSf1Step;
    expect(one('as=7').learnerGrade, 7);
    expect([one('from=3 as=7').first, one('from=3 as=7').learnerGrade], [3, 7]);
    expect(one('from=3').learnerGrade, isNull);
    expect(() => parseScenario('x', 'make-sf1 f a 8 S 2 as=x'), throwsFormatException);
    expect(() => parseScenario('x', 'make-sf1 f a 8 S 2 as=7 as=6'), throwsFormatException);
  });

  test('parses make-phil-iri-workbook with one or two sections', () {
    final one = parseScenario('x', 'make-phil-iri-workbook wb 7 ZZTEST-A 3 from=stamp').steps.single as MakePhilIriStep;
    expect([one.workbook, one.section, one.second, one.count, one.first], [true, 'ZZTEST-A', null, 3, 0]);
    final two = parseScenario('x', 'make-phil-iri-workbook wb 7 ZZTEST-A{stamp},ZZTEST-B{stamp} 3').steps.single
        as MakePhilIriStep;
    expect([two.section, two.second, two.first], ['ZZTEST-A{stamp}', 'ZZTEST-B{stamp}', 1]);
    expect(() => parseScenario('x', 'make-phil-iri-workbook wb 7 A,B,C 3'), throwsFormatException);
    expect(() => parseScenario('x', 'make-phil-iri-workbook wb 7 A, 3'), throwsFormatException);
    expect(() => parseScenario('x', 'make-phil-iri-scoresheet ss 7 A,B 3'), throwsFormatException);
  });

  test('parses write-file', () {
    final s = parseScenario('x', 'device pc admin\nwrite-file a3_text The cat  sat {stamp}.');
    final w = s.steps[1] as WriteFileStep;
    expect(w.name, 'a3_text');
    expect(w.text, 'The cat  sat {stamp}.');
    expect(() => parseScenario('x', 'write-file a3_text'), throwsFormatException);
    expect(() => parseScenario('x', 'write-file 3x some text'), throwsFormatException);
    // Not a run: checks can't follow it.
    expect(() => parseScenario('x', 'run whoami\nwrite-file t text\nexpect x'), throwsFormatException);
  });
}
