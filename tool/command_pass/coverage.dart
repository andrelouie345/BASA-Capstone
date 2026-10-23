// Coverage of the command pass (spec *Coverage*): every command of each build
// must appear in a checked run step on a device of the right build.
import 'scenario.dart';

class CoverageResult {
  final List<String> uncoveredTutor;
  final List<String> uncoveredAdmin;
  final int coveredTutor, totalTutor, coveredAdmin, totalAdmin;
  const CoverageResult({
    required this.uncoveredTutor,
    required this.uncoveredAdmin,
    required this.coveredTutor,
    required this.totalTutor,
    required this.coveredAdmin,
    required this.totalAdmin,
  });
}

/// A run counts when a check (expect, expect~, refuse, sql) follows it before
/// the next run, account or device switch. A scenario starts with no device:
/// runs before its first `device` step count for nothing.
CoverageResult computeCoverage(
  List<Scenario> scenarios, {
  required List<String> tutorCommands,
  required List<String> adminCommands,
}) {
  final onTutor = <String>{};
  final onAdmin = <String>{};
  for (final scenario in scenarios) {
    String? build;
    String? pending; // command of the current run, until a check confirms it
    String? pendingBuild;
    for (final step in scenario.steps) {
      switch (step) {
        case DeviceStep():
          build = step.build;
          pending = null;
        case AsStep():
          pending = null;
        case RunStep():
          final name = step.commandLine.trim().split(RegExp(r'\s+')).first;
          pending = build == null ? null : name;
          pendingBuild = build;
        case ExpectStep() || ExpectRegexStep() || RefuseStep() || SqlStep():
          if (pending != null) (pendingBuild == 'tutor' ? onTutor : onAdmin).add(pending);
        case CaptureStep():
          break;
        case MakeSf1Step() || WriteFileStep():
          pending = null;
      }
    }
  }

  final tutorSet = tutorCommands.toSet();
  final uncoveredTutor = [for (final c in tutorCommands) if (!onTutor.contains(c)) c];
  final uncoveredAdmin = [
    for (final c in adminCommands)
      if (!(onAdmin.contains(c) || (tutorSet.contains(c) && onTutor.contains(c)))) c
  ];
  return CoverageResult(
    uncoveredTutor: uncoveredTutor,
    uncoveredAdmin: uncoveredAdmin,
    coveredTutor: tutorCommands.length - uncoveredTutor.length,
    totalTutor: tutorCommands.length,
    coveredAdmin: adminCommands.length - uncoveredAdmin.length,
    totalAdmin: adminCommands.length,
  );
}
