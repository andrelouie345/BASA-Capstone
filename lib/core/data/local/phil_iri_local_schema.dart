// lib/core/data/local/phil_iri_local_schema.dart
//
// Phil-IRI tables in the local SQLite DB (v13). Same table and column names
// as Postgres (migrations 20261014000000/010000/020000). Called from
// LocalDatabase on create and, unconditionally, on upgrade: everything here
// is IF NOT EXISTS, and triggers are dropped and recreated.
//
// - Content (collections, rubric criteria, passages, questions, thresholds)
//   is mirror-only: it is managed online and copied down, so it has the
//   cloud's CHECKs but no triggers.
// - phil_iri_gst_results and phil_iri_assessments carry the local-only
//   `origin` column like crla_assessments: 'local' = entered on this device,
//   not uploaded; 'cloud' = mirrored. The cloud's rules are re-checked here
//   only for local rows (and their children); mirrored rows were checked there.
// - SQLite differences: attempt_no is assigned AFTER INSERT when sent as 0;
//   is_correct is computed AFTER INSERT/UPDATE; the repository supplies
//   completed_at / finalized_at (the cloud re-stamps them on upload).
//   Role checks (who may finalize) live in the ViewModel. Deletes are not
//   guarded here so pull-cloud can still clear the tables; the ViewModel
//   only discards in-progress sessions. Local FKs are off, so a repository
//   deleting a session must delete its children too.
import 'package:sqflite_common/sqflite.dart';

const _gradeLevels = "('4', '5', '6', '7', '8', '9', '10')";

/// Valid YYYY-YYYY with consecutive years, as the cloud CHECK.
String _schoolYearCheck(String column) => '''
  CHECK ($column GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
         AND CAST(substr($column, 6, 4) AS INTEGER) = CAST(substr($column, 1, 4) AS INTEGER) + 1)''';

