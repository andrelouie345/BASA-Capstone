// Phil-IRI word recognition bands (DepEd, 2026) and ma's Table 8 ("Student's
// Reading Profile Per Passage"): spec
// docs/superpowers/specs/2026-10-29-phil-iri-word-recognition-bands-design.md.
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/services/phil_iri_results.dart';
import 'package:basa_capstone/core/services/phil_iri_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const ind = PhilIriLevel.independent;
const ins = PhilIriLevel.instructional;
const fru = PhilIriLevel.frustration;
const str = PhilIriLevel.struggling;
const non = PhilIriLevel.nonReader;

void main() {
  test('lookup 1 every cell', () {
    // word recognition -> [Fast, Average, Slow, Struggling]
    const table = {
      ind: [ind, ind, ins, fru],
      ins: [ins, ins, ins, str],
      fru: [fru, fru, fru, str],
      str: [str, str, str, str],
      non: [non, non, non, non],
    };
    const speeds = [PhilIriSpeed.fast, PhilIriSpeed.average, PhilIriSpeed.slow, PhilIriSpeed.struggling];
    for (final row in table.entries) {
      for (var i = 0; i < speeds.length; i++) {
        expect(philIriWordReadingLevel(row.key, speeds[i]), row.value[i], reason: '${row.key} x ${speeds[i]}');
      }
    }
  });

  test('lookup 2 every cell', () {
    // word reading profile -> [comprehension Independent, Instructional, Frustration]
    const table = {
      ind: [ind, ins, fru],
      ins: [ind, ins, fru],
      fru: [ins, fru, fru],
      str: [str, str, str],
      non: [non, non, non],
    };
    const comps = [ind, ins, fru];
    for (final row in table.entries) {
      for (var i = 0; i < comps.length; i++) {
        expect(philIriPassageProfile(row.key, comps[i]), row.value[i], reason: '${row.key} x ${comps[i]}');
      }
    }
  });

  test('comprehension struggling or non-reader is an error', () {
    expect(() => philIriPassageProfile(ins, str), throwsArgumentError);
    expect(() => philIriPassageProfile(ins, non), throwsArgumentError);
  });

  test('band edges', () {
    expect(philIriAccuracyLevel(0.35), non);
    expect(philIriAccuracyLevel(0.36), str);
    expect(philIriAccuracyLevel(0.55), str);
    expect(philIriAccuracyLevel(0.56), fru);
    expect(philIriAccuracyLevel(0.89), fru);
    expect(philIriAccuracyLevel(0.90), ins);
    expect(philIriAccuracyLevel(0.97), ind);
    expect(philIriAccuracyLevel(0.355), str); // rounds half up to 36
  });

  test('struggling adjusted level equals frustration\'s', () {
    for (final c in [0.20, 0.27, 0.40, 0.60, 0.79]) {
      expect(philIriAdjustedLevel(str, 7, c), philIriAdjustedLevel(fru, 7, c), reason: 'comprehension $c');
    }
    expect(philIriAdjustedLevel(non, 7, 0.9), 0);
  });

  test('end result prefers Frustration over Struggling', () {
    PhilIriRoundResult r(PhilIriRound round, PhilIriLevel p) =>
        PhilIriRoundResult(round: round, given: true, profile: p);
    expect(philIriEndResult([r(PhilIriRound.mosy1, str), r(PhilIriRound.mosy2, fru)])!.round, PhilIriRound.mosy2);
    expect(philIriEndResult([r(PhilIriRound.mosy1, fru), r(PhilIriRound.mosy2, str)])!.round, PhilIriRound.mosy1);
  });

  test('not grade ready', () {
    for (final p in [fru, str, non]) {
      expect(philIriNotGradeReady(p), isTrue, reason: '$p');
    }
    for (final p in [ins, ind, null]) {
      expect(philIriNotGradeReady(p), isFalse, reason: '$p');
    }
  });

  test('finalized snapshot without struggling key loads with 55', () {
    final t = PhilIriThresholds.fromMap({'non_reader_max': 50});
    expect(t.wordReadingStrugglingMax, 55);
    expect(t.nonReaderMax, 50);
  });

  test('defaults', () {
    expect(PhilIriThresholds.defaults.nonReaderMax, 35);
    expect(PhilIriThresholds.defaults.wordReadingStrugglingMax, 55);
    expect(PhilIriThresholds.defaults.toMap()['word_reading_struggling_max'], 55);
  });

  test('validate refuses struggling max at or below non-reader max', () {
    expect(() => const PhilIriThresholds(nonReaderMax: 35, wordReadingStrugglingMax: 30).validate(),
        throwsArgumentError);
    expect(() => const PhilIriThresholds(wordReadingStrugglingMax: 90).validate(), throwsArgumentError);
    PhilIriThresholds.defaults.validate(); // the defaults themselves are valid
  });

  test('fromString parses struggling', () {
    expect(PhilIriLevel.fromString('struggling'), str);
    expect(PhilIriLevel.fromString('Struggling'), str);
  });

  test('scorePassage uses the table', () {
    // The command pass's learner B: 53/60 = 88% Frustration, 60 wpm Struggling, 3/10.
    final r = philIriScorePassage(
        wordCount: 60,
        method: PhilIriReadingMethod.oneMinute,
        wordsRead: 60,
        countedMiscues: 7,
        comprehensionCorrect: 3,
        comprehensionTotal: 10);
    expect(r.accuracyLevel, fru);
    expect(r.speed, PhilIriSpeed.struggling);
    expect(r.wordReadingLevel, str);
    expect(r.profile, str);
  });
}
