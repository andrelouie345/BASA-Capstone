// lib/core/repositories/phil_iri_gst_repository.dart
import '../models/phil_iri_gst_result.dart';

/// Phil-IRI Group Screening Test results. Never updated: a correction is a
/// retake (a new row with the next attempt_no).
abstract class PhilIriGstRepository {
  /// Returns the stored row, including the attempt_no the database assigned.
  Future<PhilIriGstResult> insert(PhilIriGstResult result);

  Future<PhilIriGstResult?> findById(int id);

  /// Ordered by student_id, attempt_no.
  Future<List<PhilIriGstResult>> getBySection(int sectionId, {String? schoolYear});

  /// Newest first (taken_at, then id).
  Future<List<PhilIriGstResult>> getByStudent(int studentId, {String? schoolYear});

  /// The learner's newest GST for that school year (the one that counts), or null.
  Future<PhilIriGstResult?> getLatest({required int studentId, required String schoolYear});

  /// Local-mirroring only, keeps Supabase's id and attempt_no. Supabase impl
  /// throws UnimplementedError.
  Future<PhilIriGstResult> upsertWithId(PhilIriGstResult result);
}
