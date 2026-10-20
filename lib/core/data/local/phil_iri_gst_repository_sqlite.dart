// lib/core/data/local/phil_iri_gst_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'sync_local_writes.dart';
import 'sqlite_values.dart';
import '../../models/phil_iri_gst_result.dart';
import '../../repositories/phil_iri_gst_repository.dart';

class PhilIriGstRepositorySqlite implements PhilIriGstRepository {
  final Database db;
  PhilIriGstRepositorySqlite(this.db);

  @override
  Future<PhilIriGstResult> insert(PhilIriGstResult result) async {
    // attempt_no is left out (default 0): the AFTER INSERT trigger assigns it,
    // so re-read the row. origin defaults to 'local'.
    final row = toSqliteRow(result.toMap())
      ..remove('attempt_no')
      ..['id'] = await nextLocalId(db);
    final id = await db.insert('phil_iri_gst_results', row);
    final stored = await findById(id);
    if (stored == null) throw StateError('phil_iri_gst_results row $id vanished right after insert');
    return stored;
  }

  @override
  Future<PhilIriGstResult?> findById(int id) async {
    final rows = await db.query('phil_iri_gst_results', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PhilIriGstResult.fromMap(rows.first);
  }

  @override
  Future<List<PhilIriGstResult>> getBySection(int sectionId, {String? schoolYear}) async {
    final rows = await db.query(
      'phil_iri_gst_results',
      where: schoolYear == null ? 'section_id = ?' : 'section_id = ? AND school_year = ?',
      whereArgs: schoolYear == null ? [sectionId] : [sectionId, schoolYear],
      orderBy: 'student_id, attempt_no',
    );
    return rows.map(PhilIriGstResult.fromMap).toList();
  }

  @override
  Future<List<PhilIriGstResult>> getByStudent(int studentId, {String? schoolYear}) async {
    final rows = await db.query(
      'phil_iri_gst_results',
      where: schoolYear == null ? 'student_id = ?' : 'student_id = ? AND school_year = ?',
      whereArgs: schoolYear == null ? [studentId] : [studentId, schoolYear],
      orderBy: 'taken_at DESC, id DESC',
    );
    return rows.map(PhilIriGstResult.fromMap).toList();
  }

  @override
  Future<PhilIriGstResult?> getLatest({required int studentId, required String schoolYear}) async {
    final rows = await getByStudent(studentId, schoolYear: schoolYear);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<PhilIriGstResult> upsertWithId(PhilIriGstResult result) async {
    if (result.id == null) throw ArgumentError('Cannot upsertWithId a PhilIriGstResult with no id');
    if (result.attemptNo == null || result.attemptNo == 0) {
      // 0 would make the local trigger renumber it.
      throw ArgumentError('upsertWithId requires the real attemptNo (got ${result.attemptNo})');
    }
    await mirrorSyncedRow(db, 'phil_iri_gst_results', {...toSqliteRow(result.toMap()), 'origin': 'cloud'});
    return (await findById(result.id!))!;
  }
}
