// lib/core/repositories/test_repository.dart
import '../models/test_item.dart';

abstract class TestRepository {
  Future<List<TestItem>> getAll();
  Future<TestItem> add(String name);
  Future<void> delete(int id);
}