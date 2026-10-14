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
// - Every assessment is ONE passage of the learner's own grade; the adjusted
//   grade level is counted from the learner's grade.
// - A blank comprehension counts as 0 (owner 2026-10-14) but stays
//   distinguishable from a real 0: the score stays null and
//   comprehensionBlank is true (the workbook used 0.1 / 0.2 markers).
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
  final double? comprehensionScore;     // 0–1; null = blank (not asked/recorded)
  final PhilIriLevel comprehensionLevel; // a blank counts as 0
  final PhilIriLevel profile;
  final bool isStrugglingReader;

  bool get comprehensionBlank => comprehensionScore == null;

  const PhilIriPassageResult({
    required this.wordReadingScore,
    required this.wordsPerMinute,
    required this.accuracyLevel,
    required this.speed,
    required this.wordReadingLevel,
    this.comprehensionScore,
    required this.comprehensionLevel,
    required this.profile,
    required this.isStrugglingReader,
  });
}

/// Scores one passage reading.
/// Whole text: accuracy over the passage's words, wpm from the reading time.
/// One minute: accuracy over the words read, wpm = words read.
/// Without comprehension (e.g. FLT) the comprehension counts as 0.
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
  final compLevel = philIriComprehensionLevel(comp ?? 0, t);

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
/// reading wins; with only a GST (no reading yet) the comprehension level.
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
  final double? comprehensionScore;     // after carry-up; null = blank (counts as 0)
  final PhilIriLevel? comprehensionLevel;
  final PhilIriLevel? profile;          // null when nothing is known yet
  final bool isStrugglingReader;
  final int? adjustedLevel;             // 1–12; 0 only for a Non-Reader
  final int? levelsDown;                // null for a Non-Reader

  bool get comprehensionBlank => comprehensionScore == null;

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
    this.adjustedLevel,
    this.levelsDown,
  });
}

