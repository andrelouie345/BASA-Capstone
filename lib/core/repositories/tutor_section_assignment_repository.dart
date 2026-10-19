// lib/core/repositories/tutor_section_assignment_repository.dart
import '../models/tutor_section_assignment.dart';

abstract class TutorSectionAssignmentRepository {

  Future<TutorSectionAssignment> create(TutorSectionAssignment assignment);
  Future<List<TutorSectionAssignment>> getByTutor(String tutorId);
  Future<List<TutorSectionAssignment>> getBySection(int sectionId);
  Future<void> delete(int id);

  // Mirroring onto this device (SQLite only; the Supabase repo throws).
  Future<void> upsertWithId(TutorSectionAssignment assignment);
  Future<void> removeMirrored(int id);
}