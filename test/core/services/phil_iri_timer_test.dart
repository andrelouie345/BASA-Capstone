import 'package:basa_capstone/core/models/phil_iri_timer_event.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.parse('2026-11-26T09:14:02+08:00');
DateTime at(num seconds) => t0.add(Duration(milliseconds: (seconds * 1000).round()));

List<PhilIriTimerEvent> log(List<(PhilIriTimerKind, num)> taps) => [
      for (var i = 0; i < taps.length; i++)
        PhilIriTimerEvent(readingId: 7, seq: i + 1, kind: taps[i].$1, at: at(taps[i].$2)),
    ];

const start = PhilIriTimerKind.start,
    pause = PhilIriTimerKind.pause,
    resume = PhilIriTimerKind.resume,
    stop = PhilIriTimerKind.stop,
    reset = PhilIriTimerKind.reset;

void main() {
  group('seconds', () {
    test('start 0, pause 68, resume 99, stop 138 -> 107', () {
      expect(philIriTimedSeconds(log([(start, 0), (pause, 68), (resume, 99), (stop, 138)])), 107);
    });
    test('round down (stop at 10.9 s -> 10)', () {
      expect(philIriTimedSeconds(log([(start, 0), (stop, 10.9)])), 10);
    });
    test('null while running or paused, and with no log', () {
      expect(philIriTimedSeconds(log([(start, 0)])), isNull);
      expect(philIriTimedSeconds(log([(start, 0), (pause, 5)])), isNull);
      expect(philIriTimedSeconds(const []), isNull);
    });
    test('reset starts over: start, stop(30), reset, start, stop(+45) -> 45', () {
      expect(philIriTimedSeconds(log([(start, 0), (stop, 30), (reset, 40), (start, 50), (stop, 95)])), 45);
    });
  });

  group('order', () {
    test('refuses pause before start', () {
      expect(philIriTimerProblem(const [], pause, at(1)), 'Start the timer first.');
    });
    test('refuses resume when not paused', () {
      expect(philIriTimerProblem(log([(start, 0)]), resume, at(1)), 'The timer is not paused.');
    });
    test('refuses a second pause', () {
      expect(philIriTimerProblem(log([(start, 0), (pause, 2)]), pause, at(3)), 'The timer is already paused.');
    });
    test('refuses a second stop', () {
      expect(philIriTimerProblem(log([(start, 0), (stop, 9)]), stop, at(10)), 'The timer is already stopped.');
    });
    test('refuses a second start without a reset', () {
      expect(philIriTimerProblem(log([(start, 0)]), start, at(2)), 'The timer is already started.');
    });
    test('refuses reset before any start', () {
      expect(philIriTimerProblem(const [], reset, at(1)), 'Start the timer before restarting it.');
      expect(philIriTimerProblem(log([(start, 0), (reset, 3)]), reset, at(4)), 'Start the timer before restarting it.');
    });
    test('refuses a tap earlier than the last', () {
      expect(philIriTimerProblem(log([(start, 10)]), stop, at(5)),
          "This time is earlier than the timer's last tap; check the device clock.");
    });
    test('allows the normal sequence and a reset at any point after a start', () {
      expect(philIriTimerProblem(const [], start, at(0)), isNull);
      expect(philIriTimerProblem(log([(start, 0)]), pause, at(1)), isNull);
      expect(philIriTimerProblem(log([(start, 0), (pause, 1)]), resume, at(2)), isNull);
      expect(philIriTimerProblem(log([(start, 0), (pause, 1)]), stop, at(2)), isNull);
      expect(philIriTimerProblem(log([(start, 0), (stop, 2)]), reset, at(3)), isNull);
      expect(philIriTimerProblem(log([(start, 0), (stop, 2), (reset, 3)]), start, at(4)), isNull);
    });
  });

  group('clock jumps back (review I3)', () {
    test('restart is allowed whatever the clock says', () {
      expect(philIriTimerProblem(log([(start, 100), (pause, 120)]), reset, at(50)), isNull);
    });
    test('after a restart, taps are compared only with the new timing', () {
      final events = log([(start, 100), (pause, 120), (reset, 50)]);
      expect(philIriTimerProblem(events, start, at(60)), isNull);
      expect(philIriTimedSeconds(log([(start, 100), (pause, 120), (reset, 50), (start, 60), (stop, 90)])), 30);
    });
    test('within one timing the clock still may not go back', () {
      expect(philIriTimerProblem(log([(start, 100), (pause, 120), (reset, 50), (start, 60)]), stop, at(55)),
          "This time is earlier than the timer's last tap; check the device clock.");
    });
  });

  group('status and elapsed', () {
    test('none / running / paused / stopped', () {
      expect(philIriTimerStatus(const []), PhilIriTimerStatus.none);
      expect(philIriTimerStatus(log([(start, 0)])), PhilIriTimerStatus.running);
      expect(philIriTimerStatus(log([(start, 0), (pause, 1)])), PhilIriTimerStatus.paused);
      expect(philIriTimerStatus(log([(start, 0), (stop, 1)])), PhilIriTimerStatus.stopped);
      expect(philIriTimerStatus(log([(start, 0), (stop, 1), (reset, 2)])), PhilIriTimerStatus.none);
    });
    test('elapsed excludes pauses', () {
      final events = log([(start, 0), (pause, 20), (resume, 50)]);
      expect(philIriElapsed(events, at(60)), const Duration(seconds: 30));
      expect(philIriElapsed(log([(start, 0), (pause, 20)]), at(100)), const Duration(seconds: 20));
    });
    test('minute mark = start + 60 s + pauses before it', () {
      expect(philIriMinuteMark(log([(start, 0), (pause, 20), (resume, 50)])), at(90));
      expect(philIriMinuteMark(log([(start, 0)])), at(60));
    });
    test('timed once the timer was used, also after a restart', () {
      expect(philIriIsTimed(log([(start, 0)])), isTrue);
      expect(philIriIsTimed(log([(start, 0), (stop, 3), (reset, 4)])), isTrue);
      expect(philIriIsTimed(const []), isFalse);
    });
  });

  test('toMap/fromMap round trip keeps the offset', () {
    final e = PhilIriTimerEvent(readingId: 7, seq: 2, kind: pause, at: at(68), createdBy: 'u1');
    final m = e.toMap();
    expect(m.containsKey('id'), isFalse);
    expect(m['kind'], 'pause');
    // Local time with its offset (whatever the machine's zone), same moment.
    expect(m['at'] as String, matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}[+-]\d\d:\d\d$')));
    expect(DateTime.parse(m['at'] as String).isAtSameMomentAs(at(68)), isTrue);
    final back = PhilIriTimerEvent.fromMap({...m, 'id': -3});
    expect(back.id, -3);
    expect(back.kind, pause);
    expect(back.at.isAtSameMomentAs(e.at), isTrue);
  });
}
