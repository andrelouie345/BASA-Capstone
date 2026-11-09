// Per-round assessment status and "not assessed = Struggling" (spec
// docs/superpowers/specs/2026-11-09-phil-iri-rules-update-design.md, D4-D9).
// Grade 7 throughout.
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/services/phil_iri_results.dart';
import 'package:basa_capstone/core/services/phil_iri_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const ind = PhilIriLevel.independent;
const ins = PhilIriLevel.instructional;
const fru = PhilIriLevel.frustration;
const str = PhilIriLevel.struggling;

/// One-minute reading of [wordsRead] words with [miscues]; comprehension
/// [correct]/10, or none when [correct] is null.
PhilIriPassageResult oneMinute(int wordsRead, int miscues, int? correct) => philIriScorePassage(
      wordCount: 150,
      method: PhilIriReadingMethod.oneMinute,
      wordsRead: wordsRead,
      countedMiscues: miscues,
      comprehensionCorrect: correct,
      comprehensionTotal: correct == null ? null : 10,
    );

PhilIriRoundResult at(List<PhilIriRoundResult> rounds, PhilIriRound r) => rounds.firstWhere((x) => x.round == r);

void main() {
  test('GST-only BOSY is carried over and Struggling', () {
    final bosy = at(philIriRoundResults(learnerGrade: 7, gstScore: 0.9, readings: {}), PhilIriRound.bosy);
    expect(bosy.status, PhilIriRoundStatus.carriedOver);
    expect(bosy.wordReadingAssumed, isTrue);
    expect(bosy.wordReadingAssessed, isFalse);
    expect(bosy.comprehensionAssessed, isFalse);
    expect(bosy.accuracyLevel, isNull);
    expect(bosy.speed, isNull);
    expect(bosy.wordReadingLevel, str);
    expect(bosy.profile, str);
    expect(bosy.adjustedLevel, 6);
    expect(bosy.levelsDown, 1);
  });

  test('reading with comprehension is assessed', () {
    final bosy = at(philIriRoundResults(learnerGrade: 7, readings: {PhilIriRound.bosy: oneMinute(120, 0, 2)}),
        PhilIriRound.bosy);
    expect(bosy.status, PhilIriRoundStatus.assessed);
    expect(bosy.wordReadingAssessed, isTrue);
    expect(bosy.comprehensionAssessed, isTrue);
    expect(bosy.wordReadingAssumed, isFalse);
    expect(bosy.comprehensionLevel, str);
    expect(bosy.wordReadingLevel, ins);
    expect(bosy.profile, str);
    expect(bosy.adjustedLevel, 3);
  });

  test('reading without comprehension: word reading only', () {
    final bosy = at(philIriRoundResults(learnerGrade: 7, readings: {PhilIriRound.bosy: oneMinute(120, 0, null)}),
        PhilIriRound.bosy);
    expect(bosy.wordReadingAssessed, isTrue);
    expect(bosy.comprehensionAssessed, isFalse);
    expect(bosy.status, PhilIriRoundStatus.carriedOver);
    expect(bosy.comprehensionLevel, str);
  });

  test('blank comprehension adjusts from the carried percent', () {
    final rounds = philIriRoundResults(learnerGrade: 7, readings: {
      PhilIriRound.bosy: oneMinute(120, 0, 5),
      PhilIriRound.mosy1: oneMinute(120, 0, null),
    });
    expect(at(rounds, PhilIriRound.bosy).profile, fru);
    expect(at(rounds, PhilIriRound.bosy).adjustedLevel, 6);
    final mosy1 = at(rounds, PhilIriRound.mosy1);
    expect(mosy1.profile, fru);
    expect(mosy1.adjustedLevel, 6); // carried 50% -> 1 down (blank as 0% would give 3)
    expect(mosy1.status, PhilIriRoundStatus.carriedOver);
  });

  test('first reading in MOSY 1', () {
    final rounds = philIriRoundResults(learnerGrade: 7, readings: {PhilIriRound.mosy1: oneMinute(120, 0, 8)});
    expect(at(rounds, PhilIriRound.bosy).status, PhilIriRoundStatus.notAssessed);
    expect(at(rounds, PhilIriRound.bosy).profile, isNull);
    expect(at(rounds, PhilIriRound.mosy1).status, PhilIriRoundStatus.assessed);
    expect(at(rounds, PhilIriRound.mosy2).status, PhilIriRoundStatus.carriedOver);
  });

  test('silent reading counts', () {
    final silent = philIriScorePassage(
      wordCount: 150,
      method: PhilIriReadingMethod.silent,
      readingSeconds: 60,
      countedMiscues: 0,
      comprehensionCorrect: 8,
      comprehensionTotal: 10,
    );
    final bosy = at(philIriRoundResults(learnerGrade: 7, readings: {PhilIriRound.bosy: silent}), PhilIriRound.bosy);
    expect(bosy.wordReadingAssessed, isTrue);
    expect(bosy.status, PhilIriRoundStatus.assessed);
    expect(bosy.profile, ind);
  });

  test('nothing all year', () {
    final rounds = philIriRoundResults(learnerGrade: 7, readings: {});
    for (final r in rounds) {
      expect(r.status, PhilIriRoundStatus.notAssessed, reason: '${r.round}');
    }
    final assumed = philIriNotAssessedResult(PhilIriRound.bosy, 7);
    expect(assumed.profile, str);
    expect(assumed.adjustedLevel, 4);
    expect(assumed.levelsDown, 3);
    expect(assumed.notAssessed, isTrue);
  });
}
