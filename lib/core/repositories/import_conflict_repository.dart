// lib/core/repositories/import_conflict_repository.dart
import '../models/import_conflict.dart';

abstract class ImportConflictRepository {
  Future<void> log(ImportConflict conflict);
  Future<List<ImportConflict>> getPending();
  Future<ImportConflict?> getById(int id);
  /// Marks a PENDING conflict resolved. Returns false when it doesn't exist,
  /// isn't visible, or was already resolved.
  Future<bool> resolve(int id, String status);
}