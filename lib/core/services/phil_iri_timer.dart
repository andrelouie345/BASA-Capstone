// lib/core/services/phil_iri_timer.dart
//
// The timing rules of a reading timed in BASA (spec 2026-11-26, D3-D6). The
// same order and time rules are in the SQLite trigger
// (phil_iri_local_schema.dart) and the server trigger
// (20261126010000_phil_iri_timed_reading.sql): change the three together.
//
// Only the taps after the last 'reset' count (the current segment). In it:
// start, then pause/resume pairs, then stop. A reset may follow any start.
import '../models/phil_iri_timer_event.dart';

enum PhilIriTimerStatus { none, running, paused, stopped }

/// The taps after the last reset.
List<PhilIriTimerEvent> _segment(List<PhilIriTimerEvent> events) {
  final sorted = [...events]..sort((a, b) => a.seq.compareTo(b.seq));
  final last = sorted.lastIndexWhere((e) => e.kind == PhilIriTimerKind.reset);
  return last < 0 ? sorted : sorted.sublist(last + 1);
}

PhilIriTimerStatus philIriTimerStatus(List<PhilIriTimerEvent> events) {
  final seg = _segment(events);
  if (seg.isEmpty) return PhilIriTimerStatus.none;
  return switch (seg.last.kind) {
    PhilIriTimerKind.stop => PhilIriTimerStatus.stopped,
    PhilIriTimerKind.pause => PhilIriTimerStatus.paused,
    _ => PhilIriTimerStatus.running,
  };
}

/// Null when [next] at [at] may be added to [events], else the refusal.
/// A restart is always allowed after a start, whatever the clock says (the
/// way out after the device clock jumped back); the other taps may not go back
/// in time within the current timing (the taps after the last restart).
String? philIriTimerProblem(List<PhilIriTimerEvent> events, PhilIriTimerKind next, DateTime at) {
  final seg = _segment(events);
  if (next != PhilIriTimerKind.reset && seg.isNotEmpty) {
    final latest = seg.map((e) => e.at).reduce((a, b) => a.isAfter(b) ? a : b);
    if (at.isBefore(latest)) return "This time is earlier than the timer's last tap; check the device clock.";
  }
  final status = philIriTimerStatus(events);
  return switch (next) {
    PhilIriTimerKind.start => status == PhilIriTimerStatus.none ? null : 'The timer is already started.',
    PhilIriTimerKind.pause => switch (status) {
        PhilIriTimerStatus.running => null,
        PhilIriTimerStatus.paused => 'The timer is already paused.',
        PhilIriTimerStatus.stopped => 'The timer is already stopped.',
        PhilIriTimerStatus.none => 'Start the timer first.',
      },
    PhilIriTimerKind.resume => status == PhilIriTimerStatus.paused ? null : 'The timer is not paused.',
    PhilIriTimerKind.stop => switch (status) {
        PhilIriTimerStatus.running || PhilIriTimerStatus.paused => null,
        PhilIriTimerStatus.stopped => 'The timer is already stopped.',
        PhilIriTimerStatus.none => 'Start the timer first.',
      },
    PhilIriTimerKind.reset => status == PhilIriTimerStatus.none ? 'Start the timer before restarting it.' : null,
  };
}

/// Reading time of the current segment up to [now] (or its stop), pauses
/// left out.
Duration philIriElapsed(List<PhilIriTimerEvent> events, DateTime now) {
  final seg = _segment(events);
  if (seg.isEmpty) return Duration.zero;
  var total = Duration.zero;
  DateTime? runningSince;
  for (final e in seg) {
    switch (e.kind) {
      case PhilIriTimerKind.start || PhilIriTimerKind.resume:
        runningSince = e.at;
      case PhilIriTimerKind.pause || PhilIriTimerKind.stop:
        if (runningSince != null) total += e.at.difference(runningSince);
        runningSince = null;
      case PhilIriTimerKind.reset:
        break;
    }
  }
  if (runningSince != null) total += now.difference(runningSince);
  return total;
}

/// The seconds of a stopped segment (rounded down); null otherwise.
int? philIriTimedSeconds(List<PhilIriTimerEvent> events) {
  if (philIriTimerStatus(events) != PhilIriTimerStatus.stopped) return null;
  final seg = _segment(events);
  return philIriElapsed(events, seg.last.at).inMilliseconds ~/ 1000;
}

/// When 60 s of reading time is reached: start + 60 s + the pauses before
/// that moment (the one-minute method's stop, D6).
DateTime philIriMinuteMark(List<PhilIriTimerEvent> events) {
  final seg = _segment(events);
  var left = const Duration(seconds: 60);
  DateTime? runningSince;
  for (final e in seg) {
    switch (e.kind) {
      case PhilIriTimerKind.start || PhilIriTimerKind.resume:
        runningSince = e.at;
      case PhilIriTimerKind.pause || PhilIriTimerKind.stop:
        if (runningSince != null) {
          final ran = e.at.difference(runningSince);
          if (ran >= left) return runningSince.add(left);
          left -= ran;
        }
        runningSince = null;
      case PhilIriTimerKind.reset:
        break;
    }
  }
  if (runningSince == null) throw StateError('the one-minute timer is not running');
  return runningSince.add(left);
}

/// Whether the reading is timed in BASA: it has any timer row. A restarted
/// reading stays timed (owner 2026-11-26: a mistake is fixed by timing it
/// again, never by typing the seconds).
bool philIriIsTimed(List<PhilIriTimerEvent> events) => events.isNotEmpty;
