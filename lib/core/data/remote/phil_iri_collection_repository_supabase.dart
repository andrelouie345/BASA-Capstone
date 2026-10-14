// lib/core/data/remote/phil_iri_collection_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/phil_iri_collection.dart';
import '../../repositories/phil_iri_collection_repository.dart';

class PhilIriCollectionRepositorySupabase implements PhilIriCollectionRepository {
  final SupabaseClient client;
  PhilIriCollectionRepositorySupabase(this.client);

  static PhilIriCollection _c(Object? r) => PhilIriCollection.fromMap(r as Map<String, Object?>);
  static PhilIriRubricCriterion _k(Object? r) => PhilIriRubricCriterion.fromMap(r as Map<String, Object?>);

  @override
  Future<PhilIriCollection> insert(PhilIriCollection collection) async {
    // created_by is stamped by the database.
    final payload = collection.toMap()..remove('created_by');
    final rows = await client.from('phil_iri_collections').insert(payload).select();
    return _c((rows as List).first);
  }

  @override
  Future<PhilIriCollection> update(PhilIriCollection collection) async {
    if (collection.id == null) throw ArgumentError('Cannot update a PhilIriCollection with no id');
    final payload = collection.toMap()
      ..remove('id')
      ..remove('created_by');
    final rows = await client.from('phil_iri_collections').update(payload).eq('id', collection.id!).select();
    if ((rows as List).isEmpty) {
      throw Exception('No collection updated — check the id or your permissions ("${collection.id}")');
    }
    return _c(rows.first);
  }

  @override
  Future<void> delete(int id) async {
    final rows = await client.from('phil_iri_collections').delete().eq('id', id).select();
    if ((rows as List).isEmpty) {
      throw Exception('No collection deleted — check the id or your permissions ("$id")');
    }
  }

  @override
  Future<PhilIriCollection?> findById(int id) async {
    final rows = await client.from('phil_iri_collections').select().eq('id', id);
    return (rows as List).isEmpty ? null : _c(rows.first);
  }

  @override
  Future<List<PhilIriCollection>> getAll({bool activeOnly = false}) async {
    var query = client.from('phil_iri_collections').select();
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query
        .order('school_id', ascending: true, nullsFirst: true)
        .order('name', ascending: true);
    return (rows as List).map(_c).toList();
  }

  @override
  Future<PhilIriRubricCriterion> insertCriterion(PhilIriRubricCriterion criterion) async {
    final rows = await client.from('phil_iri_rubric_criteria').insert(criterion.toMap()).select();
    return _k((rows as List).first);
  }

  @override
  Future<PhilIriRubricCriterion> updateCriterion(PhilIriRubricCriterion criterion) async {
    if (criterion.id == null) throw ArgumentError('Cannot update a PhilIriRubricCriterion with no id');
    final payload = criterion.toMap()..remove('id');
    final rows = await client.from('phil_iri_rubric_criteria').update(payload).eq('id', criterion.id!).select();
    if ((rows as List).isEmpty) {
      throw Exception('No rubric criterion updated — check the id or your permissions ("${criterion.id}")');
    }
    return _k(rows.first);
  }

  @override
  Future<void> deleteCriterion(int id) async {
    final rows = await client.from('phil_iri_rubric_criteria').delete().eq('id', id).select();
    if ((rows as List).isEmpty) {
      throw Exception('No rubric criterion deleted — check the id or your permissions ("$id")');
    }
  }

  @override
  Future<List<PhilIriRubricCriterion>> getCriteria(int collectionId) async {
    final rows = await client
        .from('phil_iri_rubric_criteria')
        .select()
        .eq('collection_id', collectionId)
        .order('criterion_no', ascending: true);
    return (rows as List).map(_k).toList();
  }

  @override
  Future<PhilIriCollection> upsertWithId(PhilIriCollection collection) async {
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }

  @override
  Future<PhilIriRubricCriterion> upsertCriterionWithId(PhilIriRubricCriterion criterion) async {
    throw UnimplementedError('upsertCriterionWithId is a local-mirroring operation — not meaningful against Supabase');
  }

  @override
  Future<void> removeMirrored(int id) async {
    throw UnimplementedError('removeMirrored is a local-mirroring operation — use delete against Supabase');
  }

  @override
  Future<void> removeMirroredCriterion(int id) async {
    throw UnimplementedError('removeMirroredCriterion is a local-mirroring operation — use deleteCriterion against Supabase');
  }
}
