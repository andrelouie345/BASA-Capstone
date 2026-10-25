// lib/viewmodels/round_calendar_viewmodel.dart
//
// Assessment round calendar (dashboard D1): when each Phil-IRI / CRLA round is
// held, per school year. The superadmin sets the region-wide windows; a
// school's admin/coordinator overrides a round with other dates or skips it
// (the school does not hold it). A round is scheduled for a school only when
// its effective window (school row over region row) exists and is not
// skipped. Written online and mirrored to this device; read from the local
// copy (already limited to what the signed-in user's pull could read).
import 'package:supabase/supabase.dart' show PostgrestException, SupabaseClient;

import '../core/console/logger.dart';
import '../core/models/assessment_calendar.dart';
import '../core/models/user.dart';
import '../core/models/user_role.dart';
import '../core/repositories/assessment_calendar_repository.dart';
import '../core/services/auth_messages.dart';
import '../core/services/calendar_rules.dart';
import '../core/services/normalizers.dart';
import 'auth_viewmodel.dart';
import 'viewmodel_exception.dart';

/// A window as it applies to a school: the region row, or the school's
/// override of it ([isOverride]; dates or skipped).
class CalendarEntry {
  final CalendarWindow window;
  final bool isOverride;

  const CalendarEntry(this.window, this.isOverride);

  bool get skipped => window.skipped;
}

class RoundCalendarViewModel {
  final ScopedLogger _log;
  final AuthViewModel _auth;
  final AssessmentCalendarRepository _local;
  final AssessmentCalendarRepository Function(SupabaseClient client) _cloudFor;

  /// Set when the last change reached the cloud but its local copy failed.
  String? lastMirrorWarning;

  RoundCalendarViewModel({
    required AuthViewModel auth,
    required AssessmentCalendarRepository local,
    required AssessmentCalendarRepository Function(SupabaseClient client) cloud,
    Logger? logger,
  })  : _auth = auth,
        _local = local,
        _cloudFor = cloud,
        _log = ScopedLogger(logger, 'RoundCalendarViewModel');

  // ---- Reading (this device's copy) ----

  /// Local reads need a signed-in user too (finding F18), like the other
  /// ViewModels (F5/F6): screens call these directly.
  void _requireSignIn() {
    final error = _auth.requireActiveSession();
    if (error != null) throw ViewModelException(error);
  }

  /// Every window that applies to [schoolId] in [year]: region rows, each
  /// replaced by the school's row for the same round, plus rounds only the
  /// school has. Skipped overrides are included. [schoolId] null = the region
  /// rows only. Ordered by instrument, then round order.
  Future<List<CalendarEntry>> effectiveCalendar(int? schoolId, String year) async {
    _log('effectiveCalendar($schoolId, $year)');
    _requireSignIn();
    year = _year(year);
    // A round this app version does not know for its instrument (only around
    // a change of rounds, see invalidWindows) is left out so progress and
    // reminders never meet it.
    bool valid(CalendarWindow w) {
      if (isCalendarRound(w.instrument, w.round)) return true;
      _log('WARNING: ignoring calendar row ${w.id}: ${w.instrument.label} has no round "${w.round}"');
      return false;
    }

    final byKey = <String, CalendarEntry>{
      for (final w in await _local.regionWindows(year))
        if (valid(w)) _key(w): CalendarEntry(w, false),
    };
    if (schoolId != null) {
      for (final w in await _local.schoolWindows(schoolId, year)) {
        if (valid(w)) byKey[_key(w)] = CalendarEntry(w, true);
      }
    }
    int order(CalendarEntry e) {
      final i = e.window.instrument;
      return i.index * 100 + calendarRounds[i]!.indexOf(e.window.round);
    }

    return byKey.values.toList()..sort((a, b) => order(a).compareTo(order(b)));
  }

  /// The stored windows of [schoolId] (null = region only) and the region in
  /// [year] whose round this app version does not know for its instrument.
  /// The database refuses such rows, so they only appear around a change of
  /// rounds: an updated app with an old local copy (the next pull-cloud fixes
  /// it) or an old app with new data (update the app). effectiveCalendar
  /// leaves them out; the UI shows them as invalid.
  Future<List<CalendarWindow>> invalidWindows(int? schoolId, String year) async {
    _requireSignIn();
    year = _year(year);
    return [
      ...await _local.regionWindows(year),
      if (schoolId != null) ...await _local.schoolWindows(schoolId, year),
    ].where((w) => !isCalendarRound(w.instrument, w.round)).toList();
  }

  /// The rounds of [instrument] that [schoolId] holds in [year] (not skipped).
  Future<List<CalendarEntry>> scheduledRounds(int? schoolId, String year, CalendarInstrument instrument) async =>
      (await effectiveCalendar(schoolId, year))
          .where((e) => e.window.instrument == instrument && !e.skipped)
          .toList();

  /// Upcoming / open / closed on [today] (default now). Not for skipped windows.
  RoundStatus status(CalendarWindow w, {DateTime? today}) => roundStatus(w, today ?? DateTime.now());

