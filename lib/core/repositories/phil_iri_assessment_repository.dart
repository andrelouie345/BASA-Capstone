// lib/core/repositories/phil_iri_assessment_repository.dart
import '../models/phil_iri_answer.dart';
import '../models/phil_iri_assessment.dart';
import '../models/phil_iri_miscue.dart';
import '../models/phil_iri_reading.dart';
import '../models/phil_iri_rubric_score.dart';

/// Phil-IRI assessment sessions and everything recorded under them: passage
/// readings, miscues, comprehension answers and rubric scores.
///
/// The database enforces the rules (scope, grade-level passages, lifecycle,
/// finalized = frozen); these methods surface its refusals as exceptions.
/// Only a session's status changes after insert, through [setStatus] and
/// [finalize].
abstract class PhilIriAssessmentRepository {
  // ---- Sessions ----

  /// Inserts a new in-progress session; returns it with its attempt_no.
  Future<PhilIriAssessment> insertAssessment(PhilIriAssessment assessment);

  Future<PhilIriAssessment?> findAssessment(int id);

  /// Ordered by student_id, round, attempt_no.
  Future<List<PhilIriAssessment>> getBySection(int sectionId, {String? schoolYear, PhilIriRound? round});

  /// Ordered by school_year, round, attempt_no.
  Future<List<PhilIriAssessment>> getByStudent(int studentId, {String? schoolYear});

  /// The newest attempt of one round (the one that counts), or null.
  Future<PhilIriAssessment?> getLatestAttempt({
    required int studentId,
    required int sectionId,
    required PhilIriRound round,
    required String schoolYear,
  });

  /// in_progress <-> completed. (Finalizing goes through [finalize].)
  /// Returns the stored session.
  Future<PhilIriAssessment> setStatus(int assessmentId, PhilIriStatus status);

  /// Writes each reading's frozen results, then marks the completed session
  /// finalized with [thresholdsSnapshot] (PhilIriThresholds.toMap()).
  /// SQLite does both in one transaction.
  Future<PhilIriAssessment> finalize({
    required int assessmentId,
    required Map<String, Object?> thresholdsSnapshot,
    required List<PhilIriReading> readingResults,
  });

  /// Discards an in-progress session and everything under it.
  Future<void> deleteAssessment(int assessmentId);

  // ---- Readings ----

  Future<PhilIriReading> insertReading(PhilIriReading reading);

  /// Timing, words read and observations. A reading keeps its session and passage.
  Future<PhilIriReading> updateReading(PhilIriReading reading);

  /// Deletes the reading with its miscues and answers.
  Future<void> deleteReading(int readingId);

  /// Ordered by sequence_no.
  Future<List<PhilIriReading>> getReadings(int assessmentId);

  // ---- Miscues ----

  Future<PhilIriMiscue> insertMiscue(PhilIriMiscue miscue);
  Future<PhilIriMiscue> updateMiscue(PhilIriMiscue miscue);
  Future<void> deleteMiscue(int miscueId);

  /// Ordered by word_index, id.
  Future<List<PhilIriMiscue>> getMiscues(int readingId);

  // ---- Answers ----

  /// Creates or replaces the answer to one question of a reading. is_correct
  /// is computed by the database from the key; the value sent is ignored.
  Future<PhilIriAnswer> saveAnswer(PhilIriAnswer answer);

  Future<void> deleteAnswer(int answerId);

  /// Ordered by question id.
  Future<List<PhilIriAnswer>> getAnswers(int readingId);

  // ---- Rubric scores ----

  /// Creates or replaces the score for one criterion of a session.
  Future<PhilIriRubricScore> saveRubricScore(PhilIriRubricScore score);

  Future<List<PhilIriRubricScore>> getRubricScores(int assessmentId);

  /// Local-mirroring only, keeps Supabase's id and attempt_no (origin
  /// 'cloud'). Supabase impl throws UnimplementedError.
  Future<PhilIriAssessment> upsertAssessmentWithId(PhilIriAssessment assessment);
}
