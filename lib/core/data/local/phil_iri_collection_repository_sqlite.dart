// lib/core/data/local/phil_iri_collection_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/phil_iri_collection.dart';
import '../../repositories/phil_iri_collection_repository.dart';

/// Read + mirror only: Phil-IRI content is managed online.
class PhilIriCollectionRepositorySqlite implements PhilIriCollectionRepository {
  final Database db;
  PhilIriCollectionRepositorySqlite(this.db);

  static Never _online() =>
      throw UnsupportedError('Phil-IRI collections are managed online; use the cloud repository');

  @override
  Future<PhilIriCollection> insert(PhilIriCollection collection) async => _online();
  @override
  Future<PhilIriCollection> update(PhilIriCollection collection) async => _online();
  @override
  Future<void> delete(int id) async => _online();
  @override
  Future<PhilIriRubricCriterion> insertCriterion(PhilIriRubricCriterion criterion) async => _online();
  @override
  Future<PhilIriRubricCriterion> updateCriterion(PhilIriRubricCriterion criterion) async => _online();
  @override
  Future<void> deleteCriterion(int id) async => _online();

  @override
  Future<PhilIriCollection?> findById(int id) async {
    final rows = await db.query('phil_iri_collections', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PhilIriCollection.fromMap(rows.first);
  }

  @override
  Future<List<PhilIriCollection>> getAll({bool activeOnly = false}) async {
    final rows = await db.query(
      'phil_iri_collections',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'school_id IS NOT NULL, school_id, name', // region-wide first, as the Supabase repo
    );
    return rows.map(PhilIriCollection.fromMap).toList();
  }

  @override
  Future<List<PhilIriRubricCriterion>> getCriteria(int collectionId) async {
    final rows = await db.query('phil_iri_rubric_criteria',
        where: 'collection_id = ?', whereArgs: [collectionId], orderBy: 'criterion_no');
    return rows.map(PhilIriRubricCriterion.fromMap).toList();
  }

  @override
  Future<PhilIriCollection> upsertWithId(PhilIriCollection collection) async {
    if (collection.id == null) throw ArgumentError('Cannot upsertWithId a PhilIriCollection with no id');
    await upsertById(db, 'phil_iri_collections', toSqliteRow(collection.toMap()));
    return (await findById(collection.id!))!;
  }

  @override
  Future<PhilIriRubricCriterion> upsertCriterionWithId(PhilIriRubricCriterion criterion) async {
    if (criterion.id == null) throw ArgumentError('Cannot upsertCriterionWithId a PhilIriRubricCriterion with no id');
    await upsertById(db, 'phil_iri_rubric_criteria', toSqliteRow(criterion.toMap()));
    final rows = await db.query('phil_iri_rubric_criteria', where: 'id = ?', whereArgs: [criterion.id]);
    return PhilIriRubricCriterion.fromMap(rows.first);
  }
}
