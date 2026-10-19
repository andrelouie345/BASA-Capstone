// lib/core/data/local/calendar_local_schema.dart
import 'package:sqflite_common/sqflite.dart';

/// v31: the assessment round calendar (assessment_calendar, migration
/// 20261019030000), mirror-only like aral_settings: written online, same
/// CHECKs and unique key as the cloud, no triggers. IF NOT EXISTS, so it runs
/// on every create and upgrade.
Future<void> createCalendarLocalSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS assessment_calendar (
      id INTEGER PRIMARY KEY,
      school_id INTEGER REFERENCES schools(id),
      school_year TEXT NOT NULL
        CHECK (school_year GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
               AND CAST(substr(school_year, 6, 4) AS INTEGER) = CAST(substr(school_year, 1, 4) AS INTEGER) + 1),
      instrument TEXT NOT NULL CHECK (instrument IN ('phil_iri', 'crla')),
      round TEXT NOT NULL CHECK (round IN ('bosy', 'mosy', 'mosy1', 'mosy2', 'mosy3', 'eosy')),
      opens_on TEXT,
      closes_on TEXT,
      skipped INTEGER NOT NULL DEFAULT 0 CHECK (skipped IN (0, 1)),
      updated_by TEXT,
      updated_at TEXT,
      CHECK ((skipped = 1 AND school_id IS NOT NULL AND opens_on IS NULL AND closes_on IS NULL)
          OR (skipped = 0 AND opens_on IS NOT NULL AND closes_on IS NOT NULL AND closes_on >= opens_on))
    )
  ''');
  await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS assessment_calendar_key '
      'ON assessment_calendar (IFNULL(school_id, 0), school_year, instrument, round)');
}
