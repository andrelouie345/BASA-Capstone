// lib/core/models/aral_session.dart
//
// One ARAL-Reading session: a tutor's meeting on a date (the ARAL Program
// Lesson Log), with attendance per learner (AralAttendance). Offline-first like
// the roster. Owner decisions 2026-10-15: one tutor's meeting (learners may come
// from several sections); marks present/absent/excused; the log keeps minutes,
// set-up, session number, lesson and remarks; tutors write their own sessions,
// admins/coordinators any session of their school.

/// How the session was held (DepEd delivery options).
enum AralSetup {
  pullOut('pull_out', 'Pull-out'),
  duringClass('during_class', 'During class'),
  afterClass('after_class', 'After class'),
  weekend('weekend', 'Weekend'),
  other('other', 'Other');

  final String value;
  final String label;
  const AralSetup(this.value, this.label);

  static AralSetup fromString(String v) => AralSetup.values.firstWhere(
        (s) => s.value == v || s.name == v,
        orElse: () => throw ArgumentError('Invalid AralSetup value: $v'),
      );
}

/// DepEd: a session lasts at most 1 hour on weekdays and 2 hours on weekends.
const aralWeekdayMaxMinutes = 60;
const aralMaxMinutes = 120;

class AralSession {
  final int? id;
  final String tutorId;        // users.id
  final int schoolId;
  final String schoolYear;
  /// The tutor's nth session of the school year; assigned by the database
  /// (0 / null before insert). The check-ins come after sessions 16 and 32.
  final int? sessionNo;
  final String heldOn;         // YYYY-MM-DD
  final int minutes;
  final AralSetup setup;
  final String? lesson;        // free text, e.g. "KS3 Plus Lesson 5"
  final String? remarks;
  final String? createdBy;
  final String? createdAt;
  final String? updatedAt;

  const AralSession({
    this.id,
    required this.tutorId,
    required this.schoolId,
    required this.schoolYear,
    this.sessionNo,
    required this.heldOn,
    required this.minutes,
    required this.setup,
    this.lesson,
    this.remarks,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'tutor_id': tutorId,
        'school_id': schoolId,
        'school_year': schoolYear,
        if (sessionNo != null) 'session_no': sessionNo,
        'held_on': heldOn,
        'minutes': minutes,
        'setup': setup.value,
        'lesson': lesson,
        'remarks': remarks,
        if (createdBy != null) 'created_by': createdBy,
        if (createdAt != null) 'created_at': createdAt,
        if (updatedAt != null) 'updated_at': updatedAt,
      };

  factory AralSession.fromMap(Map<String, Object?> m) => AralSession(
        id: m['id'] as int?,
        tutorId: m['tutor_id'] as String,
        schoolId: m['school_id'] as int,
        schoolYear: m['school_year'] as String,
        sessionNo: m['session_no'] as int?,
        heldOn: m['held_on'].toString().substring(0, 10),
        minutes: m['minutes'] as int,
        setup: AralSetup.fromString(m['setup'] as String),
        lesson: m['lesson'] as String?,
        remarks: m['remarks'] as String?,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );

  AralSession copyWith({
    String? heldOn,
    int? minutes,
    AralSetup? setup,
    String? Function()? lesson,
    String? Function()? remarks,
  }) =>
      AralSession(
        id: id,
        tutorId: tutorId,
        schoolId: schoolId,
        schoolYear: schoolYear,
        sessionNo: sessionNo,
        heldOn: heldOn ?? this.heldOn,
        minutes: minutes ?? this.minutes,
        setup: setup ?? this.setup,
        lesson: lesson == null ? this.lesson : lesson(),
        remarks: remarks == null ? this.remarks : remarks(),
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

enum AralMark {
  present,
  absent,
  excused;

  static AralMark fromString(String v) => AralMark.values.firstWhere(
        (m) => m.name == v,
        orElse: () => throw ArgumentError('Invalid AralMark value: $v'),
      );
}

/// One learner's attendance at one session.
class AralAttendance {
  final int? id;
  final int sessionId;
  final int enrollmentId;      // aral_enrollments.id
  final AralMark mark;
  final String? note;
  final String? createdAt;
  final String? updatedAt;

  const AralAttendance({
    this.id,
    required this.sessionId,
    required this.enrollmentId,
    required this.mark,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'enrollment_id': enrollmentId,
        'mark': mark.name,
        'note': note,
        if (createdAt != null) 'created_at': createdAt,
        if (updatedAt != null) 'updated_at': updatedAt,
      };

  factory AralAttendance.fromMap(Map<String, Object?> m) => AralAttendance(
        id: m['id'] as int?,
        sessionId: m['session_id'] as int,
        enrollmentId: m['enrollment_id'] as int,
        mark: AralMark.fromString(m['mark'] as String),
        note: m['note'] as String?,
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}
