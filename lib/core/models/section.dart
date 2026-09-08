// lib/core/models/section.dart

class Section {
  final int? id;
  final int schoolId;
  final String schoolYear;
  final String gradeLevel;
  final String sectionName;

  Section(
    {
      this.id,
      required this.schoolId,
      required this.schoolYear,
      required this.gradeLevel,
      required this.sectionName,
    }
  );

  Map<String, Object?> toMap() => {
    if(id != null) 'id': id,
    'school_id': schoolId,
    'school_year': schoolYear,
    'grade_level': gradeLevel,
    'section_name': sectionName,
  };

  factory Section.fromMap(Map<String, Object?> map) => Section(
    id: map['id'] as int?,
    schoolId: map['school_id'] as int,
    schoolYear: map['school_year'] as String,
    gradeLevel: map['grade_level'] as String,
    sectionName: map['section_name'] as String,
  );

  @override
  String toString() => '$gradeLevel - $sectionName ($schoolYear)';
}