// lib/core/models/phil_iri_workbook_import.dart
//
// Phil-IRI import (spec docs/superpowers/specs/2026-11-09-phil-iri-import-design.md).
// - PhilIriImportSource: where an imported session came from
//   (phil_iri_assessments.import_source; null = a live session).
// - PhilIriWorkbookImport: the one-time lock of a section and school year
//   whose workbook was imported (phil_iri_workbook_imports, synced; D10).

enum PhilIriImportSource {
  workbook('workbook'),
  scoresheet('scoresheet');

  final String value;
  const PhilIriImportSource(this.value);

  static PhilIriImportSource fromValue(String value) {
    return PhilIriImportSource.values.firstWhere(
      (s) => s.value == value,
      orElse: () => throw ArgumentError('Invalid PhilIriImportSource value: $value'),
    );
  }
}

class PhilIriWorkbookImport {
  final int? id;
  final int schoolId;
  final int sectionId;
  final String schoolYear;      // YYYY-YYYY
  final String? importedBy;     // users.id; the server stamps the uploader
  final String? importedAt;     // the server stamps the upload time

  PhilIriWorkbookImport({
    this.id,
    required this.schoolId,
    required this.sectionId,
    required this.schoolYear,
    this.importedBy,
    this.importedAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'school_id': schoolId,
        'section_id': sectionId,
        'school_year': schoolYear,
        if (importedBy != null) 'imported_by': importedBy,
        if (importedAt != null) 'imported_at': importedAt,
      };

  factory PhilIriWorkbookImport.fromMap(Map<String, Object?> m) => PhilIriWorkbookImport(
        id: m['id'] as int?,
        schoolId: m['school_id'] as int,
        sectionId: m['section_id'] as int,
        schoolYear: m['school_year'] as String,
        importedBy: m['imported_by'] as String?,
        importedAt: m['imported_at'] as String?,
      );
}
