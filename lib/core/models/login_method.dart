// lib/core/models/login_method.dart

enum LoginMethod{
  online,
  cachedSession;

  static LoginMethod fromString(String value) => LoginMethod.values.firstWhere(
    (m) => m.name == value,
    orElse: () => throw ArgumentError('Invalid LoginMethod value: $value'),
  );
}