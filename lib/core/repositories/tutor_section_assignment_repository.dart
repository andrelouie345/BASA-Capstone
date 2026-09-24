// lib/core/repositories/tutor_section_assignment_repository.dart
import '../models/tutor_section_assignment.dart';

abstract class TutorSectionAssignmentRepository {

  Future<TutorSectionAssignment> create(TutorSectionAssignment assignment);
  Future<List<TutorSectionAssignment>> getByTutor(String tutorId);
  Future<List<TutorSectionAssignment>> getBySection(int sectionId);
  Future<void> delete(int id);
}