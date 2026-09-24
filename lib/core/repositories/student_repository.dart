// lib/core/repositories/student_repository.dart
import '../models/student.dart';

abstract class StudentRepository {
  Future<Student?> findByLrn(String lrn);
  Future<Student> insert(Student student);
  Future<void> update(Student student);
  Future<List<Student>> getAll();
  Future<List<Student>> getBySection(int sectionId);
  Future<void> enroll({required int studentId, required int sectionId, required String schoolYear});
  Future<Student> upsertWithId(Student student);
}