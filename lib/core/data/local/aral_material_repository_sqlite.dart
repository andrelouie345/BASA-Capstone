// lib/core/data/local/aral_material_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/aral_material.dart';
import '../../repositories/aral_material_repository.dart';

/// Read + mirror only: the catalog is managed online by the superadmin and
/// school admins/coordinators.
class AralMaterialRepositorySqlite implements AralMaterialRepository {
  final Database db;
  AralMaterialRepositorySqlite(this.db);

  static Never _online() => throw UnsupportedError('ARAL materials are managed online; use the cloud repository');

  @override
  Future<AralMaterial> insert(AralMaterial material) async => _online();
  @override
  Future<AralMaterial> update(AralMaterial material) async => _online();
  @override
  Future<void> delete(int id) async => _online();

  @override
  Future<List<AralMaterial>> getAll({bool activeOnly = false}) async {
    final rows = await db.query('aral_materials',
        where: activeOnly ? 'is_active = 1' : null, orderBy: 'key_stage, title COLLATE NOCASE');
    return rows.map(AralMaterial.fromMap).toList();
  }

  @override
  Future<AralMaterial?> findById(int id) async {
    final rows = await db.query('aral_materials', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AralMaterial.fromMap(rows.first);
  }

  @override
  Future<AralMaterial> upsertWithId(AralMaterial material) async {
    if (material.id == null) throw ArgumentError('Cannot upsertWithId an AralMaterial with no id');
    await upsertById(db, 'aral_materials', toSqliteRow({
      ...material.toMap(),
      if (material.createdBy != null) 'created_by': material.createdBy,
      if (material.createdAt != null) 'created_at': material.createdAt,
      if (material.updatedAt != null) 'updated_at': material.updatedAt,
    }));
    return (await findById(material.id!))!;
  }

  @override
  Future<void> removeMirrored(int id) async {
    await db.delete('aral_materials', where: 'id = ?', whereArgs: [id]);
  }
}
