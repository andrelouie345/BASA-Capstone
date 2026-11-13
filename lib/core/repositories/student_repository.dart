// lib/core/repositories/student_repository.dart
import '../models/student.dart';

/// insert() hit the unique LRN. Against Supabase this can mean the learner
/// exists in a school the caller can't see (a transfer).
class DuplicateLrnException implements Exception {
  final String lrn;
  const DuplicateLrnException(this.lrn);

  @override
  String toString() => 'LRN $lrn is already registered';
}

/// A learner's enrollment in one school year, whatever its status, with its
/// section (SF1 leavers: the import trial's moving / returning rows).
/// [status] is the enrollment's (`active`, `transferred_out`, `dropped_out`);
/// [leftOn] is set when archived.
typedef EnrollmentInYear = ({
  int enrollmentId,
  int sectionId,
  String sectionName,
  String gradeLevel,
  int schoolId,
  String status,
  String? leftOn,
});

abstract class StudentRepository {
  Future<Student?> findByLrn(String lrn);
  /// Throws [DuplicateLrnException] when the LRN is already taken.
  Future<Student> insert(Student student);
  Future<void> update(Student student);
  Future<List<Student>> getAll(String sort);
  Future<List<Student>> getBySection(int sectionId);
  /// The section the learner is actively enrolled in for [schoolYear], if any.
  Future<int?> activeSectionId(int studentId, String schoolYear);
  /// The learner's enrollment for [schoolYear] (one per learner per year),
  /// active or archived, or null when there is none the caller can read.
  Future<EnrollmentInYear?> enrollmentInYear(int studentId, String schoolYear);
  /// One enrollment per student per school year (re-enrolling moves it).
  /// Returns the enrollment id. [id] is for local mirroring only: it keeps
  /// the cloud's id so pull-cloud's INSERT OR REPLACE lines up; Supabase
  /// ignores it.
  Future<int> enroll({required int studentId, required int sectionId, required String schoolYear, int? id});
  Future<Student> upsertWithId(Student student);
}