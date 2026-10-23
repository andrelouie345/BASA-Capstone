// lib/core/data/remote/aral_class_repository_supabase.dart
//
// Same interface as the SQLite repository (the main write path); used online.
// The database stamps created_by, created_at and updated_at; client values
// for those are dropped.
import 'package:supabase/supabase.dart';
import '../../models/aral_class.dart';
import '../../repositories/aral_class_repository.dart';

class AralClassRepositorySupabase implements AralClassRepository {
  final SupabaseClient client;
  AralClassRepositorySupabase(this.client);

  static AralClass _c(Object? r) => AralClass.fromMap(r as Map<String, Object?>);

  static const _changeable = ['class_name', 'program', 'grade_band', 'tutor_id', 'room', 'schedule', 'notes'];

  @override
  Future<AralClass> insert(AralClass aralClass) async {
    final payload = aralClass.toMap()
      ..remove('id')
      ..remove('created_by')
      ..remove('created_at')
      ..remove('updated_at');
    final rows = await client.from('aral_classes').insert(payload).select();
    return _c((rows as List).first);
  }

  @override
  Future<AralClass> update(AralClass aralClass) async {
    if (aralClass.id == null) throw ArgumentError('update needs an AralClass id');
    final all = aralClass.toMap();
    final rows = await client
        .from('aral_classes')
        .update({for (final c in _changeable) c: all[c]})
        .eq('id', aralClass.id!)
        .select();
    if ((rows as List).isEmpty) {
      throw Exception('No ARAL class changed — check the id or your permissions');
    }
    return _c(rows.first);
  }

  @override
  Future<void> delete(int id) async {
    final rows = await client.from('aral_classes').delete().eq('id', id).select();
    if ((rows as List).isEmpty) {
      throw Exception('No ARAL class deleted — check the id or your permissions');
    }
  }

  @override
  Future<AralClass?> findById(int id) async {
    final rows = await client.from('aral_classes').select().eq('id', id);
    return (rows as List).isEmpty ? null : _c(rows.first);
  }

  Future<List<AralClass>> _where(String column, Object value, String? schoolYear) async {
    var q = client.from('aral_classes').select().eq(column, value);
    if (schoolYear != null) q = q.eq('school_year', schoolYear);
    final rows = await q.order('school_year').order('class_name');
    return (rows as List).map(_c).toList();
  }

  @override
  Future<List<AralClass>> getBySchool(int schoolId, {String? schoolYear}) =>
      _where('school_id', schoolId, schoolYear);

  @override
  Future<List<AralClass>> getByTutor(String tutorId, {String? schoolYear}) =>
      _where('tutor_id', tutorId, schoolYear);

  @override
  Future<AralClass> upsertWithId(AralClass aralClass) =>
      throw UnimplementedError('upsertWithId is for local mirroring only');
}
