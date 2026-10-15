// lib/core/services/crla_rules.dart
//
// Grade rules from the CRLA2 G1–G3 scoresheets. Same numbers as the Postgres
// helpers crla_comprehension_max / crla_time_cap_seconds and the SQLite
// triggers and crla_results view in local_database.dart; change all of them
// together.
//
// CRLA is Grades 1–3 only, and the section's grade is the instrument grade.
// Grade/variant pairs with no scoresheet (e.g. G1 eng) are parked: they use
// their grade's numbers.
//
// Two kinds of numbers live here:
//  * Instrument facts (fixed): how many comprehension questions a sheet has,
//    its printed reading-time limit, and the Part 1 task structure (task 1
//    below 7 uses the low task 2, otherwise 10 + the high task 2).
//  * Interpretation cut-offs (adjustable, CrlaThresholds): the Part 1
//    refresher bands and the reading-profile bands. The defaults reproduce
//    the DepEd scoresheet formulas exactly, gaps included (owner, 2026-10-15:
//    CRLA follows the baseline).

const crlaGrades = {1, 2, 3};

/// The section's grade as a CRLA grade, or null when it isn't 1–3.
int? crlaGradeOf(String gradeLevel) {
  final grade = int.tryParse(gradeLevel.trim());
  return crlaGrades.contains(grade) ? grade : null;
}

/// Most comprehension questions: G1 5, G3 mt/fil 7, otherwise 6.
int crlaComprehensionMax(int grade, String variant) {
  if (grade == 1) return 5;
  if (grade == 3 && (variant == 'mt' || variant == 'fil')) return 7;
  return 6;
}

/// Reading-time limit in seconds: G1 60, G3 mt/fil 180, otherwise 120.
int crlaTimeCapSeconds(int grade, String variant) {
  if (grade == 1) return 60;
  if (grade == 3 && (variant == 'mt' || variant == 'fil')) return 180;
  return 120;
}

// ---- Levels and profiles (stored as these exact strings) ----

const crlaFullRefresher = 'Full Refresher';
const crlaModerateRefresher = 'Moderate Refresher';
const crlaLightRefresher = 'Light Refresher';
const crlaGradeReady = 'Grade Ready';

const crlaLowEmerging = 'Low Emerging Reader';
const crlaHighEmerging = 'High Emerging Reader';
const crlaDeveloping = 'Developing Reader';
const crlaTransitioning = 'Transitioning Reader';
const crlaAtGradeLevel = 'Reading At Grade Level';

/// The scoresheet a grade/variant is scored with (its comprehension
/// cut-offs). Parked pairs use their grade's sheet.
enum CrlaSheet {
  g1('g1'),           // G1 MT (also parked G1 fil/eng)
  g2('g2'),           // G2 MT/FIL (also parked G2 eng)
  g3MtFil('g3_mtfil'),
  g3Eng('g3_eng');

  final String key;
  const CrlaSheet(this.key);

  static CrlaSheet of(int grade, String variant) {
    if (grade == 1) return g1;
    if (grade == 2) return g2;
    return (variant == 'mt' || variant == 'fil') ? g3MtFil : g3Eng;
  }
}

/// Comprehension cut-offs of one sheet. With fluency in the 25–50 % band, a
/// score <= [h] is High Emerging; in the 50–76 % band a score <= [d2] is
/// Developing; above 75 % a score >= [g] is At Grade Level.
class CrlaSheetCutoffs {
  final int h;
  final int d2;
  final int g;
  /// G1: a Moderate Refresher is also a Low Emerging Reader.
  final bool moderateIsLowEmerging;

  const CrlaSheetCutoffs(this.h, this.d2, this.g, {this.moderateIsLowEmerging = false});
}

/// Adjustable CRLA cut-offs. Percentages are whole numbers (0–100) of
/// words read correctly over the story's word count; each value is the
/// boundary exactly as the scoresheet formula uses it.
class CrlaThresholds {
  // Part 1, mt/fil (task 1 below 7: total <= fullMax is Full, otherwise
  // Moderate; task 1 of 7+: total <= lightMax is Light, otherwise Grade Ready).
  final int part1StdFullMax;
  final int part1StdLightMax;
  // Part 1, English: total <= fullMax Full, <= moderateMax Moderate,
  // <= lightMax Light, otherwise Grade Ready.
  final int part1EngFullMax;
  final int part1EngModerateMax;
  final int part1EngLightMax;
  // Reading profile fluency bands (scoresheet: 25, 50, 51, 75, 76):
  //   High Emerging   pct <= highEmergingMax
  //                   or (highEmergingMax < pct <= lowBandMax and comp <= h)
  //   Developing      (highEmergingMax < pct < midBandMin and comp >= h+1)
  //                   or (lowBandMax < pct < midBandBelow and comp <= d2)
  //   Transitioning   (midBandMin <= pct < midBandBelow and comp >= d2+1)
  //                   or (pct > topBandAbove and comp <= g-1)
  //   At Grade Level  pct > topBandAbove and comp >= g
  // The default gaps (e.g. 50 < pct < 51 with comp > d2) give no profile,
  // as in the Excel.
  final int pctHighEmergingMax;
  final int pctLowBandMax;
  final int pctMidBandMin;
  final int pctTopBandAbove;
  final int pctMidBandBelow;
  final Map<CrlaSheet, CrlaSheetCutoffs> sheets;

