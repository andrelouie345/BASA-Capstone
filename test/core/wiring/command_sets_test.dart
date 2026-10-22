// Pins the exact console command set of each build, so a command that lands
// in the wrong half (or vanishes) fails here instead of at release time.
import 'dart:io';

import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

List<String> _expected(String file) =>
    File('test/core/wiring/$file').readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();

void main() {
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = Directory.systemTemp.createTempSync('basa_wiring_');
  });

  test('admin build registers exactly the baseline commands', () async {
    final ctx = await AppContext.open(dataDir: dir.path);
    final s = wireShared(ctx);
    final t = wireTutor(ctx, s);
    final a = await wireAdmin(ctx, s, t);
    registerSharedCommands(ctx, s);
    registerTutorCommands(ctx, s, t);
    registerAdminCommands(ctx, s, t, a);
    registerDevCommands(ctx, s);

    final names = ctx.registry.all.map((c) => c.name).toList()..sort();
    expect(names, _expected('admin_commands.txt'));
  });
}
