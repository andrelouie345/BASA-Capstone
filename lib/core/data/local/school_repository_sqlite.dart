// lib/core/data/local/school_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/school.dart';
import '../../repositories/school_repository.dart';

class SchoolRepositorySqlite implements SchoolRepository {
  final Database db;
  SchoolRepositorySqlite(this.db);

  @override
  Future<School> getOrCreate(School school) async {
    final existing = await db.query('schools', where: 'school_id = ?', whereArgs: [school.schoolId]);
    if (existing.isNotEmpty) return School.fromMap(existing.first);

    final id = await db.insert('schools', school.toMap());
    return School(id: id, schoolId: school.schoolId, schoolName: school.schoolName, region: school.region, division: school.division);
  }
}