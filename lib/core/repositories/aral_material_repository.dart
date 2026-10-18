// lib/core/repositories/aral_material_repository.dart
import '../models/aral_material.dart';

/// The ARAL material catalog. Written online (Supabase); the SQLite
/// implementation reads and mirrors only. RLS limits what the signed-in user
/// sees: region-wide rows and their own school's.
abstract class AralMaterialRepository {
  Future<List<AralMaterial>> getAll({bool activeOnly = false});

  Future<AralMaterial?> findById(int id);

  /// Creates a material (cloud); returns it with its id and stamps.
  Future<AralMaterial> insert(AralMaterial material);

  /// Saves the editable fields of [material] (cloud).
  Future<AralMaterial> update(AralMaterial material);

  /// Deletes a material (cloud). Throws when nothing was deleted.
  Future<void> delete(int id);

  /// Local-mirroring only, keeps Supabase's id. Supabase impl throws UnimplementedError.
  Future<AralMaterial> upsertWithId(AralMaterial material);

  /// Local-mirroring only: drops the local copy. Supabase impl throws UnimplementedError.
  Future<void> removeMirrored(int id);

  // ---- A school's own links (aral_material_links) ----

  /// [schoolId]'s own links.
  Future<List<AralMaterialLink>> linksForSchool(int schoolId);

  /// Creates or replaces [schoolId]'s link for the material (cloud).
  Future<AralMaterialLink> saveLink(int materialId, int schoolId, String link);

  /// Removes [schoolId]'s link (cloud). Throws when nothing was deleted.
  Future<void> deleteLink(int materialId, int schoolId);

  /// Local-mirroring only. Supabase impl throws UnimplementedError.
  Future<AralMaterialLink> upsertLinkWithId(AralMaterialLink link);

  /// Local-mirroring only. Supabase impl throws UnimplementedError.
  Future<void> removeMirroredLink(int materialId, int schoolId);
}
