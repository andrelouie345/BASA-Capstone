// lib/core/models/tutor_section_assignment.dart
import 'section.dart';

class TutorSectionAssignment {
  final int? id;
  final String tutorId;
  final int sectionId;
  final String? assignedBy;
  final DateTime assignedAt;
  final String? tutorFullName;
  final String? tutorEmail;
  final Section? section;

  TutorSectionAssignment({
    this.id,
    required this.tutorId,
    required this.sectionId,
    required this.assignedAt,
    this.assignedBy,
    this.tutorFullName,
    this.tutorEmail,
    this.section,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'tutor_id': tutorId,
    'section_id': sectionId,
    'assigned_at': assignedAt.toIso8601String(),
    if (assignedBy != null) 'assigned_by': assignedBy,
  };

  factory TutorSectionAssignment.fromMap(Map<String, Object?> map) {
    final tutor = map['tutor'] as Map<String, Object?>?;
    final sectionMap = map['section'] as Map<String, Object?>?;
    return TutorSectionAssignment(
      id: map['id'] as int?,
      tutorId: map['tutor_id'] as String,
      sectionId: map['section_id'] as int,
      assignedAt: DateTime.parse(map['assigned_at'] as String),
      assignedBy: map['assigned_by'] as String?,
      tutorFullName: tutor?['full_name'] as String?,
      tutorEmail: tutor?['email'] as String?,
      section: sectionMap != null ? Section.fromMap(sectionMap) : null,
    );
  }

  @override
  String toString() => 'tutor $tutorId -> section $sectionId';
}