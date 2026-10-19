// lib/core/data/remote/srp_class_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/srp_class.dart';
import '../../repositories/srp_class_repository.dart';

class SrpClassRepositorySupabase implements SrpClassRepository {
  final SupabaseClient client;
  SrpClassRepositorySupabase(this.client);

  static SrpClass _c(Object? r) => SrpClass.fromMap(r as Map<String, Object?>);
  static SrpClassMember _m(Object? r) => SrpClassMember.fromMap(r as Map<String, Object?>);

  @override
  Future<List<SrpClass>> classesFor(int schoolId, String schoolYear) async {
    final rows = await client
        .from('srp_classes')
        .select()
        .eq('school_id', schoolId)
        .eq('school_year', schoolYear)
        .order('assessed_grade')
        .order('class_name');
    return (rows as List).map(_c).toList();
  }

  @override
  Future<SrpClass?> findClass(int id) async {
    final rows = await client.from('srp_classes').select().eq('id', id);
    return (rows as List).isEmpty ? null : _c(rows.first);
  }

  @override
  Future<List<SrpClass>> findClassesByName(String name) async {
    final rows = await client.from('srp_classes').select().ilike('class_name', name.trim());
    return (rows as List).map(_c).toList();
  }

  @override
  Future<List<SrpClassMember>> membersFor(int schoolId, String schoolYear) async {
    final classes = await classesFor(schoolId, schoolYear);
    if (classes.isEmpty) return [];
    final rows = await client.from('srp_class_members').select().inFilter('class_id', [for (final c in classes) c.id]);
    return (rows as List).map(_m).toList();
  }

  @override
  Future<SrpClass> insertClass(SrpClass c) async {
    final row = Map.of(c.toMap())..remove('id');
    final rows = await client.from('srp_classes').insert(row).select();
    return _c((rows as List).first);
  }

  @override
  Future<SrpClass> updateClass(SrpClass c) async {
    if (c.id == null) throw ArgumentError('updateClass needs a class id');
    final rows = await client
        .from('srp_classes')
        .update({'class_name': c.className, 'room': c.room, 'schedule': c.schedule, 'tutor_id': c.tutorId})
        .eq('id', c.id!)
        .select();
    if ((rows as List).isEmpty) throw Exception('SRP class not saved — check your permissions (${c.id})');
    return _c(rows.first);
  }

  @override
  Future<void> deleteClass(int id) async {
    final rows = await client.from('srp_classes').delete().eq('id', id).select();
    if ((rows as List).isEmpty) throw Exception('No SRP class deleted — it does not exist or check your permissions ($id)');
  }

  @override
  Future<SrpClassMember> insertMember(int classId, int studentId, String schoolYear) async {
    final rows = await client
        .from('srp_class_members')
        .insert({'class_id': classId, 'student_id': studentId, 'school_year': schoolYear})
        .select();
    return _m((rows as List).first);
  }

  @override
  Future<SrpClassMember> moveMember(int memberId, int toClassId) async {
    final rows = await client.from('srp_class_members').update({'class_id': toClassId}).eq('id', memberId).select();
    if ((rows as List).isEmpty) throw Exception('Learner not moved — check your permissions ($memberId)');
    return _m(rows.first);
  }

  @override
  Future<void> deleteMember(int memberId) async {
    final rows = await client.from('srp_class_members').delete().eq('id', memberId).select();
    if ((rows as List).isEmpty) throw Exception('No SRP learner removed — check your permissions ($memberId)');
  }

  @override
  Future<void> upsertClassWithId(SrpClass c) =>
      throw UnimplementedError('upsertClassWithId is a local-mirroring operation — not meaningful against Supabase');

  @override
  Future<void> removeMirroredClass(int id) =>
      throw UnimplementedError('removeMirroredClass is a local-mirroring operation — use deleteClass against Supabase');

  @override
  Future<void> upsertMemberWithId(SrpClassMember m) =>
      throw UnimplementedError('upsertMemberWithId is a local-mirroring operation — not meaningful against Supabase');

  @override
  Future<void> removeMirroredMember(int id) =>
      throw UnimplementedError('removeMirroredMember is a local-mirroring operation — use deleteMember against Supabase');
}
