// The pull's refusal when kept work points at data the server no longer
// gives this user (SyncViewModel.pull, pullOrphansRefusal). A learner moved
// to another section (SF1 leavers D14) still takes the old tutor's unsent
// work on upload, so the message sends them to sync-upload first and keeps
// discard-local (which deletes the work) as the last resort.
import 'package:basa_capstone/core/models/sync_pull.dart';
import 'package:basa_capstone/viewmodels/sync_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PullOrphan orphan(String refTable) =>
      PullOrphan(table: 'crla_assessments', key: '-1', column: 'student_id', refTable: refTable, refValue: 900);

  test('a learner or section gone: upload first, discard-local last', () {
    for (final ref in ['students', 'sections']) {
      final m = pullOrphansRefusal([orphan(ref)]);
      expect(m, startsWith('Refused, nothing was changed: 1 record(s) on this device point at data the server '
          'no longer gives you:\n  crla_assessments -1: $ref 900'));
      expect(m, contains("Upload this device's work first (sync-upload), then pull again."));
      expect(m, endsWith("Only if the upload can't go: pull-cloud yes discard-local (it deletes this work)."));
    }
  });

  test('any other missing parent keeps the discard-local advice', () {
    final m = pullOrphansRefusal([orphan('aral_classes')]);
    expect(m, isNot(contains('sync-upload')));
    expect(m, endsWith("To go on, download again and delete this device's unsent work (pull-cloud yes discard-local)."));
  });
}
