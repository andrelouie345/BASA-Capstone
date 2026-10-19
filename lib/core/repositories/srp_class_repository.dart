// lib/core/repositories/srp_class_repository.dart
import '../models/srp_class.dart';

/// SRP classes and their learners. Written online (Supabase); the SQLite
/// implementation reads and mirrors only. RLS limits what the signed-in user
/// sees: their school's classes (superadmin: all), a tutor only their own.
abstract class SrpClassRepository {
  Future<List<SrpClass>> classesFor(int schoolId, String schoolYear);

  Future<SrpClass?> findClass(int id);

  /// Classes named [name] (any case) in every school and year visible here.
  Future<List<SrpClass>> findClassesByName(String name);

  /// Every learner in [schoolId]'s SRP classes for the year.
  Future<List<SrpClassMember>> membersFor(int schoolId, String schoolYear);

  /// Creates a class (cloud); returns it with its id and stamps.
  Future<SrpClass> insertClass(SrpClass c);

  /// Saves name, room, schedule and tutor (cloud).
  Future<SrpClass> updateClass(SrpClass c);

  /// Deletes a class and its learners (cloud). Throws when nothing was deleted.
  Future<void> deleteClass(int id);

  /// Puts a learner in a class (cloud).
  Future<SrpClassMember> insertMember(int classId, int studentId, String schoolYear);

  /// Moves a learner to another class (cloud).
  Future<SrpClassMember> moveMember(int memberId, int toClassId);

  /// Takes a learner out of their class (cloud). Throws when nothing was deleted.
  Future<void> deleteMember(int memberId);

  /// Local-mirroring only, keeps Supabase's id. Supabase impl throws UnimplementedError.
  Future<void> upsertClassWithId(SrpClass c);

  /// Local-mirroring only: drops the class and its learners. Supabase impl throws UnimplementedError.
  Future<void> removeMirroredClass(int id);

  /// Local-mirroring only. Supabase impl throws UnimplementedError.
  Future<void> upsertMemberWithId(SrpClassMember m);

  /// Local-mirroring only. Supabase impl throws UnimplementedError.
  Future<void> removeMirroredMember(int id);
}
