// lib/core/models/section.dart

class Section {
  final int? id;
  final int schoolId;
  final String schoolYear;
  final String gradeLevel;
  final String sectionName;
  /// The adviser's name as the school writes it (ARAL Form 2); optional.
  final String? adviserName;
  /// The adviser's BASA account (users.id) when they have one, a user of the
  /// section's school (cloud 20261118030000). The ARAL adviser rule reads it.
  final String? adviserUserId;

  Section(
    {
      this.id,
      required this.schoolId,
      required this.schoolYear,
      required this.gradeLevel,
      required this.sectionName,
      this.adviserName,
      this.adviserUserId,
    }
  );

  Map<String, Object?> toMap() => {
    if(id != null) 'id': id,
    'school_id': schoolId,
    'school_year': schoolYear,
    'grade_level': gradeLevel,
    'section_name': sectionName,
    'adviser_name': adviserName,
    'adviser_user_id': adviserUserId,
  };

  factory Section.fromMap(Map<String, Object?> map) => Section(
    id: map['id'] as int?,
    schoolId: map['school_id'] as int,
    schoolYear: map['school_year'] as String,
    gradeLevel: map['grade_level'] as String,
    sectionName: map['section_name'] as String,
    adviserName: map['adviser_name'] as String?,
    adviserUserId: map['adviser_user_id'] as String?,
  );

  @override
  String toString() => '$gradeLevel - $sectionName ($schoolYear)';
}
