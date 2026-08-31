// lib/core/services/roster_exporter.dart
import 'dart:io';
import '../models/student.dart';

class RosterExporter {
  Future<String> exportToCsv(List<Student> students, String outputPath) async {
    final headers = [
      'LRN', 'Last Name', 'First Name', 'Middle Name', 'Sex', 'Birth Date',
      'Mother Tongue', 'IP Group', 'Religion', 'Address', 'Barangay',
      'Municipality', 'Province', "Father's Name", "Mother's Maiden Name",
      'Guardian Name', 'Guardian Relationship', 'Contact Number',
      'Learning Modality', 'Remarks',
    ];

    final rows = students.map((s) => [
          s.lrn, s.lastName, s.firstName, s.middleName ?? '', s.sex ?? '',
          s.birthDate ?? '', s.motherTongue ?? '', s.ipGroup ?? '', s.religion ?? '',
          s.addressStreet ?? '', s.barangay ?? '', s.municipality ?? '', s.province ?? '',
          s.fatherName ?? '', s.motherMaidenName ?? '', s.guardianName ?? '',
          s.guardianRelationship ?? '', s.contactNumber ?? '', s.learningModality ?? '',
          s.remarks ?? '',
        ]);

    final buffer = StringBuffer();
    buffer.writeln(headers.map(_csvEscape).join(','));
    for (final row in rows) {
      buffer.writeln(row.map(_csvEscape).join(','));
    }

    final file = File(outputPath);
    await file.writeAsString(buffer.toString());
    return outputPath;
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}