/// Results for every round of the year, in order. [gstScore] is the GST as a
/// 0–1 fraction (null if not taken); [readings] holds the scored reading that
/// stands for each round that was given (latest attempt), each scored with
/// that round's thresholds. [roundThresholds] overrides [t] per round (a
/// finalized round's snapshot).
List<PhilIriRoundResult> philIriRoundResults({
  required int learnerGrade,
  double? gstScore,
  required Map<PhilIriRound, PhilIriPassageResult> readings,
  PhilIriThresholds t = PhilIriThresholds.defaults,
  Map<PhilIriRound, PhilIriThresholds> roundThresholds = const {},
}) {
  final results = <PhilIriRoundResult>[];
  double? comp = gstScore;
  PhilIriPassageResult? lastReading;

  for (final round in PhilIriRound.values) {
    final own = readings[round];
    if (own != null) lastReading = own;
    // A finalized round keeps the thresholds it was finalized with.
    final rt = roundThresholds[round] ?? t;
    final ownComp = own?.comprehensionScore;
    if (ownComp != null && (comp == null || ownComp > comp)) comp = ownComp;

    final wr = lastReading;
    // A blank counts as 0 once there is a reading; with nothing at all the
    // round stays unknown.
    final compLevel = comp != null
        ? philIriComprehensionLevel(comp, rt)
        : (wr != null ? philIriComprehensionLevel(0, rt) : null);
    final profile = _profile(wr?.wordReadingLevel, compLevel);
    final struggling = wr?.isStrugglingReader ?? false;
    final adjusted = profile == null
        ? null
        : philIriAdjustedLevel(profile, learnerGrade, comp, rt);
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
      profile: profile,
      isStrugglingReader: struggling,
      adjustedLevel: adjusted,
      levelsDown: adjusted == null
          ? null
          : philIriLevelsDown(adjusted, learnerGrade, nonReader: profile == PhilIriLevel.nonReader),
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

/// Adjusted grade level (workbook "Adj. Grade Level"), counted from the
/// learner's current grade: Non-Reader 0; Independent grade+1; Instructional
/// grade; Frustration by comprehension % — ≥ keep-level min stays at grade
/// (owner decision), else 1–4 levels down per the thresholds. A blank
/// comprehension (null) counts as 0.
/// Bounds (owner 2026-10-14): never above Grade 12; below Grade 1 becomes
/// Grade 1, the lowest grade. 0 is reserved for Non-Readers: a Struggling
/// Reader is not a Non-Reader and also bottoms out at Grade 1.
int philIriAdjustedLevel(
  PhilIriLevel profile,
  int learnerGrade,
  double? comprehensionScore, [
  PhilIriThresholds t = PhilIriThresholds.defaults,
]) {
  final int level;
  switch (profile) {
    case PhilIriLevel.nonReader:
      return 0;
    case PhilIriLevel.independent:
      level = learnerGrade + 1;
    case PhilIriLevel.instructional:
      level = learnerGrade;
    case PhilIriLevel.frustration:
      final pct = philIriWholePercent(comprehensionScore ?? 0);
      if (pct >= t.frustrationKeepLevelMin) {
        level = learnerGrade;
      } else if (pct <= t.frustrationFourDownMax) {
        level = learnerGrade - 4;
      } else if (pct <= t.frustrationThreeDownMax) {
        level = learnerGrade - 3;
      } else if (pct <= t.frustrationTwoDownMax) {
        level = learnerGrade - 2;
      } else {
        level = learnerGrade - 1;
      }
  }
  if (level > philIriMaxGrade) return philIriMaxGrade;
  if (level < 1) return 1;
  return level;
}

/// Levels below the learner's grade (0 = grade-level ready), or null for a
/// Non-Reader.
int? philIriLevelsDown(int adjustedLevel, int learnerGrade, {required bool nonReader}) {
  if (nonReader) return null;
  final down = learnerGrade - adjustedLevel;
  return down < 0 ? 0 : down;
}

/// Exact label: "Non-Reader", "GLR", or "N-LD" (1-LD, 2-LD, ...).
String philIriLevelsDownLabel(int? levelsDown) {
  if (levelsDown == null) return 'Non-Reader';
  if (levelsDown == 0) return 'GLR';
  return '$levelsDown-LD';
}

/// Report label, grouped per the thresholds. Default groups [2]: 1–2 down
/// -> "2-LD", 3+ -> "3-LD" (Phil-IRI reports only have 2-LD and 3-LD).
/// Each group is named after its highest level; the open last group after
/// its lowest. With grouping off this is the exact label.
String philIriReportGroup(int? levelsDown,
    [PhilIriThresholds t = PhilIriThresholds.defaults]) {
  if (levelsDown == null || levelsDown == 0 || !t.groupLevelsDown) {
    return philIriLevelsDownLabel(levelsDown);
  }
  for (final upper in t.levelsDownGroups) {
    if (levelsDown <= upper) return '$upper-LD';
  }
  final open = t.levelsDownGroups.isEmpty ? 1 : t.levelsDownGroups.last + 1;
  return '$open-LD';
}

/// K to 12 Key Stage of an adjusted grade level: KS1 = Grades 1–3,
/// KS2 = 4–6, KS3 = 7–10, KS4 = 11–12; null for a Non-Reader (0).
/// Reading coordinator: adjusted levels in KS1 are usually Struggling Readers,
/// in KS2 Frustration readers.
String? philIriKeyStage(int adjustedLevel) {
  if (adjustedLevel <= 0) return null;
  if (adjustedLevel <= 3) return 'KS1';
  if (adjustedLevel <= 6) return 'KS2';
  if (adjustedLevel <= 10) return 'KS3';
  return 'KS4';
}

/// Display label for an adjusted level, e.g. "Grade 2 (KS1)"; "Non-Reader" for 0.
String philIriAdjustedLevelLabel(int adjustedLevel) {
  final ks = philIriKeyStage(adjustedLevel);
  return ks == null ? 'Non-Reader' : 'Grade $adjustedLevel ($ks)';
}
