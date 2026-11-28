// lib/core/services/aral_effectiveness_rules.dart
//
// The no-improvement rule for ARAL learners (spec
// docs/superpowers/specs/2026-11-27-aral-effectiveness-design.md D2-D3).
// One rule, read by AralClassViewModel.noImprovement (and through it the
// tutor and coordinator reminders), so the alerts never disagree.
// Pure Dart: the caller gathers the attendance and the latest check-in.
import '../models/aral_progress.dart';
import 'aral_checkin_rules.dart';

/// A learner's latest check-in as the rule needs it.
class AralCheckinOutcome {
  /// The school's session number for the check-in's checkpoint (16 by default).
  final int afterSession;
  final AralCheckinScore score;

  /// The cut-off that applies today.
  final int passPct;

  /// Every item answered; an unfinished check-in never flags.
  final bool complete;

  const AralCheckinOutcome(
      {required this.afterSession, required this.score, required this.passPct, required this.complete});
}

/// The reasons [p]'s learner is not improving (empty = not flagged), round
/// first. Round: change same or down, and at least [minAttended] sessions
/// attended (present) on or before the latest round ([attendedBeforeLatest]).
/// Check-in: [latestCheckin] complete and below its pass mark. An exited
/// learner is never flagged.
List<AralNoImprovementReason> aralNoImprovementReasons(AralLearnerProgress p,
    {required int attendedBeforeLatest, required int minAttended, AralCheckinOutcome? latestCheckin}) {
  if (p.exited) return const [];
  final out = <AralNoImprovementReason>[];
  final stuck = p.change == AralProgressChange.same || p.change == AralProgressChange.down;
  if (stuck && attendedBeforeLatest >= minAttended) {
    out.add(AralNoImprovementReason(AralNoImprovementKind.round,
        '${p.change.label} since ${p.startRoundLabel}: ${p.startProfile} -> ${p.latestProfile} (${p.latestRoundLabel})'));
  }
  final c = latestCheckin;
  if (c != null && c.complete && !c.score.passes(c.passPct)) {
    out.add(AralNoImprovementReason(AralNoImprovementKind.checkin,
        'Check-in after session ${c.afterSession}: ${c.score.wholePercent}%, pass mark ${c.passPct}%'));
  }
  return out;
}
