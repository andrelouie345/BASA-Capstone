// lib/core/models/user.dart
import 'user_role.dart';

class User {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final int? schoolId;
  final bool isActive;
  final DateTime createdAt;
  final String? createdBy;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.createdAt,
    this.schoolId,
    this.isActive = true,
    this.createdBy,
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
      };
}