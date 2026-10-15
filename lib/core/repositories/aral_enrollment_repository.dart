// lib/core/repositories/aral_enrollment_repository.dart
import '../models/aral_enrollment.dart';

/// The ARAL roster. SQLite is the main write path (offline-first, like the
/// assessment sessions); the Supabase implementation has the same interface
/// for online use and the future sync.
abstract class AralEnrollmentRepository {
  /// Stores a new enrollment and returns it with its id (and stamps).
  Future<AralEnrollment> insert(AralEnrollment enrollment);

  /// Saves the changeable fields (section, key stage, track, tutor, status,
  /// exit date/reason, notes). Learner, school, year and basis never change.
  Future<AralEnrollment> update(AralEnrollment enrollment);

  Future<void> delete(int id);

  Future<AralEnrollment?> findById(int id);

  /// The learner's enrollment for that school year, if any (at most one).
  Future<AralEnrollment?> findForStudent(int studentId, String schoolYear);

  Future<List<AralEnrollment>> getBySection(int sectionId, {String? schoolYear});

  Future<List<AralEnrollment>> getBySchool(int schoolId, {String? schoolYear});

  Future<List<AralEnrollment>> getByTutor(String tutorId, {String? schoolYear});

  /// Local-mirroring only: keeps Supabase's id (origin 'cloud').
  /// Supabase impl throws UnimplementedError.
  Future<AralEnrollment> upsertWithId(AralEnrollment enrollment);
}
