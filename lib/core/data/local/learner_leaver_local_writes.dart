// lib/core/data/local/learner_leaver_local_writes.dart
//
// SF1 leavers (spec docs/superpowers/specs/2026-11-12-sf1-leavers-design.md,
// sections 3-4): archive, move, restore and anonymize run on the server, one
// function each (sf1_archive_learner, sf1_move_learner, sf1_restore_learner,
// learner_anonymize). Each returns what it changed; mirrorLeaverResult copies
// that onto this device so the admin's copy is right before the next pull.
//
// Result keys (any may be missing or null):
//   enrollment       the enrollments row
//   aral_enrollment  the learner's aral_enrollments row (exited or moved)
//   student          the students row (anonymized)
//   move             the enrollment_moves row
//   moved            {crla_assessments: [{id, section_id, attempt_no}],
//                     phil_iri_assessments: [id], phil_iri_gst_results: [id]}
//                    (the moved records; their new section is the
//                    enrollment's section_id)
//
// One transaction under the sync bypass: these are server rows, so nothing
// is journaled for upload and the read-only / finalized triggers let the
// server's change through (v44). Moved rows this device doesn't hold are
// skipped (an admin's copy may not have them).
import 'package:sqflite_common/sqflite.dart';

import '../pull_tables.dart';
import 'mirror_write.dart';
import 'sync_local_writes.dart';

Future<void> mirrorLeaverResult(Database db, Map<String, dynamic> result) async {
  final enrollment = _row(result['enrollment']);
  final aral = _row(result['aral_enrollment']);
  final student = _row(result['student']);
  final move = _row(result['move']);
  final moved = _row(result['moved']);

  await db.transaction((txn) => withSyncBypass(txn, () async {
        Future<Set<String>> columns(String t) async =>
            (await txn.rawQuery('PRAGMA table_info($t)')).map((c) => c['name'] as String).toSet();

        if (student != null) {
          await upsertById(txn, 'students', serverRowToLocal(student, await columns('students')));
        }
        if (enrollment != null) {
          await upsertById(txn, 'enrollments', serverRowToLocal(enrollment, await columns('enrollments')));
        }
        if (aral != null) {
          // A server row: origin 'cloud', and the server's row_version.
          // upsertById, not mirrorSyncedRow: that opens its own transaction
          // (can't nest in this one), and this row carries its row_version.
          final local = serverRowToLocal(aral, await columns('aral_enrollments'))..['origin'] = 'cloud';
          await upsertById(txn, 'aral_enrollments', local);
        }
        if (move != null) {
          await upsertById(txn, 'enrollment_moves', serverRowToLocal(move, await columns('enrollment_moves')));
        }

        if (moved != null) {
          final toSection = enrollment?['section_id'];
          // Final (section_id, attempt_no) per moved row, per table.
          final targets = <String, List<(Object, Object?, Object?)>>{
            'crla_assessments': [
              for (final c in (moved['crla_assessments'] as List? ?? const []))
                (c['id'] as Object, c['section_id'], c['attempt_no']),
            ],
          };
          for (final table in ['phil_iri_assessments', 'phil_iri_gst_results']) {
            final ids = moved[table] as List? ?? const [];
            if (ids.isEmpty) continue;
            if (toSection == null) {
              throw ArgumentError('A move result lists moved $table rows but has no enrollment (new section)');
            }
            targets[table] = [for (final id in ids) (id as Object, toSection, null)];
          }
          // Two passes: the device copy may be older than the server's (a
          // move this device hasn't pulled), so a moved row's final key can
          // be held by another moved row that hasn't been written yet. Park
          // every listed row first on a key no real row has (section_id =
          // -id: attempt_no can't go negative, CHECK >= 0), then write the
          // final values. Each update also bumps row_version by one, as the
          // server's basa_bump_row_version did (20261020020000).
          for (final e in targets.entries) {
            for (final (id, _, _) in e.value) {
              await txn.rawUpdate('UPDATE ${e.key} SET section_id = -id WHERE id = ?', [id]);
            }
          }
          for (final e in targets.entries) {
            for (final (id, section, attempt) in e.value) {
              await txn.rawUpdate(
                  'UPDATE ${e.key} SET section_id = ?${attempt == null ? '' : ', attempt_no = ?'}, '
                  'row_version = row_version + 1 WHERE id = ?',
                  [section, ?attempt, id]);
            }
          }
        }
      }));
}

Map<String, dynamic>? _row(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// The learner's records on this device that an archive, move or restore
/// would change (or stop at upload) but that are not on the server as they
/// are here: new (never uploaded), edited (journaled in sync_changes) or
/// waiting in an upload (sync_pending, which also holds an upload in flight:
/// its locks are written before it is sent). Only the learner of
/// [enrollmentId], only that enrollment's school year, only the four
/// learner-keyed records the server functions touch. 0 when the enrollment
/// is not on this device (nothing of the learner can be unsent here then).
Future<int> leaverUnsentRecords(DatabaseExecutor db, int enrollmentId) async {
  final e = await db.query('enrollments',
      columns: ['student_id', 'school_year'], where: 'id = ?', whereArgs: [enrollmentId], limit: 1);
  if (e.isEmpty) return 0;
  final student = e.first['student_id'], year = e.first['school_year'];
  var n = 0;
  for (final t in const ['crla_assessments', 'phil_iri_assessments', 'phil_iri_gst_results', 'aral_enrollments']) {
    final key = syncedTables[t]!;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS n FROM $t r
      WHERE r.student_id = ? AND r.school_year = ?
        AND (r.origin = 'local'
          OR EXISTS (SELECT 1 FROM sync_changes c WHERE c.table_name = '$t' AND c.row_key = CAST(r.$key AS TEXT))
          OR EXISTS (SELECT 1 FROM sync_pending p WHERE p.table_name = '$t' AND p.row_key = CAST(r.$key AS TEXT)))
    ''', [student, year]);
    n += (rows.first['n'] as num).toInt();
  }
  return n;
}
