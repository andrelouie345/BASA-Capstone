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
    'schoolId': schoolId,
    'schoolYear': schoolYear,
    'gradeLevel': gradeLevel,
    'sectionName': sectionName,
  };

  factory Section.fromMap(Map<String, Object?> map) => Section(
    id: map['id'] as int?,
    schoolId: map['schoolId'] as int,
    schoolYear: map['schoolYear'] as String,
    gradeLevel: map['gradeLevel'] as String,
    sectionName: map['sectionName'] as String,
  );

  @override
  String toString() => '$gradeLevel - $sectionName ($schoolYear)';
}