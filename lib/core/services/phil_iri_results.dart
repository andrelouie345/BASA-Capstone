// lib/core/services/phil_iri_results.dart
//
// Turns raw Phil-IRI readings into results: one passage, the rounds of a
// school year (BOSY -> MOSY #1–#3 -> EOSY), the end result, and the adjusted
// grade level. Pure functions; the caller passes the thresholds in force
// (the school's current ones while live, the snapshot once finalized).
//
// Rules from the reading coordinator's workbook (sheets 01–40), with the owner's
// fixes (2026-10-14):
// - Comprehension carries up: a round's comprehension is the higher of its own
//   score and the previous round's, starting from the GST. This also applies
//   BOSY -> MOSY #1 (missing in the workbook: a bug). So a learner is never
//   demoted through comprehension.
// - Word reading (accuracy, speed) may go down; a round with no reading of its
//   own carries the previous round's word reading forward.
// - A Foundational Literacy Test reading has no comprehension; in BOSY the GST
//   supplies it, as in the workbook.
// - End result: EOSY when it was given; otherwise the best of the rounds that
//   were given (ties go to the later round).
// - Only the latest attempt of a round counts; picking it is the caller's job.
import '../models/phil_iri_assessment.dart' show PhilIriRound;
import '../models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'phil_iri_rules.dart';

class PhilIriPassageResult {
  final double wordReadingScore;        // 0–1
  final double wordsPerMinute;
  final PhilIriLevel accuracyLevel;
  final PhilIriSpeed speed;
  final PhilIriLevel wordReadingLevel;
  final double? comprehensionScore;     // 0–1; null when not asked
  final PhilIriLevel? comprehensionLevel;
  final PhilIriLevel profile;
  final bool isStrugglingReader;

  const PhilIriPassageResult({
    required this.wordReadingScore,
    required this.wordsPerMinute,
    required this.accuracyLevel,
    required this.speed,
    required this.wordReadingLevel,
    this.comprehensionScore,
    this.comprehensionLevel,
    required this.profile,
    required this.isStrugglingReader,
  });
}

/// Scores one passage reading.
/// Whole text: accuracy over the passage's words, wpm from the reading time.
/// One minute: accuracy over the words read, wpm = words read.
/// Without comprehension (e.g. FLT) the profile is the word reading level.
PhilIriPassageResult philIriScorePassage({
  required int wordCount,
  required PhilIriReadingMethod method,
  int? readingSeconds,
  int? wordsRead,
  required int countedMiscues,
  int? comprehensionCorrect,
  int? comprehensionTotal,
  PhilIriThresholds t = PhilIriThresholds.defaults,
}) {
  final int words;
  final double wpm;
  switch (method) {
    case PhilIriReadingMethod.wholeText:
      if (readingSeconds == null) throw ArgumentError('readingSeconds is required for whole-text reading');
      words = wordCount;
      wpm = philIriWordsPerMinute(wordCount, readingSeconds);
    case PhilIriReadingMethod.oneMinute:
      if (wordsRead == null || wordsRead <= 0) {
        throw ArgumentError('wordsRead must be positive for one-minute reading');
      }
      words = wordsRead;
      wpm = wordsRead.toDouble();
  }
  if ((comprehensionCorrect == null) != (comprehensionTotal == null)) {
    throw ArgumentError('comprehensionCorrect and comprehensionTotal go together');
  }

  final score = philIriWordReadingScore(words, countedMiscues);
  final accuracy = philIriAccuracyLevel(score, t);
  final speed = philIriSpeed(wpm, t);
  final wordReading = philIriWordReadingLevel(accuracy, speed);
  final comp = comprehensionTotal == null
      ? null
      : philIriComprehensionScore(comprehensionCorrect!, comprehensionTotal);
  final compLevel = comp == null ? null : philIriComprehensionLevel(comp, t);

  return PhilIriPassageResult(
    wordReadingScore: score,
    wordsPerMinute: wpm,
    accuracyLevel: accuracy,
    speed: speed,
    wordReadingLevel: wordReading,
    comprehensionScore: comp,
    comprehensionLevel: compLevel,
    profile: _profile(wordReading, compLevel)!,
    isStrugglingReader: philIriIsStrugglingReader(accuracy, speed),
  );
}

/// Profile from whatever is known: the table when both exist; Non-Reader word
/// reading wins; otherwise whichever side is present.
PhilIriLevel? _profile(PhilIriLevel? wordReading, PhilIriLevel? comprehension) {
  if (wordReading == PhilIriLevel.nonReader) return PhilIriLevel.nonReader;
  if (wordReading == null) return comprehension;
  if (comprehension == null) return wordReading;
  return philIriPassageProfile(wordReading, comprehension);
}

class PhilIriRoundResult {
  final PhilIriRound round;
  final bool given;                     // the round had a reading of its own
  final double? wordReadingScore;       // own, or carried forward
  final double? wordsPerMinute;
  final PhilIriLevel? accuracyLevel;
  final PhilIriSpeed? speed;
  final PhilIriLevel? wordReadingLevel;
  final double? comprehensionScore;     // after carry-up
  final PhilIriLevel? comprehensionLevel;
  final PhilIriLevel? profile;          // null when nothing is known yet
  final bool isStrugglingReader;

