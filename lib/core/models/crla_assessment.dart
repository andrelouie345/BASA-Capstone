// lib/core/models/crla_assessment.dart
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
        'language': normalizedLanguage, // was: language
        if (attemptNo != null) 'attempt_no': attemptNo,
        'assessed_at': assessedAt,
        if (administeredBy != null) 'administered_by': administeredBy,
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
      );
  // String normalizeCrlaLanguage(String subjectVariant, String language) {
  // if (subjectVariant == 'fil') return 'Tagalog';
  // return language;
  // }

  
}