// lib/core/models/assessment_calendar.dart

import '../services/calendar_rules.dart' as rules show roundLabel;

/// The assessments that have rounds on the calendar. [dbValue] is the
/// assessment_calendar.instrument value.
enum CalendarInstrument {
  philIri('phil_iri', 'Phil-IRI'),
  crla('crla', 'CRLA');

  final String dbValue;
  final String label;
  const CalendarInstrument(this.dbValue, this.label);

  /// "phil_iri", "philiri", "phil-iri" or "crla", any case.
  static CalendarInstrument parse(String raw) {
    final v = raw.trim().toLowerCase().replaceAll(RegExp(r'[-_ ]'), '');
    for (final i in values) {
      if (i.dbValue.replaceAll('_', '') == v) return i;
    }
    throw ArgumentError('Instrument must be phil_iri or crla (got "$raw")');
  }
}

/// One stored row of assessment_calendar: the region-wide window of a round
/// (schoolId null, superadmin) or one school's override (other dates, or
/// [skipped] = the school does not hold that round). Dates are YYYY-MM-DD.
class CalendarWindow {
  final int? id;
  final int? schoolId;          // null = region-wide
  final String schoolYear;
  final CalendarInstrument instrument;
  final String round;           // bosy, mosy, mosy1-3, eosy (see calendarRounds)
  final String? opensOn;        // null when skipped
  final String? closesOn;
  final bool skipped;
  final String? updatedBy;      // users.id, stamped by the database
  final String? updatedAt;

  const CalendarWindow({
    this.id,
    this.schoolId,
    required this.schoolYear,
    required this.instrument,
    required this.round,
    this.opensOn,
    this.closesOn,
    this.skipped = false,
    this.updatedBy,
    this.updatedAt,
  });

  /// "BOSY", "MOSY #1" ... (calendar_rules.roundLabel).
  String get roundLabel => rules.roundLabel(round);

  /// updated_by / updated_at are stamped by the database, never sent.
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'school_id': schoolId,
        'school_year': schoolYear,
        'instrument': instrument.dbValue,
        'round': round,
        'opens_on': opensOn,
        'closes_on': closesOn,
        'skipped': skipped,
      };

  factory CalendarWindow.fromMap(Map<String, Object?> m) {
    // Postgres dates arrive as "YYYY-MM-DD" already; keep only the date part
    // in case a timestamp form ever comes back.
    String? date(Object? v) => v == null ? null : (v as String).substring(0, 10);
    final skipped = m['skipped'];
    return CalendarWindow(
      id: m['id'] as int?,
      schoolId: m['school_id'] as int?,
      schoolYear: m['school_year'] as String,
      instrument: CalendarInstrument.parse(m['instrument'] as String),
      round: m['round'] as String,
      opensOn: date(m['opens_on']),
      closesOn: date(m['closes_on']),
      // bool from Postgres, 0/1 from SQLite.
      skipped: skipped is bool ? skipped : skipped == 1,
      updatedBy: m['updated_by'] as String?,
      updatedAt: m['updated_at'] as String?,
    );
  }
}
