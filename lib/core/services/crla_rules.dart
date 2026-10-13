// lib/core/services/crla_rules.dart
//
// Grade rules from the CRLA2 G1–G3 scoresheets. Same numbers as the Postgres
// helpers crla_comprehension_max / crla_time_cap_seconds and the SQLite
// triggers and crla_results view in local_database.dart; change all of them
// together.
//
// CRLA is Grades 1–3 only, and the section's grade is the instrument grade.
// Grade/variant pairs with no scoresheet (e.g. G1 eng) are parked: they use
// their grade's numbers.

const crlaGrades = {1, 2, 3};

/// The section's grade as a CRLA grade, or null when it isn't 1–3.
int? crlaGradeOf(String gradeLevel) {
  final grade = int.tryParse(gradeLevel.trim());
  return crlaGrades.contains(grade) ? grade : null;
}

/// Most comprehension questions: G1 5, G3 mt/fil 7, otherwise 6.
int crlaComprehensionMax(int grade, String variant) {
  if (grade == 1) return 5;
  if (grade == 3 && (variant == 'mt' || variant == 'fil')) return 7;
  return 6;
}

/// Reading-time limit in seconds: G1 60, G3 mt/fil 180, otherwise 120.
int crlaTimeCapSeconds(int grade, String variant) {
  if (grade == 1) return 60;
  if (grade == 3 && (variant == 'mt' || variant == 'fil')) return 180;
  return 120;
}
