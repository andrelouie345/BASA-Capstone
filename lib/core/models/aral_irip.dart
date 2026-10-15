// lib/core/models/aral_irip.dart
//
// ARAL-Reading Individual Reading Intervention Plan (IRIP). Source:
// IRIP_ARAL-Reading Basic and Plus_v09122025.docx. Owner decisions (2026-10-16):
//  * KS2-3 Basic, KS2 Plus and KS3 Plus have an IRIP; KS1 and Foundational
//    don't (for now).
//  * Basic runs a Filipino and an English strand in parallel (each week one
//    target per strand); Plus has one strand of 8 targets, each a group of
//    skills.
//  * A cycle is 8 weeks; each week the tutor rates the week's target and
//    writes notes. A new cycle continues when the learner is still in ARAL.
import 'aral_enrollment.dart';

/// The IRIP target list a learner follows.
enum AralIripProgram {
  basicKs23('basic_ks23', 'KS2-3 Basic'),
  plusKs2('plus_ks2', 'KS2 Plus'),
  plusKs3('plus_ks3', 'KS3 Plus');

  final String value;
  final String label;
  const AralIripProgram(this.value, this.label);

  static AralIripProgram fromString(String v) => AralIripProgram.values.firstWhere(
        (p) => p.value == v || p.name == v,
        orElse: () => throw ArgumentError('Invalid AralIripProgram value: $v'),
      );

  /// The IRIP of a placement; null for Foundational and KS1 (no IRIP).
  static AralIripProgram? of(AralKeyStage keyStage, AralTrack? track) => switch ((keyStage, track)) {
        (AralKeyStage.ks2 || AralKeyStage.ks3, AralTrack.basic) => basicKs23,
        (AralKeyStage.ks2, AralTrack.plus) => plusKs2,
        (AralKeyStage.ks3, AralTrack.plus) => plusKs3,
        _ => null,
      };

  /// The strands that run in parallel each week.
  List<AralIripStrand> get strands =>
      this == basicKs23 ? const [AralIripStrand.filipino, AralIripStrand.english] : const [AralIripStrand.main];
}

enum AralIripStrand {
  filipino('Filipino'),
  english('English'),
  main('');

  final String label;
  const AralIripStrand(this.label);

  static AralIripStrand fromString(String v) => AralIripStrand.values.firstWhere(
        (s) => s.name == v,
        orElse: () => throw ArgumentError('Invalid AralIripStrand value: $v'),
      );
}

/// The week's rating (IRIP status legend).
enum AralIripStatus {
  observed('observed', '✔', 'Observed: ready to proceed to the next reading target'),
  partial('partial', '◑', 'Partially observed: needs additional practice on the current reading target'),
  notObserved('not_observed', '✘', 'Not observed: reteach the current reading target');

  final String value;
  final String symbol;
  final String meaning;
  const AralIripStatus(this.value, this.symbol, this.meaning);

  static AralIripStatus fromString(String v) => AralIripStatus.values.firstWhere(
        (s) => s.value == v || s.name == v,
        orElse: () => throw ArgumentError('Invalid AralIripStatus value: $v'),
      );
}

/// One reading target of a list (content; mirrored from the cloud).
class AralIripTarget {
  final int id;
  final AralIripProgram program;
  final AralIripStrand strand;
  final int seq;
  final String? focus;        // Basic: phonological awareness focus
  final String? letterFocus;  // Basic
  final String? sightWords;   // Basic
  final String? skills;       // Plus: one skill per line
  final bool isActive;

  const AralIripTarget({
    required this.id,
    required this.program,
    required this.strand,
    required this.seq,
    this.focus,
    this.letterFocus,
    this.sightWords,
    this.skills,
    this.isActive = true,
  });

  List<String> get skillList => (skills ?? '').split('\n').where((s) => s.trim().isNotEmpty).toList();

  /// A one-line label, e.g. "Filipino 2: Alliteration" or "Target 3: Reading words ... (+1 more)".
  String get label {
    if (program == AralIripProgram.basicKs23) return '${strand.label} $seq: $focus';
    final list = skillList;
    final more = list.length > 1 ? ' (+${list.length - 1} more)' : '';
    return 'Target $seq: ${list.isEmpty ? '' : list.first}$more';
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'program': program.value,
        'strand': strand.name,
        'seq': seq,
        'focus': focus,
        'letter_focus': letterFocus,
        'sight_words': sightWords,
        'skills': skills,
        'is_active': isActive,
      };

  factory AralIripTarget.fromMap(Map<String, Object?> m) => AralIripTarget(
        id: m['id'] as int,
        program: AralIripProgram.fromString(m['program'] as String),
        strand: AralIripStrand.fromString(m['strand'] as String),
        seq: m['seq'] as int,
        focus: m['focus'] as String?,
        letterFocus: m['letter_focus'] as String?,
        sightWords: m['sight_words'] as String?,
        skills: m['skills'] as String?,
        isActive: m['is_active'] == null || m['is_active'] == true || m['is_active'] == 1,
      );
}

/// One week of a learner's IRIP for one strand.
class AralIripWeek {
  final int? id;
  final int enrollmentId;   // aral_enrollments.id
  final int cycleNo;        // 1, 2, ... (8 weeks each)
  final int weekNo;         // 1-8
  final AralIripStrand strand;
  final int targetId;
  final AralIripStatus? status;  // null = not rated yet
  final String? ratedOn;         // YYYY-MM-DD, set with status
  final String? notes;
  final String? createdBy;
  final String? createdAt;
  final String? updatedAt;

  const AralIripWeek({
    this.id,
    required this.enrollmentId,
    this.cycleNo = 1,
    required this.weekNo,
    required this.strand,
    required this.targetId,
    this.status,
    this.ratedOn,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  bool get isRated => status != null;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'enrollment_id': enrollmentId,
        'cycle_no': cycleNo,
        'week_no': weekNo,
        'strand': strand.name,
        'target_id': targetId,
        'status': status?.value,
        'rated_on': ratedOn,
        'notes': notes,
        if (createdBy != null) 'created_by': createdBy,
        if (createdAt != null) 'created_at': createdAt,
        if (updatedAt != null) 'updated_at': updatedAt,
      };

  factory AralIripWeek.fromMap(Map<String, Object?> m) => AralIripWeek(
        id: m['id'] as int?,
        enrollmentId: m['enrollment_id'] as int,
        cycleNo: m['cycle_no'] as int,
        weekNo: m['week_no'] as int,
        strand: AralIripStrand.fromString(m['strand'] as String),
        targetId: m['target_id'] as int,
        status: m['status'] == null ? null : AralIripStatus.fromString(m['status'] as String),
        ratedOn: m['rated_on']?.toString().substring(0, 10),
        notes: m['notes'] as String?,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );

  AralIripWeek copyWith({
    int? targetId,
    AralIripStatus? Function()? status,
    String? Function()? ratedOn,
    String? Function()? notes,
  }) =>
      AralIripWeek(
        id: id,
        enrollmentId: enrollmentId,
        cycleNo: cycleNo,
        weekNo: weekNo,
        strand: strand,
        targetId: targetId ?? this.targetId,
        status: status == null ? this.status : status(),
        ratedOn: ratedOn == null ? this.ratedOn : ratedOn(),
        notes: notes == null ? this.notes : notes(),
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
