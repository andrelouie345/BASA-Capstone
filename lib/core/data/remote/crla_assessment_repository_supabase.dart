// lib/core/data/remote/crla_assessment_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/crla_assessment.dart';
import '../../repositories/crla_assessment_repository.dart';

class CrlaAssessmentRepositorySupabase implements CrlaAssessmentRepository {
  final SupabaseClient client;
  CrlaAssessmentRepositorySupabase(this.client);

  @override
  Future<CrlaAssessment> insert(CrlaAssessment assessment) async {
    // attempt_no is assigned by the set_crla_attempt_no trigger; toMap() omits it when null.
    // toMap() also normalizes language ('fil' -> 'Tagalog').
    final inserted = await client.from('crla_assessments').insert(assessment.toMap()).select();
    return CrlaAssessment.fromMap((inserted as List).first as Map<String, Object?>);
  }

  @override
  Future<CrlaAssessment?> findById(int id) async {
    final rows = await client.from('crla_assessments').select().eq('id', id);
    return (rows as List).isEmpty ? null : CrlaAssessment.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<List<CrlaAssessment>> getBySection(int sectionId, {String? schoolYear}) async {
    var query = client.from('crla_assessments').select().eq('section_id', sectionId);
    if (schoolYear != null) {
      query = query.eq('school_year', schoolYear);
    }
    final rows = await query
        .order('student_id', ascending: true)
        .order('subject_variant', ascending: true)
        .order('attempt_no', ascending: true);
    return (rows as List).map((r) => CrlaAssessment.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<List<CrlaAssessment>> getByStudent(int studentId) async {
    final rows = await client
        .from('crla_assessments')
        .select()
        .eq('student_id', studentId)
        .order('assessed_at', ascending: false)
        .order('attempt_no', ascending: false);
    return (rows as List).map((r) => CrlaAssessment.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<CrlaAssessment?> getLatestAttempt({
    required int studentId,
    required int sectionId,
    required String subjectVariant,
    required String schoolYear,
  }) async {
    final rows = await client
        .from('crla_assessments')
        .select()
        .eq('student_id', studentId)
        .eq('section_id', sectionId)
        .eq('subject_variant', subjectVariant)
        .eq('school_year', schoolYear)
        .order('attempt_no', ascending: false)
        .limit(1);
    return (rows as List).isEmpty ? null : CrlaAssessment.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<CrlaAssessment> upsertWithId(CrlaAssessment assessment) async {
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }

//   String _normalizeCrlaLanguage(String subjectVariant, String language) {
//   if (subjectVariant == 'fil') return 'Tagalog';
//   return language;
// }
}