  const CrlaThresholds({
    this.part1StdFullMax = 10,
    this.part1StdLightMax = 26,
    this.part1EngFullMax = 0,
    this.part1EngModerateMax = 10,
    this.part1EngLightMax = 16,
    this.pctHighEmergingMax = 25,
    this.pctLowBandMax = 50,
    this.pctMidBandMin = 51,
    this.pctTopBandAbove = 75,
    this.pctMidBandBelow = 76,
    this.sheets = defaultSheets,
  });

  static const defaultSheets = {
    CrlaSheet.g1: CrlaSheetCutoffs(0, 1, 4, moderateIsLowEmerging: true),
    CrlaSheet.g2: CrlaSheetCutoffs(0, 2, 5),
    CrlaSheet.g3MtFil: CrlaSheetCutoffs(1, 3, 6),
    CrlaSheet.g3Eng: CrlaSheetCutoffs(0, 2, 5),
  };

  static const defaults = CrlaThresholds();

  CrlaSheetCutoffs sheet(CrlaSheet s) => sheets[s] ?? defaultSheets[s]!;

  /// Flat keys, as stored in a settings row and in an assessment's snapshot.
  /// Missing keys fall back to the defaults.
  Map<String, Object?> toMap() => {
        'part1_std_full_max': part1StdFullMax,
        'part1_std_light_max': part1StdLightMax,
        'part1_eng_full_max': part1EngFullMax,
        'part1_eng_moderate_max': part1EngModerateMax,
        'part1_eng_light_max': part1EngLightMax,
        'pct_high_emerging_max': pctHighEmergingMax,
        'pct_low_band_max': pctLowBandMax,
        'pct_mid_band_min': pctMidBandMin,
        'pct_top_band_above': pctTopBandAbove,
        'pct_mid_band_below': pctMidBandBelow,
        for (final s in CrlaSheet.values) ...{
          '${s.key}_h': sheet(s).h,
          '${s.key}_d2': sheet(s).d2,
          '${s.key}_g': sheet(s).g,
          '${s.key}_moderate_is_low_emerging': sheet(s).moderateIsLowEmerging,
        },
      };

  factory CrlaThresholds.fromMap(Map<String, Object?> m) {
    const d = CrlaThresholds.defaults;
    int v(String key, int fallback) => (m[key] as num?)?.toInt() ?? fallback;
    bool b(String key, bool fallback) => switch (m[key]) {
          bool x => x,
          int i => i == 1,
          _ => fallback,
        };
    return CrlaThresholds(
      part1StdFullMax: v('part1_std_full_max', d.part1StdFullMax),
      part1StdLightMax: v('part1_std_light_max', d.part1StdLightMax),
      part1EngFullMax: v('part1_eng_full_max', d.part1EngFullMax),
      part1EngModerateMax: v('part1_eng_moderate_max', d.part1EngModerateMax),
      part1EngLightMax: v('part1_eng_light_max', d.part1EngLightMax),
      pctHighEmergingMax: v('pct_high_emerging_max', d.pctHighEmergingMax),
      pctLowBandMax: v('pct_low_band_max', d.pctLowBandMax),
      pctMidBandMin: v('pct_mid_band_min', d.pctMidBandMin),
      pctTopBandAbove: v('pct_top_band_above', d.pctTopBandAbove),
      pctMidBandBelow: v('pct_mid_band_below', d.pctMidBandBelow),
      sheets: {
        for (final s in CrlaSheet.values)
          s: CrlaSheetCutoffs(
            v('${s.key}_h', d.sheet(s).h),
            v('${s.key}_d2', d.sheet(s).d2),
            v('${s.key}_g', d.sheet(s).g),
            moderateIsLowEmerging: b('${s.key}_moderate_is_low_emerging', d.sheet(s).moderateIsLowEmerging),
          ),
      },
    );
  }

