// lib/core/data/remote/aral_session_repository_supabase.dart
//
// Same interface as the SQLite repository (the main write path today); used
// online and by the future sync. The database assigns session_no and stamps
// created_by and the times; client values for those are dropped. Deleting a
// session cascades to its attendance in Postgres.
import 'package:supabase/supabase.dart';
import '../../models/aral_session.dart';
import '../../repositories/aral_session_repository.dart';

class AralSessionRepositorySupabase implements AralSessionRepository {
  final SupabaseClient client;
  AralSessionRepositorySupabase(this.client);

  static AralSession _s(Object? r) => AralSession.fromMap(r as Map<String, Object?>);
  static AralAttendance _a(Object? r) => AralAttendance.fromMap(r as Map<String, Object?>);

  static const _changeable = ['held_on', 'minutes', 'setup', 'lesson', 'remarks'];

  @override
  Future<AralSession> insertSession(AralSession session) async {
    final payload = session.toMap()
      ..remove('id')
      ..remove('session_no')
      ..remove('created_by')
      ..remove('created_at')
      ..remove('updated_at');
    final rows = await client.from('aral_sessions').insert(payload).select();
    return _s((rows as List).first);
  }

  @override
  Future<AralSession> updateSession(AralSession session) async {
    if (session.id == null) throw ArgumentError('updateSession needs an id');
    final all = session.toMap();
    final rows = await client
        .from('aral_sessions')
        .update({for (final c in _changeable) c: all[c]})
        .eq('id', session.id!)
        .select();
    if ((rows as List).isEmpty) throw Exception('No ARAL session changed — check the id or your permissions');
    return _s(rows.first);
  }

  @override
  Future<void> deleteSession(int id) async {
    final rows = await client.from('aral_sessions').delete().eq('id', id).select();
    if ((rows as List).isEmpty) throw Exception('No ARAL session deleted — check the id or your permissions');
  }

  @override
  Future<AralSession?> findSession(int id) async {
    final rows = await client.from('aral_sessions').select().eq('id', id);
    return (rows as List).isEmpty ? null : _s(rows.first);
  }

  Future<List<AralSession>> _sessions(String column, Object value, String? schoolYear) async {
    var q = client.from('aral_sessions').select().eq(column, value);
    if (schoolYear != null) q = q.eq('school_year', schoolYear);
    final rows = await q.order('held_on').order('session_no');
    return (rows as List).map(_s).toList();
  }

  @override
  Future<List<AralSession>> getByTutor(String tutorId, {String? schoolYear}) =>
      _sessions('tutor_id', tutorId, schoolYear);

  @override
  Future<List<AralSession>> getBySchool(int schoolId, {String? schoolYear}) =>
      _sessions('school_id', schoolId, schoolYear);

  @override
  Future<List<AralSession>> getByClass(int classId) => _sessions('class_id', classId, null);

  @override
  Future<AralAttendance> saveAttendance(AralAttendance attendance) async {
    final payload = attendance.toMap()
      ..remove('id')
      ..remove('created_at')
      ..remove('updated_at');
    final rows = await client
        .from('aral_attendance')
        .upsert(payload, onConflict: 'session_id,enrollment_id')
        .select();
    return _a((rows as List).first);
  }

  @override
  Future<void> deleteAttendance(int id) async {
    final rows = await client.from('aral_attendance').delete().eq('id', id).select();
    if ((rows as List).isEmpty) throw Exception('No attendance mark deleted — check the id or your permissions');
  }

  @override
  Future<List<AralAttendance>> getAttendance(int sessionId) async {
    final rows = await client.from('aral_attendance').select().eq('session_id', sessionId).order('id');
    return (rows as List).map(_a).toList();
  }

  @override
  Future<List<AralAttendance>> getAttendanceForEnrollment(int enrollmentId) async {
    final rows = await client.from('aral_attendance').select().eq('enrollment_id', enrollmentId).order('id');
    return (rows as List).map(_a).toList();
  }

  @override
  Future<AralSession> upsertSessionWithId(AralSession session) =>
      throw UnimplementedError('upsertSessionWithId is for local mirroring only');

  @override
  Future<AralAttendance> upsertAttendanceWithId(AralAttendance attendance) =>
      throw UnimplementedError('upsertAttendanceWithId is for local mirroring only');
}
