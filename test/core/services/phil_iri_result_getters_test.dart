// Whole percents and labels of Phil-IRI results, as a screen shows them
// (screen inventory PHILIRI-G2): the same rounding and wording as the reports.
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const passage = PhilIriPassageResult(
    wordReadingScore: 0.97,
    wordsPerMinute: 120,
    accuracyLevel: PhilIriLevel.independent,
    speed: PhilIriSpeed.average,
    wordReadingLevel: PhilIriLevel.independent,
    comprehensionScore: 0.625,
    comprehensionLevel: PhilIriLevel.instructional,
    profile: PhilIriLevel.instructional,
  );

  test('passage result percents', () {
    expect(passage.wordReadingPercent, 97);
    expect(passage.comprehensionPercent, 63);
  });

  test('passage result with a blank comprehension', () {
    const blank = PhilIriPassageResult(
      wordReadingScore: 1,
      wordsPerMinute: 100,
      accuracyLevel: PhilIriLevel.independent,
      speed: PhilIriSpeed.average,
      wordReadingLevel: PhilIriLevel.independent,
      comprehensionLevel: PhilIriLevel.frustration,
      profile: PhilIriLevel.frustration,
    );

    expect(blank.comprehensionPercent, isNull);
  });

  test('round result percents and labels', () {
    const r = PhilIriRoundResult(
        round: PhilIriRound.bosy, given: true, wordReadingScore: 0.9, comprehensionScore: 0.4, adjustedLevel: 5, levelsDown: 2);

    expect(r.wordReadingPercent, 90);
    expect(r.comprehensionPercent, 40);
    expect(r.adjustedLevelLabel, 'Grade 5 (KS2)');
    expect(r.levelsDownLabel, '2-LD');
  });

  test("round result's own reading labels", () {
    const r = PhilIriRoundResult(
        round: PhilIriRound.mosy1, given: true, adjustedLevel: 5, levelsDown: 2, actualAdjustedLevel: 4, actualLevelsDown: 3);
    const none = PhilIriRoundResult(round: PhilIriRound.mosy1, given: true);

    expect(r.actualAdjustedLevelLabel, 'Grade 4 (KS2)');
    expect(r.actualLevelsDownLabel, '3-LD');
    expect(none.actualAdjustedLevelLabel, isNull);
    expect(none.actualLevelsDownLabel, isNull);
  });

  test('round result at grade level and as a non-reader', () {
    const glr = PhilIriRoundResult(round: PhilIriRound.bosy, given: true, adjustedLevel: 7, levelsDown: 0);
    const nonReader = PhilIriRoundResult(round: PhilIriRound.bosy, given: true, adjustedLevel: 0);

    expect(glr.levelsDownLabel, 'GLR');
    expect(nonReader.adjustedLevelLabel, 'Non-Reader');
    expect(nonReader.levelsDownLabel, 'Non-Reader');
  });

  test('round result with nothing known yet', () {
    const empty = PhilIriRoundResult(round: PhilIriRound.mosy1, given: false);

    expect(empty.wordReadingPercent, isNull);
    expect(empty.comprehensionPercent, isNull);
    expect(empty.adjustedLevelLabel, isNull);
    expect(empty.levelsDownLabel, isNull);
  });
}
