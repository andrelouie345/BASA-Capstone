// lib/core/repositories/school_repository.dart
import '../models/school.dart';

abstract class SchoolRepository {
  Future<School> getOrCreate(School school);
}