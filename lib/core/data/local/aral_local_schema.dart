// lib/core/data/local/aral_local_schema.dart
//
// ARAL-Reading tables in the local SQLite DB (v19 roster, v20 sessions and
// attendance, v21 Foundational program + 15 per section, v22 per-tutor
// settings + one session per tutor per date (both replaced by ARAL classes:
// v36 roster, v37 sessions), v23 IRIP targets + weeks, v24
// suggestion source columns; the suggestion may change, v25 check-in
// assessments + aral_settings, v35 exit reason classroom_support). Same table and column names as
// Postgres (migrations 20261015050000_aral_enrollments.sql,
// 20261015060000_aral_sessions.sql, 20261015070000_aral_foundational_section_cap.sql,
// 20261015080000_aral_tutor_settings.sql, 20261016010000_aral_irip.sql,
// 20261016020000_aral_auto_updates.sql, 20261016030000_aral_checkins.sql; now in
// supabase/migrations_archive/, squashed into the 20261018040000 baseline). Called from
// LocalDatabase on create and, unconditionally, on upgrade: everything here is
// IF NOT EXISTS, and triggers are dropped and recreated.
//
// - aral_enrollments is offline-first (like phil_iri_assessments): it carries
//   the local-only `origin` column ('local' = entered on this device, not
//   uploaded; 'cloud' = mirrored). The cloud's rules are re-checked here only
//   for local rows; role checks (admin/coordinator write the roster) live in
//   the ViewModel. Stamps (created_at/updated_at) come from the repository.
import 'package:sqflite_common/sqflite.dart';

const _gradeLevels = "('1', '2', '3', '4', '5', '6', '7', '8', '9', '10')";

/// Same as the cloud's class cap (aral_check_class_placement, 20261023040000).
const _classCap = 15;

/// v21: key_stage allows 'foundational' (no track, like KS1). v36 (ARAL
/// classes, cloud 20261023040000): class_id (null = waiting for a class)
/// replaces tutor_id; basis 'referral' with who referred the learner and why.
String _enrollmentsTableSql(String name) => '''
    CREATE TABLE IF NOT EXISTS $name (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id INTEGER NOT NULL REFERENCES students(id),
      school_id INTEGER NOT NULL REFERENCES schools(id),
      section_id INTEGER NOT NULL REFERENCES sections(id),
      school_year TEXT NOT NULL
        CHECK (school_year GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
               AND CAST(substr(school_year, 6, 4) AS INTEGER) = CAST(substr(school_year, 1, 4) AS INTEGER) + 1),
      key_stage TEXT NOT NULL CHECK (key_stage IN ('foundational', 'ks1', 'ks2', 'ks3')),
      track TEXT CHECK (track IN ('basic', 'plus')),
      class_id INTEGER REFERENCES aral_classes(id),
      status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'exited')),
      entered_on TEXT NOT NULL,
      exited_on TEXT,
      exit_reason TEXT CHECK (exit_reason IN ('grade_level_ready', 'transferred_out', 'dropped_out', 'other',
                                              'classroom_support')),
      basis_source TEXT NOT NULL CHECK (basis_source IN ('crla', 'phil_iri', 'manual', 'referral')),
      referred_by TEXT,
      referral_reason TEXT,
      basis_round TEXT CHECK (basis_round IN ('bosy', 'mosy', 'mosy1', 'mosy2', 'mosy3', 'eosy')),
      basis_level TEXT,
      basis_assessment_id INTEGER,   -- crla_assessments or phil_iri_assessments (by basis_source)
      suggested_key_stage TEXT CHECK (suggested_key_stage IN ('foundational', 'ks1', 'ks2', 'ks3')),
      suggested_track TEXT CHECK (suggested_track IN ('basic', 'plus')),
      suggestion_round TEXT CHECK (suggestion_round IN ('bosy', 'mosy', 'mosy1', 'mosy2', 'mosy3', 'eosy')),
      suggestion_level TEXT,
      suggestion_assessment_id INTEGER,
      suggested_on TEXT,
      notes TEXT,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      UNIQUE (student_id, school_year),
      CHECK ((key_stage IN ('foundational', 'ks1')) = (track IS NULL)),
      CHECK ((status = 'exited') = (exited_on IS NOT NULL AND exit_reason IS NOT NULL)),
      CHECK (exited_on IS NULL OR exited_on >= entered_on),
      CHECK (basis_source IN ('manual', 'referral') OR basis_level IS NOT NULL),
      CHECK ((basis_source = 'referral') = (referred_by IS NOT NULL AND trim(referred_by) <> ''
                                            AND referral_reason IS NOT NULL AND trim(referral_reason) <> ''))
    )
  ''';

// v21's copy list; tutor_id left out since v36, which runs before it.
const _enrollmentColumns = 'id, student_id, school_id, section_id, school_year, key_stage, track, status, '
    'entered_on, exited_on, exit_reason, basis_source, basis_round, basis_level, basis_assessment_id, '
    'suggested_key_stage, suggested_track, notes, created_by, created_at, updated_at, origin';

/// v21: SQLite can't alter a CHECK, so aral_enrollments (v19/v20) is rebuilt
/// with the 'foundational' key stage, keeping ids. Must run before
/// createAralLocalSchema, which recreates the triggers and indexes this drops.
/// Built new -> drop old -> rename, so aral_attendance's REFERENCES text still
/// names aral_enrollments (renaming the old table away would rewrite it).
Future<void> rebuildAralEnrollmentsForV21(Database db) async {
  final exists = (await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='aral_enrollments'",
  )).isNotEmpty;
  if (!exists) return; // createAralLocalSchema builds it fresh

  await db.transaction((txn) async {
    final triggers = await txn.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND sql LIKE '%aral_enrollments%'",
    );
    for (final t in triggers) {
      await txn.execute('DROP TRIGGER IF EXISTS ${t['name']}');
    }
    await txn.execute(_enrollmentsTableSql('aral_enrollments_v21'));
    await txn.execute('INSERT INTO aral_enrollments_v21 ($_enrollmentColumns) '
        'SELECT $_enrollmentColumns FROM aral_enrollments');
    await txn.execute('DROP TABLE aral_enrollments');
    await txn.execute('ALTER TABLE aral_enrollments_v21 RENAME TO aral_enrollments');
  });
}

