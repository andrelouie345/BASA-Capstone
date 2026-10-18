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
// - Word reading carries up too (reading coordinator, 2026-10-16; replaces
//   "word reading may go down" of 2026-10-14): the round's accuracy and speed
//   are each the highest so far, so a reader never reverts to Non-Reader.
//   Only ORAL readings count for word reading: a silent reading's 100% is not
//   a measured accuracy, so it is used only while no oral reading exists.
// - Two values per round: the carried result (above) is for reports and ARAL;
//   the round's own reading ("actual", the true current score, higher or
//   lower) is for the tutor and IRIP planning.
// - Not assessed at all in the year (no GST, no reading): reports and ARAL
//   count the learner as Frustration, exactly 3 levels down, flagged
//   notAssessed (philIriNotAssessedResult). It never carries; any later
//   assessment replaces it, even a worse one. Phil-IRI only (not CRLA).
// - Reading coordinator's workbook, adopted 2026-10-18: the profile is the
//   (carried) comprehension level, Non-Reader word reading overriding; a
//   given round's Frustration levels-down use that round's OWN comprehension;
//   a round not given keeps the previous adjusted level; BOSY with only a GST
//   (or a reading without comprehension) uses the GST starting grade
//   (philIriGstStartingGrade), a reference the IRA later validates.
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
  final bool silent;                    // read silently: word reading not measured

  bool get comprehensionBlank => comprehensionScore == null;

  const PhilIriPassageResult({
    this.silent = false,
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
/// Silent: wpm from the reading time, no miscues allowed, word reading 100%
/// (so accuracy is Independent and the profile follows the comprehension).
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
    case PhilIriReadingMethod.wholeText || PhilIriReadingMethod.silent:
      if (readingSeconds == null) throw ArgumentError('readingSeconds is required for ${method.value} reading');
      if (method == PhilIriReadingMethod.silent && countedMiscues != 0) {
        throw ArgumentError('a silent reading has no miscues');
      }
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
    silent: method == PhilIriReadingMethod.silent,
  );
}

/// Adjusted level for [profile]: Non-Reader 0, Independent grade+1,
/// Instructional grade; Frustration by [frustrationComp] (the round's own
/// comprehension), or, when there is none and a BOSY [gst] exists, the GST
/// starting grade (philIriGstStartingGrade), which can't put a Frustration
/// reader at or above grade level.
int _adjusted(PhilIriLevel profile, int grade, double? frustrationComp, double? gst, PhilIriThresholds t) {
  if (profile == PhilIriLevel.frustration && frustrationComp == null && gst != null) {
    final start = philIriGstStartingGrade(grade, gst);
    return start >= grade ? (grade > 1 ? grade - 1 : 1) : start;
  }
  return philIriAdjustedLevel(profile, grade, frustrationComp, t);
}

/// Profile from whatever is known: the comprehension level (Non-Reader word
/// reading wins); with only a word reading, its level.
PhilIriLevel? _profile(PhilIriLevel? wordReading, PhilIriLevel? comprehension) {
  if (wordReading == PhilIriLevel.nonReader) return PhilIriLevel.nonReader;
  if (wordReading == null) return comprehension;
  if (comprehension == null) return wordReading;
  return philIriPassageProfile(wordReading, comprehension);
}

/// One round. The top-level fields are the CARRIED result (for reports and
/// ARAL); [actual] / [actualAdjustedLevel] are the round's own reading, the
/// true current score for the tutor (null when the round wasn't given).
class PhilIriRoundResult {
  final PhilIriRound round;
  final bool given;                     // the round had a reading of its own
  final double? wordReadingScore;       // highest oral so far (silent-only: 1.0)
  final double? wordsPerMinute;         // highest so far, same readings as above
  final PhilIriLevel? accuracyLevel;
  final PhilIriSpeed? speed;
  final PhilIriLevel? wordReadingLevel;
  final double? comprehensionScore;     // after carry-up; null = blank (counts as 0)
  final PhilIriLevel? comprehensionLevel;
  final PhilIriLevel? profile;          // null when nothing is known yet
  final bool isStrugglingReader;
  final int? adjustedLevel;             // 1–12; 0 only for a Non-Reader
  final int? levelsDown;                // null for a Non-Reader
  final PhilIriPassageResult? actual;   // the round's own reading as scored
  final int? actualAdjustedLevel;       // from [actual] alone (BOSY: GST fills a missing comprehension)
  final int? actualLevelsDown;
  /// Not assessed at all this year: assumed Frustration, 3 levels down
  /// (philIriNotAssessedResult). Never set on a real result.
  final bool notAssessed;

  bool get comprehensionBlank => comprehensionScore == null;

