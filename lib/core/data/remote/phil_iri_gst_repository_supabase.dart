// lib/core/data/remote/phil_iri_gst_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/phil_iri_gst_result.dart';
import '../../repositories/phil_iri_gst_repository.dart';

class PhilIriGstRepositorySupabase implements PhilIriGstRepository {
  final SupabaseClient client;
  PhilIriGstRepositorySupabase(this.client);

  static PhilIriGstResult _g(Object? r) => PhilIriGstResult.fromMap(r as Map<String, Object?>);

  @override
  Future<PhilIriGstResult> insert(PhilIriGstResult result) async {
    // attempt_no and administered_by are assigned by phil_iri_gst_results_before_insert.
    final payload = result.toMap()
      ..remove('attempt_no')
      ..remove('administered_by');
    final rows = await client.from('phil_iri_gst_results').insert(payload).select();
    return _g((rows as List).first);
  }

  @override
  Future<PhilIriGstResult?> findById(int id) async {
    final rows = await client.from('phil_iri_gst_results').select().eq('id', id);
    return (rows as List).isEmpty ? null : _g(rows.first);
  }

  @override
  Future<List<PhilIriGstResult>> getBySection(int sectionId, {String? schoolYear}) async {
    var query = client.from('phil_iri_gst_results').select().eq('section_id', sectionId);
    if (schoolYear != null) query = query.eq('school_year', schoolYear);
    final rows = await query.order('student_id', ascending: true).order('attempt_no', ascending: true);
    return (rows as List).map(_g).toList();
  }

  @override
  Future<List<PhilIriGstResult>> getByStudent(int studentId, {String? schoolYear}) async {
    var query = client.from('phil_iri_gst_results').select().eq('student_id', studentId);
    if (schoolYear != null) query = query.eq('school_year', schoolYear);
    final rows = await query.order('taken_at', ascending: false).order('id', ascending: false);
    return (rows as List).map(_g).toList();
  }

  @override
  Future<PhilIriGstResult?> getLatest({required int studentId, required String schoolYear}) async {
    final rows = await getByStudent(studentId, schoolYear: schoolYear);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<PhilIriGstResult> upsertWithId(PhilIriGstResult result) async {
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }
}
