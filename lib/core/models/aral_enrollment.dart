// lib/core/models/aral_enrollment.dart
//
// One learner in ARAL-Reading for a school year (the ARAL roster). Offline-first
// like the assessment sessions: written locally, the cloud table has the same
// columns and rules for the future sync.
//
// Owner decisions (2026-10-15, revised with the reading coordinator):
//  * Grades 1-10. Programs: Foundational (non-readers, reading level 0: SHARP
//    or the school's foundational literacy program; still on the ARAL roster),
//    KS1, KS2 and KS3; KS2/KS3 have a Basic and a Plus track. Placement rules
//    are in aral_rules.dart.
//  * BASA proposes the roster (at most 15 per section) and the program from
//    CRLA / Phil-IRI results; the coordinator may change the program. What BASA
//    suggested is kept next to what was chosen (suggested_key_stage /
//    suggested_track).
//  * One ARAL enrollment per learner per school year; leaving ARAL is a status
//    change (exited, with a date and a reason). Grade-level-ready exits come
//    from results, not from the coordinator.

/// The ARAL program level. [foundational] is for non-readers (below KS1
/// material); like KS1 it has no track.
enum AralKeyStage {
  foundational('Foundational'),
  ks1('KS1'),
  ks2('KS2'),
  ks3('KS3');

  final String label;
  const AralKeyStage(this.label);

  /// KS2 and KS3 have a Basic/Plus track; Foundational and KS1 don't.
  bool get hasTrack => this == ks2 || this == ks3;

  static AralKeyStage fromString(String v) => AralKeyStage.values.firstWhere(
        (k) => k.name == v || k.label == v,
        orElse: () => throw ArgumentError('Invalid AralKeyStage value: $v'),
      );
}

/// KS2/KS3 only; Foundational and KS1 have no track.
enum AralTrack {
  basic('Basic'),
  plus('Plus');

  final String label;
  const AralTrack(this.label);

  static AralTrack fromString(String v) => AralTrack.values.firstWhere(
        (t) => t.name == v || t.label == v,
        orElse: () => throw ArgumentError('Invalid AralTrack value: $v'),
      );
}

enum AralStatus {
  active,
  exited;

  static AralStatus fromString(String v) => AralStatus.values.firstWhere(
        (s) => s.name == v,
        orElse: () => throw ArgumentError('Invalid AralStatus value: $v'),
      );
}

/// Why a learner left ARAL. Grade-level ready is the program's goal; the rest
/// are administrative.
enum AralExitReason {
  gradeLevelReady('grade_level_ready'),
  transferredOut('transferred_out'),
  droppedOut('dropped_out'),
  other('other');

  final String value;
  const AralExitReason(this.value);

  static AralExitReason fromString(String v) => AralExitReason.values.firstWhere(
        (r) => r.value == v || r.name == v,
        orElse: () => throw ArgumentError('Invalid AralExitReason value: $v'),
      );
}

/// Where the learner's ARAL placement came from.
enum AralBasisSource {
  crla,
  philIri('phil_iri'),
  manual;

  final String? _value;
  const AralBasisSource([this._value]);
  String get value => _value ?? name;

  static AralBasisSource fromString(String v) => AralBasisSource.values.firstWhere(
        (s) => s.value == v,
        orElse: () => throw ArgumentError('Invalid AralBasisSource value: $v'),
      );
}

class AralEnrollment {
  final int? id;
  final int studentId;
  final int schoolId;
  final int sectionId;
  final String schoolYear;
  final AralKeyStage keyStage;
  final AralTrack? track;          // null for Foundational and KS1
  final String? tutorId;           // users.id (a tutor of the school); assigned later is fine
  final AralStatus status;
  final String enteredOn;          // YYYY-MM-DD
  final String? exitedOn;          // set with exitReason when status is exited
  final AralExitReason? exitReason;
  final AralBasisSource basisSource;
  final String? basisRound;        // CRLA bosy/mosy/eosy or Phil-IRI bosy/mosy1-3/eosy
  final String? basisLevel;        // e.g. 'Low Emerging Reader', 'frustration', 'nonReader'
  /// The CRLA or Phil-IRI assessment the placement came from (no foreign key:
  /// it points at either table, and may be a local-only row until sync).
  final int? basisAssessmentId;
  final AralKeyStage? suggestedKeyStage;
  final AralTrack? suggestedTrack;
  final String? notes;
  final String? createdBy;         // users.id; stamped by the cloud
  final String? createdAt;
  final String? updatedAt;

