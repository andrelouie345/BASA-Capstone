// lib/core/repositories/aral_session_repository.dart
import '../models/aral_session.dart';

/// ARAL sessions (the lesson log) and their attendance. SQLite is the main
/// write path (offline-first); the Supabase implementation has the same
/// interface for online use and the future sync.
abstract class AralSessionRepository {
  /// Stores a new session; the database assigns session_no.
  Future<AralSession> insertSession(AralSession session);

  /// Saves the changeable fields (date, minutes, set-up, lesson, remarks).
  Future<AralSession> updateSession(AralSession session);

  /// Deletes the session and its attendance.
  Future<void> deleteSession(int id);

  Future<AralSession?> findSession(int id);

  Future<List<AralSession>> getByTutor(String tutorId, {String? schoolYear});

  Future<List<AralSession>> getBySchool(int schoolId, {String? schoolYear});

  /// The class's sessions, by date.
  Future<List<AralSession>> getByClass(int classId);

  /// Records or replaces a learner's mark for the session (one per learner).
  Future<AralAttendance> saveAttendance(AralAttendance attendance);

  Future<void> deleteAttendance(int id);

  Future<List<AralAttendance>> getAttendance(int sessionId);

  /// Every mark of one ARAL learner, oldest session first.
  Future<List<AralAttendance>> getAttendanceForEnrollment(int enrollmentId);

  /// Local-mirroring only: keep Supabase's ids (session origin 'cloud').
  /// Supabase impl throws UnimplementedError.
  Future<AralSession> upsertSessionWithId(AralSession session);
  Future<AralAttendance> upsertAttendanceWithId(AralAttendance attendance);
}
