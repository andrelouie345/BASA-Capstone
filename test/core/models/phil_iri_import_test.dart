// Import plan model (spec 2026-11-10-phil-iri-untitled-readings D10): a
// workbook reading may have no passage ("Untitled") with a typed word count
// and a comprehension total.
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/models/phil_iri_import.dart';
import 'package:basa_capstone/core/models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an untitled import reading keeps its word count and comprehension total', () {
    const r = PhilIriImportReading(
      ref: PhilIriImportRef(sheet: '01', row: 14, column: 'S'),
      learner: PhilIriLearnerKey(name: 'Learner, One', sex: 'M'),
      round: PhilIriRound.bosy,
      passage: null,
      method: PhilIriReadingMethod.wholeText,
      seconds: 90,
      wordCount: 120,
      correctCount: 5,
      correctTotal: 8,
    );
    expect(r.passage, isNull);
    expect(r.isUntitled, isTrue);
    expect(r.wordCount, 120);
    expect(r.correctCount, 5);
    expect(r.correctTotal, 8);
  });

  test('a reading with a passage is not untitled', () {
    const r = PhilIriImportReading(
      ref: PhilIriImportRef(sheet: '01', row: 14),
      learner: PhilIriLearnerKey(name: 'Learner, One', sex: 'M'),
      round: PhilIriRound.bosy,
      passage: PhilIriImportPassageRef(raw: '7C Dust', level: 7, code: '7C', title: 'Dust'),
      method: PhilIriReadingMethod.oneMinute,
      wordsRead: 70,
    );
    expect(r.isUntitled, isFalse);
    expect(r.wordCount, isNull);
    expect(r.correctTotal, isNull);
  });
}
