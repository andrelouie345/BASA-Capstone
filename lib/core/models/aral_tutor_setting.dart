// lib/core/models/aral_tutor_setting.dart
//
// Per-tutor ARAL switches set by the school's admin/coordinator. Offline-first
// like the roster. Owner decision (2026-10-15): a tutor holds at most one
// session per date unless a coordinator allows several for that tutor (e.g.
// one who runs two groups). A tutor without a row has the defaults.

class AralTutorSetting {
  final String tutorId;   // users.id (a tutor); the primary key
  final int schoolId;
  final bool multipleSessionsPerDay;
  final String? updatedBy;
  final String? updatedAt;

  const AralTutorSetting({
    required this.tutorId,
    required this.schoolId,
    this.multipleSessionsPerDay = false,
    this.updatedBy,
    this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'tutor_id': tutorId,
        'school_id': schoolId,
        'multiple_sessions_per_day': multipleSessionsPerDay,
        if (updatedBy != null) 'updated_by': updatedBy,
        if (updatedAt != null) 'updated_at': updatedAt,
      };

  factory AralTutorSetting.fromMap(Map<String, Object?> m) => AralTutorSetting(
        tutorId: m['tutor_id'] as String,
        schoolId: m['school_id'] as int,
        // SQLite stores 0/1, Postgres a boolean
        multipleSessionsPerDay: m['multiple_sessions_per_day'] == true || m['multiple_sessions_per_day'] == 1,
        updatedBy: m['updated_by'] as String?,
        updatedAt: m['updated_at']?.toString(),
      );
}
