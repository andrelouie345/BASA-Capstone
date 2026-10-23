// lib/core/repositories/phil_iri_passage_repository.dart
import '../models/phil_iri_passage.dart';
import '../models/phil_iri_question.dart';

/// Passages and their comprehension questions. Managed online like
/// collections: the SQLite implementation reads and mirrors only.
abstract class PhilIriPassageRepository {
  /// Returns the stored row. The cloud refuses a level in a non-graded
  /// collection and a missing level in a graded one.
  Future<PhilIriPassage> insert(PhilIriPassage passage);

  /// Throws when no row was updated. Once a passage has been read, the cloud
  /// locks its body, word count, level and collection.
  Future<PhilIriPassage> update(PhilIriPassage passage);

  /// Throws when no row was deleted (a passage that was read cannot be).
  Future<void> delete(int id);

  Future<PhilIriPassage?> findById(int id);

  /// Ordered by level, set_code, selection_no, id.
  Future<List<PhilIriPassage>> getByCollection(int collectionId, {bool activeOnly = false});

  /// Active passages of [level] in active, grade-leveled collections the
  /// caller can see: the choices for a learner of that grade.
  Future<List<PhilIriPassage>> getForLevel(int level);

  Future<PhilIriQuestion> insertQuestion(PhilIriQuestion question);
  Future<PhilIriQuestion> updateQuestion(PhilIriQuestion question);
  Future<void> deleteQuestion(int id);

  /// Ordered by question_no.
  Future<List<PhilIriQuestion>> getQuestions(int passageId);

  /// Local-mirroring only, keeps Supabase's id. Supabase impl throws UnimplementedError.
  Future<PhilIriPassage> upsertWithId(PhilIriPassage passage);
  Future<PhilIriQuestion> upsertQuestionWithId(PhilIriQuestion question);

  /// Local-mirroring only: drops the local copy of a passage (and its
  /// questions) or of one question. No-op when there is none. Throws
  /// StateError while unsent readings / answers on this device use it
  /// (sync first), [UsedOnServerError] when only rows already on the server
  /// do. Supabase impl throws UnimplementedError.
  Future<void> removeMirrored(int id);
  Future<void> removeMirroredQuestion(int id);
}

/// Only rows that are already on the server use the record, so the cloud
/// refuses the delete too: syncing won't help.
class UsedOnServerError extends StateError {
  UsedOnServerError(super.message);
}