/// v35: exit_reason gains 'classroom_support' (DepEd Memorandum 064 s. 2025,
/// cloud 20261023030000). SQLite can't alter a CHECK, so the table is rebuilt
/// like v21, but copying EVERY column the old table has (later column adds
/// such as the v24 suggestion columns and the v34 row_version, which sync
/// needs), keeping ids. Drops every trigger and view that mentions the table
/// (SQLite checks them on the rename); onUpgrade runs this before all the
/// creators, which recreate them. Does nothing when the table already takes
/// the new reason.
Future<void> rebuildAralEnrollmentsForV35(Database db) async {
  final table = await db.rawQuery("SELECT sql FROM sqlite_master WHERE type='table' AND name='aral_enrollments'");
  if (table.isEmpty) return; // createAralLocalSchema builds it fresh
  if ((table.single['sql'] as String).contains("'classroom_support'")) return;

  await db.transaction((txn) async {
    final dependents = await txn.rawQuery(
        "SELECT type, name FROM sqlite_master WHERE type IN ('trigger', 'view') AND sql LIKE '%aral_enrollments%'");
    for (final d in dependents) {
      await txn.execute('DROP ${d['type'] == 'view' ? 'VIEW' : 'TRIGGER'} IF EXISTS ${d['name']}');
    }
    final old = await txn.rawQuery('PRAGMA table_info(aral_enrollments)');
    await txn.execute(_enrollmentsTableSql('aral_enrollments_v35'));
    final have = (await txn.rawQuery('PRAGMA table_info(aral_enrollments_v35)')).map((c) => c['name']).toSet();
    for (final c in old) {
      final name = c['name'] as String;
      if (have.contains(name)) continue;
      await txn.execute('ALTER TABLE aral_enrollments_v35 ADD COLUMN $name ${_suggestionColumns[name] ?? c['type']}');
    }
    final columns = old.map((c) => c['name']).join(', ');
    await txn.execute('INSERT INTO aral_enrollments_v35 ($columns) SELECT $columns FROM aral_enrollments');
    await txn.execute('DROP TABLE aral_enrollments');
    await txn.execute('ALTER TABLE aral_enrollments_v35 RENAME TO aral_enrollments');
  });
}

/// v36: ARAL classes (cloud 20261023040000). Rebuilt like v35 (every column
/// the old table has, row_version included, ids kept), without tutor_id: a
/// learner's tutor is their class's tutor, and existing learners wait for a
/// class (spec decision 11). Drops every trigger and view that mentions the
/// table; onUpgrade runs this right after v35 and before every creator, which
/// recreate them. Does nothing when the table already takes classes.
Future<void> rebuildAralEnrollmentsForV36(Database db) async {
  final table = await db.rawQuery("SELECT sql FROM sqlite_master WHERE type='table' AND name='aral_enrollments'");
  if (table.isEmpty) return; // createAralLocalSchema builds it fresh
  final cols = (await db.rawQuery('PRAGMA table_info(aral_enrollments)')).map((c) => c['name'] as String).toSet();
  if (cols.contains('class_id') && !cols.contains('tutor_id')) return;

  await db.transaction((txn) async {
    final dependents = await txn.rawQuery(
        "SELECT type, name FROM sqlite_master WHERE type IN ('trigger', 'view') AND sql LIKE '%aral_enrollments%'");
    for (final d in dependents) {
      await txn.execute('DROP ${d['type'] == 'view' ? 'VIEW' : 'TRIGGER'} IF EXISTS ${d['name']}');
    }
    final old = (await txn.rawQuery('PRAGMA table_info(aral_enrollments)')).where((c) => c['name'] != 'tutor_id');
    await txn.execute(_enrollmentsTableSql('aral_enrollments_v36'));
    final have = (await txn.rawQuery('PRAGMA table_info(aral_enrollments_v36)')).map((c) => c['name']).toSet();
    for (final c in old) {
      final name = c['name'] as String;
      if (have.contains(name)) continue;
      await txn.execute('ALTER TABLE aral_enrollments_v36 ADD COLUMN $name ${_suggestionColumns[name] ?? c['type']}');
    }
    final columns = old.map((c) => c['name']).join(', ');
    await txn.execute('INSERT INTO aral_enrollments_v36 ($columns) SELECT $columns FROM aral_enrollments');
    await txn.execute('DROP TABLE aral_enrollments');
    await txn.execute('ALTER TABLE aral_enrollments_v36 RENAME TO aral_enrollments');
  });
}

/// v37: a session belongs to an ARAL class (cloud 20261023040000).
/// aral_sessions gains class_id, a declared reference (ALTER TABLE keeps every
/// row, row_version and session number; sessions from before keep none), and
/// the per-tutor settings go (several sessions a day is replaced by one
/// session per class per date). Before createAralLocalSchema, whose session
/// triggers read class_id. Running it again changes nothing.
Future<void> upgradeAralSessionsForV37(Database db) async {
  final table = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='aral_sessions'");
  if (table.isNotEmpty) {
    final cols = (await db.rawQuery('PRAGMA table_info(aral_sessions)')).map((c) => c['name']).toSet();
    if (!cols.contains('class_id')) {
      await db.execute('ALTER TABLE aral_sessions ADD COLUMN class_id INTEGER REFERENCES aral_classes(id)');
    }
  }
  await db.execute('DROP TABLE IF EXISTS aral_tutor_settings'); // its triggers go with it
}

