// lib/core/models/crla_part2_fluency.dart

class CrlaPart2Fluency {
  final int assessmentId;               // PK and FK to crla_assessments.id
  final int storyNo;                    // 1 or 2
  final int miscues;
  final int wordsRead;
  final int timeMinutes;
  final int timeSeconds;                // 0-59
  final double? wpm;                    // computed by the DB
  final int comprehensionCorrect;       // 0-5
  final int? learnerExperienceRating;   // 1-5
  final int? observationLevel;          // 1-4
  final String? remarks;
  /// Digitized: the last word the learner reached when the timer stopped at
  /// the grade's limit (0-based); null = the whole story (v51, spec D6).
  final int? lastWordReached;

  CrlaPart2Fluency({
    required this.assessmentId,
    required this.storyNo,
    required this.miscues,
    required this.wordsRead,
    required this.timeMinutes,
    required this.timeSeconds,
    this.wpm,
    required this.comprehensionCorrect,
    this.learnerExperienceRating,
    this.observationLevel,
    this.remarks,
    this.lastWordReached,
  });

  Map<String, Object?> toMap() => {
        'assessment_id': assessmentId,
        'story_no': storyNo,
        'miscues': miscues,
        'words_read': wordsRead,
        'time_minutes': timeMinutes,
        'time_seconds': timeSeconds,
        'comprehension_correct': comprehensionCorrect,
        'learner_experience_rating': learnerExperienceRating,
        'observation_level': observationLevel,
        'remarks': remarks,
        'last_word_reached': lastWordReached,
      };

  factory CrlaPart2Fluency.fromMap(Map<String, Object?> m) => CrlaPart2Fluency(
        assessmentId: m['assessment_id'] as int,
        storyNo: m['story_no'] as int,
        miscues: m['miscues'] as int,
        wordsRead: m['words_read'] as int,
        timeMinutes: m['time_minutes'] as int,
        timeSeconds: m['time_seconds'] as int,
        wpm: (m['wpm'] as num?)?.toDouble(),
        comprehensionCorrect: m['comprehension_correct'] as int,
        learnerExperienceRating: m['learner_experience_rating'] as int?,
        observationLevel: m['observation_level'] as int?,
        remarks: m['remarks'] as String?,
        lastWordReached: (m['last_word_reached'] as num?)?.toInt(),
      );
}