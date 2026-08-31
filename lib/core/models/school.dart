//lib/cor/models/school.dart
class School {
  final int? id;
  final String schoolId;
  final String schoolName;
  final String? region;
  final String? division;

  School({
    this.id,
    required this.schoolId,
    required this.schoolName,
    this.region,
    this.division,
  });

  Map<String, Object?> toMap() =>{
    if(id != null) 'id': id,
    'schoolId': schoolId,
    'schoolName': schoolName,
    'region': region,
    'division': division,
  };

  factory School.fromMap(Map<String, Object?> map) => School(
    id: map['id'] as int?,
    schoolId: map['schoolId'] as String,
    schoolName: map['schoolName'] as String,
    region: map['region'] as String?,
    division: map['division'] as String?,
  );
}