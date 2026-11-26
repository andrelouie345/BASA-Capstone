// Records from a target band (demo-data plan Task 3): every generated CRLA
// and Phil-IRI record must score, with BASA's own rule functions, as the band
// it was generated for.
import 'dart:math';

import 'package:basa_capstone/core/models/phil_iri_miscue.dart';
import 'package:basa_capstone/core/services/crla_rules.dart';
import 'package:basa_capstone/core/services/phil_iri_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/demo_data/records.dart';
import '../../../tool/demo_data/world.dart';

/// The profile BASA gives a CRLA plan (the scoresheet formulas).
String? _crlaProfile(CrlaPlan p, int grade, String variant, int storyWords) {
  final english = variant == 'eng';
  final total = english
      ? p.task1 + (p.task2 ?? 0)
      : p.task1 < 7
          ? p.task1 + (p.task2Low ?? 0)
          : p.task1 + 10 + (p.task2High ?? 0);
  final part1 = english ? crlaPart1EnglishLevel(total) : crlaPart1StandardLevel(p.task1, total);
  final wordsRead = crlaWordsRead(storyWords: storyWords, miscues: p.miscues);
  return crlaReadingProfile(
      part1Level: part1, pct: wordsRead / storyWords, comprehension: p.comprehension, grade: grade, variant: variant);
}

/// The profile BASA gives a Phil-IRI plan on a passage of [words] words.
PhilIriLevel _philIriProfile(PhilIriPlan p, int words, int questions) {
  final counted = p.miscues.where((m) => !m.selfCorrected).length;
  final accuracy = philIriAccuracyLevel(philIriWordReadingScore(words, counted));
  final speed = philIriSpeed(philIriWordsPerMinute(words, p.readingSeconds));
  final comprehension = philIriComprehensionLevel(philIriComprehensionScore(p.correctAnswers, questions));
  return philIriPassageProfile(philIriWordReadingLevel(accuracy, speed), comprehension);
}

const _crlaCases = [(1, 'mt', 60), (2, 'fil', 80), (3, 'eng', 100)];
const _profiles = [crlaLowEmerging, crlaHighEmerging, crlaDeveloping, crlaTransitioning, crlaAtGradeLevel];