  const AralEnrollment({
    this.id,
    required this.studentId,
    required this.schoolId,
    required this.sectionId,
    required this.schoolYear,
    required this.keyStage,
    this.track,
    this.tutorId,
    this.status = AralStatus.active,
    required this.enteredOn,
    this.exitedOn,
    this.exitReason,
    required this.basisSource,
    this.basisRound,
    this.basisLevel,
    this.basisAssessmentId,
    this.suggestedKeyStage,
    this.suggestedTrack,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  bool get isActive => status == AralStatus.active;

  /// The program label, e.g. "KS3 Plus", "KS1" or "Foundational".
  String get programLabel => track == null ? keyStage.label : '${keyStage.label} ${track!.label}';

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'student_id': studentId,
        'school_id': schoolId,
        'section_id': sectionId,
        'school_year': schoolYear,
        'key_stage': keyStage.name,
        'track': track?.name,
        'tutor_id': tutorId,
        'status': status.name,
        'entered_on': enteredOn,
        'exited_on': exitedOn,
        'exit_reason': exitReason?.value,
        'basis_source': basisSource.value,
        'basis_round': basisRound,
        'basis_level': basisLevel,
        'basis_assessment_id': basisAssessmentId,
        'suggested_key_stage': suggestedKeyStage?.name,
        'suggested_track': suggestedTrack?.name,
        'notes': notes,
        if (createdBy != null) 'created_by': createdBy,
        if (createdAt != null) 'created_at': createdAt,
        if (updatedAt != null) 'updated_at': updatedAt,
      };

  factory AralEnrollment.fromMap(Map<String, Object?> m) {
    String? s(String k) => m[k]?.toString();
    return AralEnrollment(
      id: m['id'] as int?,
      studentId: m['student_id'] as int,
      schoolId: m['school_id'] as int,
      sectionId: m['section_id'] as int,
      schoolYear: m['school_year'] as String,
      keyStage: AralKeyStage.fromString(m['key_stage'] as String),
      track: m['track'] == null ? null : AralTrack.fromString(m['track'] as String),
      tutorId: m['tutor_id'] as String?,
      status: AralStatus.fromString(m['status'] as String),
      enteredOn: s('entered_on')!.substring(0, 10),
      exitedOn: s('exited_on')?.substring(0, 10),
      exitReason: m['exit_reason'] == null ? null : AralExitReason.fromString(m['exit_reason'] as String),
      basisSource: AralBasisSource.fromString(m['basis_source'] as String),
      basisRound: m['basis_round'] as String?,
      basisLevel: m['basis_level'] as String?,
      basisAssessmentId: m['basis_assessment_id'] as int?,
      suggestedKeyStage:
          m['suggested_key_stage'] == null ? null : AralKeyStage.fromString(m['suggested_key_stage'] as String),
      suggestedTrack: m['suggested_track'] == null ? null : AralTrack.fromString(m['suggested_track'] as String),
      notes: m['notes'] as String?,
      createdBy: m['created_by'] as String?,
      createdAt: s('created_at'),
      updatedAt: s('updated_at'),
    );
  }

  AralEnrollment copyWith({
    int? sectionId,
    AralKeyStage? keyStage,
    AralTrack? Function()? track,
    String? Function()? tutorId,
    AralStatus? status,
    String? Function()? exitedOn,
    AralExitReason? Function()? exitReason,
    String? Function()? notes,
  }) =>
      AralEnrollment(
        id: id,
        studentId: studentId,
        schoolId: schoolId,
        sectionId: sectionId ?? this.sectionId,
        schoolYear: schoolYear,
        keyStage: keyStage ?? this.keyStage,
        track: track == null ? this.track : track(),
        tutorId: tutorId == null ? this.tutorId : tutorId(),
        status: status ?? this.status,
        enteredOn: enteredOn,
        exitedOn: exitedOn == null ? this.exitedOn : exitedOn(),
        exitReason: exitReason == null ? this.exitReason : exitReason(),
        basisSource: basisSource,
        basisRound: basisRound,
        basisLevel: basisLevel,
        basisAssessmentId: basisAssessmentId,
        suggestedKeyStage: suggestedKeyStage,
        suggestedTrack: suggestedTrack,
        notes: notes == null ? this.notes : notes(),
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
