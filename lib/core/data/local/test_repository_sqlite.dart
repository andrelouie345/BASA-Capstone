// lib/core/data/local/test_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/test_item.dart';
import '../../repositories/test_repository.dart';

class TestRepositorySqlite implements TestRepository {
  final Database db;
  TestRepositorySqlite(this.db);

  @override
  Future<List<TestItem>> getAll() async {
    final rows = await db.query('testTable', orderBy: 'id');
    return rows.map(TestItem.fromMap).toList();
  }

  @override
  Future<TestItem> add(String name) async {
    final id = await db.insert('testTable', {'name': name});
    return TestItem(id: id, name: name);
  }

  @override
  Future<void> delete(int id) async {
    await db.delete('testTable', where: 'id = ?', whereArgs: [id]);
  }
}