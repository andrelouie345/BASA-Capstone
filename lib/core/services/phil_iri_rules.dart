// lib/core/services/phil_iri_rules.dart
//
// Scoring rules for the Phil-IRI graded passages (oral reading), English only,
// Grades 4–10. Sources: Phil-IRI Manual 2018 (Grades 4–6) and Phil-IRI for JHS
// Manual 2024 (Grades 7–10), "Computing the Oral Reading Score", Tables 6–8.
//
// BASA uses ONE grade-level passage per assessment (FLT, BOSY, MOSY, EOSY):
// a learner reads a passage of their own grade, and the adjusted grade level
// is worked out from there (phil_iri_results.dart). The manual's Stage 2
// up/down passage ladder and GST starting levels are not used (owner and
// reading coordinator, 2026-10-14).
//
// Owner decisions (2026-10-13): the rules follow the reading coordinator's
// workbook where it differs from the manual:
// - word recognition bands (DepEd, 2026-10-29): Non-Reader <= 35%,
//   Struggling 36-55%, Frustration 56-89%, Instructional, Independent;
// - reading speed bands (Sample!AH);
// - the word reading profile and the reading profile follow the fixed
//   "Table 8. Student's Reading Profile Per Passage" (two lookups below; spec
//   docs/superpowers/specs/2026-10-29-phil-iri-word-recognition-bands-design.md).
// Every range is adjustable through PhilIriThresholds, because DepEd changes
// acceptable ranges; Table 8 itself is not.
//
// Percentages are classified after rounding to a whole percent (half up),
// because the bands are whole numbers (e.g. 96.5% -> 97 -> Independent).

enum PhilIriLevel {
  independent('Independent'),
  instructional('Instructional'),
  frustration('Frustration'),
  struggling('Struggling'),
  nonReader('Non-Reader');

  final String label;
  const PhilIriLevel(this.label);

  static PhilIriLevel fromString(String value) {
    return PhilIriLevel.values.firstWhere(
      (l) => l.name == value || l.label == value,
      orElse: () => throw ArgumentError('Invalid PhilIriLevel value: $value'),
    );
  }
}

enum PhilIriSpeed {
  struggling('Struggling'),
  slow('Slow'),
  average('Average'),
  fast('Fast');

  final String label;
  const PhilIriSpeed(this.label);

  static PhilIriSpeed fromString(String value) {
    return PhilIriSpeed.values.firstWhere(
      (s) => s.name == value || s.label == value,
      orElse: () => throw ArgumentError('Invalid PhilIriSpeed value: $value'),
    );
  }
}

/// Adjustable ranges. Percentages are whole numbers (0–100), speeds are wpm.
/// A value is the boundary itself: e.g. nonReaderMax 50 means 50% and below
/// is Non-Reader, wordReadingInstructionalMin 90 means 90% and up.
class PhilIriThresholds {
  final int nonReaderMax;                   // word recognition ≤ this: Non-Reader
  final int wordReadingStrugglingMax;       // ≤ this: Struggling (above Non-Reader)
  final int wordReadingInstructionalMin;    // ≥ this: Instructional (below: Frustration)
  final int wordReadingIndependentMin;      // ≥ this: Independent
  final int comprehensionInstructionalMin;  // ≥ this: Instructional (below: Frustration)
  final int comprehensionIndependentMin;    // ≥ this: Independent
  final int speedStrugglingMax;             // wpm ≤ this: Struggling
  final int speedSlowMax;                   // wpm ≤ this: Slow
  final int speedFastMin;                   // wpm ≥ this: Fast (between: Average)
  final int gstElementaryPassMin;           // Grades 4–6, GST /20: ≥ this passes
  final int gstJhsPassMin;                  // Grades 7–10, GST /40: ≥ this passes
  // Adjusted grade level for a Frustration profile, by comprehension %
  // (workbook "Adj. Grade Level"): ≤ fourDown -> 4 levels down, ≤ threeDown
  // -> 3, ≤ twoDown -> 2, otherwise 1; ≥ keepLevel -> stays at the base level.
  final int frustrationFourDownMax;
  final int frustrationThreeDownMax;
  final int frustrationTwoDownMax;
  final int frustrationKeepLevelMin;
  // Report grouping of "levels down" (Phil-IRI reports only have 2-LD and
  // 3-LD). Each value closes a group: [2] = 1–2 down -> "2-LD", 3+ -> "3-LD".
  // groupLevelsDown false reports each level on its own (1-LD, 2-LD, ...).
  final bool groupLevelsDown;
  final List<int> levelsDownGroups;

