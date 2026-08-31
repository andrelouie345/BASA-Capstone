// lib/core/data/local/import_conflict_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/import_conflict.dart';
import '../../repositories/import_conflict_repository.dart';

class ImportConflictRepositorySqlite implements ImportConflictRepository {
  final Database db;
  ImportConflictRepositorySqlite(this.db);

  @override
  Future<void> log(ImportConflict conflict) async {
    await db.insert('import_conflicts', {
      'lrn': conflict.lrn,
      'section_id': conflict.sectionId,
      'reason': conflict.reason,
      'incoming_data': conflict.incomingDataJson,
      'existing_student_id': conflict.existingStudentId,
      'status': conflict.status,
    });
  }

  @override
  Future<List<ImportConflict>> getPending() async {
    final rows = await db.query('import_conflicts', where: "status = 'pending'", orderBy: 'id');
    return rows.map(ImportConflict.fromMap).toList();
  }

  @override
  Future<ImportConflict?> getById(int id) async {
    final rows = await db.query('import_conflicts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : ImportConflict.fromMap(rows.first);
  }

  @override
  Future<void> resolve(int id, String status) async {
    await db.update('import_conflicts', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }
}