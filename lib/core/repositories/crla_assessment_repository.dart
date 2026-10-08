// lib/core/repositories/crla_assessment_repository.dart
import '../models/crla_assessment.dart';

abstract class CrlaAssessmentRepository {
  /// Returns the stored row, including the attempt_no assigned by the trigger.
  Future<CrlaAssessment> insert(CrlaAssessment assessment);

  Future<CrlaAssessment?> findById(int id);

  Future<List<CrlaAssessment>> getBySection(int sectionId, {String? schoolYear});

  Future<List<CrlaAssessment>> getByStudent(int studentId);

  /// Newest attempt for one student/section/variant/year, or null if none.
  Future<CrlaAssessment?> getLatestAttempt({
    required int studentId,
    required int sectionId,
    required String subjectVariant,
    required String schoolYear,
  });

  /// Local-mirroring only, keeps Supabase's id. Supabase impl throws UnimplementedError.
  Future<CrlaAssessment> upsertWithId(CrlaAssessment assessment);
}