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
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE testTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL
            )
          ''');
          await _createStudentTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async{
          if (oldVersion < 2) {
            await _createStudentTables(db);
          }
          if (oldVersion < 3) {
            await _createUserManagementTables(db);
          }
        },
      ),
    );
    return _db!;
  }

  static Future<void> _createStudentTables(Database db) async{
    //table creation
    await db.execute('''
      CREATE TABLE schools (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        school_id TEXT UNIQUE NOT NULL,
        school_name TEXT NOT NULL,
        region TEXT,
        division TEXT)
    ''');

    await db.execute('''
      CREATE TABLE sections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      school_id INTEGER NOT NULL REFERENCES schools(id),
      school_year TEXT NOT NULL,
      grade_level TEXT NOT NULL,
      section_name TEXT NOT NULL,
      UNIQUE(school_id, school_year, grade_level, section_name)
      )
    ''');

    await db.execute('''
      CREATE TABLE students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lrn TEXT UNIQUE NOT NULL,
        last_name TEXT NOT NULL,
        first_name TEXT NOT NULL,
        middle_name TEXT,
        sex TEXT,
        birth_date TEXT,
        mother_tongue TEXT,
        ip_group TEXT,
        religion TEXT,
        address_street TEXT,
        barangay TEXT,
        municipality TEXT,
        province TEXT,
        father_name TEXT,
        mother_maiden_name TEXT,
        guardian_name TEXT,
        guardian_relationship TEXT,
        contact_number TEXT,
        learning_modality TEXT,
        remarks TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE enrollments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL REFERENCES students(id),
        section_id INTEGER NOT NULL REFERENCES sections(id),
        school_year TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        UNIQUE(student_id, school_year)
      )
    ''');

    await db.execute('''
      CREATE TABLE import_conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lrn TEXT NOT NULL,
        section_id INTEGER REFERENCES sections(id),
        reason TEXT NOT NULL,
        incoming_data TEXT NOT NULL,   -- JSON blob of the parsed row
        existing_student_id INTEGER REFERENCES students(id),
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    
  }

  static Future<void> _createUserManagementTables(Database db) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,           -- matches Supabase Auth UID
        email TEXT UNIQUE NOT NULL,
        full_name TEXT NOT NULL,
        role TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        created_by TEXT REFERENCES users(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE login_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT REFERENCES users(id),
        email_attempted TEXT NOT NULL,
        success INTEGER NOT NULL,
        method TEXT NOT NULL,
        timestamp TEXT NOT NULL DEFAULT (datetime('now')),
        failure_reason TEXT
      )
    ''');
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}