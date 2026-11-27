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
