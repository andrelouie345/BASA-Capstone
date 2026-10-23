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
    try {
      final inserted = await client.from('students').insert(student.toMap()).select();
      return Student.fromMap((inserted as List).first as Map<String, Object?>);
    } on PostgrestException catch (e) {
      if (e.code == '23505' && e.message.contains('students_lrn_key')) {
        throw DuplicateLrnException(student.lrn);
      }
      rethrow;
    }
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
  Future<int?> activeSectionId(int studentId, String schoolYear) async {
    final rows = await client
        .from('enrollments')
        .select('section_id')
        .eq('student_id', studentId)
        .eq('school_year', schoolYear)
        .eq('status', 'active')
        .limit(1);
    return (rows as List).isEmpty ? null : (rows.first as Map)['section_id'] as int;
  }

  @override
  Future<int> enroll({required int studentId, required int sectionId, required String schoolYear, int? id}) async {
    final row = await client
        .from('enrollments')
        .upsert(
          {'student_id': studentId, 'section_id': sectionId, 'school_year': schoolYear, 'status': 'active'},
          onConflict: 'student_id,school_year',
        )
        .select('id')
        .single();
    return row['id'] as int;
  }

    @override
  Future<Student> upsertWithId(Student student) async {  // (School/Section/Student per class)
    throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');
  }

    @override
  Future<List<Student>> getAll(String sort) async {
    if (sort == 'lastname') {
      final rows = await client.from('students').select().order('last_name', ascending: true).order('first_name', ascending: true);
      return (rows as List).map((r) => Student.fromMap(r as Map<String, Object?>)).toList();
    } else if (sort == 'lrn') {
      final rows = await client.from('students').select().order('lrn', ascending: true);
      return (rows as List).map((r) => Student.fromMap(r as Map<String, Object?>)).toList();
    } else if (sort == 'id') {
      final rows = await client.from('students').select().order('id', ascending: true);
      return (rows as List).map((r) => Student.fromMap(r as Map<String, Object?>)).toList();
    } else {
      throw ArgumentError('Invalid sort option: $sort');
    }
  }
}