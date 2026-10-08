// lib/core/models/crla_part1_standard.dart

class CrlaPart1Standard {
  final int assessmentId;      // PK and FK to crla_assessments.id (no separate id)
  final int task1Score;        // 0-10
  final int? task2LowScore;    // 0-10, only when task1 < 7 (Rhymes/Words)
  final int? task2HighScore;   // 0-10, only when task1 >= 7 (Sentences)
  final int? totalScore;       // computed by the DB
  final String? readingLevel;  // computed by the DB

  CrlaPart1Standard({
    required this.assessmentId,
    required this.task1Score,
    this.task2LowScore,
    this.task2HighScore,
    this.totalScore,
    this.readingLevel,
  });

  Map<String, Object?> toMap() => {
        'assessment_id': assessmentId,
        'task1_score': task1Score,
        'task2_low_score': task2LowScore,
        'task2_high_score': task2HighScore,
      };

  factory CrlaPart1Standard.fromMap(Map<String, Object?> m) => CrlaPart1Standard(
        assessmentId: m['assessment_id'] as int,
        task1Score: m['task1_score'] as int,
        task2LowScore: m['task2_low_score'] as int?,
        task2HighScore: m['task2_high_score'] as int?,
        totalScore: m['total_score'] as int?,
        readingLevel: m['reading_level'] as String?,
      );
}