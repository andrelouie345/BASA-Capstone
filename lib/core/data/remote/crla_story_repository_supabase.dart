// lib/core/data/remote/crla_story_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/crla_language.dart';
import '../../models/crla_story.dart';
import '../../repositories/crla_story_repository.dart';

class CrlaStoryRepositorySupabase implements CrlaStoryRepository {
  final SupabaseClient client;
  CrlaStoryRepositorySupabase(this.client);

  @override
  Future<CrlaStory> insert(CrlaStory story) async {
    // toMap() normalizes language ('Filipino' -> 'Tagalog') and omits id when null.
    final inserted = await client.from('crla_stories').insert(story.toMap()).select();
    return CrlaStory.fromMap((inserted as List).first as Map<String, Object?>);
  }

  @override
  Future<CrlaStory?> findById(int id) async {
    final rows = await client.from('crla_stories').select().eq('id', id);
    return (rows as List).isEmpty ? null : CrlaStory.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<CrlaStory?> findByKey({
    required int regionId,
    required String language,
    required int grade,
    required int storyNo,
  }) async {
    final rows = await client
        .from('crla_stories')
        .select()
        .eq('region_id', regionId)
        .eq('language', normalizeCrlaLanguage(language))
        .eq('grade', grade)
        .eq('story_no', storyNo)
        .limit(1);
    return (rows as List).isEmpty ? null : CrlaStory.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<List<CrlaStory>> getByRegion(
    int regionId, {
    String? language,
    int? grade,
  }) async {
    var query = client.from('crla_stories').select().eq('region_id', regionId);
    if (language != null) {
      query = query.eq('language', normalizeCrlaLanguage(language));
    }
    if (grade != null) {
      query = query.eq('grade', grade);
    }
    final rows = await query
        .order('language', ascending: true)
        .order('grade', ascending: true)
        .order('story_no', ascending: true);
    return (rows as List).map((r) => CrlaStory.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<CrlaStory> upsertWithId(CrlaStory story) async {
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }
}