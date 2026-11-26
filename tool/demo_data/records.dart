// Records from a target band (demo-data plan Task 3): the raw numbers a tutor
// would record (CRLA Part 1/2, Phil-IRI miscues, time, answers, GST) for a
// learner the world says reads at a given band. Every plan is checked with
// BASA's own rule functions before it is returned, so a threshold change can
// never silently give the wrong band; a band that can't be reached throws.
import 'dart:math';

import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/services/crla_rules.dart';
import 'package:basa_capstone/core/services/phil_iri_rules.dart';

import 'world.dart';

const _tries = 400;

int _between(Random rng, int lo, int hi) => hi <= lo ? lo : lo + rng.nextInt(hi - lo + 1);

// ---- CRLA ----

/// The CRLA profile a band stands for. Independent readers are At Grade
/// Level or Transitioning (about half each), so both profiles show.
String crlaProfileFor(DemoBand b, Random rng) => switch (b) {
      DemoBand.nonReader || DemoBand.struggling => crlaLowEmerging,
      DemoBand.frustration => crlaHighEmerging,
      DemoBand.instructional => crlaDeveloping,
      DemoBand.independent => rng.nextBool() ? crlaAtGradeLevel : crlaTransitioning,
    };

class CrlaPlan {
  final int task1;
  /// Standard Part 1: low task 2 (task 1 below 7) or high task 2 (7 and up).
  final int? task2Low, task2High;
  /// English Part 1: task 2 (task 1 of 1 and up).
  final int? task2;
  final int miscues;
  final int minutes, seconds;
  final int comprehension;
  const CrlaPlan(this.task1, this.task2Low, this.task2High, this.task2, this.miscues, this.minutes, this.seconds,
      this.comprehension);
}

String? _crlaProfileOf(CrlaPlan p, int grade, String variant, int storyWords, CrlaThresholds t) {
  final english = variant == 'eng';
  final total = english
      ? p.task1 + (p.task2 ?? 0)
      : p.task1 < 7
          ? p.task1 + (p.task2Low ?? 0)
          : p.task1 + 10 + (p.task2High ?? 0);
  final part1 = english ? crlaPart1EnglishLevel(total, t) : crlaPart1StandardLevel(p.task1, total, t);
  final read = crlaWordsRead(storyWords: storyWords, miscues: p.miscues);
  return crlaReadingProfile(
      part1Level: part1, pct: read / storyWords, comprehension: p.comprehension, grade: grade, variant: variant, t: t);
}

