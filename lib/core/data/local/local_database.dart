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
        version: 6, // was 5
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE testTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL
            )
          ''');
          await _createRegionsTable(db);
          await _createStudentTables(db);
          await _createUserManagementTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createStudentTables(db);
          }

          final usersExists = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
          )).isNotEmpty;

          if (!usersExists) {
            await _createUserManagementTables(db);
          } else {
            final userColumns = await db.rawQuery('PRAGMA table_info(users)');
            final usersHasSchoolId = userColumns.any((c) => c['name'] == 'school_id');
            if (!usersHasSchoolId) {
              await db.execute('ALTER TABLE users ADD COLUMN school_id INTEGER REFERENCES schools(id)');
            }
          }

          final studentColumns = await db.rawQuery('PRAGMA table_info(students)');
          final studentsHasSchoolId = studentColumns.any((c) => c['name'] == 'school_id');
          if (!studentsHasSchoolId) {
            await db.execute('ALTER TABLE students ADD COLUMN school_id INTEGER REFERENCES schools(id)');
          }

          final regionsExists = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='regions'",
          )).isNotEmpty;
          if (!regionsExists) {
            await _createRegionsTable(db);
          }

          final schoolColumns = await db.rawQuery('PRAGMA table_info(schools)');
          final schoolsHasOldRegionText = schoolColumns.any((c) => c['name'] == 'region');
          final schoolsHasRegionId = schoolColumns.any((c) => c['name'] == 'region_id');
          if (schoolsHasOldRegionText && !schoolsHasRegionId) {
            // Rebuild-copy-rename rather than ALTER TABLE DROP COLUMN —
            // avoids depending on a specific SQLite version's feature support
            // across desktop (FFI) vs mobile (OS-bundled) builds.
            await db.execute('''
              CREATE TABLE schools_new (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                school_id TEXT UNIQUE NOT NULL,
                school_name TEXT NOT NULL,
                region_id INTEGER REFERENCES regions(id),
                division TEXT
              )
            ''');
            await db.execute('''
              INSERT INTO schools_new (id, school_id, school_name, division, region_id)
              SELECT id, school_id, school_name, division, NULL FROM schools
            ''');
            await db.execute('DROP TABLE schools');
            await db.execute('ALTER TABLE schools_new RENAME TO schools');
          }
        },
      ),
    );
    return _db!;
  }

  static Future<void> _createRegionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE regions (
        id INTEGER PRIMARY KEY,
        code TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL
      )
    ''');

    const regions = [
      [1, 'Region I', 'Ilocos Region'],
      [2, 'Region II', 'Cagayan Valley'],
      [3, 'Region III', 'Central Luzon'],
      [4, 'Region IV-A', 'CALABARZON'],
      [5, 'Region IV-B', 'MIMAROPA'],
      [6, 'Region V', 'Bicol Region'],
      [7, 'NCR', 'National Capital Region'],
      [8, 'CAR', 'Cordillera Administrative Region'],
      [9, 'Region VI', 'Western Visayas'],
      [10, 'Region VII', 'Central Visayas'],
      [11, 'Region VIII', 'Eastern Visayas'],
      [12, 'Region IX', 'Zamboanga Peninsula'],
      [13, 'Region X', 'Northern Mindanao'],
      [14, 'Region XI', 'Davao Region'],
      [15, 'Region XII', 'SOCCSKSARGEN'],
      [16, 'Region XIII', 'Caraga'],
      [17, 'BARMM', 'Bangsamoro Autonomous Region in Muslim Mindanao'],
      [18, 'NIR', 'Negros Island Region'],
    ];
    for (final r in regions) {
      await db.insert('regions', {'id': r[0], 'code': r[1], 'name': r[2]});
    }
  }

  static Future<void> _createStudentTables(Database db) async{
    //table creation
    await db.execute('''
      CREATE TABLE schools (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        school_id TEXT UNIQUE NOT NULL,
        school_name TEXT NOT NULL,
        region_id INTEGER REFERENCES regions(id),
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
        school_id INTEGER REFERENCES schools(id),
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
        school_id INTEGER REFERENCES schools(id),
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