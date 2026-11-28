// Shared reading-timer rules (CRLA digitized plan Task 1): the Phil-IRI timed
// reading's rules, now instrument-free, used by Phil-IRI and CRLA.
import 'package:basa_capstone/core/services/reading_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.parse('2026-07-01T09:00:00+08:00');
  DateTime at(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));
  TimerTap tap(TimerTapKind k, num s) => (kind: k, at: at(s));
  const start = TimerTapKind.start, pause = TimerTapKind.pause, resume = TimerTapKind.resume;
  const stop = TimerTapKind.stop, reset = TimerTapKind.reset;

  test('start 0, pause 68, resume 99, stop 138 -> 107', () {
    expect(timedSeconds([tap(start, 0), tap(pause, 68), tap(resume, 99), tap(stop, 138)]), 107);
  });

  test('seconds round down; null while running or paused', () {
    expect(timedSeconds([tap(start, 0), tap(stop, 10.9)]), 10);
    expect(timedSeconds([tap(start, 0)]), isNull);
    expect(timedSeconds([tap(start, 0), tap(pause, 5)]), isNull);
  });

  test('reset starts over', () {
    expect(timedSeconds([tap(start, 0), tap(stop, 30), tap(reset, 31), tap(start, 40), tap(stop, 85)]), 45);
  });

  test('the six refusals', () {
    expect(timerProblem([], pause, at(1)), 'Start the timer first.');
    expect(timerProblem([tap(start, 0)], resume, at(1)), 'The timer is not paused.');
    expect(timerProblem([tap(start, 0), tap(pause, 1)], pause, at(2)), 'The timer is already paused.');
    expect(timerProblem([tap(start, 0), tap(stop, 1)], stop, at(2)), 'The timer is already stopped.');
    expect(timerProblem([], reset, at(1)), 'Start the timer before restarting it.');
    expect(timerProblem([tap(start, 100)], stop, at(50)),
        "This time is earlier than the timer's last tap; check the device clock.");
    expect(timerProblem([tap(start, 0)], start, at(1)), 'The timer is already started.');
  });

  test('a restart is allowed whatever the clock says', () {
    expect(timerProblem([tap(start, 100)], reset, at(50)), isNull);
  });

  test('status and elapsed (pauses left out)', () {
    expect(timerStatus([]), TimerStatus.none);
    expect(timerStatus([tap(start, 0)]), TimerStatus.running);
    expect(timerStatus([tap(start, 0), tap(pause, 5)]), TimerStatus.paused);
    expect(timerStatus([tap(start, 0), tap(stop, 5)]), TimerStatus.stopped);
    expect(timerElapsed([tap(start, 0), tap(pause, 10), tap(resume, 40)], at(50)), const Duration(seconds: 20));
  });

  test('limitMark = start + limit + pauses before it', () {
    final taps = [tap(start, 0), tap(pause, 20), tap(resume, 30)];
    expect(limitMark(taps, const Duration(seconds: 60)), at(70));
    expect(limitMark(taps, const Duration(seconds: 120)), at(130));
    expect(limitMark([tap(start, 0), tap(pause, 70)], const Duration(seconds: 60)), at(60));
  });

  test('isTimed: any tap', () {
    expect(isTimed([]), isFalse);
    expect(isTimed([tap(start, 0), tap(reset, 1)]), isTrue);
  });
}
