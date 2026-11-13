// lib/core/models/sf1_missing_learner.dart
//
// SF1 leavers (spec docs/superpowers/specs/2026-11-12-sf1-leavers-design.md,
// section 2): a learner actively enrolled in a section this school year who
// isn't on that section's SF1 ("not on this SF1"). The coordinator decides
// per learner (archive, move); until then the learner stays active (D9).

class Sf1MissingLearner {
  final int enrollmentId;
  final int studentId;
  final String lrn;

  /// "Last, First" (with the middle name when known).
  final String name;

  const Sf1MissingLearner({
    required this.enrollmentId,
    required this.studentId,
    required this.lrn,
    required this.name,
  });

  @override
  String toString() => 'Sf1MissingLearner($enrollmentId, $lrn)';
}
