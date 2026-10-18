// lib/core/data/local/local_database.dart
import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'package:path/path.dart' as p;

import 'phil_iri_local_schema.dart';
import 'aral_local_schema.dart';
import '../../services/crla_rules.dart';

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
        // v15: Phil-IRI passage test_type allows 'mosy'.
        // v16: Phil-IRI reading trigger checks the round's test type (no table
        // change; the bump makes onUpgrade recreate the triggers).
        // v17: same, for the no-repeat check (a learner never reads a text twice).
        // v18: crla_assessments.round (bosy/mosy/eosy), added with the v14
        // columns before the CRLA creators; crla_results gains round.
        // v19: ARAL roster (aral_enrollments), built by createAralLocalSchema.
        // v20: ARAL session log + attendance (same creator).
        // v21: aral_enrollments rebuilt for the 'foundational' key stage; the
        // roster triggers cap a section at 15 active learners.
        // v22: aral_tutor_settings; one ARAL session per tutor per date unless
        // the tutor is allowed several (same creator).
        // v23: IRIP (aral_irip_targets mirror-only, aral_irip_weeks; same creator).
        // v24: aral_enrollments suggestion source columns; the suggestion may
        // change (automatic updates from results; same creator).
        // v25: check-in assessments (tools/items mirror-only, check-ins with
        // origin, answers) and the aral_settings mirror (same creator).
        // v26: phil_iri_readings rebuilt for method 'silent'; triggers refuse
        // miscues on silent readings, keep the method fixed, and let an oral
        // follow-up re-read a silently read text (same round, once).
        // v27: ARAL material catalog (aral_materials, mirror-only; createAralLocalSchema).
        // v28: aral_materials.link + aral_material_links (no stored files).
        // v29: ARAL readability log (aral_readability_logs, offline-first; createAralLocalSchema).
        version: 29,
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
          await _createSyncTables(db);
          await createPhilIriLocalSchema(db);
          await createAralLocalSchema(db);
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

          if (oldVersion < 11) {
            // Must run before the creators below, which recreate the
            // triggers and view this drops.
            await _rebuildCrlaPart2ForV11(db);
          }

          // v14 columns (and v18 round) must exist before _createCrlaViews
          // (crla_results reads reading_profile and round). A missing table is
          // created by _createCrlaTables.
          await _addCrlaV14Columns(db);
            await _createCrlaTables(db);
            await _createCrlaScoreTables(db);
            await _createCrlaViews(db);

          // v12. Checked by column, not version, like the other column adds.
          final crlaColumns = await db.rawQuery('PRAGMA table_info(crla_assessments)');
          if (!crlaColumns.any((c) => c['name'] == 'origin')) {
            // Existing rows can't be told apart, so they count as 'local'
            // (unsynced): a wipe refuses until they're pushed or discarded.
            await db.execute(
                "ALTER TABLE crla_assessments ADD COLUMN origin TEXT NOT NULL DEFAULT 'local' "
                "CHECK (origin IN ('local', 'cloud'))");
          }
          await _createSyncTables(db);
          // v15. Must run before createPhilIriLocalSchema, which recreates the
          // triggers this drops.
          if (oldVersion < 15) await rebuildPhilIriPassagesForV15(db);
          if (oldVersion < 26) await rebuildPhilIriReadingsForV26(db);
          // v13. IF NOT EXISTS + trigger recreate, so it runs on every upgrade.
          await createPhilIriLocalSchema(db);
          // v21. Must run before createAralLocalSchema, which recreates the
          // triggers and indexes this drops.
          if (oldVersion < 21) await rebuildAralEnrollmentsForV21(db);
          // v19. Same pattern: runs on every upgrade.
          await createAralLocalSchema(db);
          // v14. Rows from before v14 were scored with the default thresholds.
          if (oldVersion < 14) await backfillCrlaScoring(db);
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
        -- v18: BOSY/MOSY/EOSY administration (rows from before v18 are bosy)
        round TEXT NOT NULL DEFAULT 'bosy' CHECK (round IN ('bosy', 'mosy', 'eosy')),
        attempt_no INTEGER NOT NULL DEFAULT 0 CHECK (attempt_no >= 0),
        assessed_at TEXT NOT NULL,
        administered_by TEXT REFERENCES users(id),
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        -- Local only (no cloud column): 'local' = entered on this device and
        -- not yet uploaded; 'cloud' = mirrored from Supabase.
        origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
        -- v14: CrlaThresholds.toMap() as JSON (taken when the assessment was
        -- started), and the profile scored with it. Local rows: written by
        -- CrlaViewModel. Mirrored rows: the cloud's values.
        thresholds_snapshot TEXT,
        reading_profile TEXT,
        UNIQUE(student_id, school_id, section_id, subject_variant, school_year, attempt_no)
      )
    ''');

    // v14: mirror of the cloud's crla_thresholds (region row + school
    // overrides). Read-only locally; pull-cloud fills it.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS crla_thresholds (
        id INTEGER PRIMARY KEY,
        school_id INTEGER REFERENCES schools(id),
        settings TEXT NOT NULL,
        updated_by TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS crla_thresholds_school_key
      ON crla_thresholds (IFNULL(school_id, 0))
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

    // Same rules as the cloud insert policy: a grade 1-3 section of that
    // school, and an active enrollment in it for that year. Local inserts
    // only (attempt_no = 0); rows mirrored from the cloud were checked there.
    await db.execute('DROP TRIGGER IF EXISTS check_crla_assessment_target');
    await db.execute('''
      CREATE TRIGGER check_crla_assessment_target
      BEFORE INSERT ON crla_assessments
      WHEN NEW.attempt_no = 0
      BEGIN
        SELECT RAISE(ABORT, 'No such section')
        WHERE NOT EXISTS (SELECT 1 FROM sections WHERE id = NEW.section_id);
        SELECT RAISE(ABORT, 'CRLA is for Grade 1-3 sections only')
        WHERE (SELECT grade_level FROM sections WHERE id = NEW.section_id) NOT IN ('1', '2', '3');
        SELECT RAISE(ABORT, 'Section does not belong to that school')
        WHERE (SELECT school_id FROM sections WHERE id = NEW.section_id) IS NOT NEW.school_id;
        SELECT RAISE(ABORT, 'Learner has no active enrollment in this section for that school year')
        WHERE NOT EXISTS (
          SELECT 1 FROM enrollments
          WHERE student_id = NEW.student_id AND section_id = NEW.section_id
            AND school_year = NEW.school_year AND status = 'active');
      END
    ''');
  }

  /// v11: crla_part2_fluency's comprehension CHECK widens from 0..5 to 0..7.
  /// SQLite can't alter a CHECK, so copy into a new table. The view and the
  /// table's triggers go with the old table; the CRLA creators that run after
  /// this in onUpgrade recreate them.
  static Future<void> _rebuildCrlaPart2ForV11(Database db) async {
    final exists = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='crla_part2_fluency'",
    )).isNotEmpty;
    if (!exists) return; // the creators build it fresh

    await db.transaction((txn) async {
      await txn.execute('DROP VIEW IF EXISTS crla_results');
      await txn.execute('''
        CREATE TABLE crla_part2_fluency_v11 (
          assessment_id INTEGER PRIMARY KEY REFERENCES crla_assessments(id),
          story_no INTEGER NOT NULL CHECK (story_no IN (1, 2)),
          miscues INTEGER NOT NULL CHECK (miscues >= 0),
          words_read INTEGER NOT NULL CHECK (words_read >= 0),
          time_minutes INTEGER NOT NULL CHECK (time_minutes >= 0),
          time_seconds INTEGER NOT NULL CHECK (time_seconds BETWEEN 0 AND 59),
          wpm REAL,
          comprehension_correct INTEGER NOT NULL CHECK (comprehension_correct BETWEEN 0 AND 7),
          learner_experience_rating INTEGER CHECK (learner_experience_rating BETWEEN 1 AND 5),
          observation_level INTEGER CHECK (observation_level BETWEEN 1 AND 4),
          remarks TEXT
        )
      ''');
      await txn.execute('''
        INSERT INTO crla_part2_fluency_v11
        SELECT assessment_id, story_no, miscues, words_read, time_minutes, time_seconds,
               wpm, comprehension_correct, learner_experience_rating, observation_level, remarks
        FROM crla_part2_fluency
      ''');
      await txn.execute('DROP TABLE crla_part2_fluency');
      await txn.execute('ALTER TABLE crla_part2_fluency_v11 RENAME TO crla_part2_fluency');
    });
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

    // v14: the trigger computes total_score only. reading_level depends on the
    // assessment's thresholds: CrlaViewModel writes it for local entries
    // (crla_rules.dart), mirrored rows keep the cloud's. DROP + CREATE so
    // installs upgrading from v13 lose the old level-computing body.
    const standardCompute = '''
      UPDATE crla_part1_standard
      SET total_score = CASE
            WHEN task1_score < 7 THEN task1_score + IFNULL(task2_low_score, 0)
            ELSE task1_score + 10 + IFNULL(task2_high_score, 0)
          END
      WHERE assessment_id = NEW.assessment_id;
    ''';

    await db.execute('DROP TRIGGER IF EXISTS compute_crla_part1_standard_ins');
    await db.execute('''
      CREATE TRIGGER compute_crla_part1_standard_ins
      AFTER INSERT ON crla_part1_standard
      BEGIN $standardCompute END
    ''');
    await db.execute('DROP TRIGGER IF EXISTS compute_crla_part1_standard_upd');
    await db.execute('''
      CREATE TRIGGER compute_crla_part1_standard_upd
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

    // v14: total_score only, as for the standard table.
    const englishCompute = '''
      UPDATE crla_part1_english
      SET total_score = task1_score + IFNULL(task2_score, 0)
      WHERE assessment_id = NEW.assessment_id;
    ''';

    await db.execute('DROP TRIGGER IF EXISTS compute_crla_part1_english_ins');
    await db.execute('''
      CREATE TRIGGER compute_crla_part1_english_ins
      AFTER INSERT ON crla_part1_english
      BEGIN $englishCompute END
    ''');
    await db.execute('DROP TRIGGER IF EXISTS compute_crla_part1_english_upd');
    await db.execute('''
      CREATE TRIGGER compute_crla_part1_english_upd
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
        comprehension_correct INTEGER NOT NULL CHECK (comprehension_correct BETWEEN 0 AND 7),
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

    // Per-grade comprehension max and reading-time cap (crla_rules.dart,
    // Postgres check_crla_part2_limits). Inserts only when wpm is NULL, i.e.
    // local entries; mirrored cloud rows carry wpm and were checked there.
    const limitsCheck = '''
      SELECT RAISE(ABORT, 'Comprehension score is above the maximum for this grade')
      WHERE NEW.comprehension_correct > (
        SELECT CASE
                 WHEN CAST(sec.grade_level AS INTEGER) = 1 THEN 5
                 WHEN CAST(sec.grade_level AS INTEGER) = 3 AND ca.subject_variant IN ('mt', 'fil') THEN 7
                 ELSE 6
               END
        FROM crla_assessments ca JOIN sections sec ON sec.id = ca.section_id
        WHERE ca.id = NEW.assessment_id);
      SELECT RAISE(ABORT, 'Reading time is over the limit for this grade')
      WHERE NEW.time_minutes * 60 + NEW.time_seconds > (
        SELECT CASE
                 WHEN CAST(sec.grade_level AS INTEGER) = 1 THEN 60
                 WHEN CAST(sec.grade_level AS INTEGER) = 3 AND ca.subject_variant IN ('mt', 'fil') THEN 180
                 ELSE 120
               END
        FROM crla_assessments ca JOIN sections sec ON sec.id = ca.section_id
        WHERE ca.id = NEW.assessment_id);
    ''';
    await db.execute('DROP TRIGGER IF EXISTS check_crla_part2_limits_ins');
    await db.execute('''
      CREATE TRIGGER check_crla_part2_limits_ins
      BEFORE INSERT ON crla_part2_fluency
      WHEN NEW.wpm IS NULL
      BEGIN $limitsCheck END
    ''');
    await db.execute('DROP TRIGGER IF EXISTS check_crla_part2_limits_upd');
    await db.execute('''
      CREATE TRIGGER check_crla_part2_limits_upd
      BEFORE UPDATE OF comprehension_correct, time_minutes, time_seconds ON crla_part2_fluency
      BEGIN $limitsCheck END
    ''');
  }

  static Future<void> _createCrlaViews(Database db) async {
    // DROP + CREATE (not IF NOT EXISTS) so a changed definition always replaces the old one.
    await db.execute('DROP VIEW IF EXISTS crla_results');
    // v14: the reading profile is stored on the assessment (scored with its
    // thresholds snapshot), as in the cloud's crla_results. Same columns.
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
        ca.reading_profile,
        ca.round
      FROM crla_assessments ca
      LEFT JOIN crla_part1_standard p1s ON p1s.assessment_id = ca.id
      LEFT JOIN crla_part1_english  p1e ON p1e.assessment_id = ca.id
      LEFT JOIN crla_part2_fluency  p2  ON p2.assessment_id  = ca.id
      JOIN schools  sch ON sch.id = ca.school_id
      JOIN (SELECT id,
                   CASE WHEN grade_level <> '' AND grade_level NOT GLOB '*[^0-9]*'
                        THEN CAST(grade_level AS INTEGER) END AS grade
            FROM sections) gr ON gr.id = ca.section_id
      LEFT JOIN crla_stories cs
        ON cs.region_id = sch.region_id
       AND cs.language  = ca.language
       AND cs.grade     = gr.grade
       AND cs.story_no  = p2.story_no
    ''');
  }

  /// v14 upgrade, before the CRLA creators: the snapshot and stored-profile
  /// columns. No-op when crla_assessments doesn't exist yet (the creator
  /// builds it with them) or already has them.
  static Future<void> _addCrlaV14Columns(Database db) async {
    final cols = (await db.rawQuery('PRAGMA table_info(crla_assessments)')).map((c) => c['name']).toSet();
    if (cols.isEmpty) return;
    if (!cols.contains('thresholds_snapshot')) {
      await db.execute('ALTER TABLE crla_assessments ADD COLUMN thresholds_snapshot TEXT');
    }
    if (!cols.contains('reading_profile')) {
      await db.execute('ALTER TABLE crla_assessments ADD COLUMN reading_profile TEXT');
    }
    // v18: the round. Existing rows become BOSY, as in the cloud migration.
    if (!cols.contains('round')) {
      await db.execute("ALTER TABLE crla_assessments ADD COLUMN round TEXT NOT NULL DEFAULT 'bosy' "
          "CHECK (round IN ('bosy', 'mosy', 'eosy'))");
    }
  }

  /// v14 upgrade: assessments from before v14 were scored with the built-in
  /// defaults (their Part 1 levels already are). Give them that snapshot and
  /// store their profile, computed by crla_rules.dart exactly as the old view
  /// did. Public so tests can call it.
  static Future<void> backfillCrlaScoring(DatabaseExecutor db) async {
    const t = CrlaThresholds.defaults;
    await db.update('crla_assessments', {'thresholds_snapshot': jsonEncode(t.toMap())},
        where: 'thresholds_snapshot IS NULL');
    final rows = await db.rawQuery('''
      SELECT ca.id, ca.subject_variant,
             COALESCE(p1s.reading_level, p1e.reading_level) AS level,
             p2.words_read, p2.comprehension_correct, cs.word_count,
             CASE WHEN sec.grade_level <> '' AND sec.grade_level NOT GLOB '*[^0-9]*'
                  THEN CAST(sec.grade_level AS INTEGER) END AS grade
      FROM crla_assessments ca
      LEFT JOIN crla_part1_standard p1s ON p1s.assessment_id = ca.id
      LEFT JOIN crla_part1_english  p1e ON p1e.assessment_id = ca.id
      LEFT JOIN crla_part2_fluency  p2  ON p2.assessment_id  = ca.id
      JOIN sections sec ON sec.id = ca.section_id
      JOIN schools  sch ON sch.id = ca.school_id
      LEFT JOIN crla_stories cs
        ON cs.region_id = sch.region_id AND cs.language = ca.language
       AND cs.grade = CAST(sec.grade_level AS INTEGER) AND cs.story_no = p2.story_no
      WHERE ca.reading_profile IS NULL
    ''');
    for (final r in rows) {
      final words = r['words_read'] as int?;
      final count = r['word_count'] as int?;
      final profile = crlaReadingProfile(
        part1Level: r['level'] as String?,
        pct: (words == null || count == null || count == 0) ? null : words * 1.0 / count,
        comprehension: r['comprehension_correct'] as int?,
        // Non-numeric grade (not possible for CRLA): the old SQL used the 6-question sheet.
        grade: (r['grade'] as int?) ?? 2,
        variant: r['subject_variant'] as String,
        t: t,
      );
      if (profile != null) {
        await db.update('crla_assessments', {'reading_profile': profile}, where: 'id = ?', whereArgs: [r['id']]);
      }
    }
  }

  /// Local-only bookkeeping for pull-cloud (who pulled last, and when).
  static Future<void> _createSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}