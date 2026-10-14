// lib/core/models/phil_iri_gst_result.dart
//
// Phil-IRI Group Screening Test result (Form 1B, Class Reading Record), one per
// learner per school year. It decides who needs graded passages and the
// starting level (philIriStartingLevel). Grades 4–6 take a 20-item test,
// Grades 7–10 a 40-item test. Snapshots school and section like
// crla_assessments, so a transfer never rewrites it.

class PhilIriGstResult {
  final int? id;
  final int studentId;
  final int schoolId;
  final int sectionId;
  final String schoolYear;      // YYYY-YYYY
  final int maxScore;           // 20 (Grades 4–6) or 40 (Grades 7–10)
  final int totalScore;
  final int? literalCorrect;    // Form 1B breakdown by question type, optional
  final int? inferentialCorrect;
  final int? criticalCorrect;
  final String takenAt;         // yyyy-MM-dd
  final String? administeredBy; // users.id

  PhilIriGstResult({
    this.id,
    required this.studentId,
    required this.schoolId,
    required this.sectionId,
    required this.schoolYear,
    required this.maxScore,
    required this.totalScore,
    this.literalCorrect,
    this.inferentialCorrect,
    this.criticalCorrect,
    required this.takenAt,
    this.administeredBy,
  });

  double get percent => totalScore / maxScore;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'student_id': studentId,
        'school_id': schoolId,
        'section_id': sectionId,
        'school_year': schoolYear,
        'max_score': maxScore,
        'total_score': totalScore,
        'literal_correct': literalCorrect,
        'inferential_correct': inferentialCorrect,
        'critical_correct': criticalCorrect,
        'taken_at': takenAt,
        if (administeredBy != null) 'administered_by': administeredBy,
      };

  factory PhilIriGstResult.fromMap(Map<String, Object?> m) => PhilIriGstResult(
        id: m['id'] as int?,
        studentId: m['student_id'] as int,
        schoolId: m['school_id'] as int,
        sectionId: m['section_id'] as int,
        schoolYear: m['school_year'] as String,
        maxScore: m['max_score'] as int,
        totalScore: m['total_score'] as int,
        literalCorrect: m['literal_correct'] as int?,
        inferentialCorrect: m['inferential_correct'] as int?,
        criticalCorrect: m['critical_correct'] as int?,
        takenAt: m['taken_at'] as String,
        administeredBy: m['administered_by'] as String?,
      );
}
