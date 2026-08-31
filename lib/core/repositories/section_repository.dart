// lib/core/repositories/section_repository.dart
import '../models/section.dart';

abstract class SectionRepository {
  Future<Section> getOrCreate(Section section);
  Future<List<Section>> getAll();
  Future<Section?> getById(int id);
}