// lib/core/repositories/aral_class_repository.dart
import '../models/aral_class.dart';

/// ARAL classes. SQLite is the main write path (offline-first, like the
/// roster); the Supabase implementation has the same interface for online use.
abstract class AralClassRepository {
  /// Stores a new class and returns it with its id (and stamps).
  Future<AralClass> insert(AralClass aralClass);

  /// Saves the changeable fields (name, program, band, tutor, room, schedule,
  /// notes). School and year never change.
  Future<AralClass> update(AralClass aralClass);

  Future<void> delete(int id);

  Future<AralClass?> findById(int id);

  /// The school's classes, by name.
  Future<List<AralClass>> getBySchool(int schoolId, {String? schoolYear});

  /// The classes [tutorId] teaches, by name.
  Future<List<AralClass>> getByTutor(String tutorId, {String? schoolYear});

  /// Local-mirroring only: keeps Supabase's id (origin 'cloud').
  /// Supabase impl throws UnimplementedError.
  Future<AralClass> upsertWithId(AralClass aralClass);
}
