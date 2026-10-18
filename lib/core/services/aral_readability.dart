// lib/core/services/aral_readability.dart
//
// Readability of a reading selection used in the ARAL intervention, from its
// counts of words, sentences and syllables (the reading coordinator's workbook,
// sheet "Readability" and the table on sheet "Bases" B43:F50, 2026-10-18).
//
// - Flesch reading ease = 206.835 - 1.015 * (words / sentences)
//   - 84.6 * (syllables / words), rounded to 2 decimals.
// - Its interpretation: the band whose lower bound the score reaches (her
//   VLOOKUP): 0 Professional, 9.51 College Graduate, 29.51 College, 49.51
//   10th & 12th, 59.51 8th & 9th, 69.51 7th, 79.51 6th, 89.51 5th; above 100
//   is still 5th; below 0 has no band.
// - Flesch-Kincaid grade level = 0.39 * (words / sentences)
//   + 11.8 * (syllables / words) - 15.59, rounded to 2 decimals. Her sheet
//   multiplies words/sentences by 1.015 inside this formula too (copied from
//   the reading-ease formula); BASA uses the standard formula. Set
//   [aralReadabilityGradeSentenceFactor] to 1.015 to match her sheet exactly.
library;

/// Factor on words/sentences in the grade-level formula: 1.0 = standard
/// Flesch-Kincaid; 1.015 = the coordinator's sheet.
const aralReadabilityGradeSentenceFactor = 1.0;

class AralReadabilityBand {
  final double lowerBound;
  final String schoolLevel;
  final String notes;
  const AralReadabilityBand(this.lowerBound, this.schoolLevel, this.notes);
}

/// Highest band first.
const aralReadabilityBands = [
  AralReadabilityBand(89.51, '5th', 'Very easy to read. Easily understood by an average 11-yo student'),
  AralReadabilityBand(79.51, '6th', 'Easy to read. Conversational English.'),
  AralReadabilityBand(69.51, '7th', 'Fairly easy to read.'),
  AralReadabilityBand(59.51, '8th & 9th', 'Plain English. Easily understood by 13-15 y.o students'),
  AralReadabilityBand(49.51, '10th & 12th', 'Fairly difficult to read'),
  AralReadabilityBand(29.51, 'College', 'Difficult to read'),
  AralReadabilityBand(9.51, 'College Graduate', 'Very difficult to read. Best understood by university graduates.'),
  AralReadabilityBand(0, 'Professional', 'Extremely difficult to read. Best understood by university graduates.'),
];

class AralReadability {
  final double readingEase;
  final AralReadabilityBand? band; // null below 0
  final double gradeLevel;
  const AralReadability(this.readingEase, this.band, this.gradeLevel);
}

double _round2(double v) => (v * 100).round() / 100;

/// Throws ArgumentError on counts that can't be a text.
AralReadability aralReadability({required int words, required int sentences, required int syllables}) {
  if (words <= 0 || sentences <= 0 || syllables <= 0) {
    throw ArgumentError('words, sentences and syllables must be positive');
  }
  if (syllables < words) throw ArgumentError('a text has at least one syllable per word');
  final wps = words / sentences;
  final spw = syllables / words;
  final ease = _round2(206.835 - 1.015 * wps - 84.6 * spw);
  final grade = _round2(0.39 * (aralReadabilityGradeSentenceFactor * wps) + 11.8 * spw - 15.59);
  AralReadabilityBand? band;
  for (final b in aralReadabilityBands) {
    if (ease >= b.lowerBound) {
      band = b;
      break;
    }
  }
  return AralReadability(ease, band, grade);
}