  const PhilIriThresholds({
    this.nonReaderMax = 35,
    this.wordReadingStrugglingMax = 55,
    this.wordReadingInstructionalMin = 90,
    this.wordReadingIndependentMin = 97,
    this.comprehensionInstructionalMin = 59,
    this.comprehensionIndependentMin = 80,
    this.speedStrugglingMax = 75,
    this.speedSlowMax = 120,
    this.speedFastMin = 151,
    this.gstElementaryPassMin = 14,
    this.gstJhsPassMin = 28,
    this.frustrationFourDownMax = 25,
    this.frustrationThreeDownMax = 28,
    this.frustrationTwoDownMax = 40,
    this.frustrationKeepLevelMin = 79,
    this.groupLevelsDown = true,
    this.levelsDownGroups = const [2],
  });

  static const defaults = PhilIriThresholds();

  /// Stored as the session snapshot at finalization and as a school/region
  /// setting. Missing keys fall back to the defaults, so a snapshot written
  /// before a new threshold existed still loads.
  Map<String, Object?> toMap() => {
        'non_reader_max': nonReaderMax,
        'word_reading_struggling_max': wordReadingStrugglingMax,
        'word_reading_instructional_min': wordReadingInstructionalMin,
        'word_reading_independent_min': wordReadingIndependentMin,
        'comprehension_instructional_min': comprehensionInstructionalMin,
        'comprehension_independent_min': comprehensionIndependentMin,
        'speed_struggling_max': speedStrugglingMax,
        'speed_slow_max': speedSlowMax,
        'speed_fast_min': speedFastMin,
        'gst_elementary_pass_min': gstElementaryPassMin,
        'gst_jhs_pass_min': gstJhsPassMin,
        'frustration_four_down_max': frustrationFourDownMax,
        'frustration_three_down_max': frustrationThreeDownMax,
        'frustration_two_down_max': frustrationTwoDownMax,
        'frustration_keep_level_min': frustrationKeepLevelMin,
        'group_levels_down': groupLevelsDown,
        'levels_down_groups': levelsDownGroups,
      };

  factory PhilIriThresholds.fromMap(Map<String, Object?> m) {
    const d = PhilIriThresholds.defaults;
    int v(String key, int fallback) => (m[key] as num?)?.toInt() ?? fallback;
    return PhilIriThresholds(
      nonReaderMax: v('non_reader_max', d.nonReaderMax),
      wordReadingStrugglingMax: v('word_reading_struggling_max', d.wordReadingStrugglingMax),
      wordReadingInstructionalMin: v('word_reading_instructional_min', d.wordReadingInstructionalMin),
      wordReadingIndependentMin: v('word_reading_independent_min', d.wordReadingIndependentMin),
      comprehensionInstructionalMin: v('comprehension_instructional_min', d.comprehensionInstructionalMin),
      comprehensionIndependentMin: v('comprehension_independent_min', d.comprehensionIndependentMin),
      speedStrugglingMax: v('speed_struggling_max', d.speedStrugglingMax),
      speedSlowMax: v('speed_slow_max', d.speedSlowMax),
      speedFastMin: v('speed_fast_min', d.speedFastMin),
      gstElementaryPassMin: v('gst_elementary_pass_min', d.gstElementaryPassMin),
      gstJhsPassMin: v('gst_jhs_pass_min', d.gstJhsPassMin),
      frustrationFourDownMax: v('frustration_four_down_max', d.frustrationFourDownMax),
      frustrationThreeDownMax: v('frustration_three_down_max', d.frustrationThreeDownMax),
      frustrationTwoDownMax: v('frustration_two_down_max', d.frustrationTwoDownMax),
      frustrationKeepLevelMin: v('frustration_keep_level_min', d.frustrationKeepLevelMin),
      groupLevelsDown: switch (m['group_levels_down']) {
        bool b => b,
        int i => i == 1,
        _ => d.groupLevelsDown,
      },
      levelsDownGroups: switch (m['levels_down_groups']) {
        List l => l.map((e) => (e as num).toInt()).toList(),
        _ => d.levelsDownGroups,
      },
    );
  }

