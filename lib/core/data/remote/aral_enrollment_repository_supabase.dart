// lib/core/data/remote/aral_enrollment_repository_supabase.dart
//
// Same interface as the SQLite repository (the main write path today); used
// online and by the future sync. The database stamps created_by, created_at
// and updated_at, and a new row always starts active; client values for those
// are dropped.
import 'package:supabase/supabase.dart';
import '../../models/aral_enrollment.dart';
import '../../repositories/aral_enrollment_repository.dart';

class AralEnrollmentRepositorySupabase implements AralEnrollmentRepository {
  final SupabaseClient client;
  AralEnrollmentRepositorySupabase(this.client);

  static AralEnrollment _e(Object? r) => AralEnrollment.fromMap(r as Map<String, Object?>);

  static const _changeable = [
    'section_id', 'key_stage', 'track', 'class_id', 'status', 'entered_on', 'exited_on', 'exit_reason', 'notes',
    'suggested_key_stage', 'suggested_track', 'suggestion_round', 'suggestion_level', 'suggestion_assessment_id',
    'suggested_on',
  ];

  @override
  Future<AralEnrollment> insert(AralEnrollment enrollment) async {
    final payload = enrollment.toMap()
      ..remove('id')
      ..remove('created_by')
      ..remove('created_at')
      ..remove('updated_at');
    final rows = await client.from('aral_enrollments').insert(payload).select();
    return _e((rows as List).first);
  }

  @override
  Future<AralEnrollment> update(AralEnrollment enrollment) async {
    if (enrollment.id == null) throw ArgumentError('update needs an AralEnrollment id');
    final all = enrollment.toMap();
    final rows = await client
        .from('aral_enrollments')
        .update({for (final c in _changeable) c: all[c]})
        .eq('id', enrollment.id!)
        .select();
    if ((rows as List).isEmpty) {
      throw Exception('No ARAL enrollment changed — check the id or your permissions');
    }
    return _e(rows.first);
  }

  @override
  Future<void> delete(int id) async {
    final rows = await client.from('aral_enrollments').delete().eq('id', id).select();
    if ((rows as List).isEmpty) {
      throw Exception('No ARAL enrollment deleted — check the id or your permissions');
    }
  }

  @override
  Future<AralEnrollment?> findById(int id) async {
    final rows = await client.from('aral_enrollments').select().eq('id', id);
    return (rows as List).isEmpty ? null : _e(rows.first);
  }

  @override
  Future<AralEnrollment?> findForStudent(int studentId, String schoolYear) async {
    final rows =
        await client.from('aral_enrollments').select().eq('student_id', studentId).eq('school_year', schoolYear);
    return (rows as List).isEmpty ? null : _e(rows.first);
  }

  Future<List<AralEnrollment>> _where(String column, Object value, String? schoolYear) async {
    var q = client.from('aral_enrollments').select().eq(column, value);
    if (schoolYear != null) q = q.eq('school_year', schoolYear);
    final rows = await q.order('school_year').order('section_id').order('student_id');
    return (rows as List).map(_e).toList();
  }

  @override
  Future<List<AralEnrollment>> getBySection(int sectionId, {String? schoolYear}) =>
      _where('section_id', sectionId, schoolYear);

  @override
  Future<List<AralEnrollment>> getBySchool(int schoolId, {String? schoolYear}) =>
      _where('school_id', schoolId, schoolYear);

  @override
  Future<List<AralEnrollment>> getByTutor(String tutorId, {String? schoolYear}) async {
    final classes = await client.from('aral_classes').select('id').eq('tutor_id', tutorId);
    final ids = [for (final c in classes as List) (c as Map)['id'] as int];
    if (ids.isEmpty) return const [];
    var q = client.from('aral_enrollments').select().inFilter('class_id', ids);
    if (schoolYear != null) q = q.eq('school_year', schoolYear);
    final rows = await q.order('school_year').order('section_id').order('student_id');
    return (rows as List).map(_e).toList();
  }

  @override
  Future<List<AralEnrollment>> getByClass(int classId) => _where('class_id', classId, null);

  @override
  Future<String?> classTutorId(int enrollmentId) async {
    final rows = await client.from('aral_enrollments').select('class_id, aral_classes(tutor_id)').eq('id', enrollmentId);
    if ((rows as List).isEmpty) return null;
    final cls = (rows.first as Map)['aral_classes'] as Map?;
    return cls?['tutor_id'] as String?;
  }

  @override
  Future<AralEnrollment> upsertWithId(AralEnrollment enrollment) =>
      throw UnimplementedError('upsertWithId is for local mirroring only');
}
