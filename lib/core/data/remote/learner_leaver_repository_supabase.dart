// lib/core/data/remote/learner_leaver_repository_supabase.dart
// Admin build only. The SF1 leaver functions of migrations 20261112010000 /
// 20261112020000, called with the signed-in client (RLS and the functions'
// own caller checks decide).
import 'package:supabase/supabase.dart';

import '../../repositories/learner_leaver_repository.dart';

class LearnerLeaverRepositorySupabase implements LearnerLeaverRepository {
  final SupabaseClient _client;
  LearnerLeaverRepositorySupabase(this._client);

  Future<Map<String, dynamic>> _call(String fn, Map<String, dynamic> params) async =>
      Map<String, dynamic>.from(await _client.rpc(fn, params: params) as Map);

  Future<List<Map<String, dynamic>>> _rows(String fn, Map<String, dynamic> params) async => [
        for (final r in (await _client.rpc(fn, params: params) as List? ?? const []))
          Map<String, dynamic>.from(r as Map),
      ];

  @override
  Future<Map<String, dynamic>> archive(int enrollmentId, String reason, String? note) =>
      _call('sf1_archive_learner', {'p_enrollment_id': enrollmentId, 'p_reason': reason, 'p_note': note});

  @override
  Future<Map<String, dynamic>> move(int enrollmentId, int toSectionId, String source) => _call(
      'sf1_move_learner', {'p_enrollment_id': enrollmentId, 'p_to_section_id': toSectionId, 'p_source': source});

  @override
  Future<Map<String, dynamic>> restore(int enrollmentId, int? toSectionId) =>
      _call('sf1_restore_learner', {'p_enrollment_id': enrollmentId, 'p_to_section_id': toSectionId});

  @override
  Future<Map<String, dynamic>> anonymize(int studentId) =>
      _call('learner_anonymize', {'p_student_id': studentId});

  @override
  Future<List<Map<String, dynamic>>> anonymizeEligible(int schoolId) =>
      _rows('learner_anonymize_eligible', {'p_school_id': schoolId});

  @override
  Future<List<Map<String, dynamic>>> missing(int schoolId, {int? sectionId}) =>
      _rows('sf1_missing', {'p_school_id': schoolId, 'p_section_id': sectionId});

  @override
  Future<void> saveLastImport(int sectionId, int schoolId, String schoolYear, List<String> lrns) async {
    await _client.from('sf1_last_imports').upsert(
      {'section_id': sectionId, 'school_id': schoolId, 'school_year': schoolYear, 'lrns': lrns},
      onConflict: 'section_id',
    );
  }
}
