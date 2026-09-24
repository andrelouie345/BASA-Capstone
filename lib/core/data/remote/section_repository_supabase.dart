// lib/core/data/remote/section_repository_supabase.dart
import 'package:basa_capstone/core/models/school.dart';
import 'package:supabase/supabase.dart';
import '../../models/section.dart';
import '../../repositories/section_repository.dart';

class SectionRepositorySupabase implements SectionRepository {
  final SupabaseClient client;
  SectionRepositorySupabase(this.client);

  @override
  Future<Section> getOrCreate(Section section) async {
    final existing = await client
        .from('sections')
        .select()
        .eq('school_id', section.schoolId)
        .eq('school_year', section.schoolYear)
        .eq('grade_level', section.gradeLevel)
        .eq('section_name', section.sectionName);
    if ((existing as List).isNotEmpty) {
      return Section.fromMap(existing.first as Map<String, Object?>);
    }

    final inserted = await client.from('sections').insert(section.toMap()).select();
    return Section.fromMap((inserted as List).first as Map<String, Object?>);
  }

  @override
  Future<List<Section>> getAll() async {
    final rows = await client.from('sections').select().order('grade_level').order('section_name');
    return (rows as List).map((r) => Section.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<Section?> getById(int id) async {
    final rows = await client.from('sections').select().eq('id', id);
    return (rows as List).isEmpty ? null : Section.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<Section> update(Section section) async {
    if (section.id == null) throw ArgumentError('Cannot update a Section with no id');
    final payload = section.toMap()..remove('id');
    final rows = await client.from('sections').update(payload).eq('id', section.id!).select();
    if ((rows as List).isEmpty) {
      throw Exception('No section updated — check the id or your permissions ("${section.id}")');
    }
    return Section.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<void> delete(int id) async {
    final rows = await client.from('sections').delete().eq('id', id).select();
    if ((rows as List).isEmpty) {
      throw Exception('No section deleted — check the id or your permissions ("$id")');
    }
  }

  @override
  Future<Section> upsertWithId(Section section) async {  // (School/Section/Student per class)
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }
}