// Plain sync messages for screens (owner 2026-11-17: readers of English as a
// second language): no table names, keys, versions or console commands, and
// "1 record" / "3 records" instead of "record(s)". toString() stays the
// console's.
import 'package:basa_capstone/core/models/sync_pull.dart';
import 'package:basa_capstone/core/models/sync_upload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const conflict = SyncProblem(
      table: 'crla_assessments', key: '-12', kind: 'conflict', baseVersion: 3, serverVersion: 5, owner: 'DELA CRUZ, JUAN');

  test('a conflict names the record and says what each choice does', () {
    expect(conflict.message,
        'The CRLA attempt of DELA CRUZ, JUAN was changed on the server after your last download. Keep mine: '
        "your version replaces the server's. Take the server's: your change is removed from this device.");
    // The console keeps its own text.
    expect('$conflict', 'crla_assessments -12: changed on the server (yours from version 3, server now 5)');
  });

  test('without an owner on this device the kind alone is named; no table, key or version', () {
    const gone = SyncProblem(table: 'aral_attendance', key: '88', kind: 'server_deleted');
    expect(gone.message,
        'An attendance mark is no longer on the server for you: it was deleted, or it is not in your sections '
        "any more. Take the server's to remove it from this device.");
    for (final m in [conflict.message, gone.message]) {
      expect(m, isNot(matches(RegExp(r'crla_|aral_|-12|version [0-9]|server now|sync-'))));
    }
  });

  test('outcomes count records in words and list their conflicts plainly', () {
    expect(const SyncOutcome(uploadId: 7, status: 'rejected', records: 1, reason: 'wrong learner').message,
        'Upload 7 was rejected: wrong learner. You can change its 1 record and send it again.');
    final sentBack = SyncOutcome(uploadId: 8, status: 'conflict', records: 3, conflicts: [conflict]).message;
    expect(sentBack, startsWith('Upload 8 was stopped because some records were changed on the server.'));
    expect(sentBack, contains('its 3 records again'));
    expect(sentBack, contains('• The CRLA attempt of DELA CRUZ, JUAN was changed'));
    expect(const SyncUploadResult(uploadId: 9, records: 2).message, 'Upload 9 was sent (2 records). It waits for approval.');
  });

  test('a resolution says what happened to the record', () {
    expect(
        const SyncResolution(table: 'aral_sessions', key: '-3', choice: SyncChoice.server, serverVersion: 4, owner: 'class "ABA" on 2026-11-10')
            .message,
        'The ARAL session of class "ABA" on 2026-11-10 now has the server\'s version.');
    expect(const SyncResolution(table: 'aral_sessions', key: '-3', choice: SyncChoice.mine, serverVersion: 4).message,
        "An ARAL session keeps your version. It replaces the server's when you send your work.");
  });

  test('unsent-work lines: plural words, section by name, no section id', () {
    const many = LocalWorkLine(
        kind: 'Phil-IRI session(s)', count: 3, sectionId: 28, gradeLevel: '7', sectionName: 'RIZAL', schoolYear: '2025-2026');
    expect(many.message, '3 Phil-IRI sessions · Grade 7 RIZAL, 2025-2026');
    expect(const LocalWorkLine(kind: 'ARAL readability log entr(ies)', count: 1).message, '1 ARAL readability log entry');
    expect(const LocalWorkLine(kind: 'ARAL class(es)', count: 2).message, '2 ARAL classes');
    expect(const LocalWorkLine(kind: 'GST', count: 1, sectionId: 5).message, '1 GST · a section not on this device');
  });
}
