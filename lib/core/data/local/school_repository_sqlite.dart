// lib/core/data/local/school_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import '../../models/school.dart';
import '../../repositories/school_repository.dart';

class SchoolRepositorySqlite implements SchoolRepository {
  final Database db;
  SchoolRepositorySqlite(this.db);

  @override
  Future<School> getOrCreate(School school) async {
    final existing = await getByCode(school.schoolId);
    if (existing != null) return existing;

    final id = await db.insert('schools', school.toMap());
    return School(id: id, schoolId: school.schoolId, schoolName: school.schoolName, regionId: school.regionId, division: school.division);
  }

  @override
  Future<School?> getById(int id) async {
    final rows = await db.query('schools', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : School.fromMap(rows.first);
  }

  @override
  Future<School?> getByCode(String schoolCode) async {
    final rows = await db.query('schools', where: 'school_id = ?', whereArgs: [schoolCode]);
    return rows.isEmpty ? null : School.fromMap(rows.first);
  }

  @override
  Future<List<School>> getAll() async {
    final rows = await db.query('schools', orderBy: 'school_name COLLATE NOCASE');
    return rows.map(School.fromMap).toList();
  }

    @override
  Future<School> upsertWithId(School school) async {
    if (school.id == null) throw ArgumentError('Cannot upsertWithId a School with no id');
    await upsertById(db, 'schools', school.toMap());
    return school;
  }

    @override
  Future<School> update(School school) async {
    if (school.id == null) throw ArgumentError('Cannot update a School with no id');
    final payload = school.toMap()..remove('id');
    await db.update('schools', payload, where: 'id = ?', whereArgs: [school.id]);
    return school;
  }

  @override
  Future<void> delete(int id) async {
    await db.delete('schools', where: 'id = ?', whereArgs: [id]);
  }
}