  const PhilIriRoundResult({
    required this.round,
    required this.given,
    this.actual,
    this.actualAdjustedLevel,
    this.actualLevelsDown,
    this.notAssessed = false,
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
  // Word reading so far: highest oral accuracy and speed; silent readings only
  // supply speed while there is no oral reading.
  double? oralScore, oralWpm, silentWpm;

  double? maxOf(double? a, double b) => a == null || b > a ? b : a;

  for (final round in PhilIriRound.values) {
    final own = readings[round];
    if (own != null) {
      if (own.silent) {
        silentWpm = maxOf(silentWpm, own.wordsPerMinute);
      } else {
        oralScore = maxOf(oralScore, own.wordReadingScore);
        oralWpm = maxOf(oralWpm, own.wordsPerMinute);
      }
    }
    // A finalized round keeps the thresholds it was finalized with.
    final rt = roundThresholds[round] ?? t;
    final ownComp = own?.comprehensionScore;
    if (ownComp != null && (comp == null || ownComp > comp)) comp = ownComp;

    final wrScore = oralScore ?? (silentWpm != null ? 1.0 : null);
    final wpm = oralScore != null ? oralWpm : silentWpm;
    final accuracy = wrScore == null ? null : philIriAccuracyLevel(wrScore, rt);
    final speed = wpm == null ? null : philIriSpeed(wpm, rt);
    final wrLevel = accuracy == null ? null : philIriWordReadingLevel(accuracy, speed!);

    // A blank counts as 0 once there is a reading; with nothing at all the
    // round stays unknown.
    final compLevel = comp != null
        ? philIriComprehensionLevel(comp, rt)
        : (wrLevel != null ? philIriComprehensionLevel(0, rt) : null);
    final profile = _profile(wrLevel, compLevel);
    final bosyGst = round == PhilIriRound.bosy ? gstScore : null;
    // Adjusted level (workbook AN/BQ/CT/DW/EZ): a given round's Frustration
    // levels come from the round's OWN comprehension, not the carried one;
    // BOSY without IRA comprehension uses the GST starting grade; a round
    // that wasn't given keeps the previous round's adjusted level.
    final int? adjusted;
    if (profile == null) {
      adjusted = null;
    } else if (own != null) {
      adjusted = _adjusted(profile, learnerGrade, own.comprehensionScore, bosyGst, rt);
    } else if (round == PhilIriRound.bosy) {
      adjusted = _adjusted(profile, learnerGrade, null, bosyGst, rt); // GST only
    } else {
      adjusted = results.isEmpty ? null : results.last.adjustedLevel;
    }

    // The true score: this round's reading alone. In BOSY a reading without
    // comprehension (FLT) takes the GST's, as in the carried result.
    int? actualAdjusted;
    if (own != null) {
      final c = own.comprehensionScore ?? bosyGst;
      final p = _profile(own.wordReadingLevel, philIriComprehensionLevel(c ?? 0, rt))!;
      actualAdjusted = _adjusted(p, learnerGrade, own.comprehensionScore, bosyGst, rt);
    }

    results.add(PhilIriRoundResult(
      round: round,
      given: own != null,
      wordReadingScore: wrScore,
      wordsPerMinute: wpm,
      accuracyLevel: accuracy,
      speed: speed,
      wordReadingLevel: wrLevel,
      comprehensionScore: comp,
      comprehensionLevel: compLevel,
      profile: profile,
      isStrugglingReader: accuracy != null && philIriIsStrugglingReader(accuracy, speed!),
      adjustedLevel: adjusted,
      levelsDown: adjusted == null
          ? null
          : philIriLevelsDown(adjusted, learnerGrade, nonReader: profile == PhilIriLevel.nonReader),
      actual: own,
      actualAdjustedLevel: actualAdjusted,
      actualLevelsDown: actualAdjusted == null
          ? null
          : philIriLevelsDown(actualAdjusted, learnerGrade, nonReader: actualAdjusted == 0),
    ));
  }
  return results;
}

/// Levels down assumed for a learner not assessed at all (reading coordinator).
const philIriNotAssessedLevelsDown = 3;

/// True when nothing at all is known for the year (no GST, no reading).
bool philIriNothingAssessed(List<PhilIriRoundResult> rounds) =>
    rounds.every((r) => r.profile == null);

/// The assumed result for a learner not assessed at all: Frustration, exactly
/// 3 levels down (never below Grade 1), flagged notAssessed. Scores stay
/// blank. For reports and ARAL only; the tutor's true score stays empty.
PhilIriRoundResult philIriNotAssessedResult(PhilIriRound round, int learnerGrade) {
  var adjusted = learnerGrade - philIriNotAssessedLevelsDown;
  if (adjusted < 1) adjusted = 1;
  return PhilIriRoundResult(
    round: round,
    given: false,
    profile: PhilIriLevel.frustration,
    adjustedLevel: adjusted,
    levelsDown: learnerGrade - adjusted,
    notAssessed: true,
  );
}

/// End result for reports and ARAL: [philIriEndResult], or the assumed
/// not-assessed result when nothing at all is known (philIriEndResult is
/// null only then: with a GST alone it returns BOSY).
PhilIriRoundResult philIriReportEndResult(List<PhilIriRoundResult> rounds, int learnerGrade) =>
    philIriEndResult(rounds) ?? philIriNotAssessedResult(PhilIriRound.bosy, learnerGrade);

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
