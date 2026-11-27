// lib/core/data/local/crla_local_schema.dart
//
// Digitized CRLA on the device (SQLite v51, cloud 20261127010000; spec
// docs/superpowers/specs/2026-11-27-crla-digitized-design.md).
// - Content (pull mirror only): crla_stories.body, crla_part1_items,
//   crla_story_questions.
// - Evidence (synced children of crla_assessments): crla_part1_marks,
//   crla_part2_word_marks, crla_part2_answers, crla_timer_events; and
//   crla_part2_fluency.last_word_reached.
// Rows made on this device (row_version NULL) follow the same rules as
// services/crla_digitized.dart + services/reading_timer.dart and the server's
// triggers / crla_digitized_problem: change the three together. Pulled rows
// are the server's and are not re-checked. Called from onCreate and on every
// upgrade (IF NOT EXISTS, triggers recreated), before createSyncLocalSchema.
import 'package:sqflite_common/sqflite.dart';

Future<void> _addColumn(DatabaseExecutor db, String table, String column, String type) async {
  final cols = {for (final c in await db.rawQuery('PRAGMA table_info($table)')) c['name']};
  if (!cols.contains(column)) await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
}

Future<void> createCrlaDigitizedLocalSchema(DatabaseExecutor db) async {
  // ---- Content ----
  await _addColumn(db, 'crla_stories', 'body', 'TEXT');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS crla_part1_items (
      id INTEGER PRIMARY KEY,
      region_id INTEGER NOT NULL,
      language TEXT NOT NULL,
      grade INTEGER NOT NULL,
      task TEXT NOT NULL CHECK (task IN ('task1', 'task2_low', 'task2_high', 'task2')),
      item_no INTEGER NOT NULL,
      text TEXT NOT NULL,
      sentence_no INTEGER,
      answer_key TEXT,
      UNIQUE (region_id, language, grade, task, item_no)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS crla_story_questions (
      id INTEGER PRIMARY KEY,
      story_id INTEGER NOT NULL REFERENCES crla_stories(id),
      question_no INTEGER NOT NULL,
      after_sentence INTEGER NOT NULL,
      question TEXT NOT NULL,
      accepted_answers TEXT NOT NULL,
      UNIQUE (story_id, question_no)
    )
  ''');

  // ---- Evidence ----
  await _addColumn(db, 'crla_part2_fluency', 'last_word_reached', 'INTEGER CHECK (last_word_reached >= 0)');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS crla_part1_marks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      assessment_id INTEGER NOT NULL REFERENCES crla_assessments(id),
      task TEXT NOT NULL CHECK (task IN ('task1', 'task2_low', 'task2_high', 'task2')),
      item_no INTEGER NOT NULL CHECK (item_no >= 1),
      correct INTEGER NOT NULL,
      self_corrected INTEGER NOT NULL DEFAULT 0,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (assessment_id, task, item_no)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS crla_part2_word_marks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      assessment_id INTEGER NOT NULL REFERENCES crla_assessments(id),
      story_no INTEGER NOT NULL CHECK (story_no IN (1, 2)),
      word_index INTEGER NOT NULL CHECK (word_index >= 0),
      kind TEXT NOT NULL CHECK (kind IN ('miscue', 'self_corrected')),
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (assessment_id, word_index)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS crla_part2_answers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      assessment_id INTEGER NOT NULL REFERENCES crla_assessments(id),
      story_no INTEGER NOT NULL CHECK (story_no IN (1, 2)),
      question_no INTEGER NOT NULL CHECK (question_no >= 1),
      mark TEXT NOT NULL CHECK (mark IN ('correct', 'incorrect', 'not_asked')),
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (assessment_id, question_no)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS crla_timer_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      assessment_id INTEGER NOT NULL REFERENCES crla_assessments(id),
      story_no INTEGER NOT NULL CHECK (story_no IN (1, 2)),
      seq INTEGER NOT NULL CHECK (seq >= 1),
      kind TEXT NOT NULL CHECK (kind IN ('start', 'pause', 'resume', 'stop', 'reset')),
      at TEXT NOT NULL,
      created_by TEXT REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (assessment_id, seq)
    )
  ''');
  for (final t in ['crla_part1_marks', 'crla_part2_word_marks', 'crla_part2_answers', 'crla_timer_events']) {
    await db.execute('CREATE INDEX IF NOT EXISTS ${t}_assessment ON $t (assessment_id)');
  }

  // Part 1: Task 2 only as Task 1 leads (crlaTask2For).
  const variant = '(SELECT subject_variant FROM crla_assessments WHERE id = NEW.assessment_id)';
  const task1 = '''(SELECT count(*) FROM crla_part1_marks WHERE assessment_id = NEW.assessment_id
                    AND task = 'task1' AND (correct = 1 OR self_corrected = 1))''';
  await db.execute('DROP TRIGGER IF EXISTS check_crla_part1_mark');
  await db.execute('''
    CREATE TRIGGER check_crla_part1_mark
    BEFORE INSERT ON crla_part1_marks
    WHEN NEW.row_version IS NULL AND NEW.task <> 'task1'
    BEGIN
      SELECT RAISE(ABORT, 'Task 1 is 0: the test ends here.')
      WHERE $variant = 'eng' AND $task1 = 0;
      SELECT RAISE(ABORT, 'This Task 2 is not the one Task 1 leads to.')
      WHERE ($variant = 'eng' AND NEW.task <> 'task2')
         OR ($variant <> 'eng' AND NEW.task <> CASE WHEN $task1 < 7 THEN 'task2_low' ELSE 'task2_high' END);
    END
  ''');

  // Part 2: one story per attempt; no word marked after the last word reached.
  const otherStory = '''EXISTS (
        SELECT 1 FROM crla_part2_word_marks WHERE assessment_id = NEW.assessment_id AND story_no <> NEW.story_no
        UNION ALL SELECT 1 FROM crla_part2_answers WHERE assessment_id = NEW.assessment_id AND story_no <> NEW.story_no
        UNION ALL SELECT 1 FROM crla_timer_events WHERE assessment_id = NEW.assessment_id AND story_no <> NEW.story_no
        UNION ALL SELECT 1 FROM crla_part2_fluency WHERE assessment_id = NEW.assessment_id AND story_no <> NEW.story_no)''';
  const otherStoryMsg = "'This attempt is marked on its other story.'";
  await db.execute('DROP TRIGGER IF EXISTS check_crla_word_mark');
  await db.execute('''
    CREATE TRIGGER check_crla_word_mark
    BEFORE INSERT ON crla_part2_word_marks
    WHEN NEW.row_version IS NULL
    BEGIN
      SELECT RAISE(ABORT, $otherStoryMsg) WHERE $otherStory;
      SELECT RAISE(ABORT, 'That word is after the last word reached.')
      WHERE NEW.word_index > (SELECT last_word_reached FROM crla_part2_fluency WHERE assessment_id = NEW.assessment_id);
    END
  ''');
  await db.execute('DROP TRIGGER IF EXISTS check_crla_answer');
  await db.execute('''
    CREATE TRIGGER check_crla_answer
    BEFORE INSERT ON crla_part2_answers
    WHEN NEW.row_version IS NULL
    BEGIN
      SELECT RAISE(ABORT, $otherStoryMsg) WHERE $otherStory;
    END
  ''');

  // The timer: the shared reading-timer rules (reading_timer.dart).
  const lastKind = '''(SELECT kind FROM crla_timer_events
      WHERE assessment_id = NEW.assessment_id ORDER BY seq DESC LIMIT 1)''';
  await db.execute('DROP TRIGGER IF EXISTS check_crla_timer_event');
  await db.execute('''
    CREATE TRIGGER check_crla_timer_event
    BEFORE INSERT ON crla_timer_events
    WHEN NEW.row_version IS NULL
    BEGIN
      SELECT RAISE(ABORT, $otherStoryMsg) WHERE $otherStory;
      SELECT RAISE(ABORT, 'This time is earlier than the timer''s last tap; check the device clock.')
      WHERE NEW.kind <> 'reset'
        AND julianday(NEW.at) < (SELECT max(julianday(at)) FROM crla_timer_events
                                 WHERE assessment_id = NEW.assessment_id
                                   AND seq > coalesce((SELECT max(seq) FROM crla_timer_events
                                                       WHERE assessment_id = NEW.assessment_id AND kind = 'reset'), 0));
      SELECT RAISE(ABORT, 'The timer is already started.')
      WHERE NEW.kind = 'start' AND $lastKind IS NOT NULL AND $lastKind <> 'reset';
      SELECT RAISE(ABORT, 'Start the timer first.')
      WHERE NEW.kind IN ('pause', 'stop') AND ($lastKind IS NULL OR $lastKind = 'reset');
      SELECT RAISE(ABORT, 'The timer is already paused.')
      WHERE NEW.kind = 'pause' AND $lastKind = 'pause';
      SELECT RAISE(ABORT, 'The timer is already stopped.')
      WHERE NEW.kind IN ('pause', 'stop') AND $lastKind = 'stop';
      SELECT RAISE(ABORT, 'The timer is not paused.')
      WHERE NEW.kind = 'resume' AND $lastKind IS NOT 'pause';
      SELECT RAISE(ABORT, 'Start the timer before restarting it.')
      WHERE NEW.kind = 'reset' AND ($lastKind IS NULL OR $lastKind = 'reset');
      SELECT RAISE(ABORT, 'A timer tap must follow the attempt''s last tap (seq)')
      WHERE NEW.seq <> coalesce((SELECT max(seq) FROM crla_timer_events
                                 WHERE assessment_id = NEW.assessment_id), 0) + 1;
    END
  ''');
}
