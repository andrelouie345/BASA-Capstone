// Which rounds a CRLA or Phil-IRI run records and who records them
// (demo-data plan Task 11). The default is the 2025-2026 behaviour: every
// round the run date reached, every learner of the section, by the section's
// first tutor, the GST with BOSY, time typed in.
import 'world.dart';

class DemoRoundPlan {
  /// Round names to record ('bosy', 'mosy' / 'mosy1', 'eosy'); null = all.
  final Set<String>? rounds;

  /// The learners of a section in the round (default: the world's own list).
  /// 2026-2027 MOSY: without the archived learners, the moved one in Narra.
  final List<DemoLearner> Function(DemoSection s)? roster;

  /// Whether [l] is assessed in [round] (default: everyone).
  final bool Function(DemoLearner l, String round)? assess;

  /// The ARAL class tutor who assesses [l] in [round] (owner 2026-11-26:
  /// MOSY and EOSY by the class tutor); null = the section's first tutor.
  final String? Function(DemoLearner l, String round)? classTutor;

  /// Whether [l] gets a GST with BOSY (default: yes).
  final bool Function(DemoLearner l)? recordGst;

  /// Rounds whose Phil-IRI readings are timed in BASA (the timer log), not
  /// typed in.
  final Set<String> timedRounds;

  const DemoRoundPlan({
    this.rounds,
    this.roster,
    this.assess,
    this.classTutor,
    this.recordGst,
    this.timedRounds = const {},
  });

  bool runs(String round) => rounds == null || rounds!.contains(round);

  List<DemoLearner> learnersOf(DemoWorld w, DemoSection s) => roster?.call(s) ?? w.inSection(s);

  bool assesses(DemoLearner l, String round) => assess?.call(l, round) ?? true;

  String assessorOf(DemoLearner l, DemoSection s, String round) =>
      classTutor?.call(l, round) ?? s.tutorAccounts.first;

  bool gst(DemoLearner l) => recordGst?.call(l) ?? true;
}
