class MockUser {
  const MockUser({
    required this.name,
    required this.role,
    required this.school,
    required this.division,
    this.schoolYear = 'S.Y. 2025–26',
  });

  final String name;
  final String role;
  final String school;
  final String division;
  final String schoolYear;
}

class MockAuthState {
  static MockUser? currentUser;

  static void signIn({
    required String name,
    required String role,
    required String school,
    required String division,
    String schoolYear = 'S.Y. 2025–26',
  }) {
    currentUser = MockUser(
      name: name,
      role: role,
      school: school,
      division: division,
      schoolYear: schoolYear,
    );
  }

  static void signOut() {
    currentUser = null;
  }
}

MockUser get defaultTeacherUser => const MockUser(
  name: 'Admin Reyes',
  role: 'Reading Teacher',
  school: 'Mapayapa Elementary School',
  division: 'Quezon City',
  schoolYear: 'S.Y. 2025–26',
);
