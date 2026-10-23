// report.md of a command pass run.
import 'checks.dart';
import 'coverage.dart';
import 'runner.dart';
import 'scenario.dart';

String describe(Step s) => switch (s) {
      DeviceStep() => 'device ${s.name} ${s.build}',
      AsStep() => 'as ${s.account}',
      RunStep() => '${s.otherSchool ? 'other-school ' : ''}run ${s.commandLine}',
      ExpectStep() => 'expect ${s.text}',
      ExpectRegexStep() => 'expect~ ${s.pattern.pattern}',
      RefuseStep() => 'refuse ${s.text}',
      CaptureStep() => 'capture ${s.name} = ${s.pattern.pattern}',
      SqlStep() => 'sql ${s.query} => ${s.expected}',
    };

bool _counted(StepResult r) => !r.setup;
bool _failed(StepResult r) => _counted(r) && !r.skipped && !r.outcome.passed;

/// `[<covered>/<total> covered, ]<steps> steps, <failed> failed`.
String summaryLine(List<StepResult> results, CoverageResult? cov) {
  final steps = results.where(_counted).length;
  final failed = results.where(_failed).length;
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
