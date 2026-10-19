// lib/core/data/local/srp_local_schema.dart
import 'package:sqflite_common/sqflite.dart';

/// v30: SRP classes and their learners, mirror-only like the ARAL material
/// catalog: written online, same CHECKs and unique keys as the cloud, no
/// triggers (the cloud's tutor and enrollment rules are not repeated here).
/// IF NOT EXISTS, so it runs on every create and upgrade.
Future<void> createSrpLocalSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS srp_classes (
      id INTEGER PRIMARY KEY,
      school_id INTEGER NOT NULL REFERENCES schools(id),
      school_year TEXT NOT NULL,
      assessed_grade INTEGER NOT NULL CHECK (assessed_grade BETWEEN 0 AND 12),
      class_name TEXT NOT NULL CHECK (length(trim(class_name)) > 0),
      room TEXT,
      schedule TEXT,
      tutor_id TEXT REFERENCES users(id),
      created_by TEXT,
      created_at TEXT,
      updated_at TEXT
    )
  ''');
  await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS srp_classes_name_key '
      'ON srp_classes (school_id, school_year, lower(class_name))');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS srp_class_members (
      id INTEGER PRIMARY KEY,
      class_id INTEGER NOT NULL REFERENCES srp_classes(id),
      student_id INTEGER NOT NULL REFERENCES students(id),
      school_year TEXT NOT NULL,
      created_at TEXT,
      UNIQUE (student_id, school_year)
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS srp_class_members_class ON srp_class_members (class_id)');
}