/// A CRLA attempt that scores as [profile] on a story of [storyWords] words.
CrlaPlan crlaPlanFor({
  required String profile,
  required int grade,
  required String variant,
  required int storyWords,
  required Random rng,
  CrlaThresholds t = CrlaThresholds.defaults,
}) {
  final english = variant == 'eng';
  final low = profile == crlaLowEmerging;
  final top = profile == crlaTransitioning || profile == crlaAtGradeLevel;
  final compMax = crlaComprehensionMax(grade, variant);
  final cap = crlaTimeCapSeconds(grade, variant);
  final c = t.sheet(CrlaSheet.of(grade, variant));
  for (var i = 0; i < _tries; i++) {
    // Part 1, following the scoresheet's task structure.
    int task1;
    int? t2Low, t2High, t2;
    if (english) {
      if (low) {
        task1 = 0;
      } else if (profile == crlaHighEmerging) {
        task1 = _between(rng, 1, 5);
        t2 = _between(rng, 0, 10 - task1);
      } else if (profile == crlaDeveloping) {
        task1 = _between(rng, 6, 10);
        t2 = _between(rng, max(0, 11 - task1), min(10, 16 - task1));
      } else {
        task1 = _between(rng, 7, 10);
        t2 = _between(rng, 17 - task1, 10);
      }
    } else if (low) {
      task1 = _between(rng, 0, 4);
      t2Low = _between(rng, 0, 10 - task1);
    } else if (profile == crlaHighEmerging && !c.moderateIsLowEmerging) {
      task1 = _between(rng, 3, 6); // Moderate Refresher
      t2Low = _between(rng, 11 - task1, 10);
    } else if (top) {
      task1 = _between(rng, 7, 10); // Grade Ready
      t2High = _between(rng, 17 - task1, 10);
    } else {
      task1 = _between(rng, 7, 10); // Light Refresher
      t2High = _between(rng, 0, 16 - task1);
    }

    // Part 2: share of words read correctly and comprehension for the profile.
    final (pLo, pHi, cLo, cHi) = switch (profile) {
      crlaLowEmerging => (0.05, 0.30, 0, min(c.h + 1, compMax)),
      crlaHighEmerging => (0.10, 0.25, 0, compMax),
      crlaDeveloping => (0.27, 0.48, c.h + 1, compMax),
      crlaTransitioning => (0.55, 0.74, c.d2 + 1, compMax),
      _ => (0.80, 0.98, c.g, compMax),
    };
    final share = pLo + rng.nextDouble() * (pHi - pLo);
    final read = (share * storyWords).round().clamp(0, storyWords);
    final comprehension = _between(rng, cLo, cHi);
    final (wLo, wHi) = switch (profile) {
      crlaLowEmerging => (12, 30),
      crlaHighEmerging => (20, 40),
      crlaDeveloping => (35, 55),
      crlaTransitioning => (50, 75),
      _ => (65, 95),
    };
    final wpm = _between(rng, wLo, wHi);
    final secs = max(1, min(cap, (read * 60 / wpm).round()));
    final plan = CrlaPlan(task1, t2Low, t2High, t2, storyWords - read, secs ~/ 60, secs % 60, comprehension);
    if (_crlaProfileOf(plan, grade, variant, storyWords, t) == profile) return plan;
  }
  throw StateError('no CRLA plan reaches "$profile" for G$grade $variant ($storyWords words)');
}

// ---- Phil-IRI ----

PhilIriLevel demoPhilIriLevel(DemoBand b) => switch (b) {
      DemoBand.nonReader => PhilIriLevel.nonReader,
      DemoBand.struggling => PhilIriLevel.struggling,
      DemoBand.frustration => PhilIriLevel.frustration,
      DemoBand.instructional => PhilIriLevel.instructional,
      DemoBand.independent => PhilIriLevel.independent,
    };

typedef DemoMiscue = ({int wordIndex, PhilIriMiscueType type, bool selfCorrected});

class PhilIriPlan {
  final List<DemoMiscue> miscues;
  final int readingSeconds;
  final int correctAnswers;
  const PhilIriPlan(this.miscues, this.readingSeconds, this.correctAnswers);
}

PhilIriLevel _philIriProfileOf(int words, int counted, int seconds, int correct, int questions, PhilIriThresholds t) {
  final accuracy = philIriAccuracyLevel(philIriWordReadingScore(words, counted), t);
  final speed = philIriSpeed(philIriWordsPerMinute(words, seconds), t);
  final comprehension = philIriComprehensionLevel(philIriComprehensionScore(correct, questions), t);
  return philIriPassageProfile(philIriWordReadingLevel(accuracy, speed), comprehension);
}

/// Weighted like real oral readings: mispronunciations and substitutions
/// most, transpositions and reversals rarely.
const _miscueWeights = {
  PhilIriMiscueType.mispronunciation: 30,
  PhilIriMiscueType.substitution: 25,
  PhilIriMiscueType.omission: 20,
  PhilIriMiscueType.insertion: 10,
  PhilIriMiscueType.repetition: 10,
  PhilIriMiscueType.transposition: 3,
  PhilIriMiscueType.reversal: 2,
};

PhilIriMiscueType _miscueType(Random rng) {
  var n = rng.nextInt(_miscueWeights.values.reduce((a, b) => a + b));
  for (final MapEntry(key: type, value: w) in _miscueWeights.entries) {
    if (n < w) return type;
    n -= w;
  }
  return PhilIriMiscueType.mispronunciation;
}