  /// Throws ArgumentError when the ranges overlap or leave their scale.
  void validate() {
    void ordered(String what, List<int> values, int min, int max) {
      for (var i = 0; i < values.length; i++) {
        if (values[i] < min || values[i] > max) {
          throw ArgumentError('$what must be within $min..$max');
        }
        if (i > 0 && values[i] <= values[i - 1]) {
          throw ArgumentError('$what boundaries must increase: $values');
        }
      }
    }

    ordered('Word reading',
        [nonReaderMax, wordReadingStrugglingMax, wordReadingInstructionalMin, wordReadingIndependentMin], 0, 100);
    ordered('Comprehension',
        [comprehensionInstructionalMin, comprehensionIndependentMin], 0, 100);
    ordered('Speed', [speedStrugglingMax, speedSlowMax, speedFastMin], 0, 1000);
    ordered('GST (Grades 4–6)', [gstElementaryPassMin], 0, 20);
    ordered('GST (Grades 7–10)', [gstJhsPassMin], 0, 40);
    ordered('Frustration levels down', [
      frustrationFourDownMax,
      frustrationThreeDownMax,
      frustrationTwoDownMax,
      frustrationKeepLevelMin,
    ], 0, 100);
    ordered('Levels-down groups', levelsDownGroups, 1, philIriMaxGrade);
  }
}

/// Learner grades Phil-IRI covers (the BASA paper: 4–10). Add 11 and 12 here
/// when Senior High is brought in; adjusted levels already cap at 12.
const philIriGrades = {4, 5, 6, 7, 8, 9, 10};
const philIriMaxGrade = 12;

/// The section's grade as a Phil-IRI grade, or null when it isn't 4–10.
int? philIriGradeOf(String gradeLevel) {
  final grade = int.tryParse(gradeLevel.trim());
  return philIriGrades.contains(grade) ? grade : null;
}

/// A 0–1 score as a whole percent, rounded half up (bands are whole numbers).
int philIriWholePercent(double fraction) => (fraction * 100 + 0.5).floor();

/// Word recognition (accuracy) as a 0–1 fraction: (words − miscues) / words.
/// Only counted miscues go in (self-corrections are not counted). For a
/// one-minute reading, wordCount is the number of words read in the minute.
double philIriWordReadingScore(int wordCount, int countedMiscues) {
  if (wordCount <= 0) throw ArgumentError('wordCount must be positive');
  if (countedMiscues < 0) throw ArgumentError('miscues cannot be negative');
  final correct = wordCount - countedMiscues;
  return (correct < 0 ? 0 : correct) / wordCount;
}

/// Comprehension score as a 0–1 fraction: correct / questions.
double philIriComprehensionScore(int correct, int questions) {
  if (questions <= 0) throw ArgumentError('questions must be positive');
  if (correct < 0 || correct > questions) {
    throw ArgumentError('correct must be 0..$questions');
  }
  return correct / questions;
}

/// Reading rate in words per minute, rounded to 2 decimals.
double philIriWordsPerMinute(int wordCount, int readingSeconds) {
  if (readingSeconds <= 0) throw ArgumentError('readingSeconds must be positive');
  return (wordCount * 60 / readingSeconds * 100).round() / 100;
}

/// Word recognition band: Non-Reader, Struggling, Frustration, Instructional
/// or Independent. Word recognition only; speed plays no part.
PhilIriLevel philIriAccuracyLevel(double score,
    [PhilIriThresholds t = PhilIriThresholds.defaults]) {
  final pct = philIriWholePercent(score);
  if (pct <= t.nonReaderMax) return PhilIriLevel.nonReader;
  if (pct <= t.wordReadingStrugglingMax) return PhilIriLevel.struggling;
  if (pct >= t.wordReadingIndependentMin) return PhilIriLevel.independent;
  if (pct >= t.wordReadingInstructionalMin) return PhilIriLevel.instructional;
  return PhilIriLevel.frustration;
}

/// Reading speed band (workbook "Reading Speed Desc").
PhilIriSpeed philIriSpeed(double wpm,
    [PhilIriThresholds t = PhilIriThresholds.defaults]) {
  if (wpm <= t.speedStrugglingMax) return PhilIriSpeed.struggling;
  if (wpm <= t.speedSlowMax) return PhilIriSpeed.slow;
  if (wpm >= t.speedFastMin) return PhilIriSpeed.fast;
  return PhilIriSpeed.average;
}

const _f = PhilIriLevel.frustration, _i = PhilIriLevel.instructional, _d = PhilIriLevel.independent;
const _s = PhilIriLevel.struggling, _n = PhilIriLevel.nonReader;

