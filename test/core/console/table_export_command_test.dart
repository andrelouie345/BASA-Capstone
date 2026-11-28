// export-table (spec docs/superpowers/specs/2026-11-28-table-export-design.md,
// amended: Excel only): any CSV the console wrote, as a BASA .xlsx.
import 'dart:io';

import 'package:basa_capstone/core/console/commands/table_export_commands.dart';
import 'package:basa_capstone/core/console/console_registry.dart';
import 'package:basa_capstone/core/services/xlsx_cells.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/offline_owner.dart';

void main() {
  late AppContext ctx;
  late ConsoleRegistry r;
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = Directory.systemTemp.createTempSync('basa_export_table_cmd_');
    ctx = await AppContext.open(dataDir: dir.path);
    final t = wireTutor(ctx, wireShared(ctx));
    r = ConsoleRegistry();
    registerTableExportCommands(r, t.tableExportVm);
    File('${dir.path}/in.csv').writeAsStringSync('\uFEFFLRN,Name\r\n012345678901,"CRUZ, Ana"\r\n999600000002,BEN\r\n');
    await seedOfflineOwner(ctx.localDb, userId: '00000000-0000-0000-0000-0000000000c3', email: 'c@t', role: 'coordinator',
        schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'c@t', password: 'test-pw'), isNull);
  });

  test('writes the xlsx', () async {
    final out = '${dir.path}/out.xlsx';
    final said = await r.execute('export-table "${dir.path}/in.csv" "$out" Section roster year=2026-2027 filter=Grade 7');
    expect(said, startsWith('Wrote 2 rows to '));
    expect(said, endsWith('out.xlsx'));
    final b = XlsxWorkbook.decode(File(out).readAsBytesSync());
    expect(b.read('Section roster', 'A1'), 'BASA - Section roster');
    expect(b.read('Section roster', 'A2'), 'School year 2026-2027');
    expect(b.read('Section roster', 'A3'), 'Grade 7');
    expect(b.read('Section roster', 'A6'), '012345678901');
  });

  test('refusals', () async {
    expect(await r.execute('export-table "${dir.path}/in.csv" "${dir.path}/out.pdf" X'),
        'Use an output file ending in .xlsx.');
    expect(await r.execute('export-table "${dir.path}/missing.csv" "${dir.path}/o.xlsx" X'), startsWith("Couldn't read"));
    expect(await r.execute('export-table "${dir.path}/in.csv" "${dir.path}/no-such-folder/o.xlsx" X'),
        startsWith("Couldn't write"));
    expect(await r.execute('export-table'), startsWith('Usage: export-table'));
    expect(await r.execute('export-table "${dir.path}/in.csv" "${dir.path}/o.xlsx"'), startsWith('Usage: export-table'));
  });

  test('signed out', () async {
    await ctx.authVm.signOut();
    expect(await r.execute('export-table "${dir.path}/in.csv" "${dir.path}/o.xlsx" X'),
        contains('Not signed in. Sign in first.'));
  });
}
