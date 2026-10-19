// lib/core/repositories/assessment_calendar_repository.dart
import '../models/assessment_calendar.dart';

/// The stored assessment round windows: region-wide rows and school
/// overrides. Merging them (override wins) is the ViewModel's job. Written
/// online; the SQLite implementation reads and mirrors only.
abstract class AssessmentCalendarRepository {
  /// The region-wide rows for the year.
  Future<List<CalendarWindow>> regionWindows(String schoolYear);

  /// [schoolId]'s override rows for the year.
  Future<List<CalendarWindow>> schoolWindows(int schoolId, String schoolYear);

  /// The row for that key ([schoolId] null = region-wide), or null.
  Future<CalendarWindow?> find(int? schoolId, String schoolYear, CalendarInstrument instrument, String round);

  /// Creates or replaces the row for the window's key and returns it (cloud).
  Future<CalendarWindow> save(CalendarWindow w);

  /// Deletes a row (cloud). Throws when nothing was deleted.
  Future<void> delete(int id);

  /// Local-mirroring only, keeps Supabase's id. Supabase impl throws UnimplementedError.
  Future<CalendarWindow> upsertWithId(CalendarWindow w);

  /// Local-mirroring only: drops the local copy of [w], by id and by key
  /// (no-op when absent). Supabase impl throws UnimplementedError.
  Future<void> removeMirrored(CalendarWindow w);
}
