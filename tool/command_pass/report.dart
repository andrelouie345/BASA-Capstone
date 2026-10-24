// report.md of a command pass run.
import 'checks.dart';
import 'coverage.dart';
import 'runner.dart';
import 'scenario.dart';

String describe(Step s) => switch (s) {
      DeviceStep() => 'device ${s.name} ${s.build}${s.fresh ? ' fresh' : ''}',
      AsStep() => 'as ${s.account}',
      RunStep() => '${s.otherSchool ? 'other-school ' : ''}run ${s.commandLine}',
      ExpectStep() => 'expect ${s.text}',
      ExpectRegexStep() => 'expect~ ${s.pattern.pattern}',
      RefuseStep() => 'refuse ${s.text}',
      CaptureStep() => 'capture ${s.name} = ${s.pattern.pattern}',
      SqlStep() => 'sql ${s.query} => ${s.expected}',
      MakeSf1Step() => 'make-sf1 ${s.name} ${s.schoolB ? 'b' : 'a'} ${s.grade} ${s.section} ${s.count}${s.first == 1 ? '' : ' from=${s.first}'}',
      WriteFileStep() => 'write-file ${s.name} ${s.text}',
    };

// A failed sign-in after a device switch stops the batch: it counts (R1).
bool _counted(StepResult r) => !r.setup || !r.outcome.passed;
/// A failed step, for the report and the exit code alike.
bool isFailed(StepResult r) => _counted(r) && !r.skipped && !r.outcome.passed;

/// `[<covered>/<total> covered, ]<steps> steps, <failed> failed`.
String summaryLine(List<StepResult> results, CoverageResult? cov) {
  final steps = results.where(_counted).length;
  final failed = results.where(isFailed).length;
  final coverage =
      cov == null ? '' : '${cov.coveredTutor + cov.coveredAdmin}/${cov.totalTutor + cov.totalAdmin} covered, ';
  return '$coverage$steps steps, $failed failed';
}

String renderReport(List<StepResult> results, CoverageResult? cov, Iterable<String> secrets) {
  final b = StringBuffer('# Command pass report\n');
  String? batch;
  for (final r in results) {
    if (r.batch != batch) {
      batch = r.batch;
      b.write('\n## $batch\n\n');
    }
    final mark = r.setup
        ? 'SETUP'
        : r.skipped
            ? 'SKIP'
            : r.outcome.passed
                ? 'PASS'
                : 'FAIL';
    final label = r.setup ? 'sign in again after the device switch' : describe(r.step);
    b.write('- $mark L${r.step.line} `${mask(label, secrets)}`');
    if (mark == 'FAIL' || (r.setup && !r.outcome.passed)) {
      b.write(' — ${mask(r.outcome.message, secrets)}\n');
      if (r.output.isNotEmpty) b.write('\n  ```\n${_indent(mask(r.output, secrets))}\n  ```\n');
    } else {
      b.write('\n');
      // The refusal a user would see, for reviewing the messages.
      if (mark == 'PASS' && r.step is RefuseStep && r.output.isNotEmpty) {
        b.write('  > ${mask(r.output.split('\n').first, secrets)}\n');
      }
    }
  }
  if (cov != null) {
    b.write('\n## Coverage\n\n'
        '- tutor build: ${cov.coveredTutor}/${cov.totalTutor}\n'
        '- admin build: ${cov.coveredAdmin}/${cov.totalAdmin}\n');
    if (cov.uncoveredTutor.isNotEmpty) b.write('- UNCOVERED (tutor): ${cov.uncoveredTutor.join(', ')}\n');
    if (cov.uncoveredAdmin.isNotEmpty) b.write('- UNCOVERED (admin): ${cov.uncoveredAdmin.join(', ')}\n');
  }
  b.write('\n**${summaryLine(results, cov)}**\n');
  return b.toString();
}

String _indent(String text) => text.split('\n').map((l) => '  $l').join('\n');
