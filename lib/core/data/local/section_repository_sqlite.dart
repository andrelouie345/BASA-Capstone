// lib/core/data/local/section_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/section.dart';
import '../../repositories/section_repository.dart';

class SectionRepositorySqlite implements SectionRepository {
  final Database db;
  SectionRepositorySqlite(this.db);

  @override
  Future<Section> getOrCreate(Section section) async {
    final existing = await db.query(
      'sections',
      where: 'school_id = ? AND school_year = ? AND grade_level = ? AND section_name = ?',
      whereArgs: [section.schoolId, section.schoolYear, section.gradeLevel, section.sectionName],
    );
    if (existing.isNotEmpty) return Section.fromMap(existing.first);

    final id = await db.insert('sections', section.toMap());
    return Section(
      id: id,
      schoolId: section.schoolId,
      schoolYear: section.schoolYear,
      gradeLevel: section.gradeLevel,
      sectionName: section.sectionName,
    );
  }

  @override
  Future<List<Section>> getAll() async {
    final rows = await db.query('sections', orderBy: 'grade_level, section_name');
    return rows.map(Section.fromMap).toList();
  }

  @override
  Future<Section?> getById(int id) async {
    final rows = await db.query('sections', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Section.fromMap(rows.first);
  }
}