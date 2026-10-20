// lib/core/services/aral_rules.dart
//
// Who BASA proposes for ARAL-Reading, and in which program. Pure functions;
// the coordinator may change a learner's program (owner, 2026-10-15).
//
// Rules from the reading coordinator (2026-10-15), replacing the first version
// taken from the DepEd orientation decks:
//  * ARAL-Reading is remediation: only learners reading BELOW grade level
//    qualify. Grade-level-ready (enrichment) and advanced (enhancement)
//    readers are school reading programs, not ARAL.
//  * A section sends at most 15 learners (aralSectionCap): the lowest
//    performers. Fewer qualify -> fewer are proposed.
//  * Ranking, weakest first. Grades 4-10 (Phil-IRI): word recognition (word
//    reading score), then comprehension, then reading speed. Grades 1-3
//    (CRLA): % of words read correctly, then comprehension, then speed. A tie
//    left at the 15th place is the coordinator's pick.
//  * Grades 1-3: Grade 1 on the CRLA MOSY result, Grades 2-3 on BOSY; every
//    profile below "Reading At Grade Level" qualifies; the program is KS1.
//  * Grades 4-10: the Phil-IRI BOSY result; the program follows the ADJUSTED
//    (reading) level only (bands of 2026-10-18, aralPhilIriPlacement): 0-1
//    Foundational if the school runs a foundational literacy program
//    (AralProgramSettings), else KS1; 2-3 KS1; 4-5 KS2 Basic; 6-7 KS2 Plus;
//    8 KS3 Basic; 9 KS3 Plus.
library;

import '../models/aral_enrollment.dart';
import '../models/crla_assessment.dart' show CrlaRound;
import '../models/crla_result.dart';
import 'crla_rules.dart';
import 'phil_iri_results.dart' show PhilIriRoundResult;

/// At most this many learners of one section are in ARAL at a time.
const aralSectionCap = 15;

/// basis_level of a Phil-IRI learner entered while not assessed at all
/// (assumed Frustration, 3 levels down); a real result later replaces the
/// suggestion through applyResults, the basis itself never changes.
const aralNotAssessedLevel = 'not_assessed';

/// The CRLA round a Grade 1-3 learner's ARAL placement comes from.
CrlaRound aralCrlaBasisRound(int grade) => grade == 1 ? CrlaRound.mosy : CrlaRound.bosy;

/// CRLA reading profiles from weakest to strongest (for choosing between
/// variants and for the qualification rule).
const aralCrlaProfileOrder = [
  crlaLowEmerging,
  crlaHighEmerging,
  crlaDeveloping,
  crlaTransitioning,
  crlaAtGradeLevel,
];

/// The weaker of two CRLA profiles (a learner assessed in two variants is
/// placed on the one that shows more need). Unknown profiles lose.
String? aralWeakerCrlaProfile(String? a, String? b) {
  int rank(String? p) {
    if (p == null) return 99;
    return aralCrlaProfileOrder.contains(p) ? aralCrlaProfileOrder.indexOf(p) : 98;
  }
  return rank(a) <= rank(b) ? a : b;
}

/// One learner's CRLA profile in [round], from their [results] assessed on or
/// before [asOf] (YYYY-MM-DD): the latest attempt with a profile per variant,
/// then the weakest of those. [variant] (`mt`, `fil`, `eng`) keeps only that
/// variant's latest attempt. Null = no profile in that round. Shared by the
/// ARAL implementation report and the dashboard CRLA trend.
String? aralCrlaLearnerProfile(Iterable<CrlaResult> results, CrlaRound round, String asOf, {String? variant}) {
  final latest = <String, CrlaResult>{};
  for (final r in results) {
    if (r.round != round || r.readingProfile == null || r.assessedAt.substring(0, 10).compareTo(asOf) > 0) continue;
    if (variant != null && r.subjectVariant != variant) continue;
    final prev = latest[r.subjectVariant];
    if (prev == null || r.attemptNo > prev.attemptNo) latest[r.subjectVariant] = r;
  }
  String? weakest;
  for (final r in latest.values) {
    weakest = weakest == null ? r.readingProfile : aralWeakerCrlaProfile(r.readingProfile, weakest);
  }
  return weakest;
}