/// v24: where BASA's current suggestion came from (A4). Checked by column,
/// so it runs on every upgrade like the other column adds.
const _suggestionColumns = {
  'suggestion_round': "TEXT CHECK (suggestion_round IN ('bosy', 'mosy', 'mosy1', 'mosy2', 'mosy3', 'eosy'))",
  'suggestion_level': 'TEXT',
  'suggestion_assessment_id': 'INTEGER',
  'suggested_on': 'TEXT',
};

/// v38: aral_classes gets a home grade and may mix programs (cloud
/// 20261024010000): grade_band goes, grade_level (1-10) comes in, program may
/// be null. SQLite can't drop a CHECKed column or alter a CHECK, so the table
/// is rebuilt like aral_enrollments in v35: every column the old table has
/// except grade_band (row_version included: sync), ids kept, grade_level =
/// the lowest grade of the old band (1-3 -> 1, 4-6 -> 4, 7-10 -> 7). Drops
/// every trigger and view that mentions the table (the roster's placement
/// and the sync locks included); onUpgrade runs this before every creator,
/// which recreate them. Does nothing when the table has no grade_band.
Future<void> rebuildAralClassesForV38(Database db) async {
  final table = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='aral_classes'");
  if (table.isEmpty) return; // createAralLocalSchema builds it fresh
  final old = (await db.rawQuery('PRAGMA table_info(aral_classes)')).map((c) => c['name'] as String).toList();
  if (!old.contains('grade_band')) return;

  await db.transaction((txn) async {
    final dependents = await txn.rawQuery(
        "SELECT type, name FROM sqlite_master WHERE type IN ('trigger', 'view') AND sql LIKE '%aral_classes%'");
    for (final d in dependents) {
      await txn.execute('DROP ${d['type'] == 'view' ? 'VIEW' : 'TRIGGER'} IF EXISTS ${d['name']}');
    }
    await txn.execute(_classesTableSql('aral_classes_v38'));
    final columns = old.where((c) => c != 'grade_band' && c != 'grade_level').join(', ');
    await txn.execute('INSERT INTO aral_classes_v38 ($columns, grade_level) '
        "SELECT $columns, CAST(substr(grade_band, 1, instr(grade_band, '-') - 1) AS INTEGER) FROM aral_classes");
    await txn.execute('DROP TABLE aral_classes');
    await txn.execute('ALTER TABLE aral_classes_v38 RENAME TO aral_classes');
  });
}

/// ARAL classes (cloud 20261023040000, 20261024010000): school + year + name,
/// a home grade (1-10), one program or mixed programs (program null), an
/// optional tutor. Offline-first like the roster: `origin` tells rows made
/// here ('local', checked by the triggers) from mirrored ones. row_version is
/// the sync column (createSyncLocalSchema adds the same to the other synced
/// tables).
String _classesTableSql(String name) => '''
    CREATE TABLE IF NOT EXISTS $name (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      school_id INTEGER NOT NULL REFERENCES schools(id),
      school_year TEXT NOT NULL
        CHECK (school_year GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
               AND CAST(substr(school_year, 6, 4) AS INTEGER) = CAST(substr(school_year, 1, 4) AS INTEGER) + 1),
      class_name TEXT NOT NULL CHECK (length(trim(class_name)) > 0),
      grade_level INTEGER NOT NULL CHECK (grade_level BETWEEN 1 AND 10),
      program TEXT
        CHECK (program IN ('foundational', 'ks1', 'ks2_basic', 'ks2_plus', 'ks3_basic', 'ks3_plus')),
      tutor_id TEXT REFERENCES users(id),
      room TEXT,
      schedule TEXT,
      notes TEXT,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      row_version INTEGER
    )
  ''';

/// Before the roster, whose class_id points here.
Future<void> _createClassTables(Database db) async {
  await db.execute(_classesTableSql('aral_classes'));
  // Same name rule as the cloud's aral_classes_name_key (lower(btrim(...))).
  await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS aral_classes_name_key '
      'ON aral_classes (school_id, school_year, lower(trim(class_name)))');
  await db.execute('CREATE INDEX IF NOT EXISTS aral_classes_tutor ON aral_classes (tutor_id, school_year)');
}

