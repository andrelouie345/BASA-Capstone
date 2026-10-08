// lib/core/data/local/crla_story_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/crla_language.dart';
import '../../models/crla_story.dart';
import '../../repositories/crla_story_repository.dart';

class CrlaStoryRepositorySqlite implements CrlaStoryRepository {
  final Database db;
  CrlaStoryRepositorySqlite(this.db);

  @override
  Future<CrlaStory> insert(CrlaStory story) async {
    // toMap() normalizes language ('Filipino' -> 'Tagalog') and omits id when null.
    final id = await db.insert('crla_stories', story.toMap());
    final stored = await findById(id);
    if (stored == null) {
      throw StateError('crla_stories row $id vanished right after insert');
    }
    return stored;
  }

  @override
  Future<CrlaStory?> findById(int id) async {
    final rows = await db.query(
      'crla_stories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : CrlaStory.fromMap(rows.first);
  }

  @override
  Future<CrlaStory?> findByKey({
    required int regionId,
    required String language,
    required int grade,
    required int storyNo,
  }) async {
    final rows = await db.query(
      'crla_stories',
      where: 'region_id = ? AND language = ? AND grade = ? AND story_no = ?',
      whereArgs: [regionId, normalizeCrlaLanguage(language), grade, storyNo],
      limit: 1,
    );
    return rows.isEmpty ? null : CrlaStory.fromMap(rows.first);
  }

  @override
  Future<List<CrlaStory>> getByRegion(
    int regionId, {
    String? language,
    int? grade,
  }) async {
    final where = StringBuffer('region_id = ?');
    final args = <Object?>[regionId];
    if (language != null) {
      where.write(' AND language = ?');
      args.add(normalizeCrlaLanguage(language));
    }
    if (grade != null) {
      where.write(' AND grade = ?');
      args.add(grade);
    }
    final rows = await db.query(
      'crla_stories',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'language, grade, story_no',
    );
    return rows.map(CrlaStory.fromMap).toList();
  }

  @override
  Future<CrlaStory> upsertWithId(CrlaStory story) async {
    if (story.id == null) {
      throw ArgumentError('Cannot upsertWithId a CrlaStory with no id');
    }
    await db.insert(
      'crla_stories',
      story.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // INSERT OR REPLACE
    );
    return (await findById(story.id!))!;
  }
}