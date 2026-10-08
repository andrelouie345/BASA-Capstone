// lib/core/models/crla_part1_english.dart

class CrlaPart1English {
  final int assessmentId;      // PK and FK to crla_assessments.id (no separate id)
  final int task1Score;        // 0-10
  final int? task2Score;       // 0-10, only when task1 is 1-10
  final int? totalScore;       // computed by the DB
  final String? readingLevel;  // computed by the DB

  CrlaPart1English({
    required this.assessmentId,
    required this.task1Score,
    this.task2Score,
    this.totalScore,
    this.readingLevel,
  });

  Map<String, Object?> toMap() => {
        'assessment_id': assessmentId,
        'task1_score': task1Score,
        'task2_score': task2Score,
      };

  factory CrlaPart1English.fromMap(Map<String, Object?> m) => CrlaPart1English(
        assessmentId: m['assessment_id'] as int,
        task1Score: m['task1_score'] as int,
        task2Score: m['task2_score'] as int?,
        totalScore: m['total_score'] as int?,
        readingLevel: m['reading_level'] as String?,
      );
}