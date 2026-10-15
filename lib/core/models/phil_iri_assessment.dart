// lib/core/models/phil_iri_assessment.dart
//
// One Phil-IRI assessment session: a learner, one round of the school year,
// and the passages read in it (PhilIriReading rows).
//
// Rounds: BOSY = pretest, MOSY #1–#3 = middle-of-year checks (added SY
// 2025-2026), EOSY = posttest. A Foundational Literacy Test reading given at
// enrollment counts as a BOSY reading (it qualifies as an IRA).
//
// Lifecycle (owner decision 2026-10-13):
//   inProgress -> completed (tutor/coordinator marks the session done)
//              -> finalized (coordinator closes the round for the school).
// Until finalized, results are computed live from the raw miscues/answers with
// the school's current thresholds. Finalizing stores the thresholds used
// (thresholdsSnapshot) and the computed results on each reading; a finalized
// session never changes. Regenerating with today's thresholds is a computed
// view, never an overwrite.
import 'dart:convert';

enum PhilIriRound {
  bosy('BOSY'),
  mosy1('MOSY #1'),
  mosy2('MOSY #2'),
  mosy3('MOSY #3'),
  eosy('EOSY');

  final String label;
  const PhilIriRound(this.label);

  /// The passage test type this round reads (see philIriTestTypes):
  /// BOSY 'pre', MOSY #1-#3 'mosy', EOSY 'post'.
  String get passageTestType => switch (this) {
        PhilIriRound.bosy => 'pre',
        PhilIriRound.eosy => 'post',
        _ => 'mosy',
      };

  /// Can this round use a passage of [testType]? A passage without a test type
  /// fits any round (reading coordinator, 2026-10-15: MOSY never reuses the
  /// BOSY/EOSY passages; untyped passages, e.g. levels 2-6, are any-round).
  bool allowsPassageTestType(String? testType) => testType == null || testType == passageTestType;

  static PhilIriRound fromString(String value) {
    return PhilIriRound.values.firstWhere(
      (r) => r.name == value || r.label == value,
      orElse: () => throw ArgumentError('Invalid PhilIriRound value: $value'),
    );
  }
}

enum PhilIriStatus {
  inProgress('in_progress'),
  completed('completed'),
  finalized('finalized');

  final String value;
  const PhilIriStatus(this.value);

  static PhilIriStatus fromString(String value) {
    return PhilIriStatus.values.firstWhere(
      (s) => s.value == value || s.name == value,
      orElse: () => throw ArgumentError('Invalid PhilIriStatus value: $value'),
    );
  }
}

class PhilIriAssessment {
  final int? id;
  final int studentId;
  final int schoolId;           // snapshot, like crla_assessments
  final int sectionId;          // snapshot
  final String schoolYear;      // YYYY-YYYY
  final PhilIriRound round;
  final int? attemptNo;         // assigned by the DB on insert; retakes allowed
  final PhilIriStatus status;
  final String assessedAt;      // yyyy-MM-dd, local date
  final String? completedAt;    // ISO timestamp (UTC)
  final String? finalizedAt;    // ISO timestamp (UTC)
  final String? administeredBy; // users.id
  /// JSON of the PhilIriThresholds used, stored when finalized; null before.
  final String? thresholdsSnapshot;

  PhilIriAssessment({
    this.id,
    required this.studentId,
    required this.schoolId,
    required this.sectionId,
    required this.schoolYear,
    this.attemptNo,
    required this.round,
    this.status = PhilIriStatus.inProgress,
    required this.assessedAt,
    this.completedAt,
    this.finalizedAt,
    this.administeredBy,
    this.thresholdsSnapshot,
  });

  bool get isFinalized => status == PhilIriStatus.finalized;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'student_id': studentId,
        'school_id': schoolId,
        'section_id': sectionId,
        'school_year': schoolYear,
        if (attemptNo != null) 'attempt_no': attemptNo,
        'round': round.name,
        'status': status.value,
        'assessed_at': assessedAt,
        'completed_at': completedAt,
        'finalized_at': finalizedAt,
        if (administeredBy != null) 'administered_by': administeredBy,
        'thresholds_snapshot': thresholdsSnapshot,
      };

  factory PhilIriAssessment.fromMap(Map<String, Object?> m) {
    final snap = m['thresholds_snapshot'];
    return PhilIriAssessment(
      id: m['id'] as int?,
      studentId: m['student_id'] as int,
      schoolId: m['school_id'] as int,
      sectionId: m['section_id'] as int,
      schoolYear: m['school_year'] as String,
      attemptNo: m['attempt_no'] as int?,
      round: PhilIriRound.fromString(m['round'] as String),
      status: PhilIriStatus.fromString(m['status'] as String),
      assessedAt: m['assessed_at'] as String,
      completedAt: m['completed_at'] as String?,
      finalizedAt: m['finalized_at'] as String?,
      administeredBy: m['administered_by'] as String?,
      // jsonb comes back decoded (a Map); SQLite holds a JSON string.
      thresholdsSnapshot: snap == null || snap is String ? snap as String? : jsonEncode(snap),
    );
  }
}
