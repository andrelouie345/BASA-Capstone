// lib/core/data/local/aral_session_repository_sqlite.dart
//
// The main write path for ARAL sessions and attendance (offline-first). The
// local triggers (aral_local_schema.dart) enforce the cloud's rules for
// sessions entered on this device and assign session_no. Local foreign keys
// are off, so deleting a session deletes its attendance here.
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/aral_session.dart';
import '../../repositories/aral_session_repository.dart';

class AralSessionRepositorySqlite implements AralSessionRepository {
  final Database db;
  AralSessionRepositorySqlite(this.db);

  static String _now() => DateTime.now().toUtc().toIso8601String();

  static const _changeable = ['held_on', 'minutes', 'setup', 'lesson', 'remarks'];

  // ---- Sessions ----

  @override
  Future<AralSession> insertSession(AralSession session) async {
    final now = _now();
    // session_no left at 0: the AFTER INSERT trigger assigns it.
    final row = toSqliteRow(session.toMap())
      ..remove('id')
      ..remove('session_no')
      ..['created_at'] = now
      ..['updated_at'] = now;
    final id = await db.insert('aral_sessions', row);
    return (await findSession(id))!;
  }

  @override
  Future<AralSession> updateSession(AralSession session) async {
    if (session.id == null) throw ArgumentError('updateSession needs an id');
    final all = toSqliteRow(session.toMap());
    final n = await db.update('aral_sessions', {for (final c in _changeable) c: all[c], 'updated_at': _now()},
        where: 'id = ?', whereArgs: [session.id]);
    if (n == 0) throw StateError('No ARAL session ${session.id}');
    return (await findSession(session.id!))!;
  }

  @override
  Future<void> deleteSession(int id) async {
    await db.transaction((txn) async {
      await txn.delete('aral_attendance', where: 'session_id = ?', whereArgs: [id]);
      await txn.delete('aral_sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<AralSession?> findSession(int id) async {
    final rows = await db.query('aral_sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AralSession.fromMap(rows.first);
  }

  Future<List<AralSession>> _sessions(String column, Object value, String? schoolYear) async {
    final rows = await db.query(
      'aral_sessions',
      where: schoolYear == null ? '$column = ?' : '$column = ? AND school_year = ?',
      whereArgs: schoolYear == null ? [value] : [value, schoolYear],
      orderBy: 'held_on, session_no',
    );
    return rows.map(AralSession.fromMap).toList();
  }

  @override
  Future<List<AralSession>> getByTutor(String tutorId, {String? schoolYear}) =>
      _sessions('tutor_id', tutorId, schoolYear);

  @override
  Future<List<AralSession>> getBySchool(int schoolId, {String? schoolYear}) =>
      _sessions('school_id', schoolId, schoolYear);

  // ---- Attendance ----

  @override
  Future<AralAttendance> saveAttendance(AralAttendance attendance) async {
    final existing = await db.query('aral_attendance',
        where: 'session_id = ? AND enrollment_id = ?',
        whereArgs: [attendance.sessionId, attendance.enrollmentId],
        limit: 1);
    final now = _now();
    late final int id;
    if (existing.isEmpty) {
      id = await db.insert('aral_attendance', {
        ...toSqliteRow(attendance.toMap())..remove('id'),
        'created_at': now,
        'updated_at': now,
      });
    } else {
      id = existing.first['id'] as int;
      await db.update('aral_attendance', {'mark': attendance.mark.name, 'note': attendance.note, 'updated_at': now},
          where: 'id = ?', whereArgs: [id]);
    }
    final rows = await db.query('aral_attendance', where: 'id = ?', whereArgs: [id]);
    return AralAttendance.fromMap(rows.first);
  }

  @override
  Future<void> deleteAttendance(int id) async {
    await db.delete('aral_attendance', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<AralAttendance>> getAttendance(int sessionId) async {
    final rows = await db.query('aral_attendance', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'id');
    return rows.map(AralAttendance.fromMap).toList();
  }

  @override
  Future<List<AralAttendance>> getAttendanceForEnrollment(int enrollmentId) async {
    final rows = await db.rawQuery('''
      SELECT a.* FROM aral_attendance a
      JOIN aral_sessions s ON s.id = a.session_id
      WHERE a.enrollment_id = ?
      ORDER BY s.held_on, s.session_no
    ''', [enrollmentId]);
    return rows.map(AralAttendance.fromMap).toList();
  }

  // ---- Mirroring ----

  @override
  Future<AralSession> upsertSessionWithId(AralSession session) async {
    if (session.id == null) throw ArgumentError('Cannot upsertSessionWithId an AralSession with no id');
    if (session.sessionNo == null || session.sessionNo == 0) {
      throw ArgumentError('upsertSessionWithId requires the real sessionNo (got ${session.sessionNo})');
    }
    await upsertById(db, 'aral_sessions', {...toSqliteRow(session.toMap()), 'origin': 'cloud'});
    return (await findSession(session.id!))!;
  }

  @override
  Future<AralAttendance> upsertAttendanceWithId(AralAttendance attendance) async {
    if (attendance.id == null) throw ArgumentError('Cannot upsertAttendanceWithId an AralAttendance with no id');
    await upsertById(db, 'aral_attendance', toSqliteRow(attendance.toMap()));
    final rows = await db.query('aral_attendance', where: 'id = ?', whereArgs: [attendance.id]);
    return AralAttendance.fromMap(rows.first);
  }
}
