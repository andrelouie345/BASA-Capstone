// lib/core/data/local/aral_enrollment_repository_sqlite.dart
//
// The main write path for the ARAL roster (offline-first, like the Phil-IRI
// sessions). The local triggers (aral_local_schema.dart) enforce the cloud's
// rules for rows entered on this device; the repository stamps the times the
// cloud stamps there (the cloud re-stamps on upload).
import 'package:sqflite_common/sqflite.dart';
import 'sync_local_writes.dart';
import 'sqlite_values.dart';
import '../../models/aral_enrollment.dart';
import '../../repositories/aral_enrollment_repository.dart';

class AralEnrollmentRepositorySqlite implements AralEnrollmentRepository {
  final Database db;
  AralEnrollmentRepositorySqlite(this.db);

  static String _now() => DateTime.now().toUtc().toIso8601String();

  /// The columns an update may change (the rest are fixed at insert).
  static const _changeable = [
    'section_id', 'key_stage', 'track', 'class_id', 'status', 'entered_on', 'exited_on', 'exit_reason', 'notes',
    'suggested_key_stage', 'suggested_track', 'suggestion_round', 'suggestion_level', 'suggestion_assessment_id',
    'suggested_on',
  ];

  @override
  Future<AralEnrollment> insert(AralEnrollment enrollment) async {
    final now = _now();
    final row = toSqliteRow(enrollment.toMap())
      ..['id'] = await nextLocalId(db)
      ..['created_at'] = now
      ..['updated_at'] = now;
    final id = await db.insert('aral_enrollments', row);
    return (await findById(id))!;
  }

  @override
  Future<AralEnrollment> update(AralEnrollment enrollment) async {
    if (enrollment.id == null) throw ArgumentError('update needs an AralEnrollment id');
    final all = toSqliteRow(enrollment.toMap());
    final values = {for (final c in _changeable) c: all[c], 'updated_at': _now()};
    final n = await db.update('aral_enrollments', values, where: 'id = ?', whereArgs: [enrollment.id]);
    if (n == 0) throw StateError('No ARAL enrollment ${enrollment.id}');
    return (await findById(enrollment.id!))!;
  }

  @override
  Future<void> delete(int id) async {
    // Local foreign keys are off: the IRIP weeks and check-ins go too (the
    // cloud cascades).
    await db.transaction((txn) async {
      await txn.delete('aral_irip_weeks', where: 'enrollment_id = ?', whereArgs: [id]);
      await txn.delete('aral_checkin_answers',
          where: 'checkin_id IN (SELECT id FROM aral_checkins WHERE enrollment_id = ?)', whereArgs: [id]);
      await txn.delete('aral_checkins', where: 'enrollment_id = ?', whereArgs: [id]);
      await txn.delete('aral_enrollments', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<AralEnrollment?> findById(int id) async {
    final rows = await db.query('aral_enrollments', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AralEnrollment.fromMap(rows.first);
  }

  @override
  Future<AralEnrollment?> findForStudent(int studentId, String schoolYear) async {
    final rows = await db.query('aral_enrollments',
        where: 'student_id = ? AND school_year = ?', whereArgs: [studentId, schoolYear], limit: 1);
    return rows.isEmpty ? null : AralEnrollment.fromMap(rows.first);
  }

  Future<List<AralEnrollment>> _where(String column, Object value, String? schoolYear) async {
    final rows = await db.query(
      'aral_enrollments',
      where: schoolYear == null ? '$column = ?' : '$column = ? AND school_year = ?',
      whereArgs: schoolYear == null ? [value] : [value, schoolYear],
      orderBy: 'school_year, section_id, student_id',
    );
    return rows.map(AralEnrollment.fromMap).toList();
  }

  @override
  Future<List<AralEnrollment>> getBySection(int sectionId, {String? schoolYear}) =>
      _where('section_id', sectionId, schoolYear);

  @override
  Future<List<AralEnrollment>> getBySchool(int schoolId, {String? schoolYear}) =>
      _where('school_id', schoolId, schoolYear);

  @override
  Future<List<AralEnrollment>> getByTutor(String tutorId, {String? schoolYear}) async {
    final rows = await db.rawQuery(
      'SELECT e.* FROM aral_enrollments e JOIN aral_classes c ON c.id = e.class_id '
      'WHERE c.tutor_id = ?${schoolYear == null ? '' : ' AND e.school_year = ?'} '
      'ORDER BY e.school_year, e.section_id, e.student_id',
      [tutorId, ?schoolYear],
    );
    return rows.map(AralEnrollment.fromMap).toList();
  }

  @override
  Future<List<AralEnrollment>> getByClass(int classId) => _where('class_id', classId, null);

  @override
  Future<String?> classTutorId(int enrollmentId) async {
    final rows = await db.rawQuery(
        'SELECT c.tutor_id FROM aral_enrollments e JOIN aral_classes c ON c.id = e.class_id WHERE e.id = ?',
        [enrollmentId]);
    return rows.isEmpty ? null : rows.first['tutor_id'] as String?;
  }

  @override
  Future<AralEnrollment> upsertWithId(AralEnrollment enrollment) async {
    if (enrollment.id == null) throw ArgumentError('Cannot upsertWithId an AralEnrollment with no id');
    await mirrorSyncedRow(db, 'aral_enrollments', {...toSqliteRow(enrollment.toMap()), 'origin': 'cloud'});
    return (await findById(enrollment.id!))!;
  }
}