void main() {
  test('crla profile for each band', () {
    final rng = Random(1);
    expect(crlaProfileFor(DemoBand.nonReader, rng), crlaLowEmerging);
    expect(crlaProfileFor(DemoBand.struggling, rng), crlaLowEmerging);
    expect(crlaProfileFor(DemoBand.frustration, rng), crlaHighEmerging);
    expect(crlaProfileFor(DemoBand.instructional, rng), crlaDeveloping);
    final top = {for (var i = 0; i < 40; i++) crlaProfileFor(DemoBand.independent, rng)};
    expect(top, {crlaTransitioning, crlaAtGradeLevel});
  });

  test('crla plan scores as planned', () {
    for (final (grade, variant, words) in _crlaCases) {
      for (final profile in _profiles) {
        for (var seed = 0; seed < 50; seed++) {
          final p = crlaPlanFor(
              profile: profile, grade: grade, variant: variant, storyWords: words, rng: Random(seed));
          final why = 'G$grade $variant $profile seed $seed';
          expect(_crlaProfile(p, grade, variant, words), profile, reason: why);
          // Task 2 as the scoresheet asks: standard low for task 1 0-6, high
          // for 7+; English task 2 only from task 1 of 1.
          if (variant == 'eng') {
            expect(p.task2Low ?? p.task2High, isNull, reason: why);
            if (p.task1 == 0) expect(p.task2, isNull, reason: why);
          } else {
            expect(p.task2, isNull, reason: why);
            expect(p.task1 < 7 ? (p.task2Low != null && p.task2High == null) : (p.task2High != null && p.task2Low == null),
                isTrue, reason: why);
          }
          for (final s in [p.task1, p.task2Low, p.task2High, p.task2]) {
            if (s != null) expect(s, inInclusiveRange(0, 10), reason: why);
          }
          expect(p.comprehension, inInclusiveRange(0, crlaComprehensionMax(grade, variant)), reason: why);
          expect(p.minutes * 60 + p.seconds, inInclusiveRange(1, crlaTimeCapSeconds(grade, variant)), reason: why);
          expect(p.seconds, inInclusiveRange(0, 59), reason: why);
        }
      }
    }
  });

  test('phil-iri plan scores as planned (oral)', () {
    final words = List.generate(150, (i) => 'w$i');
    for (final band in DemoBand.values) {
      for (var seed = 0; seed < 50; seed++) {
        final p = philIriPlanFor(target: band, words: words, questionCount: 8, rng: Random(seed));
        expect(_philIriProfile(p, 150, 8), demoPhilIriLevel(band), reason: '${band.name} seed $seed');
      }
    }
  });

  test('phil-iri plan with 5 questions still reaches every band', () {
    final words = List.generate(120, (i) => 'w$i');
    for (final band in DemoBand.values) {
      for (var seed = 0; seed < 20; seed++) {
        final p = philIriPlanFor(target: band, words: words, questionCount: 5, rng: Random(seed));
        expect(_philIriProfile(p, 120, 5), demoPhilIriLevel(band), reason: '${band.name} seed $seed');
      }
    }
  });

  test('silent plan: no miscues, scores as planned; a Non-Reader cannot read silently', () {
    final words = List.generate(150, (i) => 'w$i');
    for (final band in DemoBand.values.where((b) => b != DemoBand.nonReader)) {
      for (var seed = 0; seed < 20; seed++) {
        final p = philIriPlanFor(target: band, words: words, questionCount: 8, rng: Random(seed), silent: true);
        expect(p.miscues, isEmpty);
        expect(_philIriProfile(p, 150, 8), demoPhilIriLevel(band), reason: '${band.name} seed $seed');
      }
    }
    expect(() => philIriPlanFor(target: DemoBand.nonReader, words: words, questionCount: 8, rng: Random(0), silent: true),
        throwsArgumentError);
  });

  test('miscues are on real words', () {
    final words = List.generate(150, (i) => 'w$i');
    var selfCorrected = 0, all = 0;
    for (var seed = 0; seed < 50; seed++) {
      final p = philIriPlanFor(target: DemoBand.frustration, words: words, questionCount: 8, rng: Random(seed));
      final idx = p.miscues.map((m) => m.wordIndex).toList();
      expect(idx.toSet(), hasLength(idx.length), reason: 'seed $seed: one miscue per position');
      for (final m in p.miscues) {
        final max = m.type == PhilIriMiscueType.insertion ? words.length : words.length - 1;
        expect(m.wordIndex, inInclusiveRange(0, max));
        if (m.type == PhilIriMiscueType.transposition || m.type == PhilIriMiscueType.reversal) {
          expect(m.wordIndex, lessThan(words.length - 1), reason: 'needs a next word');
        }
      }
      if (p.miscues.length >= 4) expect(p.miscues.map((m) => m.type).toSet().length, greaterThanOrEqualTo(2));
      selfCorrected += p.miscues.where((m) => m.selfCorrected).length;
      all += p.miscues.length;
    }
    expect(selfCorrected / all, inInclusiveRange(0.08, 0.25));
  });

  test('gst score follows the band', () {
    for (final grade in [4, 7, 10]) {
      for (var seed = 0; seed < 30; seed++) {
        for (final band in DemoBand.values) {
          final s = gstScoreFor(target: band, grade: grade, rng: Random(seed));
          expect(s, inInclusiveRange(0, philIriGstMaxScore(grade)));
          final passed = philIriGstPassed(grade, s);
          if (band == DemoBand.independent || band == DemoBand.instructional) expect(passed, isTrue);
          if (band == DemoBand.nonReader || band == DemoBand.struggling) expect(passed, isFalse);
        }
        final split = gstSplitFor(31, Random(seed));
        expect(split.literal + split.inferential + split.critical, 31);
      }
    }
  });
}
