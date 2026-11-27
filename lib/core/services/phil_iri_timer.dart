// lib/core/services/phil_iri_timer.dart
//
// The timing rules of a Phil-IRI reading timed in BASA (spec 2026-11-26,
// D3-D6), as wrappers over the shared rules in reading_timer.dart (since the
// digitized CRLA, 2026-11-27). The same order and time rules are in the SQLite
// trigger (phil_iri_local_schema.dart) and the server trigger
// (20261126010000 / 20261126030000): change the three together.
import '../models/phil_iri_timer_event.dart';
import 'reading_timer.dart';

enum PhilIriTimerStatus { none, running, paused, stopped }

/// The log as shared timer taps, in seq order.
List<TimerTap> _taps(List<PhilIriTimerEvent> events) => [
      for (final e in [...events]..sort((a, b) => a.seq.compareTo(b.seq)))
        (kind: TimerTapKind.fromString(e.kind.value), at: e.at),
    ];

PhilIriTimerStatus philIriTimerStatus(List<PhilIriTimerEvent> events) =>
    PhilIriTimerStatus.values[timerStatus(_taps(events)).index];

/// Null when [next] at [at] may be added to [events], else the refusal.
String? philIriTimerProblem(List<PhilIriTimerEvent> events, PhilIriTimerKind next, DateTime at) =>
    timerProblem(_taps(events), TimerTapKind.fromString(next.value), at);

/// Reading time of the current segment up to [now] (or its stop), pauses
/// left out.
Duration philIriElapsed(List<PhilIriTimerEvent> events, DateTime now) => timerElapsed(_taps(events), now);

/// The seconds of a stopped segment (rounded down); null otherwise.
int? philIriTimedSeconds(List<PhilIriTimerEvent> events) => timedSeconds(_taps(events));

/// When 60 s of reading time is reached: start + 60 s + the pauses before
/// that moment (the one-minute method's stop, D6).
DateTime philIriMinuteMark(List<PhilIriTimerEvent> events) {
  try {
    return limitMark(_taps(events), const Duration(seconds: 60));
  } on StateError {
    throw StateError('the one-minute timer is not running');
  }
}

/// Whether the reading is timed in BASA: it has any timer row. A restarted
/// reading stays timed (owner 2026-11-26: a mistake is fixed by timing it
/// again, never by typing the seconds).
bool philIriIsTimed(List<PhilIriTimerEvent> events) => isTimed(_taps(events));
