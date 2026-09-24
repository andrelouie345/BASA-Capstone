// lib/core/models/student.dart

class Student {
  final int? id;
  final String lrn;
  final String lastName;
  final String firstName;
  final String? middleName;
  final String? sex;
  final String? birthDate;
  final String? motherTongue;
  final String? ipGroup;
  final String? religion;
  final String? addressStreet;
  final String? barangay;
  final String? municipality;
  final String? province;
  final String? fatherName;
  final String? motherMaidenName;
  final String? guardianName;
  final String? guardianRelationship;
  final String? contactNumber;
  final String? learningModality;
  final String? remarks;
  final int? schoolId;

  Student({
    this.id,
    required this.lrn,
    required this.lastName,
    required this.firstName,
    this.middleName,
    this.sex,
    this.birthDate,
    this.motherTongue,
    this.ipGroup,
    this.religion,
    this.addressStreet,
    this.barangay,
    this.municipality,
    this.province,
    this.fatherName,
    this.motherMaidenName,
    this.guardianName,
    this.guardianRelationship,
    this.contactNumber,
    this.learningModality,
    this.remarks,
    this.schoolId,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'lrn': lrn,
        'last_name': lastName,
        'first_name': firstName,
        'middle_name': middleName,
        'sex': sex,
        'birth_date': birthDate,
        'mother_tongue': motherTongue,
        'ip_group': ipGroup,
        'religion': religion,
        'address_street': addressStreet,
        'barangay': barangay,
        'municipality': municipality,
        'province': province,
        'father_name': fatherName,
        'mother_maiden_name': motherMaidenName,
        'guardian_name': guardianName,
        'guardian_relationship': guardianRelationship,
        'contact_number': contactNumber,
        'learning_modality': learningModality,
        'remarks': remarks,
        'school_id': schoolId,
      };

  factory Student.fromMap(Map<String, Object?> m) => Student(
        id: m['id'] as int?,
        lrn: m['lrn'] as String,
        lastName: m['last_name'] as String,
        firstName: m['first_name'] as String,
        middleName: m['middle_name'] as String?,
        sex: m['sex'] as String?,
        birthDate: m['birth_date'] as String?,
        motherTongue: m['mother_tongue'] as String?,
        ipGroup: m['ip_group'] as String?,
        religion: m['religion'] as String?,
        addressStreet: m['address_street'] as String?,
        barangay: m['barangay'] as String?,
        municipality: m['municipality'] as String?,
        province: m['province'] as String?,
        fatherName: m['father_name'] as String?,
        motherMaidenName: m['mother_maiden_name'] as String?,
        guardianName: m['guardian_name'] as String?,
        guardianRelationship: m['guardian_relationship'] as String?,
        contactNumber: m['contact_number'] as String?,
        learningModality: m['learning_modality'] as String?,
        remarks: m['remarks'] as String?,
        schoolId: m['school_id'] as int?,
      );
}