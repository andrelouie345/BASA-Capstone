// lib/core/data/local/phil_iri_passage_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/phil_iri_passage.dart';
import '../../models/phil_iri_question.dart';
import '../../repositories/phil_iri_passage_repository.dart';

/// Read + mirror only: Phil-IRI content is managed online.
class PhilIriPassageRepositorySqlite implements PhilIriPassageRepository {
  final Database db;
  PhilIriPassageRepositorySqlite(this.db);

  static Never _online() =>
      throw UnsupportedError('Phil-IRI passages are managed online; use the cloud repository');

  @override
  Future<PhilIriPassage> insert(PhilIriPassage passage) async => _online();
  @override
  Future<PhilIriPassage> update(PhilIriPassage passage) async => _online();
  @override
  Future<void> delete(int id) async => _online();
  @override
  Future<PhilIriQuestion> insertQuestion(PhilIriQuestion question) async => _online();
  @override
  Future<PhilIriQuestion> updateQuestion(PhilIriQuestion question) async => _online();
  @override
  Future<void> deleteQuestion(int id) async => _online();

  @override
  Future<PhilIriPassage?> findById(int id) async {
    final rows = await db.query('phil_iri_passages', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PhilIriPassage.fromMap(rows.first);
  }

  @override
  Future<List<PhilIriPassage>> getByCollection(int collectionId, {bool activeOnly = false}) async {
    final rows = await db.query(
      'phil_iri_passages',
      where: activeOnly ? 'collection_id = ? AND is_active = 1' : 'collection_id = ?',
      whereArgs: [collectionId],
      // "x IS NULL, x" puts NULLs last, as Postgres ascending does (matches the Supabase repo).
      orderBy: 'level IS NULL, level, set_code IS NULL, set_code, selection_no IS NULL, selection_no, id',
    );
    return rows.map(PhilIriPassage.fromMap).toList();
  }

  @override
  Future<List<PhilIriPassage>> getForLevel(int level) async {
    final rows = await db.rawQuery('''
      SELECT p.* FROM phil_iri_passages p
      JOIN phil_iri_collections c ON c.id = p.collection_id
      WHERE p.level = ? AND p.is_active = 1 AND c.is_grade_leveled = 1 AND c.is_active = 1
      ORDER BY p.collection_id, p.set_code IS NULL, p.set_code, p.id
    ''', [level]);
    return rows.map(PhilIriPassage.fromMap).toList();
  }

  @override
  Future<List<PhilIriQuestion>> getQuestions(int passageId) async {
    final rows = await db.query('phil_iri_questions',
        where: 'passage_id = ?', whereArgs: [passageId], orderBy: 'question_no');
    return rows.map(PhilIriQuestion.fromMap).toList();
  }

  @override
  Future<PhilIriPassage> upsertWithId(PhilIriPassage passage) async {
    if (passage.id == null) throw ArgumentError('Cannot upsertWithId a PhilIriPassage with no id');
    await upsertById(db, 'phil_iri_passages', toSqliteRow(passage.toMap()));
    return (await findById(passage.id!))!;
  }

  @override
  Future<PhilIriQuestion> upsertQuestionWithId(PhilIriQuestion question) async {
    if (question.id == null) throw ArgumentError('Cannot upsertQuestionWithId a PhilIriQuestion with no id');
    await upsertById(db, 'phil_iri_questions', toSqliteRow(question.toMap()));
    final rows = await db.query('phil_iri_questions', where: 'id = ?', whereArgs: [question.id]);
    return PhilIriQuestion.fromMap(rows.first);
  }

  // Local foreign keys are off, so these look for users themselves. A
  // negative id is a row not uploaded yet (sync); positive ones are on the
  // server, where the cloud refuses the delete as well.
  @override
  Future<void> removeMirrored(int id) async {
    await db.transaction((txn) async {
      await _checkUnused(txn, 'phil_iri_readings', 'passage_id', id, 'Readings', 'passage');
      await txn.delete('phil_iri_questions', where: 'passage_id = ?', whereArgs: [id]);
      await txn.delete('phil_iri_passages', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<void> removeMirroredQuestion(int id) async {
    await db.transaction((txn) async {
      await _checkUnused(txn, 'phil_iri_answers', 'question_id', id, 'Answers', 'question');
      await txn.delete('phil_iri_questions', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> _checkUnused(Transaction txn, String table, String column, int id, String users, String what) async {
    final unsent = await txn.query(table, where: '$column = ? AND id < 0', whereArgs: [id], limit: 1);
    if (unsent.isNotEmpty) throw StateError('$users on this device use this $what');
    final synced = await txn.query(table, where: '$column = ?', whereArgs: [id], limit: 1);
    if (synced.isNotEmpty) throw UsedOnServerError('$users on the server use this $what');
  }
}
