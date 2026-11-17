// The pull's refusal when kept work points at data the server no longer
// gives this user (SyncViewModel.pull, pullOrphansRefusal). A learner moved
// to another section (SF1 leavers D14) still takes the old tutor's unsent
// work on upload, so the message sends them to Send my work first and keeps
// "Delete unsent work and download" as the last resort. Plain words only
// (owner 2026-11-17): no table names, keys or console commands.
import 'package:basa_capstone/core/models/sync_pull.dart';
import 'package:basa_capstone/viewmodels/sync_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PullOrphan orphan(String refTable) =>
      PullOrphan(table: 'crla_assessments', key: '-1', column: 'student_id', refTable: refTable, refValue: 900);

  test('a learner or section gone: send first, "Delete unsent work and download" last', () {
    for (final ref in ['students', 'sections']) {
      final m = pullOrphansRefusal([orphan(ref)]);
      expect(m, startsWith('Not downloaded, nothing was changed: 1 record on this device belongs to learners, '
          'sections or records the server no longer gives you.\n'));
      expect(m, contains('Send your work first (Send my work), then download again.'));
      expect(m, endsWith('Only if it cannot be sent: use "Delete unsent work and download" (it deletes this work).'));
      expect(m, isNot(matches(RegExp(r'crla_|-1\b|pull-cloud|sync-'))));
    }
  });

  test('any other missing parent keeps the delete advice', () {
    final m = pullOrphansRefusal([orphan('aral_classes'), orphan('aral_classes')]);
    expect(m, startsWith('Not downloaded, nothing was changed: 2 records on this device belong to'));
    expect(m, isNot(contains('Send my work')));
    expect(m, endsWith("To go on, use \"Delete unsent work and download\" (it deletes this device's unsent work)."));
  });
}
