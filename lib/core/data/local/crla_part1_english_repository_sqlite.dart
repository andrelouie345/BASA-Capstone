// lib/core/data/local/crla_part1_english_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/crla_part1_english.dart';
import '../../repositories/crla_part1_english_repository.dart';

class CrlaPart1EnglishRepositorySqlite implements CrlaPart1EnglishRepository {
  final Database db;
  CrlaPart1EnglishRepositorySqlite(this.db);

  @override
  Future<CrlaPart1English> insert(CrlaPart1English part1) async {
    // toMap() omits total_score / reading_level; the AFTER INSERT trigger
    // computes them, so re-read the row to pick them up.
    await db.insert('crla_part1_english', part1.toMap());
    final stored = await findByAssessmentId(part1.assessmentId);
    if (stored == null) {
      throw StateError(
        'crla_part1_english row for assessment ${part1.assessmentId} vanished right after insert',
      );
    }
    return stored;
  }

  @override
  Future<void> update(CrlaPart1English part1) async {
    // assessment_id is the key, not something we change.
    final values = part1.toMap()..remove('assessment_id');
    final count = await db.update(
      'crla_part1_english',
      values,
      where: 'assessment_id = ?',
      whereArgs: [part1.assessmentId],
    );
    if (count == 0) {
      throw StateError('No crla_part1_english row for assessment ${part1.assessmentId}');
    }
  }

  @override
  Future<CrlaPart1English?> findByAssessmentId(int assessmentId) async {
    final rows = await db.query(
      'crla_part1_english',
      where: 'assessment_id = ?',
      whereArgs: [assessmentId],
      limit: 1,
    );
    return rows.isEmpty ? null : CrlaPart1English.fromMap(rows.first);
  }

  @override
  Future<CrlaPart1English> upsertWithId(CrlaPart1English part1) async {
    await db.insert(
      'crla_part1_english',
      part1.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // INSERT OR REPLACE
    );
    return (await findByAssessmentId(part1.assessmentId))!;
  }
}