// Demo calendar (demo-data plan Task 4): the round windows of both school
// years and the school days ARAL sessions fall on. Nothing is ever dated after
// the run date ([today]): BASA refuses future dates, and reminders, open rounds
// and the dashboard measure everything against today.
import 'dart:math';

import 'world.dart';

class DemoWindow {
  /// 'crla' | 'phil_iri' (the calendar's instruments).
  final String instrument;
  /// CRLA 'bosy' | 'mosy' | 'eosy'; Phil-IRI 'bosy' | 'mosy1' | 'eosy'
  /// (MOSY #2 and #3 are skipped: optional rounds).
  final String round;
  final DateTime opens, closes;
  const DemoWindow(this.instrument, this.round, this.opens, this.closes);
}

/// The round windows of [y] (the same dates for CRLA and Phil-IRI).
List<DemoWindow> demoWindows(DemoYear y) {
  final (bosy, mosy, eosy) = switch (y) {
    DemoYear.y2025 => (
        (DateTime(2025, 7, 1), DateTime(2025, 8, 15)),
        (DateTime(2025, 11, 3), DateTime(2025, 12, 12)),
        (DateTime(2026, 3, 9), DateTime(2026, 4, 10)),
      ),
    DemoYear.y2026 => (
        (DateTime(2026, 6, 22), DateTime(2026, 8, 7)),
        (DateTime(2026, 11, 2), DateTime(2026, 12, 11)),
        (DateTime(2027, 3, 8), DateTime(2027, 4, 9)),
      ),
  };
  return [
    for (final (instrument, mosyRound) in [('crla', 'mosy'), ('phil_iri', 'mosy1')]) ...[
      DemoWindow(instrument, 'bosy', bosy.$1, bosy.$2),
      DemoWindow(instrument, mosyRound, mosy.$1, mosy.$2),
      DemoWindow(instrument, 'eosy', eosy.$1, eosy.$2),
    ],
  ];
}

/// Christmas break (Dec 20 - Jan 4) and Holy Week (2026: Mar 30 - Apr 3;
/// 2027: Mar 22 - 26).
bool demoBreak(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  if ((d.month == 12 && d.day >= 20) || (d.month == 1 && d.day <= 4)) return true;
  for (final (from, to) in [
    (DateTime(2026, 3, 30), DateTime(2026, 4, 3)),
    (DateTime(2027, 3, 22), DateTime(2027, 3, 26)),
  ]) {
    if (!day.isBefore(from) && !day.isAfter(to)) return true;
  }
  return false;
}

bool _schoolDay(DateTime d) => d.weekday <= DateTime.friday && !demoBreak(d);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// A school day inside the window of [round], up to [today] for an open
/// window; null when the window opens after [today].
DateTime? roundDate(DemoYear y, String instrument, String round, {required DateTime today, required Random rng}) {
  final w = demoWindows(y).singleWhere((x) => x.instrument == instrument && x.round == round);
  final end = w.closes.isAfter(_day(today)) ? _day(today) : w.closes;
  if (w.opens.isAfter(end)) return null;
  final days = [
    for (var d = w.opens; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1))
      if (_schoolDay(d)) d,
  ];
  return days.isEmpty ? null : days[rng.nextInt(days.length)];
}

/// The weekdays sessions are held on, for [perWeek] sessions a week.
List<int> demoSessionWeekdays(int perWeek) => switch (perWeek) {
      1 => [DateTime.wednesday],
      2 => [DateTime.tuesday, DateTime.thursday],
      3 => [DateTime.monday, DateTime.wednesday, DateTime.friday],
      4 => [DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday],
      _ => [DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday],
    };

/// ARAL session days of [y]: from [from] (default: the day after the BOSY
/// window closes) to the EOSY window's close or [today], whichever is first,
/// on [perWeek] fixed weekdays, skipping the breaks.
List<DateTime> sessionDays(DemoYear y, {required DateTime today, required int perWeek, DateTime? from}) {
  final windows = demoWindows(y);
  final bosyClose = windows.firstWhere((w) => w.round == 'bosy').closes;
  final eosyClose = windows.firstWhere((w) => w.round == 'eosy').closes;
  final start = _day(from ?? bosyClose.add(const Duration(days: 1)));
  final end = eosyClose.isAfter(_day(today)) ? _day(today) : eosyClose;
  final weekdays = demoSessionWeekdays(perWeek);
  return [
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1))
      if (_schoolDay(d) && weekdays.contains(d.weekday)) d,
  ];
}
