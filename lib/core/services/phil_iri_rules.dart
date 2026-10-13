// lib/core/services/phil_iri_rules.dart
//
// Scoring rules for the Phil-IRI graded passages (oral reading), English only.
// Sources: Phil-IRI Manual 2018 (Grades 4–6) and Phil-IRI for JHS Manual 2024
// (Grades 7–10), sections "Computing the Oral Reading Score", Tables 6–8.
//
// Owner decision (2026-10-13): the word reading + comprehension combination
// follows the reading coordinator's workbook (sheet "Bases", H4:J12), not the
// misaligned Table 8 in the 2018 PDF. Non-reader and reading-speed rules are
// not here yet (pending decision).
//
// Percentages are classified after rounding to a whole percent (half up),
// because the manual's bands are whole numbers (e.g. 96.5% -> 97 -> Independent).

enum PhilIriLevel {
  independent('Independent'),
  instructional('Instructional'),
  frustration('Frustration');

  final String label;
  const PhilIriLevel(this.label);

  static PhilIriLevel fromString(String value) {
    return PhilIriLevel.values.firstWhere(
      (l) => l.name == value || l.label == value,
      orElse: () => throw ArgumentError('Invalid PhilIriLevel value: $value'),
    );
  }
}

/// Lowest and highest English graded-passage levels across both manuals
/// (2018: Grades 2–7, JHS 2024: Grades 4–10).
const philIriMinPassageLevel = 2;
const philIriMaxPassageLevel = 10;

/// Learner grades the English Phil-IRI covers (2018 English GST: 4–6, JHS: 7–10).
const philIriGrades = {4, 5, 6, 7, 8, 9, 10};

/// The section's grade as a Phil-IRI grade, or null when it isn't 4–10.
int? philIriGradeOf(String gradeLevel) {
  final grade = int.tryParse(gradeLevel.trim());
  return philIriGrades.contains(grade) ? grade : null;
}

int _wholePercent(double fraction) => (fraction * 100 + 0.5).floor();

/// Word reading score as a 0–1 fraction: (words − miscues) / words.
/// Only counted miscues go in (self-corrections are not counted).
double philIriWordReadingScore(int wordCount, int countedMiscues) {
  if (wordCount <= 0) throw ArgumentError('wordCount must be positive');
  if (countedMiscues < 0) throw ArgumentError('miscues cannot be negative');
  final correct = wordCount - countedMiscues;
  return (correct < 0 ? 0 : correct) / wordCount;
}

/// Comprehension score as a 0–1 fraction: correct / questions.
double philIriComprehensionScore(int correct, int questions) {
  if (questions <= 0) throw ArgumentError('questions must be positive');
  if (correct < 0 || correct > questions) {
    throw ArgumentError('correct must be 0..$questions');
  }
  return correct / questions;
}

/// Reading rate in words per minute, rounded to 2 decimals.
double philIriWordsPerMinute(int wordCount, int readingSeconds) {
  if (readingSeconds <= 0) throw ArgumentError('readingSeconds must be positive');
  return (wordCount * 60 / readingSeconds * 100).round() / 100;
}

/// Table 7, word reading: 97–100 Independent, 90–96 Instructional, ≤89 Frustration.
PhilIriLevel philIriWordReadingLevel(double score) {
  final pct = _wholePercent(score);
  if (pct >= 97) return PhilIriLevel.independent;
  if (pct >= 90) return PhilIriLevel.instructional;
  return PhilIriLevel.frustration;
}

/// Table 7, comprehension: 80–100 Independent, 59–79 Instructional, ≤58 Frustration.
PhilIriLevel philIriComprehensionLevel(double score) {
  final pct = _wholePercent(score);
  if (pct >= 80) return PhilIriLevel.independent;
  if (pct >= 59) return PhilIriLevel.instructional;
  return PhilIriLevel.frustration;
}

/// Reading profile for one passage (workbook "Bases" H4:J12).
PhilIriLevel philIriPassageProfile(PhilIriLevel wordReading, PhilIriLevel comprehension) {
  const ind = PhilIriLevel.independent;
  const ins = PhilIriLevel.instructional;
  const frus = PhilIriLevel.frustration;
  switch (wordReading) {
    case PhilIriLevel.independent:
      return comprehension; // Ind+Ind Ind, Ind+Ins Ins, Ind+Frus Frus
    case PhilIriLevel.instructional:
      return comprehension == frus ? frus : (comprehension == ind ? ind : ins);
    case PhilIriLevel.frustration:
      return comprehension == ind ? ins : frus;
  }
}

/// Starting passage level from the English GST raw score, or null when the
/// learner passed the GST (no graded passages needed).
/// Grades 4–6 (GST out of 20): 0–7 three levels down, 8–13 two down, ≥14 passed.
/// Grades 7–10 (GST out of 40): 0–15 three down, 16–27 two down, ≥28 passed.
/// Clamped to [philIriMinPassageLevel] (there is no Grade 1 English passage).
int? philIriStartingLevel(int learnerGrade, int gstScore) {
  if (!philIriGrades.contains(learnerGrade)) {
    throw ArgumentError('Phil-IRI English covers Grades 4–10, got $learnerGrade');
  }
  final jhs = learnerGrade >= 7;
  final maxScore = jhs ? 40 : 20;
  if (gstScore < 0 || gstScore > maxScore) {
    throw ArgumentError('GST score must be 0..$maxScore');
  }
  final int levelsDown;
  if (gstScore <= (jhs ? 15 : 7)) {
    levelsDown = 3;
  } else if (gstScore <= (jhs ? 27 : 13)) {
    levelsDown = 2;
  } else {
    return null;
  }
  final start = learnerGrade - levelsDown;
  return start < philIriMinPassageLevel ? philIriMinPassageLevel : start;
}

/// Next passage level to give, from the profiles found so far
/// (passage level -> profile), or null when testing is done.
///
/// Manual Stage 2: go one level up until Frustration is found; after that,
/// go one level below the lowest passage read until Independent is found.
/// Stops at the passage-level bounds. The tutor may override.
int? philIriNextLevel(Map<int, PhilIriLevel> profiles) {
  if (profiles.isEmpty) return null;
  final levels = profiles.keys.toList()..sort();
  final found = profiles.values.toSet();
  if (!found.contains(PhilIriLevel.frustration)) {
    final next = levels.last + 1;
    return next > philIriMaxPassageLevel ? null : next;
  }
  if (found.contains(PhilIriLevel.independent)) return null;
  final next = levels.first - 1;
  return next < philIriMinPassageLevel ? null : next;
}
