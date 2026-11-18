// lib/core/models/user.dart
import 'user_role.dart';

/// A tutor's type for the ARAL daily limits (Division Memorandum 180 s. 2026;
/// cloud users.tutor_type, 20261118030000): an internal tutor is a teacher of
/// the school, an external one isn't. Null = not set, no daily limit.
enum TutorType {
  internal,
  external;

  String get value => name;

  static TutorType? fromValue(String? v) =>
      v == null ? null : TutorType.values.firstWhere((t) => t.value == v,
          orElse: () => throw ArgumentError('Invalid TutorType value: $v'));
}

class User {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final int? schoolId;
  final bool isActive;
  final DateTime createdAt;
  final String? createdBy;
  final TutorType? tutorType;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.createdAt,
    this.schoolId,
    this.isActive = true,
    this.createdBy,
    this.tutorType,
  });

  factory User.fromMap(Map<String, dynamic> map) => User(
        id: map['id'] as String,
        email: map['email'] as String,
        fullName: map['full_name'] as String,
        role: UserRole.fromString(map['role'] as String),
        schoolId: map['school_id']as int?,
        isActive: map['is_active'] is bool ? map['is_active'] as bool : (map['is_active'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        createdBy: map['created_by'] as String?,
        tutorType: TutorType.fromValue(map['tutor_type'] as String?),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'role': role.name,
        'school_id': schoolId,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'created_by': createdBy,
        'tutor_type': tutorType?.value,
      };
}
