// lib/core/data/local/aral_local_schema.dart
//
// ARAL-Reading tables in the local SQLite DB (v19). Same table and column names
// as Postgres (migration 20261015050000_aral_enrollments.sql). Called from
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

Future<void> createAralLocalSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS aral_enrollments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id INTEGER NOT NULL REFERENCES students(id),
      school_id INTEGER NOT NULL REFERENCES schools(id),
      section_id INTEGER NOT NULL REFERENCES sections(id),
      school_year TEXT NOT NULL
        CHECK (school_year GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
               AND CAST(substr(school_year, 6, 4) AS INTEGER) = CAST(substr(school_year, 1, 4) AS INTEGER) + 1),
      key_stage TEXT NOT NULL CHECK (key_stage IN ('ks1', 'ks2', 'ks3')),
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
      suggested_key_stage TEXT CHECK (suggested_key_stage IN ('ks1', 'ks2', 'ks3')),
      suggested_track TEXT CHECK (suggested_track IN ('basic', 'plus')),
      notes TEXT,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      UNIQUE (student_id, school_year),
      CHECK ((key_stage = 'ks1') = (track IS NULL)),
      CHECK ((status = 'exited') = (exited_on IS NOT NULL AND exit_reason IS NOT NULL)),
      CHECK (exited_on IS NULL OR exited_on >= entered_on),
      CHECK (basis_source = 'manual' OR basis_level IS NOT NULL)
    )
  ''');
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
    END
  ''');
}
