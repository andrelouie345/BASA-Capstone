// lib/core/data/local/aral_local_schema.dart
//
// ARAL-Reading tables in the local SQLite DB (v19 roster, v20 sessions and
// attendance, v21 Foundational program + 15 per section, v22 per-tutor
// settings + one session per tutor per date). Same table and column names as
// Postgres (migrations 20261015050000_aral_enrollments.sql,
// 20261015060000_aral_sessions.sql, 20261015070000_aral_foundational_section_cap.sql,
// 20261015080000_aral_tutor_settings.sql). Called from
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

/// Same as the cloud's aral_section_cap (20261015070000).
const _sectionCap = 15;

/// v21: key_stage allows 'foundational' (no track, like KS1).
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
      tutor_id TEXT REFERENCES users(id),
      status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'exited')),
      entered_on TEXT NOT NULL,
      exited_on TEXT,
      exit_reason TEXT CHECK (exit_reason IN ('grade_level_ready', 'transferred_out', 'dropped_out', 'other')),
      basis_source TEXT NOT NULL CHECK (basis_source IN ('crla', 'phil_iri', 'manual')),
      basis_round TEXT CHECK (basis_round IN ('bosy', 'mosy', 'mosy1', 'mosy2', 'mosy3', 'eosy')),
      basis_level TEXT,
      basis_assessment_id INTEGER,   -- crla_assessments or phil_iri_assessments (by basis_source)
      suggested_key_stage TEXT CHECK (suggested_key_stage IN ('foundational', 'ks1', 'ks2', 'ks3')),
      suggested_track TEXT CHECK (suggested_track IN ('basic', 'plus')),
      notes TEXT,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      UNIQUE (student_id, school_year),
      CHECK ((key_stage IN ('foundational', 'ks1')) = (track IS NULL)),
      CHECK ((status = 'exited') = (exited_on IS NOT NULL AND exit_reason IS NOT NULL)),
      CHECK (exited_on IS NULL OR exited_on >= entered_on),
      CHECK (basis_source = 'manual' OR basis_level IS NOT NULL)
    )
  ''';

const _enrollmentColumns = 'id, student_id, school_id, section_id, school_year, key_stage, track, tutor_id, status, '
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

Future<void> createAralLocalSchema(Database db) async {
  await db.execute(_enrollmentsTableSql('aral_enrollments'));
  await db.execute('CREATE INDEX IF NOT EXISTS aral_enrollments_section ON aral_enrollments (section_id, school_year)');
  await db.execute('CREATE INDEX IF NOT EXISTS aral_enrollments_school ON aral_enrollments (school_id, school_year)');
  await db.execute('CREATE INDEX IF NOT EXISTS aral_enrollments_tutor ON aral_enrollments (tutor_id, school_year)');

  const tutorOk = '''(SELECT 1 FROM users u WHERE u.id = NEW.tutor_id AND u.role = 'tutor'
                        AND u.is_active = 1 AND u.school_id = NEW.school_id)''';

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
      SELECT RAISE(ABORT, 'The ARAL tutor must be an active tutor of the learner''s school')
      WHERE NEW.tutor_id IS NOT NULL AND NOT EXISTS $tutorOk;
      SELECT RAISE(ABORT, 'An ARAL section has at most $_sectionCap active learners')
      WHERE (SELECT count(*) FROM aral_enrollments
             WHERE section_id = NEW.section_id AND school_year = NEW.school_year AND status = 'active') >= $_sectionCap;
    END
  ''');

  await db.execute('DROP TRIGGER IF EXISTS check_aral_enrollment_upd');
  await db.execute('''
    CREATE TRIGGER check_aral_enrollment_upd
    BEFORE UPDATE ON aral_enrollments
    WHEN OLD.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'An ARAL enrollment keeps its learner, school, year and basis; only the placement, tutor, status and notes change')
      WHERE NEW.student_id IS NOT OLD.student_id OR NEW.school_id IS NOT OLD.school_id
         OR NEW.school_year IS NOT OLD.school_year OR NEW.basis_source IS NOT OLD.basis_source
         OR NEW.basis_round IS NOT OLD.basis_round OR NEW.basis_level IS NOT OLD.basis_level
         OR NEW.basis_assessment_id IS NOT OLD.basis_assessment_id
         OR NEW.suggested_key_stage IS NOT OLD.suggested_key_stage OR NEW.suggested_track IS NOT OLD.suggested_track
         OR NEW.created_by IS NOT OLD.created_by OR NEW.created_at IS NOT OLD.created_at;
      SELECT RAISE(ABORT, 'Section does not belong to that school')
      WHERE (SELECT school_id FROM sections WHERE id = NEW.section_id) IS NOT NEW.school_id;
      SELECT RAISE(ABORT, 'ARAL-Reading is for Grade 1-10 sections only')
      WHERE (SELECT grade_level FROM sections WHERE id = NEW.section_id) NOT IN $_gradeLevels;
      SELECT RAISE(ABORT, 'Learner has no enrollment in this section for that school year')
      WHERE NOT EXISTS (
        SELECT 1 FROM enrollments
        WHERE student_id = NEW.student_id AND section_id = NEW.section_id AND school_year = NEW.school_year);
      SELECT RAISE(ABORT, 'The ARAL tutor must be an active tutor of the learner''s school')
      WHERE NEW.tutor_id IS NOT NULL AND NEW.tutor_id IS NOT OLD.tutor_id AND NOT EXISTS $tutorOk;
      -- Becoming active in a section (reactivation or a move) takes a place.
      SELECT RAISE(ABORT, 'An ARAL section has at most $_sectionCap active learners')
      WHERE NEW.status = 'active'
        AND (OLD.status <> 'active' OR NEW.section_id IS NOT OLD.section_id)
        AND (SELECT count(*) FROM aral_enrollments
             WHERE section_id = NEW.section_id AND school_year = NEW.school_year AND status = 'active'
               AND id <> NEW.id) >= $_sectionCap;
    END
  ''');

  // ---- Sessions (v20): the lesson log. origin like aral_enrollments. ----
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
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud'))
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS aral_sessions_tutor ON aral_sessions (tutor_id, school_year, held_on)');
  await db.execute('CREATE INDEX IF NOT EXISTS aral_sessions_school ON aral_sessions (school_id, school_year, held_on)');

  // session_no = 0 means "assign the next number"; mirrored rows arrive with the real one.
  await db.execute('DROP TRIGGER IF EXISTS set_aral_session_no');
  await db.execute('''
    CREATE TRIGGER set_aral_session_no
    AFTER INSERT ON aral_sessions
    WHEN NEW.session_no = 0
    BEGIN
      UPDATE aral_sessions
      SET session_no = COALESCE((
        SELECT MAX(session_no) FROM aral_sessions
        WHERE tutor_id = NEW.tutor_id AND school_year = NEW.school_year AND id <> NEW.id), 0) + 1
      WHERE id = NEW.id;
    END
  ''');

  // ---- Per-tutor settings (v22): one session per date unless allowed. ----
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_tutor_settings (
      tutor_id TEXT PRIMARY KEY REFERENCES users(id),
      school_id INTEGER NOT NULL REFERENCES schools(id),
      multiple_sessions_per_day INTEGER NOT NULL DEFAULT 0 CHECK (multiple_sessions_per_day IN (0, 1)),
      updated_by TEXT REFERENCES users(id),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud'))
    )
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_aral_tutor_setting_ins');
  await db.execute('''
    CREATE TRIGGER check_aral_tutor_setting_ins
    BEFORE INSERT ON aral_tutor_settings
    WHEN NEW.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'The session tutor must be an active tutor of the school')
      WHERE NOT EXISTS $tutorOk;
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_aral_tutor_setting_upd');
  await db.execute('''
    CREATE TRIGGER check_aral_tutor_setting_upd
    BEFORE UPDATE ON aral_tutor_settings
    WHEN NEW.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'An ARAL tutor setting keeps its tutor and school')
      WHERE NEW.tutor_id IS NOT OLD.tutor_id OR NEW.school_id IS NOT OLD.school_id;
    END
  ''');

  const sessionTutorOk = '''(SELECT 1 FROM users u WHERE u.id = NEW.tutor_id AND u.role = 'tutor'
                        AND u.is_active = 1 AND u.school_id = NEW.school_id)''';
  const oneDayOnly = '''NOT COALESCE((SELECT multiple_sessions_per_day FROM aral_tutor_settings
                                      WHERE tutor_id = NEW.tutor_id), 0)''';
  const dayTaken = 'This tutor already has an ARAL session on that date (a coordinator can allow several per day)';
  await db.execute('DROP TRIGGER IF EXISTS check_aral_session_ins');
  await db.execute('''
    CREATE TRIGGER check_aral_session_ins
    BEFORE INSERT ON aral_sessions
    WHEN NEW.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'The session tutor must be an active tutor of the school')
      WHERE NOT EXISTS $sessionTutorOk;
      SELECT RAISE(ABORT, '$dayTaken')
      WHERE $oneDayOnly
        AND EXISTS (SELECT 1 FROM aral_sessions WHERE tutor_id = NEW.tutor_id AND held_on = NEW.held_on);
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_aral_session_upd');
  await db.execute('''
    CREATE TRIGGER check_aral_session_upd
    BEFORE UPDATE ON aral_sessions
    WHEN OLD.origin = 'local'
    BEGIN
      SELECT RAISE(ABORT, 'An ARAL session keeps its tutor, school, year and number; only the date, minutes, set-up, lesson and remarks change')
      WHERE NEW.tutor_id IS NOT OLD.tutor_id OR NEW.school_id IS NOT OLD.school_id
         OR NEW.school_year IS NOT OLD.school_year
         OR (NEW.session_no IS NOT OLD.session_no AND OLD.session_no <> 0)
         OR NEW.created_by IS NOT OLD.created_by OR NEW.created_at IS NOT OLD.created_at;
      SELECT RAISE(ABORT, '$dayTaken')
      WHERE NEW.held_on IS NOT OLD.held_on AND $oneDayOnly
        AND EXISTS (SELECT 1 FROM aral_sessions
                    WHERE tutor_id = NEW.tutor_id AND held_on = NEW.held_on AND id <> NEW.id);
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
}
