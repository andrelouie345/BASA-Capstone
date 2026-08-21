// lib/core/data/remote/test_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/test_item.dart';
import '../../repositories/test_repository.dart';

class TestRepositorySupabase implements TestRepository {
  final SupabaseClient client;
  TestRepositorySupabase(this.client);

  @override
  Future<List<TestItem>> getAll() async {
    final rows = await client.from('testTable').select().order('id');
    return (rows as List).map((r) => TestItem.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<TestItem> add(String name) async {
    final row = await client.from('testTable').insert({'name': name}).select().single();
    return TestItem.fromMap(row);
  }

  @override
  Future<void> delete(int id) async {
    await client.from('testTable').delete().eq('id', id);
  }
}