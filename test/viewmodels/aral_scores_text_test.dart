// The scores in the ARAL proposal's reason (follow-up 2026-11-12, R2 review
// minor): a BOSY with no word reading (comprehension only, nothing earlier)
// says "not assessed", not "0%" and "- wpm".
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_types.dart';
import 'package:basa_capstone/core/services/phil_iri_results.dart';
import 'package:basa_capstone/viewmodels/aral_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a BOSY with word reading and comprehension shows both and the speed', () {
    const bosy = PhilIriRoundResult(
      round: PhilIriRound.bosy,
      given: true,
      wordReadingScore: 0.96,
      wordsPerMinute: 118.4,
      comprehensionScore: 0.5,
      profile: PhilIriLevel.frustration,
      adjustedLevel: 5,
    );
    expect(aralPhilIriScoresText(bosy, gstOnly: false), 'word reading 96%, comprehension 50%, 118 wpm');
  });

  test('comprehension only, nothing earlier: word reading and speed not assessed', () {
    const bosy = PhilIriRoundResult(
      round: PhilIriRound.bosy,
      given: true,
      comprehensionScore: 0.75,
      profile: PhilIriLevel.struggling,
      adjustedLevel: 4,
      wordReadingAssumed: true,
    );
    expect(aralPhilIriScoresText(bosy, gstOnly: false),
        'word reading not assessed, comprehension 75%, speed not assessed');
  });

  test('GST only and a blank comprehension keep their wording', () {
    const bosy = PhilIriRoundResult(
      round: PhilIriRound.bosy,
      given: false,
      profile: PhilIriLevel.frustration,
      adjustedLevel: 5,
    );
    expect(aralPhilIriScoresText(bosy, gstOnly: true), 'no reading, comprehension -, - wpm');
  });
}
