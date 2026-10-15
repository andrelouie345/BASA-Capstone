// lib/core/models/crla_assessment.dart
import 'dart:convert';

import 'crla_language.dart';

/// The CRLA administration within the school year (DepEd: BOSY, MOSY, EOSY).
/// ARAL-Reading enrolls Grade 1 learners on their MOSY result and Grades 2-3
/// on BOSY (owner, 2026-10-15). Rows from before the round existed are BOSY.
enum CrlaRound {
  bosy('BOSY'),
  mosy('MOSY'),
  eosy('EOSY');

  final String label;
  const CrlaRound(this.label);

  static CrlaRound fromString(String value) => CrlaRound.values.firstWhere(
        (r) => r.name == value || r.label == value,
        orElse: () => throw ArgumentError('Invalid CrlaRound value: $value'),
      );
}

class CrlaAssessment {
  final int? id;
  final int studentId;
  final int schoolId;
  final int sectionId;
  final String schoolYear;
  final String subjectVariant; // 'mt' | 'fil' | 'eng'
  final String language;
  final CrlaRound round;
  /// Assigned by the DB trigger on insert: the nth CRLA attempt of the learner
  /// in that section/variant/year, counted across rounds. The latest attempt
  /// of a round is the one with the highest attempt_no in it.
  final int? attemptNo;
  final String assessedAt;
  final String? administeredBy;
  /// The CRLA thresholds this assessment is scored with (CrlaThresholds.toMap),
  /// taken when it was started. Null on rows from before v14 = the defaults.
  /// The cloud stamps its own on insert; a value sent there is ignored.
  final Map<String, Object?>? thresholdsSnapshot;
  /// Stored reading profile, computed from Part 1 + Part 2 with the snapshot.
  final String? readingProfile;

  CrlaAssessment({
    this.id,
    required this.studentId,
    required this.schoolId,
    required this.sectionId,
    required this.schoolYear,
    required this.subjectVariant,
    required this.language,
    this.round = CrlaRound.bosy,
    this.attemptNo,
    required this.assessedAt,
    this.administeredBy,
    this.thresholdsSnapshot,
    this.readingProfile,
  });
 String get normalizedLanguage =>
      subjectVariant == 'fil' ? 'Tagalog' : normalizeCrlaLanguage(language);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'student_id': studentId,
        'school_id': schoolId,
        'section_id': sectionId,
        'school_year': schoolYear,
        'subject_variant': subjectVariant,
        'language': normalizedLanguage,
        'round': round.name,
        if (attemptNo != null) 'attempt_no': attemptNo,
        'assessed_at': assessedAt,
        if (administeredBy != null) 'administered_by': administeredBy,
        if (thresholdsSnapshot != null) 'thresholds_snapshot': thresholdsSnapshot,
        if (readingProfile != null) 'reading_profile': readingProfile,
      };

  factory CrlaAssessment.fromMap(Map<String, Object?> m) => CrlaAssessment(
        id: m['id'] as int?,
        studentId: m['student_id'] as int,
        schoolId: m['school_id'] as int,
        sectionId: m['section_id'] as int,
        schoolYear: m['school_year'] as String,
        subjectVariant: m['subject_variant'] as String,
        language: m['language'] as String,
        round: m['round'] == null ? CrlaRound.bosy : CrlaRound.fromString(m['round'] as String),
        attemptNo: m['attempt_no'] as int?,
        assessedAt: m['assessed_at'] as String,
        administeredBy: m['administered_by'] as String?,
        // jsonb comes back decoded; SQLite holds a JSON string.
        thresholdsSnapshot: switch (m['thresholds_snapshot']) {
          String s => (jsonDecode(s) as Map).cast<String, Object?>(),
          Map x => x.cast<String, Object?>(),
          _ => null,
        },
        readingProfile: m['reading_profile'] as String?,
      );
}