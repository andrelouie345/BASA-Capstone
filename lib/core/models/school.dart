// lib/core/models/school.dart
class School {
  final int? id;
  final String schoolId;
  final String schoolName;
  final int? regionId;
  final String? division;

  School({
    this.id,
    required this.schoolId,
    required this.schoolName,
    this.regionId,
    this.division,
  });

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'school_id': schoolId,
    'school_name': schoolName,
    'region_id': regionId,
    'division': division,
  };

  factory School.fromMap(Map<String, Object?> map) => School(
    id: map['id'] as int?,
    schoolId: map['school_id'] as String,
    schoolName: map['school_name'] as String,
    regionId: map['region_id'] as int?,
    division: map['division'] as String?,
  );
}