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

  test('a reading without comprehension counts when its round is in comprehensionOptional', () {
    // The FLT toggle (report_settings no_comprehension_counts_FLT): the
    // ViewModel passes the rounds read from a collection without comprehension.
    final on = at(
        philIriRoundResults(
            learnerGrade: 7,
            readings: {PhilIriRound.bosy: oneMinute(120, 0, null)},
            comprehensionOptional: {PhilIriRound.bosy}),
        PhilIriRound.bosy);
    expect(on.status, PhilIriRoundStatus.assessed);
    expect(on.comprehensionAssessed, isFalse); // still not entered
    final off = at(philIriRoundResults(learnerGrade: 7, readings: {PhilIriRound.bosy: oneMinute(120, 0, null)}),
        PhilIriRound.bosy);
    expect(off.status, PhilIriRoundStatus.carriedOver);
    // A round with no reading of its own is never made assessed by the set.
    final none = at(philIriRoundResults(learnerGrade: 7, gstScore: 0.9, readings: {}, comprehensionOptional: {PhilIriRound.bosy}),
        PhilIriRound.bosy);
    expect(none.status, PhilIriRoundStatus.carriedOver);
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

  // R2 (spec 2026-11-10-phil-iri-untitled-readings D4-D9): imported readings
  // without a passage (typed word count) and without a word reading.
  group('untitled and comprehension-only', () {
    PhilIriPassageResult compOnly(int correct, int total) => philIriScorePassage(
          method: PhilIriReadingMethod.wholeText,
          countedMiscues: 0,
          comprehensionCorrect: correct,
          comprehensionTotal: total,
          allowNoWordReading: true,
        );

    test('untitled whole text uses the typed word count', () {
      final r = philIriScorePassage(
          wordCount: 120, method: PhilIriReadingMethod.wholeText, readingSeconds: 60, countedMiscues: 6);
      expect(r.wordReadingScore, 114 / 120);
      expect(r.wordsPerMinute, 120);
      expect(r.wordReadingAssumed, isFalse);
    });

    test('one minute needs no word count', () {
      final r = philIriScorePassage(method: PhilIriReadingMethod.oneMinute, wordsRead: 70, countedMiscues: 7);
      expect(r.wordReadingScore, 63 / 70);
    });

    test('whole text with seconds but no word count throws', () {
      expect(() => philIriScorePassage(method: PhilIriReadingMethod.wholeText, readingSeconds: 60, countedMiscues: 0),
          throwsArgumentError);
    });

    test('no word reading with allowNoWordReading', () {
      final r = compOnly(6, 8);
      final comp = philIriComprehensionLevel(0.75);
      expect(r.wordReadingLevel, isNull);
      expect(r.accuracyLevel, isNull);
      expect(r.speed, isNull);
      expect(r.wordReadingScore, isNull);
      expect(r.wordsPerMinute, isNull);
      expect(r.wordReadingPercent, isNull);
      expect(r.wordReadingAssumed, isTrue);
      expect(r.comprehensionScore, 0.75);
      expect(r.comprehensionLevel, comp);
      expect(r.profile, philIriPassageProfile(str, comp));
    });

    test('no word reading without the flag still throws', () {
      expect(() => philIriScorePassage(method: PhilIriReadingMethod.wholeText, countedMiscues: 0), throwsArgumentError);
      expect(() => philIriScorePassage(method: PhilIriReadingMethod.oneMinute, countedMiscues: 0), throwsArgumentError);
    });

    test('comprehension-only round is carried over', () {
      final rounds = philIriRoundResults(learnerGrade: 7, readings: {
        PhilIriRound.bosy: oneMinute(120, 0, 5),
        PhilIriRound.mosy1: compOnly(8, 10),
      });
      final bosy = at(rounds, PhilIriRound.bosy);
      final mosy1 = at(rounds, PhilIriRound.mosy1);
      expect(bosy.status, PhilIriRoundStatus.assessed);
      expect(mosy1.status, PhilIriRoundStatus.carriedOver);
      expect(mosy1.given, isTrue);
      expect(mosy1.wordReadingAssessed, isFalse);
      expect(mosy1.comprehensionAssessed, isTrue);
      expect(mosy1.wordReadingAssumed, isFalse);
      expect(mosy1.wordReadingLevel, bosy.wordReadingLevel);
      expect(mosy1.wordReadingScore, bosy.wordReadingScore);
      expect(mosy1.comprehensionScore, 0.8);
    });

    test('comprehension-only with nothing earlier is assumed Struggling', () {
      final mosy1 = at(philIriRoundResults(learnerGrade: 7, readings: {PhilIriRound.mosy1: compOnly(8, 10)}),
          PhilIriRound.mosy1);
      expect(mosy1.wordReadingLevel, str);
      expect(mosy1.wordReadingAssumed, isTrue);
      expect(mosy1.accuracyLevel, isNull);
      expect(mosy1.status, PhilIriRoundStatus.carriedOver);
    });

    test('FLT toggle does not make a comprehension-only round assessed', () {
      final mosy1 = at(
          philIriRoundResults(
              learnerGrade: 7,
              readings: {PhilIriRound.mosy1: compOnly(8, 10)},
              comprehensionOptional: {PhilIriRound.mosy1}),
          PhilIriRound.mosy1);
      expect(mosy1.status, PhilIriRoundStatus.carriedOver);
    });

    test('comprehension-only round adjusts from its own percent', () {
      // 5/10 = 50%: Frustration; Struggling word reading x Frustration = Struggling;
      // adjusted by the round's own 50% like a Frustration reader.
      final rounds = philIriRoundResults(learnerGrade: 7, readings: {PhilIriRound.mosy1: compOnly(5, 10)});
      final mosy1 = at(rounds, PhilIriRound.mosy1);
      expect(mosy1.comprehensionLevel, fru);
      expect(mosy1.adjustedLevel, philIriAdjustedLevel(mosy1.profile!, 7, 0.5, PhilIriThresholds.defaults));
      expect(mosy1.actualAdjustedLevel, mosy1.adjustedLevel);
    });
  });
}
