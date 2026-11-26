// The demo SF1 files (demo-data plan Task 7): one workbook per section, in
// the cells the device's SF1 import reads.
import 'dart:io';

import 'package:basa_capstone/core/services/sf1_column_map.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/demo_data/sf1_files.dart';
import '../../../tool/demo_data/world.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('basa_demo_sf1_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('DepEd birth dates', () {
    expect(sf1BirthDate('2016-09-04'), '09-04-2016');
    expect(sf1BirthDate(''), ''); // a learner with no birth date on the SF1 (gap 5)
  });

  test('a section file holds its school, year, grade and learners', () async {
    final w = DemoWorld.build();
    final section = w.sections.firstWhere((s) => s.year == DemoYear.y2025 && s.grade == 3);
    final learners = w.inSection(section);
    final map = await Sf1ColumnMap.load(dir.path);
    final path = writeDemoSf1(dir, section, learners, map);
    expect(path, endsWith('${Platform.pathSeparator}sf1${Platform.pathSeparator}2025-2026'
        '${Platform.pathSeparator}NCES-DEMO-G3.xlsx'));

    final sheet = Excel.decodeBytes(File(path).readAsBytesSync()).tables.values.first;
    String? cell(int row, int col) => sheet.rows[row][col]?.value?.toString();
    expect(cell(map.schoolIdRow, map.schoolIdCol), 'NCES-DEMO');
    expect(cell(map.schoolNameRow, map.schoolNameCol), 'Night City Elementary School');
    expect(cell(map.schoolYearRow, map.schoolYearCol), '2025-2026');
    expect(cell(map.gradeLevelRow, map.gradeLevelCol), '3');
    expect(cell(map.sectionNameRow, map.sectionNameCol), section.name);
    final first = learners.first, row = map.dataStartRow;
    expect(cell(row, map.lrn), first.lrn);
    expect(cell(row, map.lastName), first.last);
    expect(cell(row, map.firstName), first.first);
    expect(cell(row, map.middleName), first.middleInitial);
    expect(cell(row, map.sex), first.sex);
    expect(cell(row, map.birthDate), sf1BirthDate(first.birthDate));
    expect(cell(row + learners.length - 1, map.lrn), learners.last.lrn);
    expect(sheet.rows.length, row + learners.length);
  });
}
