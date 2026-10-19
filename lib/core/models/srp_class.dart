// lib/core/models/srp_class.dart

/// A Summer Remediation Program class: learners of one school and school year
/// assessed at the same grade level (0 = Non-Reader), with a tutor, room and
/// schedule set by the coordinator.
class SrpClass {
  final int? id;
  final int schoolId;
  final String schoolYear;
  final int assessedGrade;
  final String className;
  final String? room;
  final String? schedule;
  final String? tutorId;
  final String? createdBy;
  final String? createdAt;
  final String? updatedAt;

  const SrpClass({
    this.id,
    required this.schoolId,
    required this.schoolYear,
    required this.assessedGrade,
    required this.className,
    this.room,
    this.schedule,
    this.tutorId,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  /// "Non-Reader" or "Grade 3".
  String get assessedLabel => assessedGrade == 0 ? 'Non-Reader' : 'Grade $assessedGrade';

  /// The editable columns (stamps are set by the database).
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'school_id': schoolId,
        'school_year': schoolYear,
        'assessed_grade': assessedGrade,
        'class_name': className,
        'room': room,
        'schedule': schedule,
        'tutor_id': tutorId,
      };

  factory SrpClass.fromMap(Map<String, Object?> m) => SrpClass(
        id: m['id'] as int?,
        schoolId: m['school_id'] as int,
        schoolYear: m['school_year'] as String,
        assessedGrade: m['assessed_grade'] as int,
        className: m['class_name'] as String,
        room: m['room'] as String?,
        schedule: m['schedule'] as String?,
        tutorId: m['tutor_id'] as String?,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
      );

  SrpClass copyWith({String? className, String? room, String? schedule, String? tutorId, bool clearRoom = false,
          bool clearSchedule = false, bool clearTutor = false}) =>
      SrpClass(
        id: id,
        schoolId: schoolId,
        schoolYear: schoolYear,
        assessedGrade: assessedGrade,
        className: className ?? this.className,
        room: clearRoom ? null : room ?? this.room,
        schedule: clearSchedule ? null : schedule ?? this.schedule,
        tutorId: clearTutor ? null : tutorId ?? this.tutorId,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// A learner in an SRP class; at most one class per learner per school year
/// (school_year is copied from the class by the database).
class SrpClassMember {
  final int? id;
  final int classId;
  final int studentId;
  final String schoolYear;
  final String? createdAt;

  const SrpClassMember({
    this.id,
    required this.classId,
    required this.studentId,
    required this.schoolYear,
    this.createdAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'class_id': classId,
        'student_id': studentId,
        'school_year': schoolYear,
      };

  factory SrpClassMember.fromMap(Map<String, Object?> m) => SrpClassMember(
        id: m['id'] as int?,
        classId: m['class_id'] as int,
        studentId: m['student_id'] as int,
        schoolYear: m['school_year'] as String,
        createdAt: m['created_at'] as String?,
      );
}
