// lib/core/data/local/crla_result_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/crla_result.dart';
import '../../repositories/crla_result_repository.dart';

class CrlaResultRepositorySqlite implements CrlaResultRepository {
  final Database db;
  CrlaResultRepositorySqlite(this.db);

  @override
  Future<CrlaResult?> findByAssessmentId(int assessmentId) async {
    final rows = await db.query(
      'crla_results',
      where: 'assessment_id = ?',
      whereArgs: [assessmentId],
      limit: 1,
    );
    return rows.isEmpty ? null : CrlaResult.fromMap(rows.first);
  }

  @override
  Future<List<CrlaResult>> getBySection(int sectionId, {String? schoolYear}) async {
    final rows = await db.query(
      'crla_results',
      where: schoolYear == null ? 'section_id = ?' : 'section_id = ? AND school_year = ?',
      whereArgs: schoolYear == null ? [sectionId] : [sectionId, schoolYear],
      orderBy: 'student_id, subject_variant, attempt_no',
    );
    return rows.map(CrlaResult.fromMap).toList();
  }

  @override
  Future<List<CrlaResult>> getByStudent(int studentId) async {
    final rows = await db.query(
      'crla_results',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'assessed_at DESC, attempt_no DESC',
    );
    return rows.map(CrlaResult.fromMap).toList();
  }
}