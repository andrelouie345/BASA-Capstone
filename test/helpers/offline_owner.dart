// Test helper: makes [userId] the owner of a test device who can sign in
// offline with [password], so ViewModel tests run signed in through the real
// AuthViewModel.signInOffline (owner decision 2026-10-24). Writes only to the
// test's own temporary database: a local users row, the offline credential
// and the device owner (sync_meta), as an online sign-in and a pull would.
import 'dart:convert';
import 'dart:typed_data';

import 'package:basa_capstone/core/services/pbkdf2.dart';
import 'package:sqflite_common/sqflite.dart';

Future<void> seedOfflineOwner(
  Database db, {
  required String userId,
  required String email,
  required String role,
  int? schoolId,
  String password = 'test-pw',
}) async {
  await db.insert('users', {'id': userId, 'email': email, 'full_name': 'Test $role', 'role': role,
      'school_id': schoolId, 'is_active': 1}, conflictAlgorithm: ConflictAlgorithm.replace);
  final salt = Uint8List.fromList(List.generate(16, (i) => i + 1));
  const iterations = 1000; // a test credential; the app's own use offlineHashIterations
  await db.delete('offline_credentials');
  await db.insert('offline_credentials', {
    'user_id': userId,
    'email': email,
    'salt': toHex(salt),
    'iterations': iterations,
    'hash': toHex(await pbkdf2HmacSha256InIsolate(utf8.encode(password), salt, iterations)),
    'last_online_at': DateTime.now().toUtc().toIso8601String(),
    'failed_attempts': 0,
  });
  await db.insert('sync_meta', {'key': 'last_pull_user_id', 'value': userId},
      conflictAlgorithm: ConflictAlgorithm.replace);
}
