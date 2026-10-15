// lib/core/repositories/school_repository.dart
import '../models/school.dart';

abstract class SchoolRepository {
  Future<School> getOrCreate(School school);
  Future<School?> getByCode(String schoolCode); // DepEd school ID (schools.school_id)
  Future<School?> getById(int id);
  Future<List<School>> getAll();
  Future<School> upsertWithId(School school); // school.id must be set — forces this exact id locally
  Future<School> update(School school);
  Future<void> delete(int id);
}