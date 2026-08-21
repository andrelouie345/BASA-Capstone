class AuthValidators {
  static String? validateUsername(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Please enter your DepEd username or email.';
    }

    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    final isEmail = emailPattern.hasMatch(trimmed);
    final isUsername = trimmed.contains('.') || trimmed.contains('_') || trimmed.length >= 4;

    if (!isEmail && !isUsername) {
      return 'Enter a valid username or email.';
    }

    return null;
  }

  static String? validatePassword(String? value) {
    final trimmed = value ?? '';
    if (trimmed.isEmpty) {
      return 'Please enter your password.';
    }
    if (trimmed.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }
}
