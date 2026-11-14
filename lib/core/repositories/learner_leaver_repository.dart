// lib/core/repositories/learner_leaver_repository.dart
//
// SF1 leavers (spec docs/superpowers/specs/2026-11-12-sf1-leavers-design.md,
// sections 2-3): the server functions that archive, move, restore and
// anonymize learners (one transaction each, online only), the undecided
// "not on the latest SF1" list, and each section's last imported LRN set.
// Admin build only. Server only: the device copy is updated from what each
// function returns (learner_leaver_local_writes.dart).

abstract class LearnerLeaverRepository {
  /// sf1_archive_learner: [reason] `transferred_out` | `dropped_out`.
  /// Returns `{enrollment, aral_enrollment}`.
  Future<Map<String, dynamic>> archive(int enrollmentId, String reason, String? note);

  /// sf1_move_learner: [source] `sf1_missing` | `sf1_incoming`. Returns
  /// `{enrollment, moved, aral_enrollment, move}`.
  Future<Map<String, dynamic>> move(int enrollmentId, int toSectionId, String source);

  /// sf1_restore_learner: into its own section ([toSectionId] null or the
  /// same), or moved into another one of the same grade. Returns
  /// `{enrollment}`, or the move's result.
  Future<Map<String, dynamic>> restore(int enrollmentId, int? toSectionId);

  /// sf1_transfer_in (D15): school B's import conflict [conflictId] for a
  /// learner enrolled this school year at another school. Returns
  /// `{enrollment, student, move, from_school: {id, name}, from_section:
  /// {id, name}, exited_aral_enrollment_id}`.
  Future<Map<String, dynamic>> transferIn(int conflictId);

  /// learner_anonymize. Returns `{student}`.
  Future<Map<String, dynamic>> anonymize(int studentId);

  /// learner_anonymize_eligible: rows `{student_id, left_on, school_year}`,
  /// by student id.
  Future<List<Map<String, dynamic>>> anonymizeEligible(int schoolId);

  /// sf1_missing: rows `{enrollment_id, student_id, lrn, last_name,
  /// first_name, section_id, section_name}` of the school (or one section).
  Future<List<Map<String, dynamic>>> missing(int schoolId, {int? sectionId});

  /// The enrollment's section and that section's school, as the server
  /// holds them; null when the caller can't read it (or it doesn't exist).
  Future<({int sectionId, int schoolId})?> enrollmentPlace(int enrollmentId);

  /// Creates or replaces the section's row of sf1_last_imports (who and when
  /// are stamped by the server).
  Future<void> saveLastImport(int sectionId, int schoolId, String schoolYear, List<String> lrns);
}
