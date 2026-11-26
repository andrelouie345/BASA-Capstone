// Demo calendar (demo-data plan Task 4): round windows for both years and
// school days, never after the run date, inside the school year, weekdays
// only, skipping the Christmas break and Holy Week.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/demo_data/dates.dart';
import '../../../tool/demo_data/world.dart';

final _runDates = [DateTime(2026, 11, 24), DateTime(2026, 12, 3)];

void main() {
  test('windows of both instruments and years', () {
    for (final y in DemoYear.values) {
      final w = demoWindows(y);
      expect(w.where((x) => x.instrument == 'crla').map((x) => x.round), ['bosy', 'mosy', 'eosy']);
      expect(w.where((x) => x.instrument == 'phil_iri').map((x) => x.round), ['bosy', 'mosy1', 'eosy']);
      for (final instrument in ['crla', 'phil_iri']) {
        final list = w.where((x) => x.instrument == instrument).toList();
        for (var i = 1; i < list.length; i++) {
          expect(list[i].opens.isAfter(list[i - 1].closes), isTrue, reason: '${y.label} $instrument: no overlap');
        }
      }
    }
  });

  test('2026-2027 MOSY #1 is open on 2026-11-24', () {
    final mosy = demoWindows(DemoYear.y2026).singleWhere((x) => x.instrument == 'phil_iri' && x.round == 'mosy1');
    final today = DateTime(2026, 11, 24);
    expect(!mosy.opens.isAfter(today) && !mosy.closes.isBefore(today), isTrue);
  });

  test('round dates: never after today, null before the window opens', () {
    for (final today in _runDates) {
      for (final y in DemoYear.values) {
        for (final w in demoWindows(y)) {
          for (var seed = 0; seed < 20; seed++) {
            final d = roundDate(y, w.instrument, w.round, today: today, rng: Random(seed));
            if (w.opens.isAfter(today)) {
              expect(d, isNull, reason: '${y.label} ${w.round}');
              continue;
            }
            expect(d, isNotNull);
            expect(d!.isAfter(today), isFalse, reason: '${y.label} ${w.round} $d');
            expect(!d.isBefore(w.opens) && !d.isAfter(w.closes), isTrue, reason: '$d in the window');
            _schoolDay(d);
          }
        }
      }
      expect(roundDate(DemoYear.y2026, 'phil_iri', 'eosy', today: today, rng: Random(0)), isNull);
    }
  });

  test('session days: never after today, school days, the given weekdays', () {
    for (final today in _runDates) {
      for (final y in DemoYear.values) {
        final days = sessionDays(y, today: today, perWeek: 3);
        expect(days, isNotEmpty);
        for (final d in days) {
          expect(d.isAfter(today), isFalse, reason: '$d');
          _schoolDay(d);
          expect(d.weekday, isIn([DateTime.monday, DateTime.wednesday, DateTime.friday]));
          final start = int.parse(y.label.substring(0, 4));
          expect(!d.isBefore(DateTime(start, 6, 1)) && !d.isAfter(DateTime(start + 1, 5, 31)), isTrue);
        }
        expect(days, orderedEquals([...days]..sort()));
      }
    }
    // 2025-2026 is over: its sessions run to its EOSY window's close.
    final last = sessionDays(DemoYear.y2025, today: DateTime(2026, 11, 24), perWeek: 5).last;
    expect(last.isAfter(DateTime(2026, 4, 1)), isTrue);
    // from= starts later; perWeek 2 = Tuesday and Thursday.
    final later = sessionDays(DemoYear.y2026, today: DateTime(2026, 11, 24), perWeek: 2, from: DateTime(2026, 10, 1));
    expect(later.first.isBefore(DateTime(2026, 10, 1)), isFalse);
    expect(later.map((d) => d.weekday).toSet(), {DateTime.tuesday, DateTime.thursday});
  });
}

void _schoolDay(DateTime d) {
  expect(d.weekday, lessThanOrEqualTo(DateTime.friday), reason: '$d is a weekday');
  expect(demoBreak(d), isFalse, reason: '$d is not in a break');
  expect(demoBreak(DateTime(2025, 12, 24)), isTrue);
  expect(demoBreak(DateTime(2026, 4, 2)), isTrue); // Holy Week 2026
  expect(demoBreak(DateTime(2027, 3, 25)), isTrue); // Holy Week 2027
}
