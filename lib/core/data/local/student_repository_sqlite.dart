// lib/core/data/local/student_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
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
    final id = await db.insert('students', student.toMap());
    return Student.fromMap({...student.toMap(), 'id': id});
  }

  @override
  Future<void> update(Student student) async {
    await db.update(
      'students',
      {...student.toMap(), 'updated_at': DateTime.now().toIso8601String()},
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
  Future<void> enroll({required int studentId, required int sectionId, required String schoolYear}) async {
    await db.insert(
      'enrollments',
      {'student_id': studentId, 'section_id': sectionId, 'school_year': schoolYear, 'status': 'active'},
      conflictAlgorithm: ConflictAlgorithm.replace, // one row per student per school_year (see UNIQUE constraint)
    );
  }

  @override
  Future<Student> upsertWithId(Student student) async {
    if (student.id == null) throw ArgumentError('Cannot upsertWithId a Student with no id');
    await db.insert('students', student.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    return student;
  }

    @override
  Future<List<Student>> getAll() async {
    final rows = await db.query('students', orderBy: 'last_name COLLATE NOCASE, first_name COLLATE NOCASE');
    return rows.map(Student.fromMap).toList();
  }
}
// MIght need to add a delete methode here or actually denote that they are finished from the program.