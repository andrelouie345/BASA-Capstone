// lib/core/repositories/crla_story_repository.dart
import '../models/crla_story.dart';

abstract class CrlaStoryRepository {
  /// Inserts a story and returns the stored row (with its id).
  /// Language is normalized by CrlaStory.toMap() ('Filipino' -> 'Tagalog').
  Future<CrlaStory> insert(CrlaStory story);

  Future<CrlaStory?> findById(int id);

  /// The one story matching the natural key
  /// UNIQUE(region_id, language, grade, story_no), or null.
  /// Pass the language as the assessment stores it (already 'Tagalog');
  /// implementations should still run it through normalizeCrlaLanguage
  /// so a raw 'Filipino' can't cause a silent miss.
  Future<CrlaStory?> findByKey({
    required int regionId,
    required String language,
    required int grade,
    required int storyNo,
  });

  /// Stories for a region, optionally narrowed by language and/or grade.
  /// Ordered by language, grade, story_no.
  Future<List<CrlaStory>> getByRegion(
    int regionId, {
    String? language,
    int? grade,
  });

  /// Local-mirroring only, keeps Supabase's id. Supabase impl throws UnimplementedError.
  Future<CrlaStory> upsertWithId(CrlaStory story);
}