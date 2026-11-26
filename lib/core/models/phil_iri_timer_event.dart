// lib/core/models/phil_iri_timer_event.dart
//
// One tap of a reading's timer (spec 2026-11-26 timed reading, D1): the timing
// log of a Phil-IRI reading timed in BASA. Rows are only ever added (a
// restart is a 'reset' row), so the log shows exactly when the reading
// started, paused, resumed and stopped. The rules are in
// services/phil_iri_timer.dart (re-exported here for screens and commands).
import '../services/phil_iri_timer.dart' show PhilIriTimerStatus;
export '../services/phil_iri_timer.dart'
    show
        PhilIriTimerStatus,
        philIriTimerProblem,
        philIriTimedSeconds,
        philIriTimerStatus,
        philIriElapsed,
        philIriMinuteMark,
        philIriIsTimed;

enum PhilIriTimerKind {
  start,
  pause,
  resume,
  stop,
  reset;

  String get value => name;

  static PhilIriTimerKind fromString(String v) =>
      PhilIriTimerKind.values.firstWhere((k) => k.name == v, orElse: () => throw ArgumentError('timer kind $v'));
}

class PhilIriTimerEvent {
  final int? id;
  final int readingId;
  final int seq; // 1, 2, ... per reading
  final PhilIriTimerKind kind;
  final DateTime at; // the device's clock, kept with its offset
  final String? createdBy;
  final String? createdAt;

  const PhilIriTimerEvent({
    this.id,
    required this.readingId,
    required this.seq,
    required this.kind,
    required this.at,
    this.createdBy,
    this.createdAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'reading_id': readingId,
        'seq': seq,
        'kind': kind.value,
        'at': isoWithOffset(at),
        if (createdBy != null) 'created_by': createdBy,
      };

  factory PhilIriTimerEvent.fromMap(Map<String, Object?> m) => PhilIriTimerEvent(
        id: (m['id'] as num?)?.toInt(),
        readingId: (m['reading_id'] as num).toInt(),
        seq: (m['seq'] as num).toInt(),
        kind: PhilIriTimerKind.fromString(m['kind'] as String),
        at: DateTime.parse(m['at'] as String),
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at'] as String?,
      );
}

/// [t] as ISO-8601 in the device's local time with its UTC offset
/// (2026-11-26T09:15:10.000+08:00), so the log keeps the time the tutor saw.
String isoWithOffset(DateTime t) {
  final local = t.isUtc ? t.toLocal() : t;
  String two(int n) => n.toString().padLeft(2, '0');
  final off = local.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final mins = off.inMinutes.abs();
  final base = '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}'
      'T${two(local.hour)}:${two(local.minute)}:${two(local.second)}.${local.millisecond.toString().padLeft(3, '0')}';
  return '$base$sign${two(mins ~/ 60)}:${two(mins % 60)}';
}

/// What a screen shows for a reading's timer (PhilIriViewModel.timer).
class PhilIriTimerState {
  final List<PhilIriTimerEvent> events;
  final PhilIriTimerStatus status;

  /// Reading time so far (pauses left out), up to the stop when stopped.
  final Duration elapsed;

  /// The reading was timed in BASA ("Timed in BASA"); false = "Time typed in".
  final bool timedInBasa;

  /// One minute: stopped, waiting for the tutor to tap the word reached.
  final bool minuteEndNeeded;

  const PhilIriTimerState({
    required this.events,
    required this.status,
    required this.elapsed,
    required this.timedInBasa,
    required this.minuteEndNeeded,
  });

  String get label => timedInBasa ? 'Timed in BASA' : 'Time typed in';
}
