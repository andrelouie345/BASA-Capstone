// lib/core/data/local/user_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/user.dart';
import '../../repositories/user_repository.dart';

class UserRepositorySqlite implements UserRepository {
  final Database db;
  UserRepositorySqlite(this.db);

  @override
  Future<String?> create(User user) async {
    await db.insert('users', user.toMap());
    return null; // local mirror only; no Auth account, so no password
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

  @override
  Future<User> setTutorType(String id, TutorType? type) async {
    final n = await db.update('users', {'tutor_type': type?.value}, where: 'id = ?', whereArgs: [id]);
    if (n == 0) throw StateError('No user $id on this device');
    return (await getById(id))!;
  }

  /// An upsert, not INSERT OR REPLACE: REPLACE deletes the old row first,
  /// which rows pointing at the account (login_logs, ...) would not allow.
  @override
  Future<void> upsertMirror(User user) async {
    await db.rawInsert('''
      INSERT INTO users (id, email, full_name, role, school_id, is_active, created_at, created_by, tutor_type)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        email = excluded.email, full_name = excluded.full_name, role = excluded.role,
        school_id = excluded.school_id, is_active = excluded.is_active,
        created_at = excluded.created_at, created_by = excluded.created_by, tutor_type = excluded.tutor_type
    ''', [
      user.id,
      user.email,
      user.fullName,
      user.role.name,
      user.schoolId,
      user.isActive ? 1 : 0,
      user.createdAt.toIso8601String(),
      user.createdBy,
      user.tutorType?.value,
    ]);
  }
}