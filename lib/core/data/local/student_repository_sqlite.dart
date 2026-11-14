// lib/core/data/local/student_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import '../../models/student.dart';
import '../../repositories/student_repository.dart';

class StudentRepositorySqlite implements StudentRepository {
  final Database db;
  StudentRepositorySqlite(this.db);

  @override
  Future<Student?> findByLrn(String lrn) async {
    final rows = await db.query('students', where: 'lrn = ?', whereArgs: [lrn]);
    return rows.isEmpty ? null : Student.fromMap(rows.first);
  }

  @override
  Future<Student> insert(Student student) async {
    try {
      final id = await db.insert('students', student.toMap());
      return Student.fromMap({...student.toMap(), 'id': id});
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw DuplicateLrnException(student.lrn);
      rethrow;
    }
  }

  @override
  Future<void> update(Student student) async {
    await db.update(
      'students',
      {...student.toMap(), 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [student.id],
    );
  }

  @override
  Future<List<Student>> getBySection(int sectionId) async {
    final rows = await db.rawQuery('''
      SELECT s.* FROM students s
      JOIN enrollments e ON e.student_id = s.id
      WHERE e.section_id = ? AND e.status = 'active'
      ORDER BY s.last_name, s.first_name
    ''', [sectionId]);
    return rows.map(Student.fromMap).toList();
  }

  @override
  Future<int?> activeSectionId(int studentId, String schoolYear) async {
    final rows = await db.query('enrollments',
        columns: ['section_id'],
        where: "student_id = ? AND school_year = ? AND status = 'active'",
        whereArgs: [studentId, schoolYear],
        limit: 1);
    return rows.isEmpty ? null : rows.first['section_id'] as int;
  }

  @override
  Future<EnrollmentInYear?> enrollmentInYear(int studentId, String schoolYear) async {
    final rows = await db.rawQuery('''
      SELECT e.id, e.section_id, e.status, e.left_on, sec.section_name, sec.grade_level, sec.school_id
      FROM enrollments e
      JOIN sections sec ON sec.id = e.section_id
      WHERE e.student_id = ? AND e.school_year = ?
      LIMIT 1
    ''', [studentId, schoolYear]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      enrollmentId: r['id'] as int,
      sectionId: r['section_id'] as int,
      sectionName: r['section_name'] as String,
      gradeLevel: r['grade_level'] as String,
      schoolId: r['school_id'] as int,
      status: r['status'] as String,
      leftOn: r['left_on'] as String?,
    );
  }

  @override
  Future<int> enroll({required int studentId, required int sectionId, required String schoolYear, int? id}) async {
    return db.insert(
      'enrollments',
      {
        'id': ?id,
        'student_id': studentId, 'section_id': sectionId, 'school_year': schoolYear, 'status': 'active',
      },
      conflictAlgorithm: ConflictAlgorithm.replace, // one row per student per school_year (see UNIQUE constraint)
    );
  }

  @override
  Future<Student> upsertWithId(Student student) async {
    if (student.id == null) throw ArgumentError('Cannot upsertWithId a Student with no id');
    await upsertById(db, 'students', student.toMap());
    return student;
  }

    @override
  Future<List<Student>> getAll(String sort) async {
    if (sort == 'lastname') {
      final rows = await db.query('students', orderBy: 'last_name COLLATE NOCASE, first_name COLLATE NOCASE');
      return rows.map(Student.fromMap).toList();
    } else if (sort == 'lrn') {
      final rows = await db.query('students', orderBy: 'lrn');
      return rows.map(Student.fromMap).toList();
    } else if (sort == 'id') {
      final rows = await db.query('students', orderBy: 'id');
      return rows.map(Student.fromMap).toList();
    } else {
      throw ArgumentError('Invalid sort option: $sort');
    }
  }
}
// MIght need to add a delete methode here or actually denote that they are finished from the program.