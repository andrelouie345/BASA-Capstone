// lib/core/models/enrollment_move.dart
//
// One section move of a learner (table enrollment_moves, spec
// docs/superpowers/specs/2026-11-12-sf1-leavers-design.md section 1). History
// only: written by the server's move function, mirrored to the device by
// pull-cloud (read-only there). Once enrollments.section_id is rewritten it
// is the only record that the learner was in the old section.

/// Where a move was decided.
enum EnrollmentMoveSource {
  /// From the old section's SF1 re-import (the learner was missing).
  sf1Missing('sf1_missing'),

  /// Confirmed from the new section's SF1 import ("moving from ...").
  sf1Incoming('sf1_incoming'),

  /// A restore of an archived learner into another section.
  returned('return'),

  /// A transfer in from another school (sf1_transfer_in, D15): the from_*
  /// fields hold the other school's side.
  transferIn('transfer_in');

  final String value;
  const EnrollmentMoveSource(this.value);

  static EnrollmentMoveSource fromValue(String v) => EnrollmentMoveSource.values.firstWhere(
        (s) => s.value == v,
        orElse: () => throw ArgumentError('Invalid EnrollmentMoveSource value: $v'),
      );
}

class EnrollmentMove {
  final int? id;
  final int enrollmentId;
  final int studentId;
  final int schoolId;
  final String schoolYear;
  final int fromSectionId;
  final int toSectionId;

  /// ISO date.
  final String movedOn;

  /// users.id (uuid) of who moved the learner.
  final String? movedBy;
  final EnrollmentMoveSource source;

  /// A transfer only: the school the learner left, its name and the
  /// section's name then (snapshots: the receiving school can't read them),
  /// and that school's archive of the enrollment (status, ISO date).
  final int? fromSchoolId;
  final String? fromSchoolName;
  final String? fromSectionName;
  final String? fromStatus;
  final String? fromLeftOn;

  EnrollmentMove({
    this.id,
    required this.enrollmentId,
    required this.studentId,
    required this.schoolId,
    required this.schoolYear,
    required this.fromSectionId,
    required this.toSectionId,
    required this.movedOn,
    this.movedBy,
    required this.source,
    this.fromSchoolId,
    this.fromSchoolName,
    this.fromSectionName,
    this.fromStatus,
    this.fromLeftOn,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'enrollment_id': enrollmentId,
        'student_id': studentId,
        'school_id': schoolId,
        'school_year': schoolYear,
        'from_section_id': fromSectionId,
        'to_section_id': toSectionId,
        'moved_on': movedOn,
        'moved_by': movedBy,
        'source': source.value,
        if (fromSchoolId != null) 'from_school_id': fromSchoolId,
        if (fromSchoolName != null) 'from_school_name': fromSchoolName,
        if (fromSectionName != null) 'from_section_name': fromSectionName,
        if (fromStatus != null) 'from_status': fromStatus,
        if (fromLeftOn != null) 'from_left_on': fromLeftOn,
      };

  factory EnrollmentMove.fromMap(Map<String, Object?> m) => EnrollmentMove(
        id: m['id'] as int?,
        enrollmentId: m['enrollment_id'] as int,
        studentId: m['student_id'] as int,
        schoolId: m['school_id'] as int,
        schoolYear: m['school_year'] as String,
        fromSectionId: m['from_section_id'] as int,
        toSectionId: m['to_section_id'] as int,
        movedOn: m['moved_on'] as String,
        movedBy: m['moved_by'] as String?,
        source: EnrollmentMoveSource.fromValue(m['source'] as String),
        fromSchoolId: m['from_school_id'] as int?,
        fromSchoolName: m['from_school_name'] as String?,
        fromSectionName: m['from_section_name'] as String?,
        fromStatus: m['from_status'] as String?,
        fromLeftOn: m['from_left_on'] as String?,
      );
}
