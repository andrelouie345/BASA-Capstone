// lib/core/data/remote/import_conflict_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/import_conflict.dart';
import '../../repositories/import_conflict_repository.dart';

class ImportConflictRepositorySupabase implements ImportConflictRepository {
  final SupabaseClient client;
  ImportConflictRepositorySupabase(this.client);

  @override
  Future<void> log(ImportConflict conflict) async {
    await client.from('import_conflicts').insert({
      'lrn': conflict.lrn,
      'section_id': conflict.sectionId,
      'reason': conflict.reason,
      'incoming_data': conflict.incomingDataJson,
      'existing_student_id': conflict.existingStudentId,
      'status': conflict.status,
    });
  }

  @override
  Future<List<ImportConflict>> getPending() async {
    final rows = await client.from('import_conflicts').select().eq('status', 'pending').order('id');
    return (rows as List).map((r) => ImportConflict.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<ImportConflict?> getById(int id) async {
    final rows = await client.from('import_conflicts').select().eq('id', id);
    return (rows as List).isEmpty ? null : ImportConflict.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<void> resolve(int id, String status) async {
    await client.from('import_conflicts').update({'status': status}).eq('id', id);
  }

  
}