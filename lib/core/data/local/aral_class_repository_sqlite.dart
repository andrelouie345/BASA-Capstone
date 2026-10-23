// lib/core/data/local/aral_class_repository_sqlite.dart
//
// The main write path for ARAL classes (offline-first, like the roster). The
// local triggers (aral_local_schema.dart) enforce the cloud's rules for
// classes made on this device; the repository stamps the times the cloud
// stamps there (the cloud re-stamps on upload).
import 'package:sqflite_common/sqflite.dart';
import 'sync_local_writes.dart';
import 'sqlite_values.dart';
import '../../models/aral_class.dart';
import '../../repositories/aral_class_repository.dart';

class AralClassRepositorySqlite implements AralClassRepository {
  final Database db;
  AralClassRepositorySqlite(this.db);

  static String _now() => DateTime.now().toUtc().toIso8601String();

  /// The columns an update may change (the rest are fixed at insert).
  static const _changeable = ['class_name', 'program', 'grade_band', 'tutor_id', 'room', 'schedule', 'notes'];

  @override
  Future<AralClass> insert(AralClass aralClass) async {
    final now = _now();
    final row = toSqliteRow(aralClass.toMap())
      ..['id'] = await nextLocalId(db)
      ..['created_at'] = now
      ..['updated_at'] = now;
    final id = await db.insert('aral_classes', row);
    return (await findById(id))!;
  }

  @override
  Future<AralClass> update(AralClass aralClass) async {
    if (aralClass.id == null) throw ArgumentError('update needs an AralClass id');
    final all = toSqliteRow(aralClass.toMap());
    final values = {for (final c in _changeable) c: all[c], 'updated_at': _now()};
    final n = await db.update('aral_classes', values, where: 'id = ?', whereArgs: [aralClass.id]);
    if (n == 0) throw StateError('No ARAL class ${aralClass.id}');
    return (await findById(aralClass.id!))!;
  }

  @override
  Future<void> delete(int id) async {
    await db.delete('aral_classes', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<AralClass?> findById(int id) async {
    final rows = await db.query('aral_classes', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AralClass.fromMap(rows.first);
  }

  Future<List<AralClass>> _where(String column, Object value, String? schoolYear) async {
    final rows = await db.query(
      'aral_classes',
      where: schoolYear == null ? '$column = ?' : '$column = ? AND school_year = ?',
      whereArgs: schoolYear == null ? [value] : [value, schoolYear],
      orderBy: 'school_year, lower(class_name), id',
    );
    return rows.map(AralClass.fromMap).toList();
  }

  @override
  Future<List<AralClass>> getBySchool(int schoolId, {String? schoolYear}) =>
      _where('school_id', schoolId, schoolYear);

  @override
  Future<List<AralClass>> getByTutor(String tutorId, {String? schoolYear}) =>
      _where('tutor_id', tutorId, schoolYear);

  @override
  Future<AralClass> upsertWithId(AralClass aralClass) async {
    if (aralClass.id == null) throw ArgumentError('Cannot upsertWithId an AralClass with no id');
    await mirrorSyncedRow(db, 'aral_classes', {...toSqliteRow(aralClass.toMap()), 'origin': 'cloud'});
    return (await findById(aralClass.id!))!;
  }
}
