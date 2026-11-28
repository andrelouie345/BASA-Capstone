// lib/core/data/local/crla_digitized_repository_sqlite.dart
//
// Digitized CRLA on the device: content reads and the attempt's evidence
// (SQLite v51, crla_local_schema.dart). New rows get the next local id
// (negative, sync_local_writes.dart); the sync triggers journal changes of
// pulled rows.
import 'package:sqflite_common/sqflite.dart';

import '../../models/crla_marks.dart';
import '../../repositories/crla_digitized_repository.dart';
import 'sync_local_writes.dart';

Map<String, Object?> _sqlite(Map<String, Object?> m) =>
    {for (final e in m.entries) e.key: e.value is bool ? ((e.value as bool) ? 1 : 0) : e.value};

class CrlaDigitizedRepositorySqlite implements CrlaDigitizedRepository {
  final Database db;
  CrlaDigitizedRepositorySqlite(this.db);

  @override
  Future<List<CrlaPart1Item>> part1Items({required int regionId, required String language, required int grade}) async {
    final rows = await db.query('crla_part1_items',
        where: 'region_id = ? AND language = ? AND grade = ?', whereArgs: [regionId, language, grade],
        orderBy: 'task, item_no');
    return rows.map(CrlaPart1Item.fromMap).toList();
  }

  @override
  Future<String?> storyBody(int storyId) async {
    final rows = await db.query('crla_stories', columns: ['body'], where: 'id = ?', whereArgs: [storyId]);
    return rows.isEmpty ? null : rows.first['body'] as String?;
  }

  @override
  Future<List<CrlaStoryQuestion>> questions(int storyId) async {
    final rows =
        await db.query('crla_story_questions', where: 'story_id = ?', whereArgs: [storyId], orderBy: 'question_no');
    return rows.map(CrlaStoryQuestion.fromMap).toList();
  }

  /// Updates [fields] of the row matching [where], else inserts [row] with a
  /// new local id.
  Future<void> _upsert(
      String table, Map<String, Object?> row, String where, List<Object?> args, List<String> fields) async {
    final existing = await db.query(table, columns: ['id'], where: where, whereArgs: args);
    if (existing.isNotEmpty) {
      await db.update(table, {for (final f in fields) f: row[f]}, where: 'id = ?', whereArgs: [existing.first['id']]);
    } else {
      await db.insert(table, {...row..remove('id'), 'id': await nextLocalId(db)});
    }
  }

  @override
  Future<void> setPart1Mark(CrlaPart1Mark mark) => _upsert('crla_part1_marks', _sqlite(mark.toMap()),
      'assessment_id = ? AND task = ? AND item_no = ?', [mark.assessmentId, mark.task.value, mark.itemNo],
      ['correct', 'self_corrected']);

  @override
  Future<void> deletePart1Mark(int assessmentId, CrlaTask task, int itemNo) async {
    await db.delete('crla_part1_marks',
        where: 'assessment_id = ? AND task = ? AND item_no = ?', whereArgs: [assessmentId, task.value, itemNo]);
  }

  @override
  Future<void> deletePart1Marks(int assessmentId, CrlaTask task) async {
    await db.delete('crla_part1_marks', where: 'assessment_id = ? AND task = ?', whereArgs: [assessmentId, task.value]);
  }

  @override
  Future<void> setWordMark(CrlaWordMark mark) => _upsert('crla_part2_word_marks', _sqlite(mark.toMap()),
      'assessment_id = ? AND word_index = ?', [mark.assessmentId, mark.wordIndex], ['kind']);

  @override
  Future<void> deleteWordMark(int assessmentId, int wordIndex) async {
    await db.delete('crla_part2_word_marks',
        where: 'assessment_id = ? AND word_index = ?', whereArgs: [assessmentId, wordIndex]);
  }

  @override
  Future<void> setAnswer(CrlaAnswer answer) => _upsert('crla_part2_answers', _sqlite(answer.toMap()),
      'assessment_id = ? AND question_no = ?', [answer.assessmentId, answer.questionNo], ['mark']);

  @override
  Future<CrlaTimerEvent> insertTimerEvent(CrlaTimerEvent event) async {
    final id = await db.insert('crla_timer_events', {...event.toMap()..remove('id'), 'id': await nextLocalId(db)});
    final rows = await db.query('crla_timer_events', where: 'id = ?', whereArgs: [id]);
    return CrlaTimerEvent.fromMap(rows.first);
  }

  @override
  Future<CrlaEvidence> evidence(int assessmentId) async {
    Future<List<Map<String, Object?>>> q(String t, String order) =>
        db.query(t, where: 'assessment_id = ?', whereArgs: [assessmentId], orderBy: order);
    return CrlaEvidence(
      part1: (await q('crla_part1_marks', 'task, item_no')).map(CrlaPart1Mark.fromMap).toList(),
      words: (await q('crla_part2_word_marks', 'word_index')).map(CrlaWordMark.fromMap).toList(),
      answers: (await q('crla_part2_answers', 'question_no')).map(CrlaAnswer.fromMap).toList(),
      timer: (await q('crla_timer_events', 'seq')).map(CrlaTimerEvent.fromMap).toList(),
    );
  }

  @override
  Future<bool> hasEvidence(int assessmentId) async {
    final rows = await db.rawQuery('''
      SELECT EXISTS (SELECT 1 FROM crla_part1_marks WHERE assessment_id = ?1)
          OR EXISTS (SELECT 1 FROM crla_part2_word_marks WHERE assessment_id = ?1)
          OR EXISTS (SELECT 1 FROM crla_part2_answers WHERE assessment_id = ?1)
          OR EXISTS (SELECT 1 FROM crla_timer_events WHERE assessment_id = ?1) AS any_row''', [assessmentId]);
    return (rows.first['any_row'] as int) == 1;
  }

  @override
  Future<void> deletePart1(int assessmentId) async {
    if (assessmentId >= 0) throw StateError('only an attempt made on this device is cleared here');
    for (final t in ['crla_part1_standard', 'crla_part1_english']) {
      await db.delete(t, where: 'assessment_id = ?', whereArgs: [assessmentId]);
    }
  }

  @override
  Future<List<({int assessmentId, String lastName, String firstName})>> attemptsWithUnsentTimerTaps() async {
    final rows = await db.rawQuery('''
      SELECT DISTINCT e.assessment_id, s.last_name, s.first_name
        FROM crla_timer_events e
        JOIN crla_assessments a ON a.id = e.assessment_id
        LEFT JOIN students s ON s.id = a.student_id
       WHERE e.row_version IS NULL
       ORDER BY s.last_name, s.first_name''');
    return [
      for (final r in rows)
        (
          assessmentId: (r['assessment_id'] as num).toInt(),
          lastName: r['last_name'] as String? ?? '',
          firstName: r['first_name'] as String? ?? '',
        ),
    ];
  }
}
