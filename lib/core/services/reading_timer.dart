// lib/core/services/reading_timer.dart
//
// The rules of a reading timed in BASA, shared by the Phil-IRI timed reading
// (spec 2026-11-26, D3-D6) and digitized CRLA (spec 2026-11-27, D5). Each
// instrument keeps its own timing log and wraps these functions. The same order
// and time rules are in each log's SQLite trigger and server trigger: change
// them together.
//
// Only the taps after the last 'reset' count (the current timing). In it:
// start, then pause/resume pairs, then stop. A reset may follow any start.

enum TimerTapKind {
  start,
  pause,
  resume,
  stop,
  reset;

  String get value => name;

  static TimerTapKind fromString(String s) =>
      values.firstWhere((k) => k.name == s, orElse: () => throw ArgumentError('timer tap kind "$s"'));
}

/// One tap of a timing log, in the order of the log.
typedef TimerTap = ({TimerTapKind kind, DateTime at});

enum TimerStatus { none, running, paused, stopped }

/// The taps after the last reset ([taps] are in log order).
List<TimerTap> _segment(List<TimerTap> taps) {
  final last = taps.lastIndexWhere((t) => t.kind == TimerTapKind.reset);
  return last < 0 ? taps : taps.sublist(last + 1);
}

TimerStatus timerStatus(List<TimerTap> taps) {
  final seg = _segment(taps);
  if (seg.isEmpty) return TimerStatus.none;
  return switch (seg.last.kind) {
    TimerTapKind.stop => TimerStatus.stopped,
    TimerTapKind.pause => TimerStatus.paused,
    _ => TimerStatus.running,
  };
}

/// Null when [next] at [at] may follow [taps], else the refusal. A restart is
/// always allowed after a start, whatever the clock says (the way out after
/// the device clock jumped back); the other taps may not go back in time
/// within the current timing.
String? timerProblem(List<TimerTap> taps, TimerTapKind next, DateTime at) {
  final seg = _segment(taps);
  if (next != TimerTapKind.reset && seg.isNotEmpty) {
    final latest = seg.map((t) => t.at).reduce((a, b) => a.isAfter(b) ? a : b);
    if (at.isBefore(latest)) return "This time is earlier than the timer's last tap; check the device clock.";
  }
  final status = timerStatus(taps);
  return switch (next) {
    TimerTapKind.start => status == TimerStatus.none ? null : 'The timer is already started.',
    TimerTapKind.pause => switch (status) {
        TimerStatus.running => null,
        TimerStatus.paused => 'The timer is already paused.',
        TimerStatus.stopped => 'The timer is already stopped.',
        TimerStatus.none => 'Start the timer first.',
      },
    TimerTapKind.resume => status == TimerStatus.paused ? null : 'The timer is not paused.',
    TimerTapKind.stop => switch (status) {
        TimerStatus.running || TimerStatus.paused => null,
        TimerStatus.stopped => 'The timer is already stopped.',
        TimerStatus.none => 'Start the timer first.',
      },
    TimerTapKind.reset => status == TimerStatus.none ? 'Start the timer before restarting it.' : null,
  };
}

/// Reading time of the current timing up to [now] (or its stop), pauses left
/// out.
Duration timerElapsed(List<TimerTap> taps, DateTime now) {
  var total = Duration.zero;
  DateTime? runningSince;
  for (final t in _segment(taps)) {
    switch (t.kind) {
      case TimerTapKind.start || TimerTapKind.resume:
        runningSince = t.at;
      case TimerTapKind.pause || TimerTapKind.stop:
        if (runningSince != null) total += t.at.difference(runningSince);
        runningSince = null;
      case TimerTapKind.reset:
        break;
    }
  }
  if (runningSince != null) total += now.difference(runningSince);
  return total;
}

/// The seconds of a stopped timing (rounded down); null otherwise.
int? timedSeconds(List<TimerTap> taps) {
  if (timerStatus(taps) != TimerStatus.stopped) return null;
  return timerElapsed(taps, _segment(taps).last.at).inMilliseconds ~/ 1000;
}

/// When [limit] of reading time is reached: start + limit + the pauses before
/// that moment (the automatic stop of a timer with a limit).
DateTime limitMark(List<TimerTap> taps, Duration limit) {
  var left = limit;
  DateTime? runningSince;
  for (final t in _segment(taps)) {
    switch (t.kind) {
      case TimerTapKind.start || TimerTapKind.resume:
        runningSince = t.at;
      case TimerTapKind.pause || TimerTapKind.stop:
        if (runningSince != null) {
          final ran = t.at.difference(runningSince);
          if (ran >= left) return runningSince.add(left);
          left -= ran;
        }
        runningSince = null;
      case TimerTapKind.reset:
        break;
    }
  }
  if (runningSince == null) throw StateError('the timer is not running');
  return runningSince.add(left);
}

/// Whether the reading is timed in BASA: it has any timer tap. A restarted
/// reading stays timed (a mistake is fixed by timing it again, never by typing).
bool isTimed(List<TimerTap> taps) => taps.isNotEmpty;
