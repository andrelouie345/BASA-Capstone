// lib/core/repositories/phil_iri_collection_repository.dart
import '../models/phil_iri_collection.dart';

/// Material collections and their rubric criteria.
/// Content is managed online: the Supabase implementation writes (RLS decides
/// who may), the SQLite implementation only reads what pull-cloud or
/// upsertWithId mirrored, and its write methods throw UnsupportedError.
abstract class PhilIriCollectionRepository {
  /// Returns the stored row (id and created_by from the database).
  Future<PhilIriCollection> insert(PhilIriCollection collection);

  /// Throws when no row was updated (wrong id, or RLS refused it).
  Future<PhilIriCollection> update(PhilIriCollection collection);

  /// Throws when no row was deleted. The cloud refuses a collection that
  /// still has passages.
  Future<void> delete(int id);

  Future<PhilIriCollection?> findById(int id);

  /// Every collection the caller can see (cloud: region-wide + own school,
  /// all for the superadmin; local: what was pulled). Region-wide first,
  /// then by name.
  Future<List<PhilIriCollection>> getAll({bool activeOnly = false});

  Future<PhilIriRubricCriterion> insertCriterion(PhilIriRubricCriterion criterion);
  Future<PhilIriRubricCriterion> updateCriterion(PhilIriRubricCriterion criterion);
  Future<void> deleteCriterion(int id);

  /// Ordered by criterion_no.
  Future<List<PhilIriRubricCriterion>> getCriteria(int collectionId);

  /// Local-mirroring only, keeps Supabase's id. Supabase impl throws UnimplementedError.
  Future<PhilIriCollection> upsertWithId(PhilIriCollection collection);
  Future<PhilIriRubricCriterion> upsertCriterionWithId(PhilIriRubricCriterion criterion);
}
