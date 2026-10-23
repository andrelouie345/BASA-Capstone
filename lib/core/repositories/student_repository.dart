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

abstract class StudentRepository {
  Future<Student?> findByLrn(String lrn);
  /// Throws [DuplicateLrnException] when the LRN is already taken.
  Future<Student> insert(Student student);
  Future<void> update(Student student);
  Future<List<Student>> getAll(String sort);
  Future<List<Student>> getBySection(int sectionId);
  /// The section the learner is actively enrolled in for [schoolYear], if any.
  Future<int?> activeSectionId(int studentId, String schoolYear);
  /// One enrollment per student per school year (re-enrolling moves it).
  /// Returns the enrollment id. [id] is for local mirroring only: it keeps
  /// the cloud's id so pull-cloud's INSERT OR REPLACE lines up; Supabase
  /// ignores it.
  Future<int> enroll({required int studentId, required int sectionId, required String schoolYear, int? id});
  Future<Student> upsertWithId(Student student);
}