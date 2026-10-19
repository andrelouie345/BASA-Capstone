// lib/core/data/local/tutor_assignment_local_schema.dart
import 'package:sqflite_common/sqflite.dart';

/// v33: tutor <-> section assignments (tutor_section_assignments), mirror-only:
/// written online by an admin/coordinator, copied by pull-cloud and mirrored on
/// assign/unassign, so tutor reminders (dashboard D3) know a tutor's sections
/// offline. Same unique key as the cloud, no triggers. IF NOT EXISTS, so it
/// runs on every create and upgrade.
Future<void> createTutorAssignmentLocalSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS tutor_section_assignments (
      id INTEGER PRIMARY KEY,
      tutor_id TEXT NOT NULL,
      section_id INTEGER NOT NULL REFERENCES sections(id),
      assigned_by TEXT,
      assigned_at TEXT NOT NULL,
      UNIQUE (tutor_id, section_id)
    )
  ''');
}
