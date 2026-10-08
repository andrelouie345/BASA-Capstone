// lib/core/data/local/crla_assessment_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/crla_assessment.dart';
import '../../repositories/crla_assessment_repository.dart';

class CrlaAssessmentRepositorySqlite implements CrlaAssessmentRepository {
  final Database db;
  CrlaAssessmentRepositorySqlite(this.db);

  @override
  Future<CrlaAssessment> insert(CrlaAssessment assessment) async {
    final id = await db.insert('crla_assessments', assessment.toMap());
    // The AFTER INSERT trigger rewrites attempt_no, so re-read the row.
    final stored = await findById(id);
    if (stored == null) {
      throw StateError('crla_assessments row $id vanished right after insert');
    }
    return stored;
  }

  @override
  Future<CrlaAssessment?> findById(int id) async {
    final rows = await db.query(
      'crla_assessments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : CrlaAssessment.fromMap(rows.first);
  }

  @override
  Future<List<CrlaAssessment>> getBySection(int sectionId, {String? schoolYear}) async {
    final rows = await db.query(
      'crla_assessments',
      where: schoolYear == null ? 'section_id = ?' : 'section_id = ? AND school_year = ?',
      whereArgs: schoolYear == null ? [sectionId] : [sectionId, schoolYear],
      orderBy: 'assessed_at DESC, id DESC',
    );
    return rows.map(CrlaAssessment.fromMap).toList();
  }

  @override
  Future<List<CrlaAssessment>> getByStudent(int studentId) async {
    final rows = await db.query(
      'crla_assessments',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'assessed_at DESC, id DESC',
    );
    return rows.map(CrlaAssessment.fromMap).toList();
  }

  @override
  Future<CrlaAssessment?> getLatestAttempt({
    required int studentId,
    required int sectionId,
    required String subjectVariant,
    required String schoolYear,
  }) async {
    final rows = await db.query(
      'crla_assessments',
      where: 'student_id = ? AND section_id = ? AND subject_variant = ? AND school_year = ?',
      whereArgs: [studentId, sectionId, subjectVariant, schoolYear],
      orderBy: 'attempt_no DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : CrlaAssessment.fromMap(rows.first);
  }

  @override
  Future<CrlaAssessment> upsertWithId(CrlaAssessment assessment) async {
    if (assessment.id == null) {
      throw ArgumentError('Cannot upsertWithId a CrlaAssessment with no id');
    }
    if (assessment.attemptNo == null || assessment.attemptNo == 0) {
      // A mirrored row must carry Supabase's real attempt_no. If it were 0,
      // the local trigger would renumber it and the two sides would drift.
      throw ArgumentError('upsertWithId requires the real attemptNo (got ${assessment.attemptNo})');
    }
    await db.insert(
      'crla_assessments',
      assessment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // INSERT OR REPLACE
    );
    return (await findById(assessment.id!))!;
  }
}