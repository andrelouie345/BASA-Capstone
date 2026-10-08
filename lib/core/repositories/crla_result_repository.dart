// lib/core/repositories/crla_result_repository.dart
import '../models/crla_result.dart';

abstract class CrlaResultRepository {
  Future<CrlaResult?> findByAssessmentId(int assessmentId);

  /// All attempts for the section, ordered by student, variant, then attempt.
  Future<List<CrlaResult>> getBySection(int sectionId, {String? schoolYear});

  /// All attempts for one student, newest first.
  Future<List<CrlaResult>> getByStudent(int studentId);
}