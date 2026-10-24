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
//  * Every learner below grade level is proposed (the 15-per-section cap went
//    with the ARAL classes, 2026-10-24: 15 ACTIVE learners per class,
//    aralClassCap).
//  * Ranking, weakest first. Grades 4-10 (Phil-IRI): word recognition (word
//    reading score), then comprehension, then reading speed. Grades 1-3
//    (CRLA): % of words read correctly, then comprehension, then speed. A
//    class filled from the proposal takes the weakest first.
//  * Grades 1-3 (DepEd Memorandum 064 s. 2025, Encl. 2; owner 2026-10-23):
//    Grade 1 on the CRLA MOSY result, Grades 2-3 on BOSY, in the grade's
//    language (G1 Mother Tongue else Filipino, G2 Filipino, G3 English). Low
//    and High Emerging qualify; Developing and Transitioning only when the
//    school runs the extended program (AralProgramSettings.ks1Extended).
//    Otherwise they stay in the regular class, and an ARAL learner who
//    reaches them exits with classroom support. The program is KS1.
//  * Grades 4-10: the Phil-IRI BOSY result; the program follows the ADJUSTED
//    (reading) level only (bands of 2026-10-18, aralPhilIriPlacement): 0-1
//    Foundational if the school runs a foundational literacy program
//    (AralProgramSettings), else KS1; 2-3 KS1; 4-5 KS2 Basic; 6-7 KS2 Plus;
//    8 KS3 Basic; 9 KS3 Plus.
library;

import '../models/aral_class.dart';
import '../models/aral_enrollment.dart';
import '../models/crla_assessment.dart' show CrlaRound;
import '../models/crla_result.dart';
import 'crla_rules.dart';
import 'phil_iri_results.dart' show PhilIriRoundResult;

/// At most this many ACTIVE learners in one ARAL class (DepEd Memorandum 064
/// s. 2025, Encl. 2 item 7; hard stop on the device and the cloud). Exited
/// learners stay linked to the class but don't count.
const aralClassCap = 15;

/// Why a learner can't go into an ARAL class. School, program and cap are
/// checked in the order of the cloud's aral_check_class_placement
/// (20261024010000); the grade only here, after the program (owner
/// 2026-10-24, G3: another grade joins only when the coordinator confirms it).
enum AralPlacementProblem { otherSchoolOrYear, programMismatch, otherGrade, full }

/// The first reason an active learner of [schoolId]/[schoolYear] in [program]
/// and Grade [grade] can't go into [target], which already holds
/// [activeOthersInClass] other active learners; null = they can. A mixed
/// class takes any program; a learner of another grade than the class's
/// only with [otherGradeOk] (the coordinator's confirmation).
AralPlacementProblem? aralPlacementProblem({
  required AralClass target,
  required int schoolId,
  required String schoolYear,
  required AralClassProgram program,
  required int grade,
  required int activeOthersInClass,
  bool otherGradeOk = false,
}) {
  if (target.schoolId != schoolId || target.schoolYear != schoolYear) return AralPlacementProblem.otherSchoolOrYear;
  if (target.program != null && target.program != program) return AralPlacementProblem.programMismatch;
  if (grade != target.gradeLevel && !otherGradeOk) return AralPlacementProblem.otherGrade;
  if (activeOthersInClass >= aralClassCap) return AralPlacementProblem.full;
  return null;
}

/// The refusal text for [p] ([learner] = "Last, First").
String aralPlacementMessage(AralPlacementProblem p,
        {required String learner, required AralClass target, required int grade, required AralClassProgram program}) =>
    switch (p) {
      AralPlacementProblem.full => 'Class "${target.className}" already has $aralClassCap active ARAL learners.',
      AralPlacementProblem.programMismatch =>
        '$learner is in ${program.label}; class "${target.className}" is ${target.program?.label}.',
      AralPlacementProblem.otherGrade =>
        '$learner is in Grade $grade; class "${target.className}" is for Grade ${target.gradeLevel}.',
      AralPlacementProblem.otherSchoolOrYear =>
        'Class "${target.className}" belongs to another school or school year.',
    };

/// basis_level of a Phil-IRI learner entered while not assessed at all
/// (assumed Frustration, 3 levels down); a real result later replaces the
/// suggestion through applyResults, the basis itself never changes.
const aralNotAssessedLevel = 'not_assessed';

/// The CRLA round a Grade 1-3 learner's ARAL placement comes from.
CrlaRound aralCrlaBasisRound(int grade) => grade == 1 ? CrlaRound.mosy : CrlaRound.bosy;