/// Whether [e] is on the ARAL roster on [day] (YYYY-MM-DD): entered by then
/// and not exited by then (a learner who left later was still in ARAL that
/// day). Tutor reminders and the dashboard.
bool aralActiveOn(AralEnrollment e, String day) => _byDay(e.enteredOn, day) && !aralExitedBy(e, day);

/// Whether [e] left ARAL on or before [day] (YYYY-MM-DD).
bool aralExitedBy(AralEnrollment e, String day) => e.exitedOn != null && _byDay(e.exitedOn!, day);

bool _byDay(String date, String day) =>
    (date.length >= 10 ? date.substring(0, 10) : date).compareTo(day) <= 0;

/// Every CRLA profile below "Reading At Grade Level" qualifies.
bool aralCrlaQualifies(String profile) =>
    aralCrlaProfileOrder.contains(profile) && profile != crlaAtGradeLevel;

class AralPlacement {
  final AralKeyStage keyStage;
  final AralTrack? track; // null for Foundational and KS1
  const AralPlacement(this.keyStage, [this.track]);

  String get label => track == null ? keyStage.label : '${keyStage.label} ${track!.label}';

  @override
  bool operator ==(Object other) => other is AralPlacement && other.keyStage == keyStage && other.track == track;
  @override
  int get hashCode => Object.hash(keyStage, track);
}

/// Grades 1-3 (CRLA) are always KS1.
const aralCrlaPlacement = AralPlacement(AralKeyStage.ks1);

/// The program for a Phil-IRI reading level ([adjustedLevel], 0 = non-reader)
/// of a [grade] learner; null when the learner reads at or above grade level
/// (grade-level ready: enrichment, not ARAL). Reading coordinator's bands
/// (2026-10-18), the same for the program and its materials:
/// 0-1 Foundational (SHARP or another foundational literacy program) when the
/// school runs one ([foundationalProgram]), else KS1; 2-3 KS1; 4-5 KS2 Basic;
/// 6-7 KS2 Plus (7 is one step below KS3 Basic on purpose: moved up if too
/// easy); 8 KS3 Basic; 9 and up KS3 Plus.
AralPlacement? aralPhilIriPlacement({
  required int adjustedLevel,
  required int grade,
  bool foundationalProgram = false,
}) {
  if (adjustedLevel >= grade && adjustedLevel > 0) return null;
  if (adjustedLevel <= 1) {
    return foundationalProgram
        ? const AralPlacement(AralKeyStage.foundational)
        : const AralPlacement(AralKeyStage.ks1);
  }
  if (adjustedLevel <= 3) return const AralPlacement(AralKeyStage.ks1);
  if (adjustedLevel <= 5) return const AralPlacement(AralKeyStage.ks2, AralTrack.basic);
  if (adjustedLevel <= 7) return const AralPlacement(AralKeyStage.ks2, AralTrack.plus);
  if (adjustedLevel == 8) return const AralPlacement(AralKeyStage.ks3, AralTrack.basic);
  return const AralPlacement(AralKeyStage.ks3, AralTrack.plus);
}

/// ARAL program settings (keys of aral_settings.settings; defaults <- region
/// <- school, like the check-in cut-off). foundational_program: the school
/// runs SHARP or another foundational literacy program for learners reading
/// at levels 0-1 (and keeps a readability log of the materials used). Off by
/// default, which follows the current ARAL program guidelines (those learners
/// go to KS1). The coordinator switches it (reading coordinator 2026-10-18).
class AralProgramSettings {
  static const foundationalProgramKey = 'foundational_program';
  static const defaults = AralProgramSettings(foundationalProgram: false);

  final bool foundationalProgram;

  const AralProgramSettings({required this.foundationalProgram});

  /// Defaults, then [m]'s keys (unknown keys and bad values are ignored).
  factory AralProgramSettings.fromMap(Map<String, Object?> m) {
    final v = m[foundationalProgramKey];
    return AralProgramSettings(foundationalProgram: v is bool ? v : defaults.foundationalProgram);
  }
}

