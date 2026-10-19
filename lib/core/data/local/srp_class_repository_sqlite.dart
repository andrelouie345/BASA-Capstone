// lib/core/data/local/srp_class_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import '../../models/srp_class.dart';
import '../../repositories/srp_class_repository.dart';

/// Read + mirror only: SRP classes are managed online by admins/coordinators.
class SrpClassRepositorySqlite implements SrpClassRepository {
  final Database db;
  SrpClassRepositorySqlite(this.db);

  static Never _online() => throw UnsupportedError('SRP classes are managed online; use the cloud repository');

  @override
  Future<SrpClass> insertClass(SrpClass c) async => _online();
  @override
  Future<SrpClass> updateClass(SrpClass c) async => _online();
  @override
  Future<void> deleteClass(int id) async => _online();
  @override
  Future<SrpClassMember> insertMember(int classId, int studentId, String schoolYear) async => _online();
  @override
  Future<SrpClassMember> moveMember(int memberId, int toClassId) async => _online();
  @override
  Future<void> deleteMember(int memberId) async => _online();

  @override
  Future<List<SrpClass>> classesFor(int schoolId, String schoolYear) async {
    final rows = await db.query('srp_classes',
        where: 'school_id = ? AND school_year = ?',
        whereArgs: [schoolId, schoolYear],
        orderBy: 'assessed_grade, class_name COLLATE NOCASE');
    return rows.map(SrpClass.fromMap).toList();
  }

  @override
  Future<SrpClass?> findClass(int id) async {
    final rows = await db.query('srp_classes', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : SrpClass.fromMap(rows.first);
  }

  @override
  Future<List<SrpClass>> findClassesByName(String name) async {
    final rows = await db.query('srp_classes', where: 'lower(class_name) = lower(?)', whereArgs: [name.trim()]);
    return rows.map(SrpClass.fromMap).toList();
  }

  @override
  Future<List<SrpClassMember>> membersFor(int schoolId, String schoolYear) async {
    final rows = await db.rawQuery('''
      SELECT m.* FROM srp_class_members m
      JOIN srp_classes c ON c.id = m.class_id
      WHERE c.school_id = ? AND c.school_year = ?
    ''', [schoolId, schoolYear]);
    return rows.map(SrpClassMember.fromMap).toList();
  }

  @override
  Future<void> upsertClassWithId(SrpClass c) async {
    if (c.id == null) throw ArgumentError('Cannot upsertClassWithId an SrpClass with no id');
    await upsertById(db, 'srp_classes', {
      ...c.toMap(),
      'created_by': c.createdBy,
      'created_at': c.createdAt,
      'updated_at': c.updatedAt,
    });
  }

  @override
  Future<void> removeMirroredClass(int id) async {
    await db.delete('srp_class_members', where: 'class_id = ?', whereArgs: [id]);
    await db.delete('srp_classes', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> upsertMemberWithId(SrpClassMember m) async {
    if (m.id == null) throw ArgumentError('Cannot upsertMemberWithId an SrpClassMember with no id');
    await upsertById(db, 'srp_class_members', {...m.toMap(), 'created_at': m.createdAt});
  }

  @override
  Future<void> removeMirroredMember(int id) async {
    await db.delete('srp_class_members', where: 'id = ?', whereArgs: [id]);
  }
}
