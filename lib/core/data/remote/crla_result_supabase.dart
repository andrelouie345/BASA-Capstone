// lib/core/data/remote/crla_result_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/crla_result.dart';
import '../../repositories/crla_result_repository.dart';

class CrlaResultRepositorySupabase implements CrlaResultRepository {
  final SupabaseClient client;
  CrlaResultRepositorySupabase(this.client);

  @override
  Future<CrlaResult?> findByAssessmentId(int assessmentId) async {
    final rows = await client.from('crla_results').select().eq('assessment_id', assessmentId);
    return (rows as List).isEmpty ? null : CrlaResult.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<List<CrlaResult>> getBySection(int sectionId, {String? schoolYear}) async {
    var query = client.from('crla_results').select().eq('section_id', sectionId);
    if (schoolYear != null) {
      query = query.eq('school_year', schoolYear);
    }
    final rows = await query
        .order('student_id', ascending: true)
        .order('subject_variant', ascending: true)
        .order('attempt_no', ascending: true);
    return (rows as List).map((r) => CrlaResult.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<List<CrlaResult>> getByStudent(int studentId) async {
    final rows = await client
        .from('crla_results')
        .select()
        .eq('student_id', studentId)
        .order('assessed_at', ascending: false)
        .order('attempt_no', ascending: false);
    return (rows as List).map((r) => CrlaResult.fromMap(r as Map<String, Object?>)).toList();
  }
}