// SF1 workbooks the command pass imports (students exist only through an SF1
// import). Cells follow the device's Sf1ColumnMap, the one its import reads.
import 'dart:io';

import 'package:basa_capstone/core/services/sf1_column_map.dart';
import 'package:excel_plus/excel_plus.dart';

class Sf1Learner {
  final String lrn, last, first, sex; // sex: M | F
  final String? birthDate;
  const Sf1Learner(this.lrn, this.last, this.first, this.sex, {this.birthDate});
}

/// Region 13 (Region X), the only region with CRLA stories.
const sf1RegionLabel = 'Region X';

String sf1SchoolCode(int runNumber, {bool schoolB = false}) =>
    'ZZPASS${runNumber.toString().padLeft(4, '0')}${schoolB ? 'B' : ''}';

String sf1SchoolName(int runNumber, {bool schoolB = false}) => 'ZZTEST PASS r$runNumber${schoolB ? ' B' : ''}';

/// The school year a date falls in (it starts in June).
String currentSchoolYear(DateTime now) {
  final start = now.month >= 6 ? now.year : now.year - 1;
  return '$start-${start + 1}';
}

/// LRN = 9990 + run (4) + grade's last digit (1) + index (3); school B's
/// indexes start at 501. Sexes alternate from M.
List<Sf1Learner> sf1Learners({required int runNumber, required int grade, required int count, bool schoolB = false}) {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  return [
    for (var i = 1; i <= count; i++)
      Sf1Learner(
        '9990${runNumber.toString().padLeft(4, '0')}${grade % 10}${(i + (schoolB ? 500 : 0)).toString().padLeft(3, '0')}',
        'ZZTEST${letters[(i - 1) % 26]}',
        'Learner${i.toString().padLeft(3, '0')}',
        i.isOdd ? 'M' : 'F',
      ),
  ];
}

void writeSf1(
  String path, {
  required Sf1ColumnMap map,
  required String schoolCode,
  required String schoolName,
  required String regionLabel,
  required String schoolYear,
  required String grade,
  required String section,
  required List<Sf1Learner> learners,
}) {
  final excel = Excel.createExcel();
  final sheet = excel[excel.tables.keys.first]; // the importer reads the first sheet
  void put(int row, int col, String? value) {
    if (value == null) return;
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row), TextCellValue(value));
  }

  put(map.schoolIdRow, map.schoolIdCol, schoolCode);
  put(map.regionRow, map.regionCol, regionLabel);
  put(map.schoolNameRow, map.schoolNameCol, schoolName);
  put(map.schoolYearRow, map.schoolYearCol, schoolYear);
  put(map.gradeLevelRow, map.gradeLevelCol, grade);
  put(map.sectionNameRow, map.sectionNameCol, section);
  for (var i = 0; i < learners.length; i++) {
    final l = learners[i];
    final row = map.dataStartRow + i;
    put(row, map.lrn, l.lrn);
    put(row, map.lastName, l.last);
    put(row, map.firstName, l.first);
    put(row, map.sex, l.sex);
    put(row, map.birthDate, l.birthDate);
  }
  final bytes = excel.encode();
  if (bytes == null) throw StateError('excel_plus could not encode the SF1 workbook');
  File(path).writeAsBytesSync(bytes);
}
