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
        version: 10, // was 9
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
          await _createCrlaTables(db);
          await _createCrlaScoreTables(db);
          await _createCrlaViews(db);

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

            await _createCrlaTables(db);
            await _createCrlaScoreTables(db);
            await _createCrlaViews(db);
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

  static Future<void> _createCrlaTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS crla_stories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        region_id INTEGER NOT NULL REFERENCES regions(id),
        language TEXT NOT NULL,
        grade INTEGER NOT NULL CHECK (grade IN (1, 2, 3)),
        story_no INTEGER NOT NULL CHECK (story_no IN (1, 2)),
        title TEXT NOT NULL,
        word_count INTEGER NOT NULL CHECK (word_count > 0),
        source_story_no INTEGER,
        UNIQUE(region_id, language, grade, story_no)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS crla_assessments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL REFERENCES students(id),
        school_id INTEGER NOT NULL REFERENCES schools(id),
        section_id INTEGER NOT NULL REFERENCES sections(id),
        school_year TEXT NOT NULL,
        subject_variant TEXT NOT NULL CHECK (subject_variant IN ('mt', 'fil', 'eng')),
        language TEXT NOT NULL,
        attempt_no INTEGER NOT NULL DEFAULT 0 CHECK (attempt_no >= 0),
        assessed_at TEXT NOT NULL,
        administered_by TEXT REFERENCES users(id),
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(student_id, school_id, section_id, subject_variant, school_year, attempt_no)
      )
    ''');

    // attempt_no = 0 means "assign the next number"; mirrored rows arrive with the real one.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS set_crla_attempt_no
      AFTER INSERT ON crla_assessments
      WHEN NEW.attempt_no = 0
      BEGIN
        UPDATE crla_assessments
        SET attempt_no = COALESCE((
          SELECT MAX(attempt_no) FROM crla_assessments
          WHERE student_id = NEW.student_id
            AND school_id = NEW.school_id
            AND section_id = NEW.section_id
            AND subject_variant = NEW.subject_variant
            AND school_year = NEW.school_year
            AND id <> NEW.id
        ), 0) + 1
        WHERE id = NEW.id;
      END
    ''');
  }

  static Future<void> _createCrlaScoreTables(Database db) async {
    // ---- Part 1 (standard: mt / fil) ----
    await db.execute('''
      CREATE TABLE IF NOT EXISTS crla_part1_standard (
        assessment_id INTEGER PRIMARY KEY REFERENCES crla_assessments(id),
        task1_score INTEGER NOT NULL CHECK (task1_score BETWEEN 0 AND 10),
        task2_low_score INTEGER CHECK (task2_low_score BETWEEN 0 AND 10),
        task2_high_score INTEGER CHECK (task2_high_score BETWEEN 0 AND 10),
        total_score INTEGER,
        reading_level TEXT,
        CHECK (task2_low_score IS NULL OR task1_score < 7),
        CHECK (task2_high_score IS NULL OR task1_score >= 7)
      )
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS check_crla_part1_standard_variant
      BEFORE INSERT ON crla_part1_standard
      WHEN IFNULL((SELECT subject_variant FROM crla_assessments WHERE id = NEW.assessment_id), '')
           NOT IN ('mt', 'fil')
      BEGIN
        SELECT RAISE(ABORT, 'Standard Part 1 requires an mt or fil assessment');
      END
    ''');

        // after check_crla_part1_standard_variant
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS check_crla_part1_standard_variant_upd
      BEFORE UPDATE OF assessment_id ON crla_part1_standard
      WHEN IFNULL((SELECT subject_variant FROM crla_assessments WHERE id = NEW.assessment_id), '')
           NOT IN ('mt', 'fil')
      BEGIN
        SELECT RAISE(ABORT, 'Standard Part 1 requires an mt or fil assessment');
      END
    ''');

    const standardCompute = '''
      UPDATE crla_part1_standard
      SET total_score = CASE
            WHEN task1_score < 7 THEN task1_score + IFNULL(task2_low_score, 0)
            ELSE task1_score + 10 + IFNULL(task2_high_score, 0)
          END,
          reading_level = CASE
            WHEN task1_score < 7 THEN
              CASE WHEN task1_score + IFNULL(task2_low_score, 0) <= 10
                   THEN 'Full Refresher' ELSE 'Moderate Refresher' END
            ELSE
              CASE WHEN task1_score + 10 + IFNULL(task2_high_score, 0) < 27
                   THEN 'Light Refresher' ELSE 'Grade Ready' END
          END
      WHERE assessment_id = NEW.assessment_id;
    ''';

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS compute_crla_part1_standard_ins
      AFTER INSERT ON crla_part1_standard
      BEGIN $standardCompute END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS compute_crla_part1_standard_upd
      AFTER UPDATE OF task1_score, task2_low_score, task2_high_score ON crla_part1_standard
      BEGIN $standardCompute END
    ''');

    // ---- Part 1 (English: eng) ----
    await db.execute('''
      CREATE TABLE IF NOT EXISTS crla_part1_english (
        assessment_id INTEGER PRIMARY KEY REFERENCES crla_assessments(id),
        task1_score INTEGER NOT NULL CHECK (task1_score BETWEEN 0 AND 10),
        task2_score INTEGER CHECK (task2_score BETWEEN 0 AND 10),
        total_score INTEGER,
        reading_level TEXT,
        CHECK (task2_score IS NULL OR task1_score >= 1)
      )
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS check_crla_part1_english_variant
      BEFORE INSERT ON crla_part1_english
      WHEN IFNULL((SELECT subject_variant FROM crla_assessments WHERE id = NEW.assessment_id), '')
           <> 'eng'
      BEGIN
        SELECT RAISE(ABORT, 'English Part 1 requires an eng assessment');
      END
    ''');

        // after check_crla_part1_english_variant
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS check_crla_part1_english_variant_upd
      BEFORE UPDATE OF assessment_id ON crla_part1_english
      WHEN IFNULL((SELECT subject_variant FROM crla_assessments WHERE id = NEW.assessment_id), '')
           <> 'eng'
      BEGIN
        SELECT RAISE(ABORT, 'English Part 1 requires an eng assessment');
      END
    ''');

    const englishCompute = '''
      UPDATE crla_part1_english
      SET total_score = task1_score + IFNULL(task2_score, 0),
          reading_level = CASE
            WHEN task1_score + IFNULL(task2_score, 0) = 0 THEN 'Full Refresher'
            WHEN task1_score + IFNULL(task2_score, 0) <= 10 THEN 'Moderate Refresher'
            WHEN task1_score + IFNULL(task2_score, 0) <= 16 THEN 'Light Refresher'
            ELSE 'Grade Ready'
          END
      WHERE assessment_id = NEW.assessment_id;
    ''';

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS compute_crla_part1_english_ins
      AFTER INSERT ON crla_part1_english
      BEGIN $englishCompute END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS compute_crla_part1_english_upd
      AFTER UPDATE OF task1_score, task2_score ON crla_part1_english
      BEGIN $englishCompute END
    ''');

    // ---- Part 2 (fluency, all variants) ----
    await db.execute('''
      CREATE TABLE IF NOT EXISTS crla_part2_fluency (
        assessment_id INTEGER PRIMARY KEY REFERENCES crla_assessments(id),
        story_no INTEGER NOT NULL CHECK (story_no IN (1, 2)),
        miscues INTEGER NOT NULL CHECK (miscues >= 0),
        words_read INTEGER NOT NULL CHECK (words_read >= 0),
        time_minutes INTEGER NOT NULL CHECK (time_minutes >= 0),
        time_seconds INTEGER NOT NULL CHECK (time_seconds BETWEEN 0 AND 59),
        wpm REAL,
        comprehension_correct INTEGER NOT NULL CHECK (comprehension_correct BETWEEN 0 AND 5),
        learner_experience_rating INTEGER CHECK (learner_experience_rating BETWEEN 1 AND 5),
        observation_level INTEGER CHECK (observation_level BETWEEN 1 AND 4),
        remarks TEXT
      )
    ''');

    const fluencyCompute = '''
      UPDATE crla_part2_fluency
      SET wpm = CASE
            WHEN time_minutes * 60 + time_seconds > 0
            THEN ROUND(words_read * 1.0 / (time_minutes * 60 + time_seconds) * 60, 1)
            ELSE NULL
          END
      WHERE assessment_id = NEW.assessment_id;
    ''';

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS compute_crla_part2_fluency_ins
      AFTER INSERT ON crla_part2_fluency
      BEGIN $fluencyCompute END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS compute_crla_part2_fluency_upd
      AFTER UPDATE OF words_read, time_minutes, time_seconds ON crla_part2_fluency
      BEGIN $fluencyCompute END
    ''');

    await db.execute('DROP TRIGGER IF EXISTS compute_crla_part2_fluency_ins');
    await db.execute('''
      CREATE TRIGGER compute_crla_part2_fluency_ins
      AFTER INSERT ON crla_part2_fluency
      WHEN NEW.wpm IS NULL
      BEGIN $fluencyCompute END
    ''');
  }

  static Future<void> _createCrlaViews(Database db) async {
    // DROP + CREATE (not IF NOT EXISTS) so a changed definition always replaces the old one.
    await db.execute('DROP VIEW IF EXISTS crla_results');
    await db.execute('''
      CREATE VIEW crla_results AS
      SELECT
        ca.id AS assessment_id,
        ca.student_id,
        ca.school_id,
        ca.section_id,
        ca.school_year,
        ca.subject_variant,
        ca.language,
        ca.attempt_no,
        ca.assessed_at,
        COALESCE(p1s.total_score, p1e.total_score) AS part1_total_score,
        COALESCE(p1s.reading_level, p1e.reading_level) AS part1_reading_level,
        p2.story_no,
        p2.words_read,
        p2.miscues,
        p2.wpm,
        p2.comprehension_correct,
        p2.learner_experience_rating,
        p2.observation_level,
        p2.remarks,
        ROUND(p2.words_read * 1.0 / NULLIF(cs.word_count, 0), 4) AS pct_correct_words_read,
        CASE
          WHEN COALESCE(p1s.reading_level, p1e.reading_level)
               IN ('Full Refresher', 'Moderate Refresher')
            THEN 'Low Emerging Reader'
          WHEN p2.story_no IS NULL OR cs.word_count IS NULL THEN NULL
          WHEN (p2.words_read * 1.0 / cs.word_count) <= 0.25
               OR ((p2.words_read * 1.0 / cs.word_count) > 0.25
                   AND (p2.words_read * 1.0 / cs.word_count) <= 0.50
                   AND p2.comprehension_correct = 0)
            THEN 'High Emerging Reader'
          WHEN ((p2.words_read * 1.0 / cs.word_count) > 0.25
                AND (p2.words_read * 1.0 / cs.word_count) < 0.51
                AND p2.comprehension_correct >= 1)
               OR ((p2.words_read * 1.0 / cs.word_count) > 0.50
                   AND (p2.words_read * 1.0 / cs.word_count) < 0.76
                   AND p2.comprehension_correct <= 1)
            THEN 'Developing Reader'
          WHEN ((p2.words_read * 1.0 / cs.word_count) >= 0.51
                AND (p2.words_read * 1.0 / cs.word_count) < 0.76
                AND p2.comprehension_correct >= 2)
               OR ((p2.words_read * 1.0 / cs.word_count) > 0.75
                   AND p2.comprehension_correct <= 3)
            THEN 'Transitioning Reader'
          WHEN (p2.words_read * 1.0 / cs.word_count) > 0.75
               AND p2.comprehension_correct >= 4
            THEN 'Reading At Grade Level'
          ELSE NULL
        END AS reading_profile
      FROM crla_assessments ca
      LEFT JOIN crla_part1_standard p1s ON p1s.assessment_id = ca.id
      LEFT JOIN crla_part1_english  p1e ON p1e.assessment_id = ca.id
      LEFT JOIN crla_part2_fluency  p2  ON p2.assessment_id  = ca.id
      JOIN sections sec ON sec.id = ca.section_id
      JOIN schools  sch ON sch.id = ca.school_id
      LEFT JOIN crla_stories cs
        ON cs.region_id = sch.region_id
       AND cs.language  = ca.language
       AND cs.grade     = CAST(sec.grade_level AS INTEGER)
       AND cs.story_no  = p2.story_no
    ''');
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}