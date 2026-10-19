// lib/core/services/calendar_rules.dart
//
// Assessment round calendar rules (dashboard D1). A calendar round is a round
// that can be assessed: calendarRounds is built from the assessment round
// enums (PhilIriRound, CrlaRound), so the two can never disagree. The
// database holds the same pairing (assessment_calendar_round_pairing, as the
// assessment tables' round checks). CRLA's rounds are not settled yet (owner
// 2026-10-19); changing them = the CrlaRound enum plus ONE migration swapping
// crla_assessments_round_check and the calendar pairing together (see
// lib/core/CLAUDE.md).
import '../models/assessment_calendar.dart';
import '../models/crla_assessment.dart' show CrlaRound;
import '../models/phil_iri_assessment.dart' show PhilIriRound;

/// The rounds each instrument holds, in calendar (enum) order.
final Map<CalendarInstrument, List<String>> calendarRounds = Map.unmodifiable({
  CalendarInstrument.philIri: List<String>.unmodifiable(PhilIriRound.values.map((r) => r.name)),
  CalendarInstrument.crla: List<String>.unmodifiable(CrlaRound.values.map((r) => r.name)),
});

/// Whether [round] is one of [instrument]'s rounds in this app version. A
/// stored row that fails this (only possible around a change of rounds, when
/// an app and its data are from different versions) is ignored on read.
bool isCalendarRound(CalendarInstrument instrument, String round) => calendarRounds[instrument]!.contains(round);

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
