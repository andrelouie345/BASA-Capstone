// lib/core/models/aral_progress.dart
//
// One ARAL class learner's change from their ARAL starting round to their
// latest assessed round (spec docs/superpowers/specs/2026-11-27-aral-class-tutor-design.md D2):
// AralClassViewModel.classProgress. No carried/actual wording: tutors read it.
import 'aral_enrollment.dart';

export 'aral_enrollment.dart' show AralEnrollment;

enum AralProgressChange {
  up('Up'),
  same('Same'),
  down('Down'),
  notAssessedYet('Not assessed yet'),
  noStartingResult('No starting result');

  final String label;
  const AralProgressChange(this.label);
}

/// The numbers behind a profile. CRLA: correct words % (0-100), words per
/// minute, comprehension = questions right. Phil-IRI: word recognition %,
/// words per minute, comprehension %. Null where the round has none.
class AralProgressNumbers {
  final double? correctWordsPct;
  final double? wpm;
  final double? comprehension;
  const AralProgressNumbers({this.correctWordsPct, this.wpm, this.comprehension});

  @override
  String toString() => 'words ${correctWordsPct ?? '-'}%, wpm ${wpm ?? '-'}, comprehension ${comprehension ?? '-'}';
}

class AralLearnerProgress {
  static const crla = 'CRLA';
  static const philIri = 'Phil-IRI';

  final AralEnrollment enrollment;

  /// "LAST, First".
  final String learnerName;
  final int grade;

  /// [crla] (Grades 1-3) or [philIri] (Grades 4-10).
  final String instrument;

  /// The ARAL starting round (`bosy`, `mosy`, `mosy1`-`mosy3`, `eosy`).
  final String startRound;
  final String? startProfile;
  final AralProgressNumbers? startNumbers;

  /// The latest round after the start with a result of the learner's own.
  final String? latestRound;
  final String? latestProfile;
  final AralProgressNumbers? latestNumbers;

  /// The latest round's assessment date (YYYY-MM-DD); null without a latest round.
  final String? latestAssessedOn;
  final AralProgressChange change;

  const AralLearnerProgress({
    required this.enrollment,
    required this.learnerName,
    required this.grade,
    required this.instrument,
    required this.startRound,
    this.startProfile,
    this.startNumbers,
    this.latestRound,
    this.latestProfile,
    this.latestNumbers,
    this.latestAssessedOn,
    required this.change,
  });

  /// A round as screens show it: BOSY, MOSY, MOSY #1-#3, EOSY.
  static String roundLabel(String round) =>
      round.startsWith('mosy') && round.length > 4 ? 'MOSY #${round.substring(4)}' : round.toUpperCase();

  String get startRoundLabel => roundLabel(startRound);
  String? get latestRoundLabel => latestRound == null ? null : roundLabel(latestRound!);

  /// The learner left ARAL (exit date and reason on [enrollment]).
  bool get exited => enrollment.exitedOn != null;

  @override
  String toString() => '$learnerName | Grade $grade $instrument | $startRound ${startProfile ?? '-'} -> '
      '${latestRound ?? '-'} ${latestProfile ?? '-'} | ${change.label}${exited ? ' | exited' : ''}';
}

/// Why a learner is flagged as not improving (spec
/// docs/superpowers/specs/2026-11-27-aral-effectiveness-design.md D2):
/// [round] = same or down since the ARAL start after enough sessions
/// attended; [checkin] = the latest complete check-in below the pass mark.
enum AralNoImprovementKind { round, checkin }

class AralNoImprovementReason {
  final AralNoImprovementKind kind;

  /// Plain words, e.g. "Same since BOSY: Frustration -> Frustration (MOSY #1)".
  final String message;

  const AralNoImprovementReason(this.kind, this.message);

  @override
  String toString() => message;
}

/// One ARAL class learner who is not improving, with their reasons (one or two).
class AralNoImprovement {
  final AralLearnerProgress progress;
  final List<AralNoImprovementReason> reasons;

  const AralNoImprovement(this.progress, this.reasons);

  @override
  String toString() => '${progress.learnerName} | Grade ${progress.grade} ${progress.instrument} | ${reasons.join('; ')}';
}
