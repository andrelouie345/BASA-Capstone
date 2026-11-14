// philIriRoundView: a round as a list shows it under carried or actual values
// (spec docs/superpowers/specs/2026-11-14-phil-iri-value-sources-design.md,
// D3, D5, D11). Grade 7 throughout.
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:basa_capstone/core/services/phil_iri_results.dart';
import 'package:basa_capstone/core/services/phil_iri_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const carried = PhilIriValues.carried, actual = PhilIriValues.actual;
const bosy = PhilIriRound.bosy, mosy1 = PhilIriRound.mosy1;

/// One-minute reading of [wordsRead] words; comprehension [correct]/10.
PhilIriPassageResult oneMinute(int wordsRead, int miscues, int? correct) => philIriScorePassage(
      wordCount: 150,
      method: PhilIriReadingMethod.oneMinute,
      wordsRead: wordsRead,
      countedMiscues: miscues,
      comprehensionCorrect: correct,
      comprehensionTotal: correct == null ? null : 10,
    );

/// A silent whole-text reading of 150 words in [seconds]; comprehension [correct]/10.
PhilIriPassageResult silent(int seconds, int correct) => philIriScorePassage(
      wordCount: 150,
      method: PhilIriReadingMethod.silent,
      readingSeconds: seconds,
      countedMiscues: 0,
      comprehensionCorrect: correct,
      comprehensionTotal: 10,
    );

PhilIriRoundResult at(List<PhilIriRoundResult> rounds, PhilIriRound r) => rounds.firstWhere((x) => x.round == r);

PhilIriRoundView viewOf(PhilIriRoundResult r, PhilIriValues v) =>
    philIriRoundView(r, v, ownReading: r.given, learnerGrade: 7);

void main() {
  test('carried copies the round result', () {
    final rounds = philIriRoundResults(learnerGrade: 7, readings: {bosy: oneMinute(120, 3, 8), mosy1: oneMinute(100, 0, 5)});
    for (final r in rounds) {
      final v = viewOf(r, carried);
      expect(v.round, r.round);
      expect(v.values, carried);
      expect(v.notAssessedThisRound, isFalse);
      expect(v.notAssessed, r.notAssessed);
      expect((v.wordReadingScore, v.wordsPerMinute, v.comprehensionScore),
          (r.wordReadingScore, r.wordsPerMinute, r.comprehensionScore));
      expect((v.accuracyLevel, v.speed, v.wordReadingLevel, v.comprehensionLevel),
          (r.accuracyLevel, r.speed, r.wordReadingLevel, r.comprehensionLevel));
      expect((v.profile, v.adjustedLevel, v.levelsDown), (r.profile, r.adjustedLevel, r.levelsDown));
      expect((v.wordReadingAssumed, v.silentOnly, v.status), (r.wordReadingAssumed, false, r.status));
      expect((v.wordReadingPercent, v.comprehensionPercent, v.adjustedLevelLabel, v.levelsDownLabel),
          (r.wordReadingPercent, r.comprehensionPercent, r.adjustedLevelLabel, r.levelsDownLabel));
    }
  });

  test('actual with an own reading: the round alone (MOSY1 50% comp, carried 80%)', () {
    final rounds = philIriRoundResults(learnerGrade: 7, readings: {bosy: oneMinute(120, 0, 8), mosy1: oneMinute(120, 0, 5)});
    final m = at(rounds, mosy1);
    expect(viewOf(m, carried).comprehensionScore, 0.8);
    final v = viewOf(m, actual);
    expect(v.values, actual);
    expect(v.notAssessedThisRound, isFalse);
    expect(v.comprehensionScore, 0.5);
    expect(v.comprehensionLevel, m.actual!.comprehensionLevel);
    expect((v.wordReadingScore, v.wordsPerMinute), (m.actual!.wordReadingScore, m.actual!.wordsPerMinute));
    expect((v.profile, v.adjustedLevel, v.levelsDown), (m.actualProfile, m.actualAdjustedLevel, m.actualLevelsDown));
    expect(v.profile, isNot(viewOf(m, carried).profile));
  });

  test('actual without an own reading: the not-assessed stand-in, flagged', () {
    final rounds = philIriRoundResults(learnerGrade: 7, readings: {bosy: oneMinute(120, 0, 8)});
    final v = viewOf(at(rounds, mosy1), actual);
    expect(v.notAssessedThisRound, isTrue);
    expect(v.profile, PhilIriLevel.struggling);
    expect((v.adjustedLevel, v.levelsDown), (4, 3));
    expect((v.wordReadingScore, v.comprehensionScore, v.wordsPerMinute), (null, null, null));
    // Under carried the same round shows BOSY's result carried forward.
    expect(viewOf(at(rounds, mosy1), carried).profile, at(rounds, bosy).profile);
    // A Grade 2 stand-in never goes below Grade 1.
    expect(philIriRoundView(at(rounds, mosy1), actual, ownReading: false, learnerGrade: 2).adjustedLevel, 1);
  });

  test('GST-only BOSY: actual is not assessed this round, carried shows the GST', () {
    final b = at(philIriRoundResults(learnerGrade: 7, gstScore: 0.9, readings: {}), bosy);
    expect(philIriRoundView(b, actual, ownReading: false, learnerGrade: 7).notAssessedThisRound, isTrue);
    final c = philIriRoundView(b, carried, ownReading: false, learnerGrade: 7);
    expect((c.notAssessedThisRound, c.comprehensionScore, c.profile), (false, 0.9, b.profile));
  });

  test('silent only: word reading 1.0 marked silentOnly under both values', () {
    final rounds = philIriRoundResults(learnerGrade: 7, readings: {bosy: silent(90, 8)});
    final b = at(rounds, bosy);
    expect(b.wordReadingSilentOnly, isTrue);
    final c = viewOf(b, carried), a = viewOf(b, actual);
    expect((c.wordReadingScore, c.silentOnly), (1.0, true));
    expect((a.wordReadingScore, a.silentOnly), (1.0, true));
    // An oral reading later: the carried accuracy is measured, no longer silent-only.
    final later = philIriRoundResults(learnerGrade: 7, readings: {bosy: silent(90, 8), mosy1: oneMinute(120, 3, 8)});
    expect(at(later, mosy1).wordReadingSilentOnly, isFalse);
    expect(viewOf(at(later, mosy1), carried).silentOnly, isFalse);
    expect(at(philIriRoundResults(learnerGrade: 7, readings: {bosy: oneMinute(120, 0, 8)}), bosy).wordReadingSilentOnly,
        isFalse);
  });

  test('comprehension-only import: word reading assumed, no value under actual', () {
    final compOnly = philIriScorePassage(
      wordCount: 150,
      method: PhilIriReadingMethod.wholeText,
      countedMiscues: 0,
      comprehensionCorrect: 6,
      comprehensionTotal: 10,
      allowNoWordReading: true,
    );
    final rounds = philIriRoundResults(learnerGrade: 7, readings: {bosy: oneMinute(120, 0, 8), mosy1: compOnly});
    final a = viewOf(at(rounds, mosy1), actual);
    expect((a.wordReadingAssumed, a.wordReadingScore, a.wordsPerMinute, a.silentOnly), (true, null, null, false));
    expect(a.comprehensionScore, 0.6);
    // Carried keeps BOSY's measured word reading.
    final c = viewOf(at(rounds, mosy1), carried);
    expect((c.wordReadingAssumed, c.wordReadingScore), (false, at(rounds, bosy).wordReadingScore));
  });
}
