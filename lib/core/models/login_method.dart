// lib/core/models/login_method.dart

enum LoginMethod{
  online,
  cachedSession,
  offline; // offline sign-in against the stored credential (local log only, mode 'offline')

  static LoginMethod fromString(String value) => LoginMethod.values.firstWhere(
    (m) => m.name == value,
    orElse: () => throw ArgumentError('Invalid LoginMethod value: $value'),
  );
}