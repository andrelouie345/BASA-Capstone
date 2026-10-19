// lib/core/data/local/calendar_local_schema.dart
import 'package:sqflite_common/sqflite.dart';

/// v31: the assessment round calendar (assessment_calendar, migration
/// 20261019030000), mirror-only like aral_settings: written online, same
/// CHECKs and unique key as the cloud, no triggers. IF NOT EXISTS, so it runs
/// on every create and upgrade.
///
/// Deliberately WITHOUT the cloud's instrument/round pairing check
/// (assessment_calendar_round_pairing, migration 20261019050000): the cloud
/// already refuses wrong pairs, and a local copy would add one more way for an
/// older app's pull-cloud to roll back. That only helps while a changed round
/// list reuses existing names and has no assessments yet; otherwise the
/// round-name CHECK below or the assessment tables' round CHECKs still stop an
/// old app's pull (see "Assessment rounds" in lib/core/CLAUDE.md: ship the app
/// update first).
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