/// The class triggers; after the roster table, which one of them reads.
Future<void> _createClassTriggers(Database db) async {
  const tutorOk = '''(SELECT 1 FROM users u WHERE u.id = NEW.tutor_id AND u.role = 'tutor'
                        AND u.is_active = 1 AND u.school_id = NEW.school_id)''';
  const tutorMsg = "The ARAL class tutor must be an active tutor of the class''s school";
  await db.execute('DROP TRIGGER IF EXISTS check_aral_class_ins');
  await db.execute('''
    CREATE TRIGGER check_aral_class_ins
    BEFORE INSERT ON aral_classes
    WHEN NEW.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, '$tutorMsg')
      WHERE NEW.tutor_id IS NOT NULL AND NOT EXISTS $tutorOk;
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_aral_class_upd');
  await db.execute('''
    CREATE TRIGGER check_aral_class_upd
    BEFORE UPDATE ON aral_classes
    WHEN OLD.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'An ARAL class keeps its school and school year')
      WHERE NEW.school_id IS NOT OLD.school_id OR NEW.school_year IS NOT OLD.school_year;
      SELECT RAISE(ABORT, '$tutorMsg')
      WHERE NEW.tutor_id IS NOT NULL AND NEW.tutor_id IS NOT OLD.tutor_id AND NOT EXISTS $tutorOk;
      SELECT RAISE(ABORT, 'An ARAL class with learners keeps its grade and program')
      WHERE (NEW.program IS NOT OLD.program OR NEW.grade_level IS NOT OLD.grade_level)
        AND EXISTS (SELECT 1 FROM aral_enrollments WHERE class_id = NEW.id);
    END
  ''');
}

Future<void> createAralLocalSchema(Database db) async {
  await _createClassTables(db);
  await db.execute(_enrollmentsTableSql('aral_enrollments'));
  final have = (await db.rawQuery('PRAGMA table_info(aral_enrollments)')).map((c) => c['name']).toSet();
  for (final c in _suggestionColumns.entries) {
    if (!have.contains(c.key)) await db.execute('ALTER TABLE aral_enrollments ADD COLUMN ${c.key} ${c.value}');
  }
  await db.execute('CREATE INDEX IF NOT EXISTS aral_enrollments_section ON aral_enrollments (section_id, school_year)');
  await db.execute('CREATE INDEX IF NOT EXISTS aral_enrollments_school ON aral_enrollments (school_id, school_year)');
  await db.execute('DROP INDEX IF EXISTS aral_enrollments_tutor'); // tutor_id went in v36
  await db.execute('CREATE INDEX IF NOT EXISTS aral_enrollments_class ON aral_enrollments (class_id)');
  await _createClassTriggers(db);

  // Placement (v38, same rules as the cloud's aral_check_class_placement): an
  // active learner going into a class matches its school and year and, in a
  // one-program class, its program; the class has fewer than 15 other active
  // learners. Grades are not checked here: another grade joins only when the
  // coordinator confirms it (AralClassViewModel.place), and a placed learner
  // whose grade changes stays (flagged by aral-update).
  String placement(String applies) => '''
      SELECT RAISE(ABORT, 'The ARAL class belongs to another school or school year')
      WHERE $applies AND NOT EXISTS (
        SELECT 1 FROM aral_classes c
        WHERE c.id = NEW.class_id AND c.school_id = NEW.school_id AND c.school_year = NEW.school_year);
      SELECT RAISE(ABORT, 'The learner''s program does not match the ARAL class')
      WHERE $applies AND EXISTS (
        SELECT 1 FROM aral_classes WHERE id = NEW.class_id AND program IS NOT NULL
          AND program IS NOT (NEW.key_stage || COALESCE('_' || NEW.track, '')));
      SELECT RAISE(ABORT, 'An ARAL class has at most $_classCap active learners')
      WHERE $applies AND (SELECT count(*) FROM aral_enrollments
                          WHERE class_id = NEW.class_id AND status = 'active' AND id IS NOT NEW.id) >= $_classCap;''';

  await db.execute('DROP TRIGGER IF EXISTS check_aral_enrollment_ins');
  await db.execute('''
    CREATE TRIGGER check_aral_enrollment_ins
    BEFORE INSERT ON aral_enrollments
    WHEN NEW.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'No such section')
      WHERE NOT EXISTS (SELECT 1 FROM sections WHERE id = NEW.section_id);
      SELECT RAISE(ABORT, 'ARAL-Reading is for Grade 1-10 sections only')
      WHERE (SELECT grade_level FROM sections WHERE id = NEW.section_id) NOT IN $_gradeLevels;
      SELECT RAISE(ABORT, 'Section does not belong to that school')
      WHERE (SELECT school_id FROM sections WHERE id = NEW.section_id) IS NOT NEW.school_id;
      SELECT RAISE(ABORT, 'Learner has no active enrollment in this section for that school year')
      WHERE NOT EXISTS (
        SELECT 1 FROM enrollments
        WHERE student_id = NEW.student_id AND section_id = NEW.section_id
          AND school_year = NEW.school_year AND status = 'active');
      SELECT RAISE(ABORT, 'A new ARAL enrollment starts active')
      WHERE NEW.status <> 'active';
${placement("NEW.class_id IS NOT NULL")}
    END
  ''');

  await db.execute('DROP TRIGGER IF EXISTS check_aral_enrollment_upd');
  await db.execute('''
    CREATE TRIGGER check_aral_enrollment_upd
    BEFORE UPDATE ON aral_enrollments
    WHEN OLD.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'An ARAL enrollment keeps its learner, school, year and basis; only the placement, class, status and notes change')
      WHERE NEW.student_id IS NOT OLD.student_id OR NEW.school_id IS NOT OLD.school_id
         OR NEW.school_year IS NOT OLD.school_year OR NEW.basis_source IS NOT OLD.basis_source
         OR NEW.basis_round IS NOT OLD.basis_round OR NEW.basis_level IS NOT OLD.basis_level
         OR NEW.basis_assessment_id IS NOT OLD.basis_assessment_id
         OR NEW.referred_by IS NOT OLD.referred_by OR NEW.referral_reason IS NOT OLD.referral_reason
         OR NEW.created_by IS NOT OLD.created_by OR NEW.created_at IS NOT OLD.created_at;
      SELECT RAISE(ABORT, 'Section does not belong to that school')
      WHERE (SELECT school_id FROM sections WHERE id = NEW.section_id) IS NOT NEW.school_id;
      SELECT RAISE(ABORT, 'ARAL-Reading is for Grade 1-10 sections only')
      WHERE (SELECT grade_level FROM sections WHERE id = NEW.section_id) NOT IN $_gradeLevels;
      SELECT RAISE(ABORT, 'Learner has no enrollment in this section for that school year')
      WHERE NOT EXISTS (
        SELECT 1 FROM enrollments
        WHERE student_id = NEW.student_id AND section_id = NEW.section_id AND school_year = NEW.school_year);
      -- Going into a class (placement, a move, reactivation) is checked in
      -- full; a program change or a section move that keeps the class is not
      -- (decision 7, G4).
