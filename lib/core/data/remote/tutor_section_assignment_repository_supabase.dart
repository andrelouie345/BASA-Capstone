// lib/core/data/remote/tutor_section_assignment_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/tutor_section_assignment.dart';
import '../../repositories/tutor_section_assignment_repository.dart';

class TutorSectionAssignmentRepositorySupabase implements TutorSectionAssignmentRepository {
  final SupabaseClient client;
  TutorSectionAssignmentRepositorySupabase(this.client);

  static const _embed =
      '*, tutor:users!tutor_section_assignments_tutor_id_fkey(full_name, email), section:sections(*)';

  @override
  Future<TutorSectionAssignment> create(TutorSectionAssignment assignment) async {
    final inserted = await client
        .from('tutor_section_assignments')
        .insert(assignment.toMap())
        .select();
    return TutorSectionAssignment.fromMap((inserted as List).first as Map<String, Object?>);
  }

  @override
  Future<List<TutorSectionAssignment>> getByTutor(String tutorId) async {
    final rows = await client
        .from('tutor_section_assignments')
        .select(_embed)
        .eq('tutor_id', tutorId)
        .order('assigned_at');
    return (rows as List).map((r) => TutorSectionAssignment.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<List<TutorSectionAssignment>> getBySection(int sectionId) async {
    final rows = await client
        .from('tutor_section_assignments')
        .select(_embed)
        .eq('section_id', sectionId)
        .order('assigned_at');
    return (rows as List).map((r) => TutorSectionAssignment.fromMap(r as Map<String, Object?>)).toList();
  }

  @override
  Future<void> delete(int id) async {
    final rows = await client.from('tutor_section_assignments').delete().eq('id', id).select();
    if ((rows as List).isEmpty) {
      throw Exception('No assignment deleted — check the id or your permissions ("$id")');
    }
  }
}