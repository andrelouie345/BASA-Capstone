// lib/core/data/remote/student_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/student.dart';
import '../../repositories/student_repository.dart';

class StudentRepositorySupabase implements StudentRepository {
  final SupabaseClient client;
  StudentRepositorySupabase(this.client);

  @override
  Future<Student?> findByLrn(String lrn) async {
    final rows = await client.from('students').select().eq('lrn', lrn);
    return (rows as List).isEmpty ? null : Student.fromMap(rows.first as Map<String, Object?>);
  }

  @override
  Future<Student> insert(Student student) async {
    final inserted = await client.from('students').insert(student.toMap()).select();
    return Student.fromMap((inserted as List).first as Map<String, Object?>);
  }

  @override
  Future<void> update(Student student) async {
    if (student.id == null) throw ArgumentError('Cannot update a Student with no id');
    final payload = student.toMap()..remove('id');
    final rows = await client.from('students').update(payload).eq('id', student.id!).select();
    if ((rows as List).isEmpty) {
      throw Exception('No student updated — check the id or your permissions ("${student.id}")');
    }
  }

  @override
  Future<List<Student>> getBySection(int sectionId) async {
    final rows = await client
        .from('enrollments')
        .select('student:students(*)')
        .eq('section_id', sectionId)
        .eq('status', 'active');
    return (rows as List)
        .map((r) => Student.fromMap((r as Map<String, Object?>)['student'] as Map<String, Object?>))
        .toList()
      ..sort((a, b) {
        final byLast = a.lastName.compareTo(b.lastName);
        return byLast != 0 ? byLast : a.firstName.compareTo(b.firstName);
      });
  }

  @override
  Future<void> enroll({required int studentId, required int sectionId, required String schoolYear}) async {
    await client.from('enrollments').upsert(
      {'student_id': studentId, 'section_id': sectionId, 'school_year': schoolYear, 'status': 'active'},
      onConflict: 'student_id,school_year',
    );
  }

    @override
  Future<Student> upsertWithId(Student student) async {  // (School/Section/Student per class)
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }

    @override
  Future<List<Student>> getAll() async {
    final rows = await client.from('students').select().order('last_name').order('first_name');
    return (rows as List).map((r) => Student.fromMap(r as Map<String, Object?>)).toList();
  }
}