${placement("NEW.class_id IS NOT NULL AND NEW.status = 'active' AND (NEW.class_id IS NOT OLD.class_id OR OLD.status <> 'active' OR NEW.school_id IS NOT OLD.school_id OR NEW.school_year IS NOT OLD.school_year)")}
    END
  ''');

  // ---- Sessions (v20): the lesson log. origin like aral_enrollments. v37: a
  // session is one ARAL class's meeting (class_id; sessions from before keep
  // none). ----
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tutor_id TEXT NOT NULL REFERENCES users(id),
      school_id INTEGER NOT NULL REFERENCES schools(id),
      school_year TEXT NOT NULL
        CHECK (school_year GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
               AND CAST(substr(school_year, 6, 4) AS INTEGER) = CAST(substr(school_year, 1, 4) AS INTEGER) + 1),
      session_no INTEGER NOT NULL DEFAULT 0 CHECK (session_no >= 0),
      held_on TEXT NOT NULL,
      minutes INTEGER NOT NULL CHECK (minutes BETWEEN 1 AND 120),
      setup TEXT NOT NULL CHECK (setup IN ('pull_out', 'during_class', 'after_class', 'weekend', 'other')),
      lesson TEXT,
      remarks TEXT,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      class_id INTEGER REFERENCES aral_classes(id)
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS aral_sessions_tutor ON aral_sessions (tutor_id, school_year, held_on)');
  await db.execute('CREATE INDEX IF NOT EXISTS aral_sessions_school ON aral_sessions (school_id, school_year, held_on)');
  await db.execute('CREATE INDEX IF NOT EXISTS aral_sessions_class ON aral_sessions (class_id, held_on)');

  // session_no = 0 means "assign the next number" (per class; per tutor for a
  // session without one); mirrored rows arrive with the real one.
  await db.execute('DROP TRIGGER IF EXISTS set_aral_session_no');
  await db.execute('''
    CREATE TRIGGER set_aral_session_no
    AFTER INSERT ON aral_sessions
    WHEN NEW.session_no = 0
    BEGIN
      UPDATE aral_sessions
      SET session_no = COALESCE((
        SELECT MAX(session_no) FROM aral_sessions
        WHERE id <> NEW.id
          AND CASE WHEN NEW.class_id IS NULL
                   THEN tutor_id = NEW.tutor_id AND school_year = NEW.school_year
                   ELSE class_id = NEW.class_id END), 0) + 1
      WHERE id = NEW.id;
    END
  ''');

  const sessionTutorOk = '''(SELECT 1 FROM users u WHERE u.id = NEW.tutor_id AND u.role = 'tutor'
                        AND u.is_active = 1 AND u.school_id = NEW.school_id)''';
  const dayTaken = 'An ARAL class already has a session on that date';
  await db.execute('DROP TRIGGER IF EXISTS check_aral_session_ins');
  await db.execute('''
    CREATE TRIGGER check_aral_session_ins
    BEFORE INSERT ON aral_sessions
    WHEN NEW.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'The session tutor must be an active tutor of the school')
      WHERE NOT EXISTS $sessionTutorOk;
      SELECT RAISE(ABORT, 'A new ARAL session needs a class')
      WHERE NEW.class_id IS NULL;
      SELECT RAISE(ABORT, 'The ARAL class belongs to another school or school year')
      WHERE NOT EXISTS (SELECT 1 FROM aral_classes c WHERE c.id = NEW.class_id
                          AND c.school_id = NEW.school_id AND c.school_year = NEW.school_year);
      SELECT RAISE(ABORT, '$dayTaken')
      WHERE EXISTS (SELECT 1 FROM aral_sessions WHERE class_id = NEW.class_id AND held_on = NEW.held_on);
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_aral_session_upd');
  await db.execute('''
    CREATE TRIGGER check_aral_session_upd
    BEFORE UPDATE ON aral_sessions
    WHEN OLD.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'An ARAL session keeps its tutor, class, school, year and number; only the date, minutes, set-up, lesson and remarks change')
      WHERE NEW.tutor_id IS NOT OLD.tutor_id OR NEW.class_id IS NOT OLD.class_id OR NEW.school_id IS NOT OLD.school_id
         OR NEW.school_year IS NOT OLD.school_year
         OR (NEW.session_no IS NOT OLD.session_no AND OLD.session_no <> 0)
         OR NEW.created_by IS NOT OLD.created_by OR NEW.created_at IS NOT OLD.created_at;
      SELECT RAISE(ABORT, '$dayTaken')
      WHERE NEW.held_on IS NOT OLD.held_on AND NEW.class_id IS NOT NULL
        AND EXISTS (SELECT 1 FROM aral_sessions
                    WHERE class_id = NEW.class_id AND held_on = NEW.held_on AND id <> NEW.id);
    END
  ''');

  // ---- Attendance (v20): one mark per learner per session. Its session's
  // origin tells whether the local checks apply. ----
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_attendance (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL REFERENCES aral_sessions(id),
      enrollment_id INTEGER NOT NULL REFERENCES aral_enrollments(id),
      mark TEXT NOT NULL CHECK (mark IN ('present', 'absent', 'excused')),
      note TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (session_id, enrollment_id)
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS aral_attendance_enrollment ON aral_attendance (enrollment_id)');

  await db.execute('DROP TRIGGER IF EXISTS check_aral_attendance_ins');
  await db.execute('''
    CREATE TRIGGER check_aral_attendance_ins
    BEFORE INSERT ON aral_attendance
    WHEN (SELECT origin FROM aral_sessions WHERE id = NEW.session_id) = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'That learner was not in ARAL in this school on the session date')
      WHERE NOT EXISTS (
        SELECT 1 FROM aral_sessions s
        JOIN aral_enrollments e ON e.school_id = s.school_id AND e.school_year = s.school_year
        WHERE s.id = NEW.session_id AND e.id = NEW.enrollment_id
          AND e.entered_on <= s.held_on
          AND (e.exited_on IS NULL OR e.exited_on >= s.held_on));
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_aral_attendance_upd');
  await db.execute('''
    CREATE TRIGGER check_aral_attendance_upd
    BEFORE UPDATE ON aral_attendance
    WHEN (SELECT origin FROM aral_sessions WHERE id = OLD.session_id) = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'An attendance mark keeps its session and learner; delete it and add a new one instead')
      WHERE NEW.session_id IS NOT OLD.session_id OR NEW.enrollment_id IS NOT OLD.enrollment_id;
    END
  ''');

  // ---- IRIP (v23): target lists (mirror-only content) and weeks (origin). ----
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_irip_targets (
      id INTEGER PRIMARY KEY,
      program TEXT NOT NULL CHECK (program IN ('basic_ks23', 'plus_ks2', 'plus_ks3')),
      strand TEXT NOT NULL CHECK (strand IN ('filipino', 'english', 'main')),
      seq INTEGER NOT NULL CHECK (seq >= 1),
      focus TEXT,
      letter_focus TEXT,
      sight_words TEXT,
      skills TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (program, strand, seq)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_irip_weeks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      enrollment_id INTEGER NOT NULL REFERENCES aral_enrollments(id),
      cycle_no INTEGER NOT NULL DEFAULT 1 CHECK (cycle_no >= 1),
      week_no INTEGER NOT NULL CHECK (week_no BETWEEN 1 AND 8),
      strand TEXT NOT NULL CHECK (strand IN ('filipino', 'english', 'main')),
      target_id INTEGER NOT NULL REFERENCES aral_irip_targets(id),
      status TEXT CHECK (status IN ('observed', 'partial', 'not_observed')),
      rated_on TEXT,
      notes TEXT,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      UNIQUE (enrollment_id, cycle_no, week_no, strand),
      CHECK ((status IS NULL) = (rated_on IS NULL))
    )
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS aral_irip_weeks_enrollment ON aral_irip_weeks (enrollment_id, cycle_no, week_no)');

  // The target must be active, in the IRIP of the learner's current placement
  // (as aral_irip_program in the cloud), and of the week's strand.
  const targetOk = '''EXISTS (
        SELECT 1 FROM aral_irip_targets t JOIN aral_enrollments e ON e.id = NEW.enrollment_id
        WHERE t.id = NEW.target_id AND t.is_active = 1 AND t.strand = NEW.strand
          AND t.program = CASE
            WHEN e.key_stage IN ('ks2', 'ks3') AND e.track = 'basic' THEN 'basic_ks23'
            WHEN e.key_stage = 'ks2' AND e.track = 'plus' THEN 'plus_ks2'
            WHEN e.key_stage = 'ks3' AND e.track = 'plus' THEN 'plus_ks3' END)''';
  const learnerActive =
      "EXISTS (SELECT 1 FROM aral_enrollments WHERE id = NEW.enrollment_id AND status = 'active')";
  await db.execute('DROP TRIGGER IF EXISTS check_aral_irip_week_ins');
  await db.execute('''
    CREATE TRIGGER check_aral_irip_week_ins
    BEFORE INSERT ON aral_irip_weeks
    WHEN NEW.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'The learner is not active in ARAL')
      WHERE NOT $learnerActive;
      SELECT RAISE(ABORT, 'That reading target is not in the learner''s IRIP list')
      WHERE NOT $targetOk;
      SELECT RAISE(ABORT, 'An IRIP week needs the previous week of its cycle')
      WHERE NEW.week_no > 1 AND NOT EXISTS (
        SELECT 1 FROM aral_irip_weeks
        WHERE enrollment_id = NEW.enrollment_id AND cycle_no = NEW.cycle_no
          AND week_no = NEW.week_no - 1 AND strand = NEW.strand);
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_aral_irip_week_upd');
  await db.execute('''
    CREATE TRIGGER check_aral_irip_week_upd
    BEFORE UPDATE ON aral_irip_weeks
    WHEN OLD.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'An IRIP week keeps its learner, cycle, week and strand; only the target, status and notes change')
      WHERE NEW.enrollment_id IS NOT OLD.enrollment_id OR NEW.cycle_no IS NOT OLD.cycle_no
         OR NEW.week_no IS NOT OLD.week_no OR NEW.strand IS NOT OLD.strand
         OR NEW.created_by IS NOT OLD.created_by OR NEW.created_at IS NOT OLD.created_at;
      SELECT RAISE(ABORT, 'A rated IRIP week keeps its target')
      WHERE NEW.target_id IS NOT OLD.target_id AND OLD.status IS NOT NULL;
      SELECT RAISE(ABORT, 'The learner is not active in ARAL')
      WHERE NEW.target_id IS NOT OLD.target_id AND NOT $learnerActive;
      SELECT RAISE(ABORT, 'That reading target is not in the learner''s IRIP list')
      WHERE NEW.target_id IS NOT OLD.target_id AND NOT $targetOk;
    END
  ''');

  await _createCheckinTables(db);
  await _createMaterialTables(db);
  await _createReadabilityTables(db);
}

