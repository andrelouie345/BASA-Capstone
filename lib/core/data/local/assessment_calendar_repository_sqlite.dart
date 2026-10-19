// lib/core/data/local/assessment_calendar_repository_sqlite.dart
import 'package:sqflite_common/sqflite.dart';
import 'mirror_write.dart';
import 'sqlite_values.dart';
import '../../models/assessment_calendar.dart';
import '../../repositories/assessment_calendar_repository.dart';

/// Read + mirror only: the calendar is set online by the superadmin and
/// school admins/coordinators.
class AssessmentCalendarRepositorySqlite implements AssessmentCalendarRepository {
  final Database db;
  AssessmentCalendarRepositorySqlite(this.db);

  static const _byKey = '(IFNULL(school_id, 0) = ? AND school_year = ? AND instrument = ? AND round = ?)';
  static List<Object?> _keyArgs(CalendarWindow w) => [w.schoolId ?? 0, w.schoolYear, w.instrument.dbValue, w.round];

  static Never _online() => throw UnsupportedError('The assessment calendar is set online; use the cloud repository');

  @override
  Future<CalendarWindow> save(CalendarWindow w) async => _online();
  @override
  Future<void> delete(int id) async => _online();

  @override
  Future<List<CalendarWindow>> regionWindows(String schoolYear) async {
    final rows = await db.query('assessment_calendar',
        where: 'school_id IS NULL AND school_year = ?', whereArgs: [schoolYear], orderBy: 'id');
    return rows.map(CalendarWindow.fromMap).toList();
  }

  @override
  Future<List<CalendarWindow>> schoolWindows(int schoolId, String schoolYear) async {
    final rows = await db.query('assessment_calendar',
        where: 'school_id = ? AND school_year = ?', whereArgs: [schoolId, schoolYear], orderBy: 'id');
    return rows.map(CalendarWindow.fromMap).toList();
  }

  @override
  Future<CalendarWindow?> find(int? schoolId, String schoolYear, CalendarInstrument instrument, String round) async {
    final rows = await db.query('assessment_calendar',
        where: _byKey,
        whereArgs: [schoolId ?? 0, schoolYear, instrument.dbValue, round],
        limit: 1);
    return rows.isEmpty ? null : CalendarWindow.fromMap(rows.first);
  }

  @override
  Future<CalendarWindow> upsertWithId(CalendarWindow w) async {
    if (w.id == null) throw ArgumentError('Cannot upsertWithId a CalendarWindow with no id');
    await db.transaction((txn) async {
      // The cloud key is unique, so a local row with this key under another id
      // is stale (cleared and set again on another device): drop it.
      await txn.delete('assessment_calendar', where: '$_byKey AND id <> ?', whereArgs: [..._keyArgs(w), w.id]);
      await upsertById(txn, 'assessment_calendar', toSqliteRow({
        ...w.toMap(),
        if (w.updatedBy != null) 'updated_by': w.updatedBy,
        if (w.updatedAt != null) 'updated_at': w.updatedAt,
      }));
    });
    final rows = await db.query('assessment_calendar', where: 'id = ?', whereArgs: [w.id]);
    return CalendarWindow.fromMap(rows.first);
  }

  @override
  Future<void> removeMirrored(CalendarWindow w) async {
    // By id and by key: the local copy may hold the key under an older id.
    await db.delete('assessment_calendar', where: 'id = ? OR $_byKey', whereArgs: [w.id, ..._keyArgs(w)]);
  }
}
