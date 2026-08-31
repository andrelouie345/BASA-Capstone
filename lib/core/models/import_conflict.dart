// lib/core/models/import_conflict.dart
class ImportConflict {
  final int? id;
  final String lrn;
  final int? sectionId;
  final String reason;
  final String incomingDataJson;
  final int? existingStudentId;
  final String status; // pending | resolved_updated | resolved_skipped

  ImportConflict({
    this.id,
    required this.lrn,
    this.sectionId,
    required this.reason,
    required this.incomingDataJson,
    this.existingStudentId,
    this.status = 'pending',
  });

  factory ImportConflict.fromMap(Map<String, Object?> m) => ImportConflict(
        id: m['id'] as int?,
        lrn: m['lrn'] as String,
        sectionId: m['section_id'] as int?,
        reason: m['reason'] as String,
        incomingDataJson: m['incoming_data'] as String,
        existingStudentId: m['existing_student_id'] as int?,
        status: m['status'] as String,
      );
}