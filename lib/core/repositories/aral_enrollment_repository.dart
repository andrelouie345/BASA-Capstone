// lib/core/repositories/aral_enrollment_repository.dart
import '../models/aral_enrollment.dart';

/// The ARAL roster. SQLite is the main write path (offline-first, like the
/// assessment sessions); the Supabase implementation has the same interface
/// for online use and the future sync.
abstract class AralEnrollmentRepository {
  /// Stores a new enrollment and returns it with its id (and stamps).
  Future<AralEnrollment> insert(AralEnrollment enrollment);

  /// Saves the changeable fields (section, key stage, track, class, status,
  /// exit date/reason, notes). Learner, school, year and basis never change.
  Future<AralEnrollment> update(AralEnrollment enrollment);

  Future<void> delete(int id);

  Future<AralEnrollment?> findById(int id);

  /// The learner's enrollment for that school year, if any (at most one).
  Future<AralEnrollment?> findForStudent(int studentId, String schoolYear);

  Future<List<AralEnrollment>> getBySection(int sectionId, {String? schoolYear});

  Future<List<AralEnrollment>> getBySchool(int schoolId, {String? schoolYear});

  /// The learners whose class [tutorId] teaches (any status).
  Future<List<AralEnrollment>> getByTutor(String tutorId, {String? schoolYear});

  /// The learners placed in the class (any status).
  Future<List<AralEnrollment>> getByClass(int classId);

  /// The tutor of the learner's class; null when unplaced or the class has none.
  Future<String?> classTutorId(int enrollmentId);

  /// Local-mirroring only: keeps Supabase's id (origin 'cloud').
  /// Supabase impl throws UnimplementedError.
  Future<AralEnrollment> upsertWithId(AralEnrollment enrollment);
}