Future<void> createPhilIriLocalSchema(Database db) async {
  // ---- Content (mirror-only) ----
  await db.execute('''
    CREATE TABLE IF NOT EXISTS phil_iri_collections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      school_id INTEGER REFERENCES schools(id),
      name TEXT NOT NULL,
      description TEXT,
      is_prescribed INTEGER NOT NULL DEFAULT 0,
      is_grade_leveled INTEGER NOT NULL DEFAULT 1,
      has_comprehension INTEGER NOT NULL DEFAULT 1,
      reading_order TEXT,            -- JSON array
      is_active INTEGER NOT NULL DEFAULT 1,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      CHECK (NOT is_prescribed OR school_id IS NULL)
    )
  ''');
  await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS phil_iri_collections_name_key
    ON phil_iri_collections (IFNULL(school_id, 0), lower(name))
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS phil_iri_rubric_criteria (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      collection_id INTEGER NOT NULL REFERENCES phil_iri_collections(id),
      criterion_no INTEGER NOT NULL CHECK (criterion_no > 0),
      name TEXT NOT NULL,
      scale_min INTEGER NOT NULL DEFAULT 1,
      scale_max INTEGER NOT NULL,
      CHECK (scale_min < scale_max),
      UNIQUE (collection_id, criterion_no)
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS phil_iri_passages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      collection_id INTEGER NOT NULL REFERENCES phil_iri_collections(id),
      language TEXT NOT NULL DEFAULT 'English' CHECK (language = 'English'),
      test_type TEXT CHECK (test_type IN ('pre', 'post')),
      set_code TEXT,
      level INTEGER CHECK (level BETWEEN 1 AND 12),
      selection_no INTEGER CHECK (selection_no > 0),
      title TEXT NOT NULL,
      motivation TEXT,
      body TEXT NOT NULL,
      word_count INTEGER NOT NULL CHECK (word_count > 0),
      is_active INTEGER NOT NULL DEFAULT 1,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS phil_iri_questions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      passage_id INTEGER NOT NULL REFERENCES phil_iri_passages(id),
      question_no INTEGER NOT NULL CHECK (question_no > 0),
      question_type TEXT CHECK (question_type IN ('L', 'I', 'C')),
      prompt TEXT NOT NULL,
      choices TEXT NOT NULL,          -- JSON array, 2+ items
      answer_key TEXT NOT NULL CHECK (length(answer_key) = 1 AND answer_key BETWEEN 'a' AND 'z'),
      UNIQUE (passage_id, question_no)
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS phil_iri_thresholds (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      school_id INTEGER REFERENCES schools(id),
      settings TEXT NOT NULL,         -- JSON object (PhilIriThresholds.toMap)
      updated_by TEXT REFERENCES users(id),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  ''');
  await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS phil_iri_thresholds_school_key
    ON phil_iri_thresholds (IFNULL(school_id, 0))
  ''');

  // ---- GST results ----
  await db.execute('''
    CREATE TABLE IF NOT EXISTS phil_iri_gst_results (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id INTEGER NOT NULL REFERENCES students(id),
      school_id INTEGER NOT NULL REFERENCES schools(id),
      section_id INTEGER NOT NULL REFERENCES sections(id),
      school_year TEXT NOT NULL ${_schoolYearCheck('school_year')},
      attempt_no INTEGER NOT NULL DEFAULT 0 CHECK (attempt_no >= 0),
      max_score INTEGER NOT NULL CHECK (max_score IN (20, 40)),
      total_score INTEGER NOT NULL,
      literal_correct INTEGER CHECK (literal_correct >= 0),
      inferential_correct INTEGER CHECK (inferential_correct >= 0),
      critical_correct INTEGER CHECK (critical_correct >= 0),
      taken_at TEXT NOT NULL,
      administered_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      CHECK (total_score BETWEEN 0 AND max_score),
      CHECK (literal_correct IS NULL OR inferential_correct IS NULL OR critical_correct IS NULL
             OR literal_correct + inferential_correct + critical_correct = total_score),
      UNIQUE (student_id, school_id, section_id, school_year, attempt_no)
    )
  ''');

  // Shared target rule (cloud insert policy): Grade 4-10 section of that
  // school, learner actively enrolled in it for that year.
  const targetCheck = '''
      SELECT RAISE(ABORT, 'No such section')
      WHERE NOT EXISTS (SELECT 1 FROM sections WHERE id = NEW.section_id);
      SELECT RAISE(ABORT, 'Phil-IRI is for Grade 4-10 sections only')
      WHERE (SELECT grade_level FROM sections WHERE id = NEW.section_id) NOT IN $_gradeLevels;
      SELECT RAISE(ABORT, 'Section does not belong to that school')
      WHERE (SELECT school_id FROM sections WHERE id = NEW.section_id) IS NOT NEW.school_id;
      SELECT RAISE(ABORT, 'Learner has no active enrollment in this section for that school year')
      WHERE NOT EXISTS (
        SELECT 1 FROM enrollments
        WHERE student_id = NEW.student_id AND section_id = NEW.section_id
          AND school_year = NEW.school_year AND status = 'active');''';

  await db.execute('DROP TRIGGER IF EXISTS check_phil_iri_gst_target');
  await db.execute('''
    CREATE TRIGGER check_phil_iri_gst_target
    BEFORE INSERT ON phil_iri_gst_results
    WHEN NEW.origin = 'local'
    BEGIN
      $targetCheck
      SELECT RAISE(ABORT, 'The GST for Grades 4-6 is out of 20, for Grades 7-10 out of 40')
      WHERE NEW.max_score <> CASE
        WHEN CAST((SELECT grade_level FROM sections WHERE id = NEW.section_id) AS INTEGER) >= 7
        THEN 40 ELSE 20 END;
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS set_phil_iri_gst_attempt_no');
  await db.execute('''
    CREATE TRIGGER set_phil_iri_gst_attempt_no
    AFTER INSERT ON phil_iri_gst_results
    WHEN NEW.attempt_no = 0
    BEGIN
      UPDATE phil_iri_gst_results
      SET attempt_no = COALESCE((
        SELECT MAX(attempt_no) FROM phil_iri_gst_results
        WHERE student_id = NEW.student_id AND school_id = NEW.school_id
          AND section_id = NEW.section_id AND school_year = NEW.school_year
          AND id <> NEW.id), 0) + 1
      WHERE id = NEW.id;
    END
  ''');
  // GST results are never edited (a retake is a new row), like the cloud.
  await db.execute('DROP TRIGGER IF EXISTS lock_phil_iri_gst_results');
  await db.execute('''
    CREATE TRIGGER lock_phil_iri_gst_results
    BEFORE UPDATE ON phil_iri_gst_results
    WHEN OLD.origin = 'local' AND NEW.origin = 'local'
         AND NOT (OLD.attempt_no = 0 AND NEW.attempt_no > 0)
    BEGIN
      SELECT RAISE(ABORT, 'GST results are not edited; record a retake instead');
    END
  ''');

  // ---- Assessment sessions ----
  await db.execute('''
    CREATE TABLE IF NOT EXISTS phil_iri_assessments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id INTEGER NOT NULL REFERENCES students(id),
      school_id INTEGER NOT NULL REFERENCES schools(id),
      section_id INTEGER NOT NULL REFERENCES sections(id),
      school_year TEXT NOT NULL ${_schoolYearCheck('school_year')},
      attempt_no INTEGER NOT NULL DEFAULT 0 CHECK (attempt_no >= 0),
      round TEXT NOT NULL CHECK (round IN ('bosy', 'mosy1', 'mosy2', 'mosy3', 'eosy')),
      status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'finalized')),
      assessed_at TEXT NOT NULL,
      completed_at TEXT,
      finalized_at TEXT,
      administered_by TEXT REFERENCES users(id),
      thresholds_snapshot TEXT,       -- JSON object, set at finalization
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      origin TEXT NOT NULL DEFAULT 'local' CHECK (origin IN ('local', 'cloud')),
      CHECK ((status = 'finalized') = (finalized_at IS NOT NULL AND thresholds_snapshot IS NOT NULL)),
      UNIQUE (student_id, school_id, section_id, round, school_year, attempt_no)
    )
  ''');

  await db.execute('DROP TRIGGER IF EXISTS check_phil_iri_assessment_target');
  await db.execute('''
    CREATE TRIGGER check_phil_iri_assessment_target
    BEFORE INSERT ON phil_iri_assessments
    WHEN NEW.origin = 'local'
    BEGIN
      $targetCheck
      SELECT RAISE(ABORT, 'A new Phil-IRI session starts in progress')
      WHERE NEW.status <> 'in_progress' OR NEW.thresholds_snapshot IS NOT NULL;
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS set_phil_iri_assessment_attempt_no');
  await db.execute('''
    CREATE TRIGGER set_phil_iri_assessment_attempt_no
    AFTER INSERT ON phil_iri_assessments
    WHEN NEW.attempt_no = 0
    BEGIN
      UPDATE phil_iri_assessments
      SET attempt_no = COALESCE((
        SELECT MAX(attempt_no) FROM phil_iri_assessments
        WHERE student_id = NEW.student_id AND school_id = NEW.school_id
          AND section_id = NEW.section_id AND round = NEW.round
          AND school_year = NEW.school_year AND id <> NEW.id), 0) + 1
      WHERE id = NEW.id;
    END
  ''');
  // Lifecycle for local sessions (cloud trigger phil_iri_assessments_before_update).
  // The attempt_no assignment above is the one other update allowed.
  await db.execute('DROP TRIGGER IF EXISTS check_phil_iri_assessment_update');
  await db.execute('''
    CREATE TRIGGER check_phil_iri_assessment_update
    BEFORE UPDATE ON phil_iri_assessments
    WHEN OLD.origin = 'local' AND NEW.origin = 'local'
         AND NOT (OLD.attempt_no = 0 AND NEW.attempt_no > 0)
    BEGIN
      SELECT RAISE(ABORT, 'A finalized Phil-IRI assessment cannot be changed')
      WHERE OLD.status = 'finalized';
      SELECT RAISE(ABORT, 'Only the status of a Phil-IRI assessment can change')
      WHERE NEW.student_id IS NOT OLD.student_id OR NEW.school_id IS NOT OLD.school_id
         OR NEW.section_id IS NOT OLD.section_id OR NEW.school_year IS NOT OLD.school_year
         OR NEW.round IS NOT OLD.round OR NEW.attempt_no IS NOT OLD.attempt_no
         OR NEW.administered_by IS NOT OLD.administered_by OR NEW.assessed_at IS NOT OLD.assessed_at;
      SELECT RAISE(ABORT, 'Only a completed Phil-IRI assessment can be finalized')
      WHERE NEW.status = 'finalized' AND OLD.status <> 'completed';
    END
  ''');

  // ---- Readings ----
  await db.execute('''
    CREATE TABLE IF NOT EXISTS phil_iri_readings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      assessment_id INTEGER NOT NULL REFERENCES phil_iri_assessments(id),
      sequence_no INTEGER NOT NULL CHECK (sequence_no > 0),
      passage_id INTEGER NOT NULL REFERENCES phil_iri_passages(id),
      method TEXT NOT NULL DEFAULT 'whole_text' CHECK (method IN ('whole_text', 'one_minute')),
      reading_seconds INTEGER CHECK (reading_seconds > 0),
      words_read INTEGER CHECK (words_read > 0),
      obs_word_by_word INTEGER NOT NULL DEFAULT 0,
      obs_lacks_expression INTEGER NOT NULL DEFAULT 0,
      obs_voice_inaudible INTEGER NOT NULL DEFAULT 0,
      obs_disregards_punctuation INTEGER NOT NULL DEFAULT 0,
      obs_points_to_words INTEGER NOT NULL DEFAULT 0,
      obs_little_analysis INTEGER NOT NULL DEFAULT 0,
      obs_other TEXT,
      word_reading_score REAL CHECK (word_reading_score BETWEEN 0 AND 1),
      words_per_minute REAL CHECK (words_per_minute >= 0),
      accuracy_level TEXT CHECK (accuracy_level IN ('independent', 'instructional', 'frustration', 'nonReader')),
      speed TEXT CHECK (speed IN ('struggling', 'slow', 'average', 'fast')),
      word_reading_level TEXT CHECK (word_reading_level IN ('independent', 'instructional', 'frustration', 'nonReader')),
      comprehension_score REAL CHECK (comprehension_score BETWEEN 0 AND 1),
      comprehension_level TEXT CHECK (comprehension_level IN ('independent', 'instructional', 'frustration')),
      profile TEXT CHECK (profile IN ('independent', 'instructional', 'frustration', 'nonReader')),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (assessment_id, sequence_no),
      CHECK ((method = 'whole_text' AND words_read IS NULL)
             OR (method = 'one_minute' AND reading_seconds IS NULL))
    )
  ''');

  // "Is the parent session a local one that is not finalized?" helpers.
  const sessionOrigin = "(SELECT origin FROM phil_iri_assessments WHERE id = NEW.assessment_id)";
  const sessionStatus = "(SELECT status FROM phil_iri_assessments WHERE id = NEW.assessment_id)";
  const readingOrigin = '''(SELECT a.origin FROM phil_iri_readings r
      JOIN phil_iri_assessments a ON a.id = r.assessment_id WHERE r.id = NEW.reading_id)''';
  const readingStatus = '''(SELECT a.status FROM phil_iri_readings r
      JOIN phil_iri_assessments a ON a.id = r.assessment_id WHERE r.id = NEW.reading_id)''';
  const finalizedMsg = "'This Phil-IRI assessment is finalized and cannot be changed'";

  await db.execute('DROP TRIGGER IF EXISTS check_phil_iri_reading_ins');
  await db.execute('''
    CREATE TRIGGER check_phil_iri_reading_ins
    BEFORE INSERT ON phil_iri_readings
    WHEN $sessionOrigin = 'local'
    BEGIN
      SELECT RAISE(ABORT, $finalizedMsg) WHERE $sessionStatus = 'finalized';
      SELECT RAISE(ABORT, 'No such passage')
      WHERE NOT EXISTS (SELECT 1 FROM phil_iri_passages WHERE id = NEW.passage_id);
      SELECT RAISE(ABORT, 'This passage or its collection is not active')
      WHERE (SELECT p.is_active AND c.is_active FROM phil_iri_passages p
             JOIN phil_iri_collections c ON c.id = p.collection_id WHERE p.id = NEW.passage_id) = 0;
      SELECT RAISE(ABORT, 'A learner reads a passage of their own grade')
      WHERE (SELECT c.is_grade_leveled FROM phil_iri_passages p
             JOIN phil_iri_collections c ON c.id = p.collection_id WHERE p.id = NEW.passage_id) = 1
        AND (SELECT level FROM phil_iri_passages WHERE id = NEW.passage_id) IS NOT
            (SELECT CAST(s.grade_level AS INTEGER) FROM phil_iri_assessments a
             JOIN sections s ON s.id = a.section_id WHERE a.id = NEW.assessment_id);
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_phil_iri_reading_upd');
  await db.execute('''
    CREATE TRIGGER check_phil_iri_reading_upd
    BEFORE UPDATE ON phil_iri_readings
    WHEN (SELECT origin FROM phil_iri_assessments WHERE id = OLD.assessment_id) = 'local'
    BEGIN
      SELECT RAISE(ABORT, $finalizedMsg)
      WHERE (SELECT status FROM phil_iri_assessments WHERE id = OLD.assessment_id) = 'finalized';
      SELECT RAISE(ABORT, 'A reading keeps its session and passage; delete it and add a new one instead')
      WHERE NEW.assessment_id IS NOT OLD.assessment_id OR NEW.passage_id IS NOT OLD.passage_id;
    END
  ''');

  // ---- Miscues ----
  await db.execute('''
    CREATE TABLE IF NOT EXISTS phil_iri_miscues (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reading_id INTEGER NOT NULL REFERENCES phil_iri_readings(id),
      word_index INTEGER NOT NULL CHECK (word_index >= 0),
      miscue_type TEXT NOT NULL CHECK (miscue_type IN ('mispronunciation', 'omission', 'substitution',
        'insertion', 'repetition', 'transposition', 'reversal')),
      spoken_text TEXT,
      self_corrected INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS phil_iri_miscues_reading ON phil_iri_miscues (reading_id)');

  const miscueCheck = '''
      SELECT RAISE(ABORT, $finalizedMsg) WHERE $readingStatus = 'finalized';
      SELECT RAISE(ABORT, 'Word position is outside the passage')
      WHERE NEW.word_index > (SELECT p.word_count FROM phil_iri_readings r
                              JOIN phil_iri_passages p ON p.id = r.passage_id WHERE r.id = NEW.reading_id)
         OR (NEW.miscue_type <> 'insertion'
             AND NEW.word_index >= (SELECT p.word_count FROM phil_iri_readings r
                                    JOIN phil_iri_passages p ON p.id = r.passage_id WHERE r.id = NEW.reading_id));''';
  for (final op in ['INSERT', 'UPDATE']) {
    final name = 'check_phil_iri_miscue_${op.toLowerCase()}';
    await db.execute('DROP TRIGGER IF EXISTS $name');
    await db.execute('''
      CREATE TRIGGER $name
      BEFORE $op ON phil_iri_miscues
      WHEN $readingOrigin = 'local'
      BEGIN $miscueCheck END
    ''');
  }

  // ---- Answers ----
  await db.execute('''
    CREATE TABLE IF NOT EXISTS phil_iri_answers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reading_id INTEGER NOT NULL REFERENCES phil_iri_readings(id),
      question_id INTEGER NOT NULL REFERENCES phil_iri_questions(id),
      chosen TEXT CHECK (chosen IS NULL OR (length(chosen) = 1 AND chosen BETWEEN 'a' AND 'z')),
      is_correct INTEGER NOT NULL DEFAULT 0,
      looked_back INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (reading_id, question_id)
    )
  ''');

  const answerCheck = '''
      SELECT RAISE(ABORT, $finalizedMsg) WHERE $readingStatus = 'finalized';
      SELECT RAISE(ABORT, 'That question is not a question of this reading''s passage')
      WHERE (SELECT passage_id FROM phil_iri_questions WHERE id = NEW.question_id) IS NOT
            (SELECT passage_id FROM phil_iri_readings WHERE id = NEW.reading_id);''';
  for (final op in ['INSERT', 'UPDATE']) {
    final name = 'check_phil_iri_answer_${op.toLowerCase()}';
    await db.execute('DROP TRIGGER IF EXISTS $name');
    await db.execute('''
      CREATE TRIGGER $name
      BEFORE $op ON phil_iri_answers
      WHEN $readingOrigin = 'local'
      BEGIN $answerCheck END
    ''');
  }
  // is_correct from the key; a client value is ignored (cloud trigger does the same).
  const answerCompute = '''
      UPDATE phil_iri_answers
      SET is_correct = CASE WHEN NEW.chosen IS NOT NULL
                             AND NEW.chosen = (SELECT answer_key FROM phil_iri_questions WHERE id = NEW.question_id)
                            THEN 1 ELSE 0 END
      WHERE id = NEW.id;''';
  await db.execute('DROP TRIGGER IF EXISTS compute_phil_iri_answer_ins');
  await db.execute('''
    CREATE TRIGGER compute_phil_iri_answer_ins
    AFTER INSERT ON phil_iri_answers
    WHEN $readingOrigin = 'local'
    BEGIN $answerCompute END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS compute_phil_iri_answer_upd');
  await db.execute('''
    CREATE TRIGGER compute_phil_iri_answer_upd
    AFTER UPDATE OF chosen, question_id, is_correct ON phil_iri_answers
    WHEN $readingOrigin = 'local'
      AND NEW.is_correct IS NOT CASE WHEN NEW.chosen IS NOT NULL
              AND NEW.chosen = (SELECT answer_key FROM phil_iri_questions WHERE id = NEW.question_id)
              THEN 1 ELSE 0 END
    BEGIN $answerCompute END
  ''');

  // ---- Rubric scores ----
  await db.execute('''
    CREATE TABLE IF NOT EXISTS phil_iri_rubric_scores (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      assessment_id INTEGER NOT NULL REFERENCES phil_iri_assessments(id),
      criterion_id INTEGER NOT NULL REFERENCES phil_iri_rubric_criteria(id),
      score INTEGER NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (assessment_id, criterion_id)
    )
  ''');
  const rubricCheck = '''
      SELECT RAISE(ABORT, $finalizedMsg) WHERE $sessionStatus = 'finalized';
      SELECT RAISE(ABORT, 'Score is outside the rubric scale')
      WHERE NEW.score < (SELECT scale_min FROM phil_iri_rubric_criteria WHERE id = NEW.criterion_id)
         OR NEW.score > (SELECT scale_max FROM phil_iri_rubric_criteria WHERE id = NEW.criterion_id);''';
  for (final op in ['INSERT', 'UPDATE']) {
    final name = 'check_phil_iri_rubric_score_${op.toLowerCase()}';
    await db.execute('DROP TRIGGER IF EXISTS $name');
    await db.execute('''
      CREATE TRIGGER $name
      BEFORE $op ON phil_iri_rubric_scores
      WHEN $sessionOrigin = 'local'
      BEGIN $rubricCheck END
    ''');
  }
}
