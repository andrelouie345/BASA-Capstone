// A CSV the console wrote, read into an ExportTable (spec 2026-11-28 table
// export): first row = columns; a column is a number column only when every
// value is a plain number, so an LRN stays text.
import 'dart:io';

import 'package:basa_capstone/core/models/export_table.dart';
import 'package:basa_capstone/core/models/messages.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

void main() {
  late AppContext ctx;
  late TutorVms t;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_table_export_csv_').path);
    t = wireTutor(ctx, wireShared(ctx));
    await seedOfflineOwner(ctx.localDb, userId: '00000000-0000-0000-0000-0000000000c2', email: 'c@t', role: 'coordinator',
        schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: 'c@t', password: 'test-pw'), isNull);
  });

  test('LRN column stays text', () {
    final table = t.tableExportVm.tableFromCsv(
        '\uFEFFLRN,Name,Score\r\n012345678901,"CRUZ, Ana",8\r\n\r\n999600000002,"CRUZ, Ben",\r\n', 'Roster',
        schoolYear: '2026-2027', filters: ['Grade 7']);
    expect(table.title, 'Roster');
    expect(table.schoolYear, '2026-2027');
    expect(table.filters, ['Grade 7']);
    expect(table.columns.map((c) => (c.label, c.kind)),
        [('LRN', ExportColumnKind.text), ('Name', ExportColumnKind.text), ('Score', ExportColumnKind.number)]);
    expect(table.rows, [
      ['012345678901', 'CRUZ, Ana', 8],
      ['999600000002', 'CRUZ, Ben', null],
    ]);
  });

  test('10-digit cap and signs', () {
    final table = t.tableExportVm.tableFromCsv('A,B,C\n12345678901,-3,0\n5,2.5,0.5\n', 'X');
    expect(table.columns.map((c) => c.kind), [ExportColumnKind.text, ExportColumnKind.number, ExportColumnKind.number]);
    expect(table.rows.last, ['5', 2.5, 0.5]);
  });

  test('signed out', () async {
    await ctx.authVm.signOut();
    expect(() => t.tableExportVm.tableFromCsv('A\n1\n', 'X'),
        throwsA(isA<ViewModelException>().having((e) => e.message, 'message', notSignedInMessage)));
  });
}
