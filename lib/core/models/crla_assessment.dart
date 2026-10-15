// lib/core/models/crla_assessment.dart
import 'dart:convert';

import 'crla_language.dart';

class CrlaAssessment {
  final int? id;
  final int studentId;
  final int schoolId;
  final int sectionId;
  final String schoolYear;
  final String subjectVariant; // 'mt' | 'fil' | 'eng'
  final String language;
  final int? attemptNo;        // assigned by the DB trigger on insert
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