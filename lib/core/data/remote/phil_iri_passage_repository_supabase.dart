// lib/core/data/remote/phil_iri_passage_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/phil_iri_passage.dart';
import '../../models/phil_iri_question.dart';
import '../../repositories/phil_iri_passage_repository.dart';

class PhilIriPassageRepositorySupabase implements PhilIriPassageRepository {
  final SupabaseClient client;
  PhilIriPassageRepositorySupabase(this.client);

  static PhilIriPassage _p(Object? r) => PhilIriPassage.fromMap(r as Map<String, Object?>);
  static PhilIriQuestion _q(Object? r) => PhilIriQuestion.fromMap(r as Map<String, Object?>);

  @override
  Future<PhilIriPassage> insert(PhilIriPassage passage) async {
    final payload = passage.toMap()..remove('created_by'); // stamped by the database
    final rows = await client.from('phil_iri_passages').insert(payload).select();
    return _p((rows as List).first);
  }

  @override
  Future<PhilIriPassage> update(PhilIriPassage passage) async {
    if (passage.id == null) throw ArgumentError('Cannot update a PhilIriPassage with no id');
    final payload = passage.toMap()
      ..remove('id')
      ..remove('created_by');
    final rows = await client.from('phil_iri_passages').update(payload).eq('id', passage.id!).select();
    if ((rows as List).isEmpty) {
      throw Exception('No passage updated — check the id or your permissions ("${passage.id}")');
    }
    return _p(rows.first);
  }

  @override
  Future<void> delete(int id) async {
    final rows = await client.from('phil_iri_passages').delete().eq('id', id).select();
    if ((rows as List).isEmpty) {
      throw Exception('No passage deleted — check the id or your permissions ("$id")');
    }
  }

  @override
  Future<PhilIriPassage?> findById(int id) async {
    final rows = await client.from('phil_iri_passages').select().eq('id', id);
    return (rows as List).isEmpty ? null : _p(rows.first);
  }

  @override
  Future<List<PhilIriPassage>> getByCollection(int collectionId, {bool activeOnly = false}) async {
    var query = client.from('phil_iri_passages').select().eq('collection_id', collectionId);
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query
        .order('level', ascending: true)
        .order('set_code', ascending: true)
        .order('selection_no', ascending: true)
        .order('id', ascending: true);
    return (rows as List).map(_p).toList();
  }

  @override
  Future<List<PhilIriPassage>> getForLevel(int level) async {
    // !inner keeps only passages whose collection matches the embedded filters.
    final rows = await client
        .from('phil_iri_passages')
        .select('*, phil_iri_collections!inner(is_grade_leveled, is_active)')
        .eq('level', level)
        .eq('is_active', true)
        .eq('phil_iri_collections.is_grade_leveled', true)
        .eq('phil_iri_collections.is_active', true)
        .order('collection_id', ascending: true)
        .order('set_code', ascending: true)
        .order('id', ascending: true);
    return (rows as List).map(_p).toList();
  }

  @override
  Future<PhilIriQuestion> insertQuestion(PhilIriQuestion question) async {
    final rows = await client.from('phil_iri_questions').insert(question.toMap()).select();
    return _q((rows as List).first);
  }

  @override
  Future<PhilIriQuestion> updateQuestion(PhilIriQuestion question) async {
    if (question.id == null) throw ArgumentError('Cannot update a PhilIriQuestion with no id');
    final payload = question.toMap()..remove('id');
    final rows = await client.from('phil_iri_questions').update(payload).eq('id', question.id!).select();
    if ((rows as List).isEmpty) {
      throw Exception('No question updated — check the id or your permissions ("${question.id}")');
    }
    return _q(rows.first);
  }

  @override
  Future<void> deleteQuestion(int id) async {
    final rows = await client.from('phil_iri_questions').delete().eq('id', id).select();
    if ((rows as List).isEmpty) {
      throw Exception('No question deleted — check the id or your permissions ("$id")');
    }
  }

  @override
  Future<List<PhilIriQuestion>> getQuestions(int passageId) async {
    final rows = await client
        .from('phil_iri_questions')
        .select()
        .eq('passage_id', passageId)
        .order('question_no', ascending: true);
    return (rows as List).map(_q).toList();
  }

  @override
  Future<PhilIriPassage> upsertWithId(PhilIriPassage passage) async {
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }

  @override
  Future<PhilIriQuestion> upsertQuestionWithId(PhilIriQuestion question) async {
    throw UnimplementedError('upsertQuestionWithId is a local-mirroring operation — not meaningful against Supabase');
  }
}
