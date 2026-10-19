// lib/core/data/local/tutor_section_assignment_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/tutor_section_assignment.dart';
import '../../repositories/tutor_section_assignment_repository.dart';

/// This device's copy of the assignments (read + mirror only). Assigning and
/// unassigning are online (TutorSectionAssignmentViewModel); local rows carry
/// no tutor name, e-mail or embedded section.
class TutorSectionAssignmentRepositorySqlite implements TutorSectionAssignmentRepository {
  final Database db;
  TutorSectionAssignmentRepositorySqlite(this.db);

  static const _table = 'tutor_section_assignments';

  @override
  Future<TutorSectionAssignment> create(TutorSectionAssignment assignment) =>
      throw UnsupportedError('Assigning a tutor is online only.');

  @override
  Future<void> delete(int id) => throw UnsupportedError('Unassigning a tutor is online only.');

  @override
  Future<List<TutorSectionAssignment>> getByTutor(String tutorId) async =>
      (await db.query(_table, where: 'tutor_id = ?', whereArgs: [tutorId], orderBy: 'assigned_at, id'))
          .map(TutorSectionAssignment.fromMap)
          .toList();

  @override
  Future<List<TutorSectionAssignment>> getBySection(int sectionId) async =>
      (await db.query(_table, where: 'section_id = ?', whereArgs: [sectionId], orderBy: 'assigned_at, id'))
          .map(TutorSectionAssignment.fromMap)
          .toList();

  @override
  Future<void> upsertWithId(TutorSectionAssignment a) async {
    await db.insert(
        _table,
        {
          'id': a.id,
          'tutor_id': a.tutorId,
          'section_id': a.sectionId,
          'assigned_by': a.assignedBy,
          'assigned_at': (a.assignedAt ?? DateTime.now()).toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removeMirrored(int id) async {
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
