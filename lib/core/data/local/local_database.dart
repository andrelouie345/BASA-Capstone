// lib/core/data/local/local_database.dart
import 'package:sqflite_common/sqflite.dart';
import 'package:path/path.dart' as p;

/// Opens/creates the local SQLite DB.
/// IMPORTANT: the caller must set the global `databaseFactory`
/// BEFORE calling this — see the two entry points below. This file
/// only imports sqflite_common (pure Dart), so it's safe to use from
/// both the Flutter app and the plain `dart run` console.
class LocalDatabase {
  static Database? _db;

  static Future<Database> instance(String directory) async {
    if (_db != null) return _db!;
    final path = p.join(directory, 'basa_local.db');
    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE testTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    return _db!;
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}