// lib/core/services/calendar_rules.dart
//
// Assessment round calendar rules (dashboard D1). The only place that pairs an
// instrument with its rounds: the database checks the union of round names,
// not which instrument has which. CRLA's rounds are not settled yet (owner
// 2026-10-19); a change there is a change to this map (plus at most a
// constraint swap in a new migration).
import '../models/assessment_calendar.dart';

/// The rounds each instrument holds, in calendar order.
const Map<CalendarInstrument, List<String>> calendarRounds = {
  CalendarInstrument.philIri: ['bosy', 'mosy1', 'mosy2', 'mosy3', 'eosy'],
  CalendarInstrument.crla: ['bosy', 'mosy', 'eosy'],
};

enum RoundStatus {
  upcoming('UPCOMING'),
  open('OPEN'),
  closed('CLOSED');

  final String label;
  const RoundStatus(this.label);
}

/// YYYY-MM-DD of [t] in local time.
String calendarDate(DateTime t) {
  final d = t.toLocal();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Upcoming before opens_on, open from opens_on to closes_on (both days
/// included), closed after. A skipped window has no status.
RoundStatus roundStatus(CalendarWindow w, DateTime today) {
  if (w.skipped || w.opensOn == null || w.closesOn == null) {
    throw StateError('A skipped round has no status');
  }
  final d = calendarDate(today);
  if (d.compareTo(w.opensOn!) < 0) return RoundStatus.upcoming;
  if (d.compareTo(w.closesOn!) > 0) return RoundStatus.closed;
  return RoundStatus.open;
}

/// "BOSY", "MOSY #1" ... for Phil-IRI; "BOSY", "MOSY", "EOSY" for CRLA.
String roundLabel(String round) => switch (round) {
      'mosy1' => 'MOSY #1',
      'mosy2' => 'MOSY #2',
      'mosy3' => 'MOSY #3',
      _ => round.toUpperCase(),
    };
