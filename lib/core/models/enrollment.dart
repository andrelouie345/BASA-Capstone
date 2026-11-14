// lib/core/models/enrollment.dart
//
// One learner in one section for a school year (one row per learner per
// year; a section move changes section_id). SF1 leavers (spec
// docs/superpowers/specs/2026-11-12-sf1-leavers-design.md, D1): a learner who
// transferred out or dropped out is archived, never deleted: the status
// changes and left_on / left_by (and an optional left_note) are set. Only
// the server functions archive, move and restore; the device mirrors their
// results (learner_leaver_local_writes.dart).

/// An enrollment's status. Archived = [transferredOut] or [droppedOut].
enum EnrollmentStatus {
  active('active'),
  transferredOut('transferred_out'),
  droppedOut('dropped_out');

  final String value;
  const EnrollmentStatus(this.value);

  bool get isArchived => this != active;

  static EnrollmentStatus fromValue(String v) => EnrollmentStatus.values.firstWhere(
        (s) => s.value == v,
        orElse: () => throw ArgumentError('Invalid EnrollmentStatus value: $v'),
      );
}

class Enrollment {
  final int? id;
  final int studentId;
  final int sectionId;
  final String schoolYear;
  final EnrollmentStatus status;

  /// Set exactly when archived (ISO date).
  final String? leftOn;

  /// Who archived (users.id, a uuid); set exactly when archived.
  final String? leftBy;

  /// Optional, only when archived.
  final String? leftNote;

  Enrollment({
    this.id,
    required this.studentId,
    required this.sectionId,
    required this.schoolYear,
    this.status = EnrollmentStatus.active,
    this.leftOn,
    this.leftBy,
    this.leftNote,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'student_id': studentId,
        'section_id': sectionId,
        'school_year': schoolYear,
        'status': status.value,
        'left_on': leftOn,
        'left_by': leftBy,
        'left_note': leftNote,
      };

  factory Enrollment.fromMap(Map<String, Object?> m) => Enrollment(
        id: m['id'] as int?,
        studentId: m['student_id'] as int,
        sectionId: m['section_id'] as int,
        schoolYear: m['school_year'] as String,
        status: EnrollmentStatus.fromValue((m['status'] as String?) ?? 'active'),
        leftOn: m['left_on'] as String?,
        leftBy: m['left_by'] as String?,
        leftNote: m['left_note'] as String?,
      );
}
