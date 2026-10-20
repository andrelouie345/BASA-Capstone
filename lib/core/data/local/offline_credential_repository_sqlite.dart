// lib/core/data/local/offline_credential_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import '../../models/offline_credential.dart';
import '../../repositories/offline_credential_repository.dart';

class OfflineCredentialRepositorySqlite implements OfflineCredentialRepository {
  final Database db;
  OfflineCredentialRepositorySqlite(this.db);

  @override
  Future<OfflineCredential?> get() async {
    final rows = await db.query('offline_credentials', limit: 1);
    return rows.isEmpty ? null : OfflineCredential.fromMap(rows.first);
  }

  @override
  Future<void> save(OfflineCredential credential) async {
    await db.transaction((txn) async {
      await txn.delete('offline_credentials');
      await txn.insert('offline_credentials', credential.toMap());
    });
  }

  @override
  Future<void> revoke(String userId) async {
    await db.delete('offline_credentials', where: 'user_id = ?', whereArgs: [userId]);
  }

  @override
  Future<void> recordFailure(String userId) async {
    await db.rawUpdate(
        'UPDATE offline_credentials SET failed_attempts = failed_attempts + 1 WHERE user_id = ?', [userId]);
  }

  @override
  Future<String?> dataOwnerId() async {
    final rows = await db.query('sync_meta', where: "key = 'last_pull_user_id'", limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }
}