/// ARAL session settings (keys of aral_settings.settings; defaults <- region
/// <- school). idle_session_days: a tutor with active ARAL learners gets a "no
/// session lately" reminder when their last session is more than this many
/// days ago (dashboard D3). A whole number 1-60, default 7.
class AralSessionSettings {
  static const idleSessionDaysKey = 'idle_session_days';
  static const minIdleSessionDays = 1;
  static const maxIdleSessionDays = 60;
  static const defaults = AralSessionSettings(idleSessionDays: 7);

  final int idleSessionDays;

  const AralSessionSettings({required this.idleSessionDays});

  /// Defaults, then [m]'s keys (unknown keys and bad values are ignored).
  factory AralSessionSettings.fromMap(Map<String, Object?> m) {
    final v = m[idleSessionDaysKey];
    return AralSessionSettings(
        idleSessionDays: v is num && v == v.roundToDouble() && v >= minIdleSessionDays && v <= maxIdleSessionDays
            ? v.toInt()
            : defaults.idleSessionDays);
  }
}

/// Why a Phil-IRI result is outside ARAL (reads at or above grade level).
String aralNotAralLabel(int adjustedLevel, int grade) =>
    adjustedLevel > grade ? 'advanced reader (enhancement, not ARAL)' : 'grade-level ready (enrichment, not ARAL)';

/// What the ranking compares, weakest first: word recognition, then
/// comprehension, then speed (each 0 when unknown).
class AralRankKey implements Comparable<AralRankKey> {
  final double wordRecognition; // Phil-IRI word reading score / CRLA % correct, 0-1
  final double comprehension;   // 0-1 (Phil-IRI) or items correct (CRLA)
  final double speed;           // words per minute

  const AralRankKey(this.wordRecognition, this.comprehension, this.speed);

  factory AralRankKey.philIri(PhilIriRoundResult r) =>
      AralRankKey(r.wordReadingScore ?? 0, r.comprehensionScore ?? 0, r.wordsPerMinute ?? 0);

  /// CRLA's pct_correct_words_read is a percent (0-100).
  factory AralRankKey.crla({double? pctCorrectWordsRead, int? comprehensionCorrect, double? wpm}) =>
      AralRankKey((pctCorrectWordsRead ?? 0) / 100, (comprehensionCorrect ?? 0).toDouble(), wpm ?? 0);

  @override
  int compareTo(AralRankKey o) {
    final a = wordRecognition.compareTo(o.wordRecognition);
    if (a != 0) return a;
    final b = comprehension.compareTo(o.comprehension);
    if (b != 0) return b;
    return speed.compareTo(o.speed);
  }

  @override
  bool operator ==(Object other) => other is AralRankKey && compareTo(other) == 0;
  @override
  int get hashCode => Object.hash(wordRecognition, comprehension, speed);
}

/// Picks up to [seats] of [keys] (qualifying learners), weakest first.
/// Returns, per index into [keys], its rank (1 = weakest) and whether it is
/// in, out, or tied at the cut-off (learners equal to the last seat but not
/// all fitting: the coordinator picks among them).
List<({int rank, AralSeat seat})> aralPickSeats(List<AralRankKey> keys, int seats) {
  final order = List<int>.generate(keys.length, (i) => i)..sort((a, b) => keys[a].compareTo(keys[b]));
  final out = List<({int rank, AralSeat seat})>.filled(keys.length, (rank: 0, seat: AralSeat.out));
  if (seats < 0) seats = 0;
  final cutoff = seats > 0 && seats < order.length ? keys[order[seats - 1]] : null;
  final tieSpansCut = cutoff != null && keys[order[seats]] == cutoff;
  for (var pos = 0; pos < order.length; pos++) {
    final i = order[pos];
    // Ranks are shared by equal keys (1, 2, 2, 4 ...).
    final rank = pos > 0 && keys[order[pos - 1]] == keys[i] ? out[order[pos - 1]].rank : pos + 1;
    final AralSeat seat;
    if (tieSpansCut && keys[i] == cutoff) {
      seat = AralSeat.tie;
    } else {
      seat = pos < seats ? AralSeat.inside : AralSeat.out;
    }
    out[i] = (rank: rank, seat: seat);
  }
  return out;
}

enum AralSeat { inside, tie, out }
