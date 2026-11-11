// lib/core/data/local/phil_iri_import_writer_sqlite.dart
//
// The Phil-IRI import's device writes (spec 2026-11-09-phil-iri-import-design,
// import()). Every row gets a negative id from nextLocalId and row_version
// NULL, so the next upload sends it. The device triggers check each row as
// for a live session, with the import exceptions (phil_iri_local_schema.dart:
// no active/no-repeat check, position-less miscues, imported counts, v42
// Untitled readings); the own-grade check stays.
import 'package:sqflite_common/sqflite.dart';

import '../../models/phil_iri_assessment.dart';
import '../../models/phil_iri_reading.dart';
import '../../repositories/phil_iri_import_writer.dart';
import '../../models/phil_iri_gst_result.dart';
import '../../models/phil_iri_workbook_import.dart';
import 'sqlite_values.dart';
import 'sync_local_writes.dart';

class PhilIriImportWriterSqlite implements PhilIriImportWriter {
  final Database db;
  PhilIriImportWriterSqlite(this.db);

  @override
  Future<List<int>> writeLearner({
    required List<PhilIriImportedSession> sessions,
    PhilIriGstResult? gst,
    PhilIriWorkbookImport? lock,
  }) =>
      db.transaction((txn) async {
        if (gst != null) {
          // attempt_no left out (default 0): the AFTER INSERT trigger assigns it.
          await txn.insert('phil_iri_gst_results', {
            ...toSqliteRow(gst.toMap())..remove('attempt_no'),
            'id': await nextLocalId(txn),
          });
        }
        final ids = <int>[];
        for (final s in sessions) {
          ids.add(await _session(txn, s));
        }
        if (lock != null) {
          // imported_by / imported_at: the server stamps the uploader and time.
          await txn.insert('phil_iri_workbook_imports', {
            ...lock.toMap()..remove('imported_by')..remove('imported_at'),
            'id': await nextLocalId(txn),
          });
        }
        return ids;
      });

  Future<int> _session(DatabaseExecutor txn, PhilIriImportedSession s) async {
    // A new session starts in progress (device trigger), then completes.
    final sessionId = await nextLocalId(txn);
    await txn.insert('phil_iri_assessments', {
      ...toSqliteRow(s.assessment.toMap())..remove('attempt_no'),
      'id': sessionId,
      'status': PhilIriStatus.inProgress.value,
      'completed_at': null,
      'finalized_at': null,
      'thresholds_snapshot': null,
    });

    final reading = toSqliteRow(s.reading.toMap());
    for (final c in PhilIriReading.resultColumns) {
      reading.remove(c); // results are written at finalization only
    }
    final readingId = await nextLocalId(txn);
    await txn.insert('phil_iri_readings', {...reading, 'id': readingId, 'assessment_id': sessionId});

    for (final m in s.miscues) {
      await txn.insert('phil_iri_miscues',
          {...toSqliteRow(m.toMap()), 'id': await nextLocalId(txn), 'reading_id': readingId});
    }
    for (final a in s.answers) {
      // is_correct is computed from the key by the device trigger.
      await txn.insert('phil_iri_answers',
          {...toSqliteRow(a.toMap()), 'id': await nextLocalId(txn), 'reading_id': readingId});
    }

    await txn.update(
      'phil_iri_assessments',
      {'status': PhilIriStatus.completed.value, 'completed_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    return sessionId;
  }

  @override
  Future<bool> isLocked(int sectionId, String schoolYear) async {
    final rows = await db.query('phil_iri_workbook_imports',
        columns: ['id'], where: 'section_id = ? AND school_year = ?', whereArgs: [sectionId, schoolYear], limit: 1);
    return rows.isNotEmpty;
  }
}
