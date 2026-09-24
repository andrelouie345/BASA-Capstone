// lib/core/data/remote/user_repository_supabase.dart
import 'package:supabase/supabase.dart' hide User; 
import '../../models/user.dart';
import '../../repositories/user_repository.dart';

class UserRepositorySupabase implements UserRepository {
  final SupabaseClient client;
  UserRepositorySupabase(this.client);

  @override
  Future<void> create(User user) async {
    // Account creation is NOT a direct insert — it goes through a
    // server-side Edge Function that holds the service role key.
    // The function creates the Supabase Auth user AND the public.users
    // profile row internally; this client only ever uses the anon key.
    final response = await client.functions.invoke('create-user', body: {
      'email': user.email,
      'full_name': user.fullName,
      'school_id':user.schoolId,
      'role': user.role.name,
      'created_by': user.createdBy,
    });

    if (response.status != 200) {
      throw Exception('create-user failed (${response.status}): ${response.data}');
    }
  }

  @override
  Future<User?> getById(String id) async {
    final rows = await client.from('users').select().eq('id', id);
    return (rows as List).isEmpty ? null : User.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<User?> getByEmail(String email) async {
    final rows = await client.from('users').select().eq('email', email);
    return (rows as List).isEmpty ? null : User.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<List<User>> getAll() async {
    final rows = await client.from('users').select().order('full_name');
    return (rows as List).map((r) => User.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<void> setActive(String id, bool isActive) async {
    final rows = await client.from('users').update({'is_active': isActive}).eq('id', id).select();
    if ((rows as List).isEmpty) {
      throw Exception('No user updated — check the id or your permissions ("$id")');
    }
  }
}