  /// Throws ArgumentError when the bands overlap or leave their scale.
  void validate() {
    void ordered(String what, List<int> values, int min, int max) {
      for (var i = 0; i < values.length; i++) {
        if (values[i] < min || values[i] > max) {
          throw ArgumentError('$what must be within $min..$max');
        }
        if (i > 0 && values[i] < values[i - 1]) {
          throw ArgumentError('$what boundaries must not go down: $values');
        }
      }
    }

    // Part 1 totals: mt/fil low branch 0..16 (task 1 0-6 + task 2 0-10),
    // high branch 17..30; English 0..20.
    ordered('Part 1 (mt/fil) Full Refresher', [part1StdFullMax], 0, 16);
    ordered('Part 1 (mt/fil) Light Refresher', [part1StdLightMax], 17, 30);
    ordered('Part 1 (English)', [part1EngFullMax, part1EngModerateMax, part1EngLightMax], 0, 20);
    if (part1EngFullMax == part1EngModerateMax || part1EngModerateMax == part1EngLightMax) {
      throw ArgumentError('Part 1 (English) bands must be different: '
          '$part1EngFullMax, $part1EngModerateMax, $part1EngLightMax');
    }
    ordered('Reading profile fluency',
        [pctHighEmergingMax, pctLowBandMax, pctMidBandMin, pctTopBandAbove, pctMidBandBelow], 0, 100);
    for (final s in CrlaSheet.values) {
      final c = sheet(s);
      final max = switch (s) { CrlaSheet.g1 => 5, CrlaSheet.g3MtFil => 7, _ => 6 };
      ordered('Comprehension cut-offs (${s.key})', [c.h, c.d2, c.g], 0, max);
      if (c.d2 >= c.g) throw ArgumentError('Comprehension cut-offs (${s.key}): d2 must be below g');
    }
  }
}

/// Part 1 level for mt/fil from the stored total (task 1 below 7: total is
/// task 1 + low task 2; otherwise task 1 + 10 + high task 2).
String crlaPart1StandardLevel(int task1Score, int totalScore,
    [CrlaThresholds t = CrlaThresholds.defaults]) {
  if (task1Score < 7) {
    return totalScore <= t.part1StdFullMax ? crlaFullRefresher : crlaModerateRefresher;
  }
  return totalScore <= t.part1StdLightMax ? crlaLightRefresher : crlaGradeReady;
}

/// Part 1 level for English from the total (task 1 + task 2).
String crlaPart1EnglishLevel(int totalScore, [CrlaThresholds t = CrlaThresholds.defaults]) {
  if (totalScore <= t.part1EngFullMax) return crlaFullRefresher;
  if (totalScore <= t.part1EngModerateMax) return crlaModerateRefresher;
  if (totalScore <= t.part1EngLightMax) return crlaLightRefresher;
  return crlaGradeReady;
}

/// The reading profile, as the scoresheet's row 11 formula. Null until Part 1
/// exists ([part1Level] null), and when Part 2 or the story's word count is
/// missing (unless Part 1 already makes the learner Low Emerging). [pct] is
/// words read / word count, unrounded.
String? crlaReadingProfile({
  required String? part1Level,
  required double? pct,
  required int? comprehension,
  required int grade,
  required String variant,
  CrlaThresholds t = CrlaThresholds.defaults,
}) {
  if (part1Level == null) return null;
  final c = t.sheet(CrlaSheet.of(grade, variant));
  if (part1Level == crlaFullRefresher ||
      (c.moderateIsLowEmerging && part1Level == crlaModerateRefresher)) {
    return crlaLowEmerging;
  }
  if (pct == null || comprehension == null) return null;
  // Compare fractions, not pct * 100: 51 / 100 and a learner's 51 / 100 are
  // the same double, as in the SQLite view; pct * 100 can miss by 1e-14.
  final p = pct;
  final a = t.pctHighEmergingMax / 100, b = t.pctLowBandMax / 100, mid = t.pctMidBandMin / 100;
  final top = t.pctTopBandAbove / 100, below = t.pctMidBandBelow / 100;
  final comp = comprehension;
  if (p <= a || (p > a && p <= b && comp <= c.h)) return crlaHighEmerging;
  if ((p > a && p < mid && comp >= c.h + 1) || (p > b && p < below && comp <= c.d2)) return crlaDeveloping;
  if ((p >= mid && p < below && comp >= c.d2 + 1) || (p > top && comp <= c.g - 1)) return crlaTransitioning;
  if (p > top && comp >= c.g) return crlaAtGradeLevel;
  return null;
}
