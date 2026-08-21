import '../models/user_role.dart';

abstract class AuthService {
  Future<bool> login({
    required String username,
    required String password,
    required UserRole role,
  });
}

class MockAuthService implements AuthService {
  @override
  Future<bool> login({
    required String username,
    required String password,
    required UserRole role,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    final trimmedUsername = username.trim();
    final trimmedPassword = password.trim();

    if (trimmedUsername.isEmpty || trimmedPassword.isEmpty) {
      return false;
    }

    if (trimmedPassword.length < 6) {
      return false;
    }

    return true;
  }
}
