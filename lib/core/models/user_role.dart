//lib/core/models/user_role.dart
enum UserRole{
  admin,
  coordinator,
  tutor;

  static UserRole fromString(String value){
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => throw ArgumentError('Invalid UserRole value: $value'),
    );
  }

}