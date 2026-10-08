// lib/core/data/local/crla_part2_fluency_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/crla_part2_fluency.dart';
import '../../repositories/crla_part2_fluency_repository.dart';

class CrlaPart2FluencyRepositorySqlite implements CrlaPart2FluencyRepository {
  final Database db;
  CrlaPart2FluencyRepositorySqlite(this.db);

  @override
  Future<CrlaPart2Fluency> insert(CrlaPart2Fluency fluency) async {
    // toMap() omits wpm, so it is NULL on insert and the
    // compute_crla_part2_fluency_ins trigger (WHEN NEW.wpm IS NULL) fills it.
    await db.insert('crla_part2_fluency', fluency.toMap());
    final stored = await findByAssessmentId(fluency.assessmentId);
    if (stored == null) {
      throw StateError(
        'crla_part2_fluency row for assessment ${fluency.assessmentId} vanished right after insert',
      );
    }
    return stored;
  }

  @override
  Future<void> update(CrlaPart2Fluency fluency) async {
    // assessment_id is the key, not something we change.
    final values = fluency.toMap()..remove('assessment_id');
    final count = await db.update(
      'crla_part2_fluency',
      values,
      where: 'assessment_id = ?',
      whereArgs: [fluency.assessmentId],
    );
    if (count == 0) {
      throw StateError('No crla_part2_fluency row for assessment ${fluency.assessmentId}');
    }
  }

  @override
  Future<CrlaPart2Fluency?> findByAssessmentId(int assessmentId) async {
    final rows = await db.query(
      'crla_part2_fluency',
      where: 'assessment_id = ?',
      whereArgs: [assessmentId],
      limit: 1,
    );
    return rows.isEmpty ? null : CrlaPart2Fluency.fromMap(rows.first);
  }

  @override
  Future<CrlaPart2Fluency> upsertWithId(CrlaPart2Fluency fluency) async {
    await db.insert(
      'crla_part2_fluency',
      {
        ...fluency.toMap(),
        // Mirrored rows keep Supabase's wpm. A non-null wpm makes the insert
        // trigger's WHEN NEW.wpm IS NULL false, so it is stored as-is.
        if (fluency.wpm != null) 'wpm': fluency.wpm,
      },
      conflictAlgorithm: ConflictAlgorithm.replace, // INSERT OR REPLACE
    );
    return (await findByAssessmentId(fluency.assessmentId))!;
  }
}