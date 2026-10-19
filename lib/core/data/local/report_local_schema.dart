// lib/core/data/local/report_local_schema.dart
import 'package:sqflite_common/sqflite.dart';

/// v32: report settings (report_settings, migration 20261019040000),
/// mirror-only like aral_settings: written online, same unique key as the
/// cloud, no triggers. IF NOT EXISTS, so it runs on every create and upgrade.
Future<void> createReportLocalSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS report_settings (
      id INTEGER PRIMARY KEY,
      school_id INTEGER REFERENCES schools(id),
      settings TEXT NOT NULL,
      updated_by TEXT,
      updated_at TEXT
    )
  ''');
  await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS report_settings_school_key ON report_settings (IFNULL(school_id, 0))');
}