/// CRLA reading profiles from weakest to strongest (chart order).
const aralCrlaProfileOrder = [
  crlaLowEmerging,
  crlaHighEmerging,
  crlaDeveloping,
  crlaTransitioning,
  crlaAtGradeLevel,
];

/// One Grade [grade] learner's CRLA profile in [round], from their [results]
/// assessed on or before [asOf] (YYYY-MM-DD): the latest attempt with a
/// profile in the grade's language (aralCrlaBasisVariant, the rule the ARAL
/// proposal uses; owner 2026-10-23), or in [variant] (`mt`, `fil`, `eng`) when
/// given. Null = no profile in that language and round. Shared by the ARAL
/// implementation report and the dashboard CRLA trend.
String? aralCrlaLearnerProfile(Iterable<CrlaResult> results, CrlaRound round, String asOf,
    {required int grade, String? variant}) {
  final scored = results
      .where((r) => r.round == round && r.readingProfile != null && r.assessedAt.substring(0, 10).compareTo(asOf) <= 0)
      .toList();
  final v = variant ?? aralCrlaBasisVariant(grade, scored.map((r) => r.subjectVariant).toSet());
  CrlaResult? latest;
  for (final r in scored.where((r) => r.subjectVariant == v)) {
    if (latest == null || r.attemptNo > latest.attemptNo) latest = r;
  }
  return latest?.readingProfile;
}

/// Whether [e] is on the ARAL roster on [day] (YYYY-MM-DD): entered by then
/// and not exited by then (a learner who left later was still in ARAL that
/// day). Tutor reminders and the dashboard.
bool aralActiveOn(AralEnrollment e, String day) => _byDay(e.enteredOn, day) && !aralExitedBy(e, day);

/// Whether [e] left ARAL on or before [day] (YYYY-MM-DD).
bool aralExitedBy(AralEnrollment e, String day) => e.exitedOn != null && _byDay(e.exitedOn!, day);

bool _byDay(String date, String day) =>
    (date.length >= 10 ? date.substring(0, 10) : date).compareTo(day) <= 0;

/// Low and High Emerging qualify; with [extended] (the school's extended
/// KS1 program) Developing and Transitioning too. Never Reading At Grade
/// Level.
bool aralCrlaQualifies(String profile, {bool extended = false}) =>
    profile == crlaLowEmerging ||
    profile == crlaHighEmerging ||
    (extended && (profile == crlaDeveloping || profile == crlaTransitioning));

/// The CRLA variant (`mt`, `fil`, `eng`) whose result places a Grade 1-3
/// learner (Encl. 2 Table 2): Grade 1 Mother Tongue when the learner has an
/// MT result ([variants] = the variants they have results in), else Filipino;
/// Grade 2 Filipino; Grade 3 English. Results in other variants don't count.
String aralCrlaBasisVariant(int grade, Set<String> variants) => switch (grade) {
      1 => variants.contains('mt') ? 'mt' : 'fil',
      2 => 'fil',
      _ => 'eng',
    };

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
/// ks1_extended: the school extends KS1 to Developing and Transitioning
/// learners (DepEd Memorandum 064 s. 2025, Encl. 1 item 7: schools with the
/// needed personnel). Off by default (owner 2026-10-23).
class AralProgramSettings {
  static const foundationalProgramKey = 'foundational_program';
  static const ks1ExtendedKey = 'ks1_extended';
  static const defaults = AralProgramSettings(foundationalProgram: false);

  final bool foundationalProgram;
  final bool ks1Extended;

  const AralProgramSettings({required this.foundationalProgram, this.ks1Extended = false});

  /// Defaults, then [m]'s keys (unknown keys and bad values are ignored).
  factory AralProgramSettings.fromMap(Map<String, Object?> m) {
    final v = m[foundationalProgramKey];
    final k = m[ks1ExtendedKey];
    return AralProgramSettings(
        foundationalProgram: v is bool ? v : defaults.foundationalProgram,
        ks1Extended: k is bool ? k : defaults.ks1Extended);
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

  /// CRLA's pct_correct_words_read is already a fraction (words_read /
  /// word_count, 0-1), like the Phil-IRI word reading score.
  factory AralRankKey.crla({double? pctCorrectWordsRead, int? comprehensionCorrect, double? wpm}) =>
      AralRankKey(pctCorrectWordsRead ?? 0, (comprehensionCorrect ?? 0).toDouble(), wpm ?? 0);

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
