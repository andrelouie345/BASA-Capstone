// lib/core/data/local/aral_enrollment_repository_sqlite.dart
//
// The main write path for the ARAL roster (offline-first, like the Phil-IRI
// sessions). The local triggers (aral_local_schema.dart) enforce the cloud's
// rules for rows entered on this device; the repository stamps the times the
// cloud stamps there (the cloud re-stamps on upload).
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/aral_enrollment.dart';
import '../../repositories/aral_enrollment_repository.dart';

class AralEnrollmentRepositorySqlite implements AralEnrollmentRepository {
  final Database db;
  AralEnrollmentRepositorySqlite(this.db);

  static String _now() => DateTime.now().toUtc().toIso8601String();

  /// The columns an update may change (the rest are fixed at insert).
  static const _changeable = [
    'section_id', 'key_stage', 'track', 'tutor_id', 'status', 'entered_on', 'exited_on', 'exit_reason', 'notes',
  ];

  @override
  Future<AralEnrollment> insert(AralEnrollment enrollment) async {
    final now = _now();
    final row = toSqliteRow(enrollment.toMap())
      ..remove('id')
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
    await db.delete('aral_enrollments', where: 'id = ?', whereArgs: [id]);
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
  Future<List<AralEnrollment>> getByTutor(String tutorId, {String? schoolYear}) =>
      _where('tutor_id', tutorId, schoolYear);

  @override
  Future<AralEnrollment> upsertWithId(AralEnrollment enrollment) async {
    if (enrollment.id == null) throw ArgumentError('Cannot upsertWithId an AralEnrollment with no id');
    await upsertById(db, 'aral_enrollments', {...toSqliteRow(enrollment.toMap()), 'origin': 'cloud'});
    return (await findById(enrollment.id!))!;
  }
}