/// A passage reading of [words] that scores as [target]: miscues on real
/// word positions (about 1 in 6 extra self-corrections, which don't count),
/// a reading time and how many of [questionCount] answers are right.
/// [silent]: no miscues (word reading counts as 100%); a Non-Reader can't
/// be planned silently.
PhilIriPlan philIriPlanFor({
  required DemoBand target,
  required List<String> words,
  required int questionCount,
  required Random rng,
  bool silent = false,
  PhilIriThresholds t = PhilIriThresholds.defaults,
}) {
  if (silent && target == DemoBand.nonReader) {
    throw ArgumentError('a Non-Reader is identified by oral reading only');
  }
  final level = demoPhilIriLevel(target);
  final n = words.length;
  final (aLo, aHi) = switch (target) {
    DemoBand.nonReader => (15, 35),
    DemoBand.struggling => (40, 55),
    DemoBand.frustration => (70, 89),
    DemoBand.instructional => (90, 96),
    DemoBand.independent => (97, 100),
  };
  final (wLo, wHi) = switch (target) {
    DemoBand.nonReader => (30, 70),
    DemoBand.struggling => silent ? (45, 75) : (40, 90),
    DemoBand.frustration => silent ? (50, 120) : (80, 140),
    DemoBand.instructional => silent ? (80, 120) : (100, 150),
    DemoBand.independent => (125, 180),
  };
  final (cLo, cHi) = switch (target) {
    DemoBand.nonReader => (0, 50),
    DemoBand.struggling => (0, 40),
    DemoBand.frustration => (41, 79),
    DemoBand.instructional => (59, 79),
    DemoBand.independent => (80, 100),
  };
  for (var i = 0; i < _tries; i++) {
    final counted = silent ? 0 : (n * (100 - _between(rng, aLo, aHi)) / 100).round();
    final seconds = max(1, (n * 60 / _between(rng, wLo, wHi)).round());
    final correct = (questionCount * _between(rng, cLo, cHi) / 100).round().clamp(0, questionCount);
    if (_philIriProfileOf(n, counted, seconds, correct, questionCount, t) != level) continue;
    if (silent) return PhilIriPlan(const [], seconds, correct);

    // Extra self-corrections (recorded, not counted): about 1 in 6 of all.
    var corrected = 0;
    for (var k = 0; k < counted; k++) {
      if (rng.nextInt(5) == 0) corrected++;
    }
    // Distinct positions; the last word is kept free so transpositions and
    // reversals always have a next word.
    final positions = List.generate(n - 1, (k) => k)..shuffle(rng);
    if (counted + corrected > positions.length) corrected = max(0, positions.length - counted);
    final miscues = <DemoMiscue>[
      for (var k = 0; k < counted + corrected; k++)
        (wordIndex: positions[k], type: _miscueType(rng), selfCorrected: k >= counted),
    ]..sort((a, b) => a.wordIndex.compareTo(b.wordIndex));
    return PhilIriPlan(miscues, seconds, correct);
  }
  throw StateError('no Phil-IRI plan reaches ${level.label} ($n words, $questionCount questions, silent: $silent)');
}

/// A GST raw score for a learner reading at [target]: grade-level readers
/// pass, Struggling and Non-Readers don't, Frustration readers are near the mark.
int gstScoreFor({required DemoBand target, required int grade, required Random rng, PhilIriThresholds t = PhilIriThresholds.defaults}) {
  final maxScore = philIriGstMaxScore(grade);
  final pass = grade >= 7 ? t.gstJhsPassMin : t.gstElementaryPassMin;
  final (lo, hi) = switch (target) {
    DemoBand.independent => (pass + (maxScore - pass) ~/ 2, maxScore),
    DemoBand.instructional => (pass, pass + (maxScore - pass) ~/ 2),
    DemoBand.frustration => (pass - 3, pass + 1),
    DemoBand.struggling => (pass ~/ 2, pass - 2),
    DemoBand.nonReader => (0, pass ~/ 2),
  };
  return _between(rng, lo, hi).clamp(0, maxScore);
}

/// The GST total split into literal / inferential / critical items (about
/// 40 / 35 / 25 %), summing to [total].
({int literal, int inferential, int critical}) gstSplitFor(int total, Random rng) {
  final literal = min(total, (total * 0.4).round() + rng.nextInt(2));
  final inferential = min(total - literal, (total * 0.35).round());
  return (literal: literal, inferential: inferential, critical: total - literal - inferential);
}
