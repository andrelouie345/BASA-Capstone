// lib/core/repositories/learner_history_repository.dart
// Read-only: one learner's rows across every school year, for the learner
// history (admin build; spec docs/superpowers/specs/2026-10-25-learner-history-design.md).
// Local only: the history reads the device copy.
import '../models/aral_enrollment.dart';
import '../models/enrollment_move.dart';
import '../models/srp_class.dart';
import '../models/student.dart';

/// One enrollments row of the learner with its section and school.
class LearnerSectionRow {
  final String schoolYear;
  final String status;       // enrollments.status
  final int sectionId;
  final String sectionName;
  final String gradeLevel;   // bare numeric string
  final int schoolId;
  final String? schoolName;  // null when the school row is not on this device
  final String? leftOn;      // set when archived (ISO date)
  final String? leftNote;    // optional, only when archived

  const LearnerSectionRow({
    required this.schoolYear,
    required this.status,
    required this.sectionId,
    required this.sectionName,
    required this.gradeLevel,
    required this.schoolId,
    required this.schoolName,
    this.leftOn,
    this.leftNote,
  });
}

/// One section move of the learner (enrollment_moves) with both sections'
/// names (null when that section is not on this device).
class LearnerMoveRow {
  final EnrollmentMove move;
  final String? fromSectionName;
  final String? toSectionName;

  const LearnerMoveRow({required this.move, required this.fromSectionName, required this.toSectionName});
}

abstract class LearnerHistoryRepository {
  Future<Student?> student(int id);
  Future<Student?> studentByLrn(String lrn);
  /// Every enrollments row of the learner joined to sections (and schools, when on
  /// the device); school_year DESC. At most one per year (UNIQUE student, year).
  Future<List<LearnerSectionRow>> sectionEnrollments(int studentId);
  /// Every enrollment_moves row of the learner; school_year DESC, moved_on ASC.
  Future<List<LearnerMoveRow>> moves(int studentId);
  /// Every aral_enrollments row of the learner, all years; school_year DESC, entered_on ASC.
  Future<List<AralEnrollment>> aralEntries(int studentId);
  /// The SRP classes the learner is a member of (srp_class_members -> srp_classes); school_year DESC.
  Future<List<SrpClass>> srpClasses(int studentId);
}
