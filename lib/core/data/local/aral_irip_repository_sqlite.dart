// lib/core/data/local/aral_irip_repository_sqlite.dart
//
// IRIP targets (mirror-only content) and weeks (the main write path,
// offline-first). The local triggers (aral_local_schema.dart) re-check the
// cloud's rules for weeks entered on this device.
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/aral_irip.dart';
import '../../repositories/aral_irip_repository.dart';

class AralIripRepositorySqlite implements AralIripRepository {
  final Database db;
  AralIripRepositorySqlite(this.db);

  static String _now() => DateTime.now().toUtc().toIso8601String();

  static const _changeable = ['target_id', 'status', 'rated_on', 'notes'];

  @override
  Future<List<AralIripTarget>> targets(AralIripProgram program) async {
    final rows = await db.query('aral_irip_targets',
        where: 'program = ? AND is_active = 1', whereArgs: [program.value], orderBy: 'strand DESC, seq');
    return rows.map(AralIripTarget.fromMap).toList();
  }

  @override
  Future<AralIripTarget?> findTarget(int id) async {
    final rows = await db.query('aral_irip_targets', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AralIripTarget.fromMap(rows.first);
  }

  @override
  Future<List<AralIripWeek>> weeks(int enrollmentId) async {
    final rows = await db.query('aral_irip_weeks',
        where: 'enrollment_id = ?', whereArgs: [enrollmentId], orderBy: 'cycle_no, week_no, strand DESC');
    return rows.map(AralIripWeek.fromMap).toList();
  }

  @override
  Future<AralIripWeek?> findWeek(int id) async {
    final rows = await db.query('aral_irip_weeks', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AralIripWeek.fromMap(rows.first);
  }

  @override
  Future<AralIripWeek> insertWeek(AralIripWeek week) async {
    final now = _now();
    final row = toSqliteRow(week.toMap())
      ..remove('id')
      ..['created_at'] = now
      ..['updated_at'] = now;
    final id = await db.insert('aral_irip_weeks', row);
    return (await findWeek(id))!;
  }

  @override
  Future<AralIripWeek> updateWeek(AralIripWeek week) async {
    if (week.id == null) throw ArgumentError('updateWeek needs an id');
    final all = toSqliteRow(week.toMap());
    final n = await db.update('aral_irip_weeks', {for (final c in _changeable) c: all[c], 'updated_at': _now()},
        where: 'id = ?', whereArgs: [week.id]);
    if (n == 0) throw StateError('No IRIP week ${week.id}');
    return (await findWeek(week.id!))!;
  }

  @override
  Future<void> deleteWeek(int id) async {
    await db.delete('aral_irip_weeks', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<AralIripTarget> upsertTargetWithId(AralIripTarget target) async {
    await upsertById(db, 'aral_irip_targets', toSqliteRow(target.toMap()));
    return (await findTarget(target.id))!;
  }

  @override
  Future<AralIripWeek> upsertWeekWithId(AralIripWeek week) async {
    if (week.id == null) throw ArgumentError('Cannot upsertWeekWithId an AralIripWeek with no id');
    await upsertById(db, 'aral_irip_weeks', {...toSqliteRow(week.toMap()), 'origin': 'cloud'});
    return (await findWeek(week.id!))!;
  }
}
