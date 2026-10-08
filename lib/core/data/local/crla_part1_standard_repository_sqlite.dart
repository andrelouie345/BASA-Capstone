// lib/core/data/local/crla_part1_standard_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/crla_part1_standard.dart';
import '../../repositories/crla_part1_standard_repository.dart';

class CrlaPart1StandardRepositorySqlite implements CrlaPart1StandardRepository {
  final Database db;
  CrlaPart1StandardRepositorySqlite(this.db);

  @override
  Future<CrlaPart1Standard> insert(CrlaPart1Standard part1) async {
    // toMap() omits total_score / reading_level; the AFTER INSERT trigger
    // computes them, so re-read the row to pick them up.
    await db.insert('crla_part1_standard', part1.toMap());
    final stored = await findByAssessmentId(part1.assessmentId);
    if (stored == null) {
      throw StateError(
        'crla_part1_standard row for assessment ${part1.assessmentId} vanished right after insert',
      );
    }
    return stored;
  }

  @override
  Future<void> update(CrlaPart1Standard part1) async {
    // assessment_id is the key, not something we change.
    final values = part1.toMap()..remove('assessment_id');
    final count = await db.update(
      'crla_part1_standard',
      values,
      where: 'assessment_id = ?',
      whereArgs: [part1.assessmentId],
    );
    if (count == 0) {
      throw StateError('No crla_part1_standard row for assessment ${part1.assessmentId}');
    }
  }

  @override
  Future<CrlaPart1Standard?> findByAssessmentId(int assessmentId) async {
    final rows = await db.query(
      'crla_part1_standard',
      where: 'assessment_id = ?',
      whereArgs: [assessmentId],
      limit: 1,
    );
    return rows.isEmpty ? null : CrlaPart1Standard.fromMap(rows.first);
  }

  @override
  Future<CrlaPart1Standard> upsertWithId(CrlaPart1Standard part1) async {
    await db.insert(
      'crla_part1_standard',
      part1.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // INSERT OR REPLACE
    );
    return (await findByAssessmentId(part1.assessmentId))!;
  }
}