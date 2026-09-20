// lib/core/data/local/user_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/user.dart';
import '../../repositories/user_repository.dart';

class UserRepositorySqlite implements UserRepository {
  final Database db;
  UserRepositorySqlite(this.db);

  @override
  Future<void> create(User user) async {
    await db.insert('users', user.toMap());
  }

  @override
  Future<User?> getById(String id) async {
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : User.fromMap(rows.first);
  }

  @override
  Future<User?> getByEmail(String email) async {
    final rows = await db.query('users', where: 'email = ?', whereArgs: [email]);
    return rows.isEmpty ? null : User.fromMap(rows.first);
  }

  @override
  Future<List<User>> getAll() async {
    final rows = await db.query('users', orderBy: 'full_name COLLATE NOCASE');
    return rows.map(User.fromMap).toList();
  }

  @override
  Future<void> setActive(String id, bool isActive) async {
    await db.update('users', {'is_active': isActive ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }
}