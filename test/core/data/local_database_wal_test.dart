// The device database writes through a write-ahead log (owner 2026-11-27):
// one commit per write cost ~340 ms on the dev PC in the old rollback-journal
// mode with full sync, so a CRLA or Phil-IRI tap took about a second. WAL with
// synchronous NORMAL never corrupts the database; a power cut can lose the
// last write or two.
import 'dart:io';

import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('the database opens in WAL mode with synchronous NORMAL', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('basa_wal_');
    final ctx = await AppContext.open(dataDir: dir.path);
    final db = ctx.localDb;
    expect((await db.rawQuery('PRAGMA journal_mode')).first.values.first, 'wal');
    expect((await db.rawQuery('PRAGMA synchronous')).first.values.first, 1); // NORMAL

    // 20 single writes, each its own commit (as a tap is).
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await db.rawInsert("INSERT INTO local_ids (made_at) VALUES (datetime('now'))");
    }
    // ignore: avoid_print
    print('20 single writes: ${sw.elapsedMilliseconds} ms');
  });
}
