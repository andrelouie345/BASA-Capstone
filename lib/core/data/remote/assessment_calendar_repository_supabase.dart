// lib/core/data/remote/assessment_calendar_repository_supabase.dart
import 'package:supabase/supabase.dart';
import '../../models/assessment_calendar.dart';
import '../../repositories/assessment_calendar_repository.dart';

class AssessmentCalendarRepositorySupabase implements AssessmentCalendarRepository {
  final SupabaseClient client;
  AssessmentCalendarRepositorySupabase(this.client);

  static const _table = 'assessment_calendar';

  static List<CalendarWindow> _list(Object? rows) =>
      (rows as List).map((r) => CalendarWindow.fromMap(r as Map<String, Object?>)).toList();

  @override
  Future<List<CalendarWindow>> regionWindows(String schoolYear) async =>
      _list(await client.from(_table).select().isFilter('school_id', null).eq('school_year', schoolYear).order('id'));

  @override
  Future<List<CalendarWindow>> schoolWindows(int schoolId, String schoolYear) async =>
      _list(await client.from(_table).select().eq('school_id', schoolId).eq('school_year', schoolYear).order('id'));

  @override
  Future<CalendarWindow?> find(int? schoolId, String schoolYear, CalendarInstrument instrument, String round) async {
    var q = client.from(_table).select().eq('school_year', schoolYear).eq('instrument', instrument.dbValue).eq('round', round);
    q = schoolId == null ? q.isFilter('school_id', null) : q.eq('school_id', schoolId);
    final rows = _list(await q);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<CalendarWindow> save(CalendarWindow w) async {
    // No upsert: the unique index is on coalesce(school_id, 0), which
    // on_conflict cannot name. A concurrent insert hits that index (23505).
    final existing = await find(w.schoolId, w.schoolYear, w.instrument, w.round);
    final values = Map.of(w.toMap())..remove('id');
    if (existing == null) {
      return _list(await client.from(_table).insert(values).select()).first;
    }
    final rows = _list(await client.from(_table).update(values).eq('id', existing.id!).select());
    if (rows.isEmpty) {
      throw Exception('Calendar window not saved — it was changed or removed meanwhile (show the calendar and try '
          'again), or check your permissions');
    }
    return rows.first;
  }

  @override
  Future<void> delete(int id) async {
    final rows = await client.from(_table).delete().eq('id', id).select();
    if ((rows as List).isEmpty) {
      throw Exception('No calendar window deleted — it is gone, or check your permissions (id $id)');
    }
  }

  @override
  Future<CalendarWindow> upsertWithId(CalendarWindow w) =>
      throw UnimplementedError('upsertWithId is a local-mirroring operation — not meaningful against Supabase');

  @override
  Future<void> removeMirrored(CalendarWindow w) =>
      throw UnimplementedError('removeMirrored is a local-mirroring operation — use delete against Supabase');
}
