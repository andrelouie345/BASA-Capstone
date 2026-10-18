// lib/core/data/remote/aral_material_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/aral_material.dart';
import '../../repositories/aral_material_repository.dart';

class AralMaterialRepositorySupabase implements AralMaterialRepository {
  final SupabaseClient client;
  AralMaterialRepositorySupabase(this.client);

  static AralMaterial _m(Object? r) => AralMaterial.fromMap(r as Map<String, Object?>);

  @override
  Future<List<AralMaterial>> getAll({bool activeOnly = false}) async {
    var q = client.from('aral_materials').select();
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('key_stage').order('title');
    return (rows as List).map(_m).toList();
  }

  @override
  Future<AralMaterial?> findById(int id) async {
    final rows = await client.from('aral_materials').select().eq('id', id);
    return (rows as List).isEmpty ? null : _m(rows.first);
  }

  @override
  Future<AralMaterial> insert(AralMaterial material) async {
    final row = Map.of(material.toMap())..remove('id');
    final rows = await client.from('aral_materials').insert(row).select();
    return _m((rows as List).first);
  }

  @override
  Future<AralMaterial> update(AralMaterial material) async {
    if (material.id == null) throw ArgumentError('update needs a material id');
    final row = Map.of(material.toMap())
      ..remove('id')
      ..remove('school_id'); // a material keeps its owner
    final rows = await client.from('aral_materials').update(row).eq('id', material.id!).select();
    if ((rows as List).isEmpty) throw Exception('Material not saved — check your permissions (${material.id})');
    return _m(rows.first);
  }

  @override
  Future<void> delete(int id) async {
    final rows = await client.from('aral_materials').delete().eq('id', id).select();
    if ((rows as List).isEmpty) throw Exception('No material deleted — it does not exist or check your permissions ($id)');
  }

  @override
  Future<AralMaterial> upsertWithId(AralMaterial material) =>
      throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');

  @override
  Future<void> removeMirrored(int id) =>
      throw UnimplementedError('removeMirrored is a local-mirroring operation — use delete against Supabase');

  static AralMaterialLink _l(Object? r) => AralMaterialLink.fromMap(r as Map<String, Object?>);

  @override
  Future<List<AralMaterialLink>> linksForSchool(int schoolId) async {
    final rows = await client.from('aral_material_links').select().eq('school_id', schoolId);
    return (rows as List).map(_l).toList();
  }

  @override
  Future<AralMaterialLink> saveLink(int materialId, int schoolId, String link) async {
    final existing =
        await client.from('aral_material_links').select().eq('material_id', materialId).eq('school_id', schoolId);
    if ((existing as List).isEmpty) {
      final rows = await client
          .from('aral_material_links')
          .insert({'material_id': materialId, 'school_id': schoolId, 'link': link}).select();
      return _l((rows as List).first);
    }
    final rows = await client
        .from('aral_material_links')
        .update({'link': link})
        .eq('material_id', materialId)
        .eq('school_id', schoolId)
        .select();
    if ((rows as List).isEmpty) throw Exception('Link not saved — check your permissions');
    return _l(rows.first);
  }

  @override
  Future<void> deleteLink(int materialId, int schoolId) async {
    final rows = await client
        .from('aral_material_links')
        .delete()
        .eq('material_id', materialId)
        .eq('school_id', schoolId)
        .select();
    if ((rows as List).isEmpty) throw Exception('No link deleted — the school has none for that material');
  }

  @override
  Future<AralMaterialLink> upsertLinkWithId(AralMaterialLink link) =>
      throw UnimplementedError('upsertLinkWithId is a local-mirroring operation — not meaningful against Supabase');

  @override
  Future<void> removeMirroredLink(int materialId, int schoolId) =>
      throw UnimplementedError('removeMirroredLink is a local-mirroring operation — use deleteLink against Supabase');
}
