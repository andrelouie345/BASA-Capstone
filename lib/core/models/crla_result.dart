// lib/core/models/crla_result.dart

/// Read-only row from the crla_results view. No toMap(): never inserted or updated.
class CrlaResult {
  // From crla_assessments (always present)
  final int assessmentId;
  final int studentId;
  final int schoolId;
  final int sectionId;
  final String schoolYear;
  final String subjectVariant;
  final String language;
  final int attemptNo;
  final String assessedAt;

  // From Part 1 (null if no Part 1 row yet)
  final int? part1TotalScore;
  final String? part1ReadingLevel;

  // From Part 2 (null if no fluency row yet)
  final int? storyNo;
  final int? wordsRead;
  final int? miscues;
  final double? wpm;
  final int? comprehensionCorrect;
  final int? learnerExperienceRating;
  final int? observationLevel;
  final String? remarks;

  // Computed by the view
  final double? pctCorrectWordsRead; // null when no crla_stories match
  final String? readingProfile;

  CrlaResult({
    required this.assessmentId,
    required this.studentId,
    required this.schoolId,
    required this.sectionId,
    required this.schoolYear,
    required this.subjectVariant,
    required this.language,
    required this.attemptNo,
    required this.assessedAt,
    this.part1TotalScore,
    this.part1ReadingLevel,
    this.storyNo,
    this.wordsRead,
    this.miscues,
    this.wpm,
    this.comprehensionCorrect,
    this.learnerExperienceRating,
    this.observationLevel,
    this.remarks,
    this.pctCorrectWordsRead,
    this.readingProfile,
  });

  factory CrlaResult.fromMap(Map<String, Object?> m) => CrlaResult(
        assessmentId: m['assessment_id'] as int,
        studentId: m['student_id'] as int,
        schoolId: m['school_id'] as int,
        sectionId: m['section_id'] as int,
        schoolYear: m['school_year'] as String,
        subjectVariant: m['subject_variant'] as String,
        language: m['language'] as String,
        attemptNo: m['attempt_no'] as int,
        assessedAt: m['assessed_at'] as String,
        part1TotalScore: m['part1_total_score'] as int?,
        part1ReadingLevel: m['part1_reading_level'] as String?,
        storyNo: m['story_no'] as int?,
        wordsRead: m['words_read'] as int?,
        miscues: m['miscues'] as int?,
        wpm: (m['wpm'] as num?)?.toDouble(),
        comprehensionCorrect: m['comprehension_correct'] as int?,
        learnerExperienceRating: m['learner_experience_rating'] as int?,
        observationLevel: m['observation_level'] as int?,
        remarks: m['remarks'] as String?,
        pctCorrectWordsRead: (m['pct_correct_words_read'] as num?)?.toDouble(),
        readingProfile: m['reading_profile'] as String?,
      );
}