  // ---- Writing (online, then mirrored) ----

  /// Sets the window of a round: [schoolId] null = region-wide (superadmin),
  /// else that school's override (replacing a skip).
  Future<CalendarWindow> setWindow(int? schoolId, String year, CalendarInstrument instrument, String round,
      DateTime opens, DateTime closes) async {
    _log('setWindow($schoolId, $year, ${instrument.dbValue}, $round, ${calendarDate(opens)}, ${calendarDate(closes)})');
    year = _year(year);
    round = _round(instrument, round);
    final o = calendarDate(opens), c = calendarDate(closes);
    if (c.compareTo(o) < 0) throw ViewModelException('The round closes ($c) before it opens ($o).');
    final cloud = _writer(schoolId);
    final saved = await _cloudWrite(() => cloud.save(CalendarWindow(
        schoolId: schoolId, schoolYear: year, instrument: instrument, round: round, opensOn: o, closesOn: c)));
    await _mirror(() => _local.upsertWithId(saved));
    return saved;
  }

  /// Marks a round as not held by [schoolId] in [year], whether or not the
  /// region schedules it (a later region window then stays skipped there).
  Future<CalendarWindow> skipRound(int schoolId, String year, CalendarInstrument instrument, String round) async {
    _log('skipRound($schoolId, $year, ${instrument.dbValue}, $round)');
    year = _year(year);
    round = _round(instrument, round);
    final cloud = _writer(schoolId);
    final saved = await _cloudWrite(() => cloud.save(CalendarWindow(
        schoolId: schoolId, schoolYear: year, instrument: instrument, round: round, skipped: true)));
    await _mirror(() => _local.upsertWithId(saved));
    return saved;
  }

  /// Removes a window: a school's override (the region window applies again)
  /// or, [schoolId] null, the region window (schools' overrides stay).
  /// Returns the removed window.
  Future<CalendarWindow> clearWindow(int? schoolId, String year, CalendarInstrument instrument, String round) async {
    _log('clearWindow($schoolId, $year, ${instrument.dbValue}, $round)');
    year = _year(year);
    round = _round(instrument, round);
    final cloud = _writer(schoolId);
    final row = await _cloudWrite(() => cloud.find(schoolId, year, instrument, round));
    if (row == null) {
      throw ViewModelException('No ${instrument.label} ${roundLabel(round)} window for '
          '${schoolId == null ? 'the region' : 'school $schoolId'} in $year.');
    }
    await _cloudWrite(() => cloud.delete(row.id!));
    await _mirror(() => _local.removeMirrored(row));
    return row;
  }

  // ---- Helpers ----

  static String _key(CalendarWindow w) => '${w.instrument.dbValue}/${w.round}';

  static String _year(String raw) {
    try {
      return normalizeSchoolYear(raw);
    } on FormatException catch (e) {
      throw ViewModelException(e.message);
    }
  }

  static String _round(CalendarInstrument instrument, String raw) {
    final round = raw.trim().toLowerCase();
    final valid = calendarRounds[instrument]!;
    if (!valid.contains(round)) {
      throw ViewModelException('${instrument.label} has no round "$raw"; its rounds are ${valid.join(', ')}.');
    }
    return round;
  }

  User _me() {
    final me = _auth.currentUser;
    if (me == null) throw const ViewModelException(notSignedInMessage);
    return me;
  }

  /// The cloud repository for a change to [schoolId]'s windows (null = the
  /// region's): an online session of the superadmin, or of an admin/
  /// coordinator of that school.
  AssessmentCalendarRepository _writer(int? schoolId) {
    final sessionError = _auth.requireOnlineSession();
    if (sessionError != null) throw ViewModelException(sessionError);
    final me = _me();
    final superadmin = me.role == UserRole.admin && me.schoolId == null;
    if (!superadmin) {
      if (me.role != UserRole.admin && me.role != UserRole.coordinator) {
        throw const ViewModelException('Forbidden: only an admin or coordinator sets the assessment calendar.');
      }
      if (schoolId == null) {
        throw const ViewModelException('Forbidden: only the superadmin sets the region-wide calendar.');
      }
      if (me.schoolId != schoolId) {
        throw const ViewModelException("Forbidden: you can only set your own school's calendar.");
      }
    }
    lastMirrorWarning = null;
    return _cloudFor(_auth.client!);
  }

  Future<T> _cloudWrite<T>(Future<T> Function() write) async {
    try {
      return await write();
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const ViewModelException('Forbidden: the database refused this change.');
      if (e.code == '23505') {
        throw const ViewModelException('That window was just saved by someone else; show the calendar and try again.');
      }
      if (e.code == 'P0001' || e.code == '23514') throw ViewModelException('The database refused it: ${e.message}.');
      rethrow;
    }
  }

  Future<void> _mirror(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      lastMirrorWarning = 'The calendar was changed online, but the copy on this device was not updated. Download the latest data (pull-cloud).';
      _log('calendar mirror failed: $e');
    }
  }
}
