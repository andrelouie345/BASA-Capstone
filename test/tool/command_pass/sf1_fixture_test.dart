// SF1 workbook generator of the command pass (tool/command_pass/sf1_fixture.dart).
import 'dart:io';

import 'package:basa_capstone/core/models/region.dart';
import 'package:basa_capstone/core/services/normalizers.dart';
import 'package:basa_capstone/core/services/sf1_column_map.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../tool/command_pass/device.dart';
import '../../../tool/command_pass/runner.dart';
import '../../../tool/command_pass/scenario.dart';
import '../../../tool/command_pass/sf1_fixture.dart';

void main() {
  test('writes the header and learners where the importer reads them', () async {
    final dir = Directory.systemTemp.createTempSync('basa_sf1_');
    final path = '${dir.path}/sf1.xlsx';
    final map = await Sf1ColumnMap.load(dir.path); // a fresh folder gives the defaults
    writeSf1(path,
        map: map,
        schoolCode: 'ZZPASS0007',
        schoolName: 'ZZTEST PASS r7',
        regionLabel: sf1RegionLabel,
        schoolYear: '2026-2027',
        grade: '7',
        section: 'ZZTEST-G7',
        learners: sf1Learners(runNumber: 7, grade: 7, count: 3));

    final excel = Excel.decodeBytes(File(path).readAsBytesSync());
    final sheet = excel.tables[excel.tables.keys.first]!; // the importer reads the first sheet
    String? cell(int row, int col) =>
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value?.toString().trim();

    expect(cell(map.schoolIdRow, map.schoolIdCol), 'ZZPASS0007');
    expect(cell(map.schoolNameRow, map.schoolNameCol), 'ZZTEST PASS r7');
    expect(Region.resolve(cell(map.regionRow, map.regionCol)), 13);
    expect(normalizeSchoolYear(cell(map.schoolYearRow, map.schoolYearCol)!), '2026-2027');
    expect(normalizeGradeLevel(cell(map.gradeLevelRow, map.gradeLevelCol)!), '7');
    expect(cell(map.sectionNameRow, map.sectionNameCol), 'ZZTEST-G7');

    final start = map.dataStartRow;
    expect([for (var i = 0; i < 3; i++) cell(start + i, map.lrn)], ['999000077001', '999000077002', '999000077003']);
    expect([for (var i = 0; i < 3; i++) cell(start + i, map.sex)], ['M', 'F', 'M']);
    expect(cell(start, map.lastName), 'ZZTESTA');
    expect(cell(start, map.firstName), 'Learner001');
    expect(cell(start + 3, map.lrn), isNull);
  });

  test('LRNs are 12 digits and differ per run, grade and school', () {
    final a = sf1Learners(runNumber: 12, grade: 2, count: 2).map((l) => l.lrn).toList();
    expect(a, ['999000122001', '999000122002']);
    final b = sf1Learners(runNumber: 12, grade: 2, count: 2, schoolB: true).map((l) => l.lrn).toList();
    expect(b, ['999000122501', '999000122502']);
    expect(sf1Learners(runNumber: 13, grade: 2, count: 1).single.lrn, '999000132001');
    final c = sf1Learners(runNumber: 12, grade: 7, count: 2, first: 101);
    expect(c.map((l) => l.lrn), ['999000127101', '999000127102']);
    expect(c.first.first, 'Learner101');
  });

  test('school year follows the June start', () {
    expect(currentSchoolYear(DateTime(2026, 10, 23)), '2026-2027');
    expect(currentSchoolYear(DateTime(2027, 5, 31)), '2026-2027');
    expect(currentSchoolYear(DateTime(2027, 6, 1)), '2027-2028');
  });

  test('school codes and names per run', () {
    expect(sf1SchoolCode(7), 'ZZPASS0007');
    expect(sf1SchoolCode(7, schoolB: true), 'ZZPASS0007B');
    expect(sf1SchoolName(7), 'ZZTEST PASS r7');
    expect(sf1SchoolName(7, schoolB: true), 'ZZTEST PASS r7 B');
  });

  test('make-sf1 step writes the file into the run folder and captures its path', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final runDir = Directory.systemTemp.createTempSync('basa_pass_sf1_');
    final devices = DeviceManager(runDir);
    final state = await RunState.load(runDir);
    final results = await runScenario(
        parseScenario('t', 'device a admin\nmake-sf1 sf1_g2 a 2 ZZTEST-G2-r{run} 4\nrun get-text\nexpect Text'),
        devices,
        state,
        Accounts(runNumber: 9, superAccount: null, state: state),
        readOnlyCommands: const {});
    await devices.close();
    expect(results.every((r) => r.outcome.passed), isTrue, reason: results.map((r) => r.outcome.message).join('; '));
    final path = state.captures['sf1_g2']!;
    expect(File(path).existsSync(), isTrue);
    expect(path, contains(runDir.path));
    final excel = Excel.decodeBytes(File(path).readAsBytesSync());
    final sheet = excel.tables[excel.tables.keys.first]!;
    expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 9)).value?.toString(), '999000092004');
    // {..} values are filled into the section name.
    expect(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 38, rowIndex: 3)).value?.toString(), 'ZZTEST-G2-r9');
  });

  test('write-file step writes the substituted text into the run folder and captures its path', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final runDir = Directory.systemTemp.createTempSync('basa_pass_wf_');
    final devices = DeviceManager(runDir);
    final state = await RunState.load(runDir);
    final results = await runScenario(
        parseScenario('t', 'device a admin\nwrite-file a3_text Run {run} at {stamp}.\nrun get-text\nexpect Text'),
        devices,
        state,
        Accounts(runNumber: 9, superAccount: null, state: state),
        readOnlyCommands: const {});
    await devices.close();
    expect(results.every((r) => r.outcome.passed), isTrue, reason: results.map((r) => r.outcome.message).join('; '));
    final path = state.captures['a3_text']!;
    expect(path, '${runDir.path}/a3_text.txt');
    expect(File(path).readAsStringSync(), 'Run 9 at ${state.stamp}.');
  });
}