  const PhilIriRoundResult({
    required this.round,
    required this.given,
    this.wordReadingScore,
    this.wordsPerMinute,
    this.accuracyLevel,
    this.speed,
    this.wordReadingLevel,
    this.comprehensionScore,
    this.comprehensionLevel,
    this.profile,
    this.isStrugglingReader = false,
  });
}

/// Results for every round of the year, in order. [gstScore] is the GST as a
/// 0–1 fraction (null if not taken); [readings] holds the scored reading that
/// stands for each round that was given (latest attempt).
List<PhilIriRoundResult> philIriRoundResults({
  double? gstScore,
  required Map<PhilIriRound, PhilIriPassageResult> readings,
  PhilIriThresholds t = PhilIriThresholds.defaults,
}) {
  final results = <PhilIriRoundResult>[];
  double? comp = gstScore;
  PhilIriPassageResult? lastReading;

  for (final round in PhilIriRound.values) {
    final own = readings[round];
    if (own != null) lastReading = own;
    final ownComp = own?.comprehensionScore;
    if (ownComp != null && (comp == null || ownComp > comp)) comp = ownComp;

    final compLevel = comp == null ? null : philIriComprehensionLevel(comp, t);
    final wr = lastReading;
    results.add(PhilIriRoundResult(
      round: round,
      given: own != null,
      wordReadingScore: wr?.wordReadingScore,
      wordsPerMinute: wr?.wordsPerMinute,
      accuracyLevel: wr?.accuracyLevel,
      speed: wr?.speed,
      wordReadingLevel: wr?.wordReadingLevel,
      comprehensionScore: comp,
      comprehensionLevel: compLevel,
      profile: _profile(wr?.wordReadingLevel, compLevel),
      isStrugglingReader: wr?.isStrugglingReader ?? false,
    ));
  }
  return results;
}

int _rank(PhilIriLevel? level) => switch (level) {
      PhilIriLevel.independent => 3,
      PhilIriLevel.instructional => 2,
      PhilIriLevel.frustration => 1,
      PhilIriLevel.nonReader => 0,
      null => -1,
    };

/// The year's end result: EOSY when given; otherwise the best given round
/// (later round wins a tie); with no reading at all, BOSY (GST only) if it has
/// a profile; null when nothing is known.
PhilIriRoundResult? philIriEndResult(List<PhilIriRoundResult> rounds) {
  final eosy = rounds.where((r) => r.round == PhilIriRound.eosy && r.given);
  if (eosy.isNotEmpty) return eosy.first;
  PhilIriRoundResult? best;
  for (final r in rounds.where((r) => r.given)) {
    if (best == null || _rank(r.profile) >= _rank(best.profile)) best = r;
  }
  if (best != null) return best;
  final bosy = rounds.where((r) => r.round == PhilIriRound.bosy && r.profile != null);
  return bosy.isEmpty ? null : bosy.first;
}

/// Adjusted grade level (workbook "Adj. Grade Level"), relative to [baseLevel]:
/// Non-Reader 0; Independent base+1; Instructional base; Frustration by
/// comprehension % — ≥ keep-level min stays at base (owner decision), else
/// 1–4 levels down per the thresholds. Never below 1.
/// [comprehensionScore] null on a Frustration profile counts as 1 level down.
int philIriAdjustedLevel(
  PhilIriLevel profile,
  int baseLevel,
  double? comprehensionScore, [
  PhilIriThresholds t = PhilIriThresholds.defaults,
]) {
  final int level;
  switch (profile) {
    case PhilIriLevel.nonReader:
      return 0;
    case PhilIriLevel.independent:
      level = baseLevel + 1;
    case PhilIriLevel.instructional:
      level = baseLevel;
    case PhilIriLevel.frustration:
      if (comprehensionScore == null) {
        level = baseLevel - 1;
      } else {
        final pct = philIriWholePercent(comprehensionScore);
        if (pct >= t.frustrationKeepLevelMin) {
          level = baseLevel;
        } else if (pct <= t.frustrationFourDownMax) {
          level = baseLevel - 4;
        } else if (pct <= t.frustrationThreeDownMax) {
          level = baseLevel - 3;
        } else if (pct <= t.frustrationTwoDownMax) {
          level = baseLevel - 2;
        } else {
          level = baseLevel - 1;
        }
      }
  }
  return level < 1 ? 1 : level;
}

/// Levels below the learner's grade (0 = grade-level ready), or null for a
/// Non-Reader (adjusted level 0).
int? philIriLevelsDown(int adjustedLevel, int learnerGrade) {
  if (adjustedLevel == 0) return null;
  final down = learnerGrade - adjustedLevel;
  return down < 0 ? 0 : down;
}

/// Workbook "Reading Level": GLR at or above grade, 3-LD at 3+ levels down,
/// 2-LD otherwise (the workbook files 1 level down under 2-LD), Non-Reader at 0.
String philIriReadingLevelLabel(int adjustedLevel, int learnerGrade) {
  if (adjustedLevel == 0) return 'Non-Reader';
  if (adjustedLevel >= learnerGrade) return 'GLR';
  if (adjustedLevel <= learnerGrade - 3) return '3-LD';
  return '2-LD';
}