/// Table 8, word recognition x reading speed -> word reading profile.
const _wordReadingTable = <PhilIriLevel, Map<PhilIriSpeed, PhilIriLevel>>{
  _d: {PhilIriSpeed.fast: _d, PhilIriSpeed.average: _d, PhilIriSpeed.slow: _i, PhilIriSpeed.struggling: _f},
  _i: {PhilIriSpeed.fast: _i, PhilIriSpeed.average: _i, PhilIriSpeed.slow: _i, PhilIriSpeed.struggling: _s},
  _f: {PhilIriSpeed.fast: _f, PhilIriSpeed.average: _f, PhilIriSpeed.slow: _f, PhilIriSpeed.struggling: _s},
  _s: {PhilIriSpeed.fast: _s, PhilIriSpeed.average: _s, PhilIriSpeed.slow: _s, PhilIriSpeed.struggling: _s},
  _n: {PhilIriSpeed.fast: _n, PhilIriSpeed.average: _n, PhilIriSpeed.slow: _n, PhilIriSpeed.struggling: _n},
};

/// Table 8, word reading profile x comprehension -> reading profile.
const _profileTable = <PhilIriLevel, Map<PhilIriLevel, PhilIriLevel>>{
  _d: {_d: _d, _i: _i, _f: _f},
  _i: {_d: _d, _i: _i, _f: _f},
  _f: {_d: _i, _i: _f, _f: _f},
  _s: {_d: _s, _i: _s, _f: _s},
  _n: {_d: _n, _i: _n, _f: _n},
};

/// Word reading profile: Table 8, word recognition band x reading speed.
PhilIriLevel philIriWordReadingLevel(PhilIriLevel accuracy, PhilIriSpeed speed) =>
    _wordReadingTable[accuracy]![speed]!;

/// Comprehension band. There is no comprehension Non-Reader: Non-Reader
/// comes from word recognition only.
PhilIriLevel philIriComprehensionLevel(double score,
    [PhilIriThresholds t = PhilIriThresholds.defaults]) {
  final pct = philIriWholePercent(score);
  if (pct >= t.comprehensionIndependentMin) return PhilIriLevel.independent;
  if (pct >= t.comprehensionInstructionalMin) return PhilIriLevel.instructional;
  return PhilIriLevel.frustration;
}

/// Reading profile for one passage: Table 8, word reading profile x
/// comprehension level. Comprehension has no Struggling or Non-Reader level.
PhilIriLevel philIriPassageProfile(PhilIriLevel wordReading, PhilIriLevel comprehension) {
  final row = _profileTable[wordReading]!;
  final profile = row[comprehension];
  if (profile == null) {
    throw ArgumentError('comprehension has no ${comprehension.label} level');
  }
  return profile;
}

/// GST "starting grade level" (workbook column M): the learner's grade moved by
/// the GST percent, never below Grade 1. Reference only — the IRA validates
/// it; used for the adjusted level when there is no IRA comprehension in BOSY
/// (reading coordinator 2026-10-18). Whole percents (rounded like the bands):
/// <=9 -9, <=16 -8, <=24 -7, <=31 -6, <=39 -5, <=46 -4, <=54 -3, <=61 -2,
/// <=68 -1, >=79 +1, otherwise 0.
int philIriGstStartingGrade(int learnerGrade, double gstFraction) {
  final pct = philIriWholePercent(gstFraction);
  final delta = pct <= 9
      ? -9
      : pct <= 16
          ? -8
          : pct <= 24
              ? -7
              : pct <= 31
                  ? -6
                  : pct <= 39
                      ? -5
                      : pct <= 46
                          ? -4
                          : pct <= 54
                              ? -3
                              : pct <= 61
                                  ? -2
                                  : pct <= 68
                                      ? -1
                                      : pct >= 79
                                          ? 1
                                          : 0;
  final level = learnerGrade + delta;
  if (level > philIriMaxGrade) return philIriMaxGrade;
  return level < 1 ? 1 : level;
}

/// GST size for a learner grade: 20 items (Grades 4–6), 40 items (7 and up).
int philIriGstMaxScore(int learnerGrade) => learnerGrade >= 7 ? 40 : 20;

/// True when the GST raw score reaches the pass mark (14/20 or 28/40 by default).
bool philIriGstPassed(int learnerGrade, int gstScore,
    [PhilIriThresholds t = PhilIriThresholds.defaults]) {
  if (!philIriGrades.contains(learnerGrade)) {
    throw ArgumentError('Phil-IRI covers Grades ${philIriGrades.first}–${philIriGrades.last}, got $learnerGrade');
  }
  final maxScore = philIriGstMaxScore(learnerGrade);
  if (gstScore < 0 || gstScore > maxScore) {
    throw ArgumentError('GST score must be 0..$maxScore');
  }
  return gstScore >= (learnerGrade >= 7 ? t.gstJhsPassMin : t.gstElementaryPassMin);
}
