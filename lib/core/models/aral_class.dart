// lib/core/models/aral_class.dart
//
// An ARAL class: the group a tutor actually teaches (DepEd Memorandum 064 s.
// 2025: at most 15 learners, grouped by reading profile). Offline-first and
// synced like the roster; same columns as the cloud table aral_classes
// (20261023040000, grade and mixed programs 20261024010000).
//
// Owner decisions (2026-10-23, spec docs/superpowers/specs/2026-10-23-aral-classes-design.md):
//  * A class belongs to a school and a school year, not to a section; its
//    learners come from any section of the school.
//  * At most 15 active learners (aralClassCap, the placement rules are in
//    aral_rules.dart).
// Owner decisions (2026-10-24, from the reading coordinator; plan
// docs/superpowers/plans/2026-10-24-aral-class-grade.md G1-G2):
//  * A class has a home grade (1-10) and one program or mixed programs
//    (program null). The grade band (1-3 / 4-6 / 7-10) is gone.
//  * One tutor, possibly blank for a while; a tutor may teach several classes.
import 'aral_enrollment.dart';

/// The ARAL program a class teaches: a key stage, plus the track for KS2/KS3.
enum AralClassProgram {
  foundational('foundational', 'Foundational'),
  ks1('ks1', 'KS1'),
  ks2Basic('ks2_basic', 'KS2 Basic'),
  ks2Plus('ks2_plus', 'KS2 Plus'),
  ks3Basic('ks3_basic', 'KS3 Basic'),
  ks3Plus('ks3_plus', 'KS3 Plus');

  final String value;
  final String label;
  const AralClassProgram(this.value, this.label);

  /// The program of a learner placed in [ks] with [track] (null for
  /// Foundational and KS1).
  static AralClassProgram of(AralKeyStage ks, AralTrack? track) => switch (ks) {
        AralKeyStage.foundational => foundational,
        AralKeyStage.ks1 => ks1,
        AralKeyStage.ks2 => track == AralTrack.plus ? ks2Plus : ks2Basic,
        AralKeyStage.ks3 => track == AralTrack.plus ? ks3Plus : ks3Basic,
      };

  static AralClassProgram fromString(String v) => AralClassProgram.values.firstWhere(
        (p) => p.value == v,
        orElse: () => throw ArgumentError('Invalid AralClassProgram value: $v'),
      );
}

class AralClass {
  final int? id;
  final int schoolId;
  final String schoolYear;
  final String className;
  final int gradeLevel;              // the home grade, 1-10
  final AralClassProgram? program;   // null = mixed programs
  final String? tutorId;       // users.id, an active tutor of the school; null = none yet
  final String? room;
  final String? schedule;
  final String? notes;
  final String? createdBy;     // users.id; stamped by the cloud
  final String? createdAt;
  final String? updatedAt;

  const AralClass({
    this.id,
    required this.schoolId,
    required this.schoolYear,
    required this.className,
    required this.gradeLevel,
    this.program,
    this.tutorId,
    this.room,
    this.schedule,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'school_id': schoolId,
        'school_year': schoolYear,
        'class_name': className,
        'grade_level': gradeLevel,
        'program': program?.value,
        'tutor_id': tutorId,
        'room': room,
        'schedule': schedule,
        'notes': notes,
        if (createdBy != null) 'created_by': createdBy,
        if (createdAt != null) 'created_at': createdAt,
        if (updatedAt != null) 'updated_at': updatedAt,
      };

  factory AralClass.fromMap(Map<String, Object?> m) => AralClass(
        id: m['id'] as int?,
        schoolId: m['school_id'] as int,
        schoolYear: m['school_year'] as String,
        className: m['class_name'] as String,
        gradeLevel: m['grade_level'] as int,
        program: m['program'] == null ? null : AralClassProgram.fromString(m['program'] as String),
        tutorId: m['tutor_id'] as String?,
        room: m['room'] as String?,
        schedule: m['schedule'] as String?,
        notes: m['notes'] as String?,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );

  AralClass copyWith({
    String? className,
    int? gradeLevel,
    AralClassProgram? Function()? program,
    String? Function()? tutorId,
    String? Function()? room,
    String? Function()? schedule,
    String? Function()? notes,
  }) =>
      AralClass(
        id: id,
        schoolId: schoolId,
        schoolYear: schoolYear,
        className: className ?? this.className,
        gradeLevel: gradeLevel ?? this.gradeLevel,
        program: program == null ? this.program : program(),
        tutorId: tutorId == null ? this.tutorId : tutorId(),
        room: room == null ? this.room : room(),
        schedule: schedule == null ? this.schedule : schedule(),
        notes: notes == null ? this.notes : notes(),
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Whether the class takes every program.
  bool get isMixed => program == null;

  /// `Grade 7, KS2 Basic` or `Grade 7, mixed programs`.
  String get groupLabel => 'Grade $gradeLevel, ${program?.label ?? 'mixed programs'}';
}
