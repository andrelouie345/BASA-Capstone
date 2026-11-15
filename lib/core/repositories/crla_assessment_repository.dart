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

  /// Local only: stores the reading profile CrlaViewModel computed. The cloud
  /// computes and stores its own (Supabase impl throws UnsupportedError).
  Future<void> setReadingProfile(int assessmentId, String? readingProfile);

  /// Cloud only: re-scores [assessmentIds] with today's thresholds
  /// (crla_regenerate_results; all-or-nothing, superadmin or the school's
  /// admin/coordinator). Returns how many were re-scored. SQLite impl throws
  /// UnsupportedError.
  Future<int> regenerateResults(List<int> assessmentIds);

  /// Local only: how many ARAL roster entries use this attempt as their
  /// basis or suggestion. Supabase impl throws UnsupportedError.
  Future<int> aralEntriesUsing(int assessmentId);

  /// Local only: deletes an attempt made on this device and not uploaded
  /// (negative id) with its Part 1 / Part 2, in one transaction. The sync
  /// triggers refuse a row waiting in an upload. Supabase impl throws
  /// UnsupportedError (the server has no delete for attempts).
  Future<void> deleteNew(int assessmentId);
}