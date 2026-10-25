// lib/core/data/local/learner_history_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/aral_enrollment.dart';
import '../../models/srp_class.dart';
import '../../models/student.dart';
import '../../repositories/learner_history_repository.dart';

class LearnerHistoryRepositorySqlite implements LearnerHistoryRepository {
  final Database db;
  LearnerHistoryRepositorySqlite(this.db);

  @override
  Future<Student?> student(int id) async {
    final rows = await db.query('students', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Student.fromMap(rows.first);
  }

  @override
  Future<Student?> studentByLrn(String lrn) async {
    final rows = await db.query('students', where: 'lrn = ?', whereArgs: [lrn.trim()], limit: 1);
    return rows.isEmpty ? null : Student.fromMap(rows.first);
  }

  @override
  Future<List<LearnerSectionRow>> sectionEnrollments(int studentId) async {
    final rows = await db.rawQuery('''
      SELECT e.school_year, e.status, s.id AS section_id, s.section_name, s.grade_level,
             s.school_id, sc.school_name
      FROM enrollments e
      JOIN sections s ON s.id = e.section_id
      LEFT JOIN schools sc ON sc.id = s.school_id
      WHERE e.student_id = ?
      ORDER BY e.school_year DESC, s.section_name COLLATE NOCASE
    ''', [studentId]);
    return [
      for (final r in rows)
        LearnerSectionRow(
          schoolYear: r['school_year'] as String,
          status: r['status'] as String,
          sectionId: r['section_id'] as int,
          sectionName: r['section_name'] as String,
          gradeLevel: r['grade_level'] as String,
          schoolId: r['school_id'] as int,
          schoolName: r['school_name'] as String?,
        ),
    ];
  }

  @override
  Future<List<AralEnrollment>> aralEntries(int studentId) async {
    final rows = await db.query('aral_enrollments',
        where: 'student_id = ?', whereArgs: [studentId], orderBy: 'school_year DESC, entered_on, id');
    return rows.map(AralEnrollment.fromMap).toList();
  }

  @override
  Future<List<SrpClass>> srpClasses(int studentId) async {
    final rows = await db.rawQuery('''
      SELECT c.* FROM srp_class_members m
      JOIN srp_classes c ON c.id = m.class_id
      WHERE m.student_id = ?
      ORDER BY c.school_year DESC, c.class_name COLLATE NOCASE
    ''', [studentId]);
    return rows.map(SrpClass.fromMap).toList();
  }
}
