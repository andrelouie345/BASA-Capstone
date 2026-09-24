// lib/core/data/remote/school_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/school.dart';
import '../../repositories/school_repository.dart';

class SchoolRepositorySupabase implements SchoolRepository {
  final SupabaseClient client;
  SchoolRepositorySupabase(this.client);

  @override
  Future<School> getOrCreate(School school) async {
    final existing = await client.from('schools').select().eq('school_id', school.schoolId);
    if ((existing as List).isNotEmpty) {
      return School.fromMap(existing.first as Map<String, Object?>);
    }

    final inserted = await client.from('schools').insert(school.toMap()).select();
    return School.fromMap((inserted as List).first as Map<String, Object?>);
  }

  @override
  Future<List<School>> getAll() async {
    final rows = await client.from('schools').select().order('school_name');
    return (rows as List).map((r) => School.fromMap(r as Map<String, Object?>)).toList();
  }

    @override
  Future<School> upsertWithId(School school) async {  // (School/Section/Student per class)
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }

    @override
  Future<School> update(School school) async {
    if (school.id == null) throw ArgumentError('Cannot update a School with no id');
    final payload = school.toMap()..remove('id');
    final rows = await client.from('schools').update(payload).eq('id', school.id!).select();
    if ((rows as List).isEmpty) {
      throw Exception('No school updated — check the id or your permissions ("${school.id}")');
    }
    return School.fromMap(rows.first as Map<String, Object?>);
  }
}