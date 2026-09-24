// lib/core/repositories/section_repository.dart
import '../models/section.dart';

abstract class SectionRepository {
  Future<Section> getOrCreate(Section section);
  Future<List<Section>> getAll();
  Future<Section?> getById(int id);
  Future<Section> update(Section section);
  Future<void> delete(int id);
  Future<Section> upsertWithId(Section section);
}