/// v29: the readability log (aral_readability_logs), offline-first with the
/// origin column like the check-ins; the triggers re-check the cloud's rules
/// for local rows. Only while the school's foundational literacy program
/// (SHARP) is on: aral_settings.foundational_program, school row over region
/// row, default off (JSON in the mirror; json_extract gives 1/0).
Future<void> _createReadabilityTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_readability_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      enrollment_id INTEGER NOT NULL REFERENCES aral_enrollments(id),
      read_on TEXT NOT NULL,
      title TEXT NOT NULL CHECK (length(trim(title)) > 0),
      words INTEGER NOT NULL CHECK (words > 0),
      sentences INTEGER NOT NULL CHECK (sentences > 0),
      syllables INTEGER NOT NULL CHECK (syllables > 0),
      source TEXT,
      material_id INTEGER REFERENCES aral_materials(id),
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      CHECK (syllables >= words)
    )
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS aral_readability_logs_enrollment ON aral_readability_logs (enrollment_id, read_on)');

  const school = '(SELECT school_id FROM aral_enrollments WHERE id = NEW.enrollment_id)';
  const sharpOn = '''COALESCE(
        (SELECT json_extract(settings, '\$.foundational_program') FROM aral_settings WHERE school_id = $school),
        (SELECT json_extract(settings, '\$.foundational_program') FROM aral_settings WHERE school_id IS NULL),
        0) = 1''';
  const beforeEntry =
      'NEW.read_on < (SELECT entered_on FROM aral_enrollments WHERE id = NEW.enrollment_id)';
  await db.execute('DROP TRIGGER IF EXISTS check_aral_readability_ins');
  await db.execute('''
    CREATE TRIGGER check_aral_readability_ins
    BEFORE INSERT ON aral_readability_logs
    WHEN NEW.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'The learner is not active in ARAL')
      WHERE NOT EXISTS (SELECT 1 FROM aral_enrollments WHERE id = NEW.enrollment_id AND status = 'active');
      SELECT RAISE(ABORT, 'The readability log is only kept while the school''s foundational literacy program (SHARP) is switched on')
      WHERE NOT ($sharpOn);
      SELECT RAISE(ABORT, 'A reading cannot be dated before the learner entered ARAL')
      WHERE $beforeEntry;
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_aral_readability_upd');
  await db.execute('''
    CREATE TRIGGER check_aral_readability_upd
    BEFORE UPDATE ON aral_readability_logs
    WHEN OLD.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'A readability log entry keeps its learner; only the selection, counts, date and source change')
      WHERE NEW.enrollment_id IS NOT OLD.enrollment_id OR NEW.created_by IS NOT OLD.created_by
         OR NEW.created_at IS NOT OLD.created_at;
      SELECT RAISE(ABORT, 'A reading cannot be dated before the learner entered ARAL')
      WHERE $beforeEntry;
    END
  ''');
}

/// v27: the material catalog (aral_materials), mirror-only like the check-in
/// tools: written online, same CHECKs as the cloud, no triggers.
/// v28: no stored files (link instead of storage); aral_material_links (a
/// school's own links). v27 devices keep three unused, always-null columns
/// (file_size, file_sha256, storage_path): SQLite on older Android can't
/// DROP COLUMN, and they do no harm.
Future<void> _createMaterialTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_materials (
      id INTEGER PRIMARY KEY,
      school_id INTEGER REFERENCES schools(id),
      title TEXT NOT NULL CHECK (length(trim(title)) > 0),
      description TEXT,
      key_stage TEXT NOT NULL CHECK (key_stage IN ('foundational', 'ks1', 'ks2', 'ks3')),
      track TEXT CHECK (track IN ('basic', 'plus')),
      kind TEXT NOT NULL DEFAULT 'learner' CHECK (kind IN ('learner', 'tutor', 'supplementary')),
      language TEXT NOT NULL DEFAULT 'English' CHECK (language IN ('English', 'Filipino')),
      min_grade INTEGER NOT NULL DEFAULT 7,
      max_grade INTEGER NOT NULL DEFAULT 10,
      file_name TEXT,
      link TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_by TEXT,
      created_at TEXT,
      updated_at TEXT,
      CHECK (key_stage IN ('ks2', 'ks3') OR track IS NULL),
      CHECK (min_grade BETWEEN 1 AND 12 AND max_grade BETWEEN min_grade AND 12),
      CHECK (key_stage <> 'ks3' OR min_grade >= 7)
    )
  ''');
  await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS aral_materials_title_key ON aral_materials (IFNULL(school_id, 0), lower(title))');
  final columns = (await db.rawQuery('PRAGMA table_info(aral_materials)')).map((c) => c['name']).toSet();
  if (!columns.contains('link')) await db.execute('ALTER TABLE aral_materials ADD COLUMN link TEXT');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_material_links (
      id INTEGER PRIMARY KEY,
      material_id INTEGER NOT NULL REFERENCES aral_materials(id),
      school_id INTEGER NOT NULL REFERENCES schools(id),
      link TEXT NOT NULL,
      updated_by TEXT,
      updated_at TEXT,
      UNIQUE (material_id, school_id)
    )
  ''');
}

/// v25: check-in tools and items (mirror-only content), check-ins (origin)
/// and their answers, and the aral_settings mirror (read-only locally).
Future<void> _createCheckinTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_checkin_tools (
      id INTEGER PRIMARY KEY,
      key_stage TEXT NOT NULL CHECK (key_stage IN ('ks2', 'ks3')),
      track TEXT NOT NULL CHECK (track IN ('basic', 'plus')),
      checkpoint INTEGER NOT NULL CHECK (checkpoint IN (16, 32)),
      language TEXT NOT NULL CHECK (language IN ('filipino', 'english')),
      title TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (key_stage, track, checkpoint)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_checkin_items (
      id INTEGER PRIMARY KEY,
      tool_id INTEGER NOT NULL REFERENCES aral_checkin_tools(id),
      item_no INTEGER NOT NULL CHECK (item_no >= 1),
      label TEXT,
      section TEXT,
      kind TEXT NOT NULL CHECK (kind IN ('choice', 'open')),
      answer_key TEXT,
      prompt TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (tool_id, item_no),
      CHECK (kind = 'open' OR COALESCE(answer_key GLOB '[A-E]', 0))
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_checkins (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      enrollment_id INTEGER NOT NULL REFERENCES aral_enrollments(id),
      tool_id INTEGER NOT NULL REFERENCES aral_checkin_tools(id),
      attempt_no INTEGER NOT NULL DEFAULT 0 CHECK (attempt_no >= 0),
      taken_on TEXT NOT NULL,
      notes TEXT,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      UNIQUE (enrollment_id, tool_id, attempt_no)
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS aral_checkins_enrollment ON aral_checkins (enrollment_id, tool_id)');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_checkin_answers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      checkin_id INTEGER NOT NULL REFERENCES aral_checkins(id),
      item_id INTEGER NOT NULL REFERENCES aral_checkin_items(id),
      response TEXT,
      is_correct INTEGER NOT NULL CHECK (is_correct IN (0, 1)),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (checkin_id, item_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_settings (
      id INTEGER PRIMARY KEY,
      school_id INTEGER REFERENCES schools(id),
      settings TEXT NOT NULL,
      updated_by TEXT,
      updated_at TEXT
    )
  ''');
  await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS aral_settings_school_key ON aral_settings (IFNULL(school_id, 0))');

  // attempt_no = 0 means "assign the next number"; mirrored rows arrive with the real one.
  await db.execute('DROP TRIGGER IF EXISTS set_aral_checkin_attempt_no');
  await db.execute('''
    CREATE TRIGGER set_aral_checkin_attempt_no
    AFTER INSERT ON aral_checkins
    WHEN NEW.attempt_no = 0
    BEGIN
      UPDATE aral_checkins
      SET attempt_no = COALESCE((
        SELECT MAX(attempt_no) FROM aral_checkins
        WHERE enrollment_id = NEW.enrollment_id AND tool_id = NEW.tool_id AND id <> NEW.id), 0) + 1
      WHERE id = NEW.id;
    END
  ''');

  const notBeforeEntry = '''NEW.taken_on < (SELECT entered_on FROM aral_enrollments WHERE id = NEW.enrollment_id)''';
  await db.execute('DROP TRIGGER IF EXISTS check_aral_checkin_ins');
  await db.execute('''
    CREATE TRIGGER check_aral_checkin_ins
    BEFORE INSERT ON aral_checkins
    WHEN NEW.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'The learner is not active in ARAL')
      WHERE NOT EXISTS (SELECT 1 FROM aral_enrollments WHERE id = NEW.enrollment_id AND status = 'active');
      SELECT RAISE(ABORT, 'That check-in tool is not for the learner''s ARAL program')
      WHERE NOT EXISTS (
        SELECT 1 FROM aral_checkin_tools t JOIN aral_enrollments e ON e.id = NEW.enrollment_id
        WHERE t.id = NEW.tool_id AND t.is_active = 1 AND t.key_stage = e.key_stage AND t.track = e.track);
      SELECT RAISE(ABORT, 'A check-in cannot be dated before the learner entered ARAL')
      WHERE $notBeforeEntry;
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_aral_checkin_upd');
  await db.execute('''
    CREATE TRIGGER check_aral_checkin_upd
    BEFORE UPDATE ON aral_checkins
    WHEN OLD.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'A check-in keeps its learner, tool and attempt; only the date and notes change')
      WHERE NEW.enrollment_id IS NOT OLD.enrollment_id OR NEW.tool_id IS NOT OLD.tool_id
         OR (NEW.attempt_no IS NOT OLD.attempt_no AND OLD.attempt_no <> 0)
         OR NEW.created_by IS NOT OLD.created_by OR NEW.created_at IS NOT OLD.created_at;
      SELECT RAISE(ABORT, 'A check-in cannot be dated before the learner entered ARAL')
      WHERE NEW.taken_on IS NOT OLD.taken_on AND $notBeforeEntry;
    END
  ''');

  // Answers have no origin: these checks and the scoring run for every row
  // (mirrored rows already satisfy them), so an answer added on this device to
  // a mirrored check-in is checked and scored too.
  const itemOnTool = '''EXISTS (
        SELECT 1 FROM aral_checkin_items i JOIN aral_checkins c ON c.tool_id = i.tool_id
        WHERE i.id = NEW.item_id AND c.id = NEW.checkin_id)''';
  const itemKind = '(SELECT kind FROM aral_checkin_items WHERE id = NEW.item_id)';
  const badLetter = "$itemKind = 'choice' AND NEW.response IS NOT NULL AND NEW.response NOT GLOB '[A-E]'";
  await db.execute('DROP TRIGGER IF EXISTS check_aral_checkin_answer_ins');
  await db.execute('''
    CREATE TRIGGER check_aral_checkin_answer_ins
    BEFORE INSERT ON aral_checkin_answers
    BEGIN
      SELECT RAISE(ABORT, 'That item is not on the check-in''s tool')
      WHERE NOT $itemOnTool;
      SELECT RAISE(ABORT, 'A multiple-choice answer is a letter A-E (or empty)')
      WHERE $badLetter;
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_aral_checkin_answer_upd');
  await db.execute('''
    CREATE TRIGGER check_aral_checkin_answer_upd
    BEFORE UPDATE ON aral_checkin_answers
    BEGIN
      SELECT RAISE(ABORT, 'An answer keeps its check-in and item; only the response and mark change')
      WHERE NEW.checkin_id IS NOT OLD.checkin_id OR NEW.item_id IS NOT OLD.item_id
         OR NEW.created_at IS NOT OLD.created_at;
      SELECT RAISE(ABORT, 'A multiple-choice answer is a letter A-E (or empty)')
      WHERE $badLetter;
    END
  ''');

  // Choice items: is_correct = (response = key), as the cloud's trigger. The
  // UPDATE trigger fires on response/is_correct and writes is_correct only
  // when it is wrong, so it cannot loop.
  const score = '''
      UPDATE aral_checkin_answers
      SET is_correct = COALESCE((SELECT NEW.response = answer_key FROM aral_checkin_items WHERE id = NEW.item_id), 0)
      WHERE id = NEW.id AND $itemKind = 'choice'
        AND is_correct IS NOT COALESCE((SELECT NEW.response = answer_key FROM aral_checkin_items WHERE id = NEW.item_id), 0);''';
  await db.execute('DROP TRIGGER IF EXISTS score_aral_checkin_answer_ins');
  await db.execute('''
    CREATE TRIGGER score_aral_checkin_answer_ins
    AFTER INSERT ON aral_checkin_answers
    BEGIN
      $score
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS score_aral_checkin_answer_upd');
  await db.execute('''
    CREATE TRIGGER score_aral_checkin_answer_upd
    AFTER UPDATE OF response, is_correct ON aral_checkin_answers
    BEGIN
      $score
    END
  ''');
}
