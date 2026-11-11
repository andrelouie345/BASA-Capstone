// lib/core/repositories/phil_iri_import_writer.dart
//
// Phil-IRI import (spec docs/superpowers/specs/2026-11-09-phil-iri-import-design.md):
// writes what the import ViewModel built, one learner per device transaction.
// Device only: the rows reach the server through the normal upload.
import '../models/phil_iri_answer.dart';
import '../models/phil_iri_assessment.dart';
import '../models/phil_iri_gst_result.dart';
import '../models/phil_iri_miscue.dart';
import '../models/phil_iri_reading.dart';
import '../models/phil_iri_workbook_import.dart';

/// One imported session: the session (importSource set), its one reading,
/// the reading's miscues (no position) and answers (scoresheet only). The
/// ids and the links between them (assessmentId, readingId) are ignored:
/// the writer gives every row a local id and links them itself.
class PhilIriImportedSession {
  final PhilIriAssessment assessment;
  final PhilIriReading reading;
  final List<PhilIriMiscue> miscues;
  final List<PhilIriAnswer> answers;

  const PhilIriImportedSession({
    required this.assessment,
    required this.reading,
    this.miscues = const [],
    this.answers = const [],
  });
}

abstract class PhilIriImportWriter {
  /// One transaction: [gst], then each session (created in progress, its
  /// reading, miscues and answers, then completed), then [lock]. A refusal
  /// by any device trigger rolls the whole call back and is rethrown.
  /// Returns the new session ids, in the order given.
  Future<List<int>> writeLearner({
    required List<PhilIriImportedSession> sessions,
    PhilIriGstResult? gst,
    PhilIriWorkbookImport? lock,
  });

  /// Whether this section's workbook for [schoolYear] was already imported
  /// (a lock row on this device, written here or pulled).
  Future<bool> isLocked(int sectionId, String schoolYear);
}
