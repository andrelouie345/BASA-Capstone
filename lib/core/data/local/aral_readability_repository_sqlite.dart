// lib/core/data/local/aral_readability_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'sync_local_writes.dart';
import 'sqlite_values.dart';
import '../../models/aral_readability_log.dart';
import '../../repositories/aral_readability_repository.dart';

/// The main write path: rows written here are origin 'local' (the local
/// triggers re-check the cloud's rules for them). Stamps come from here.
class AralReadabilityRepositorySqlite implements AralReadabilityRepository {
  final Database db;
  AralReadabilityRepositorySqlite(this.db);

  static String _now() => DateTime.now().toUtc().toIso8601String();

  @override
  Future<List<AralReadabilityLog>> forEnrollment(int enrollmentId) async {
    final rows = await db.query('aral_readability_logs',
        where: 'enrollment_id = ?', whereArgs: [enrollmentId], orderBy: 'read_on, id');
    return rows.map(AralReadabilityLog.fromMap).toList();
  }

  @override
  Future<AralReadabilityLog?> findById(int id) async {
    final rows = await db.query('aral_readability_logs', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AralReadabilityLog.fromMap(rows.first);
  }

  @override
  Future<AralReadabilityLog> insert(AralReadabilityLog log) async {
    final now = _now();
    final id = await db.insert('aral_readability_logs', toSqliteRow({
      ...log.toMap(),
      'id': await nextLocalId(db),
      'created_at': now,
      'updated_at': now,
      'origin': 'local',
    }));
    return (await findById(id))!;
  }

  @override
  Future<AralReadabilityLog> update(AralReadabilityLog log) async {
    final row = Map.of(log.toMap())
      ..remove('id')
      ..remove('enrollment_id')
      ..remove('created_by');
    final n = await db.update('aral_readability_logs', toSqliteRow({...row, 'updated_at': _now()}),
        where: 'id = ?', whereArgs: [log.id]);
    if (n == 0) throw StateError('No readability log entry with id ${log.id}');
    return (await findById(log.id!))!;
  }

  @override
  Future<void> delete(int id) async {
    final n = await db.delete('aral_readability_logs', where: 'id = ?', whereArgs: [id]);
    if (n == 0) throw StateError('No readability log entry with id $id');
  }
}
