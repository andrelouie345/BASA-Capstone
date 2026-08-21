enum UserRole {
  teacher,
  coordinator,
  admin,
}

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.teacher:
        return 'Teacher';
      case UserRole.coordinator:
        return 'Coordinator';
      case UserRole.admin:
        return 'Admin';
    }
  }

  String get shortLabel {
    switch (this) {
      case UserRole.teacher:
        return 'Teacher';
      case UserRole.coordinator:
        return 'Coordinator';
      case UserRole.admin:
        return 'Admin';
    }
  }
}
