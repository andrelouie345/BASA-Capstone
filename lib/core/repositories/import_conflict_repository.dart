// lib/core/repositories/import_conflict_repository.dart
import '../models/import_conflict.dart';

abstract class ImportConflictRepository {
  Future<void> log(ImportConflict conflict);
  Future<List<ImportConflict>> getPending();
  Future<ImportConflict?> getById(int id);
  Future<void> resolve(int id, String status);
}