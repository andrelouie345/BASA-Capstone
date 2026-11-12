// SF1 import safety net (2026-11-12): a cell holding control characters means
// the file was not read correctly (the .xls reader bug of that day turned a
// name into binary garbage and emptied later cells). The import refuses the
// whole file with a clear message instead of skipping rows silently or
// failing on a raw database error.
import 'package:basa_capstone/core/services/sf1_importer.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';

Sheet _sheet(Map<(int, int), String> cells) {
  final excel = Excel.createExcel();
  final sheet = excel[excel.tables.keys.first];
  cells.forEach((rc, v) => sheet.updateCell(CellIndex.indexByColumnRow(rowIndex: rc.$1, columnIndex: rc.$2), TextCellValue(v)));
  return sheet;
}

void main() {
  test('a clean sheet has no unreadable cell (tabs and line breaks are fine)', () {
    expect(sf1FirstUnreadableCell(_sheet({(6, 0): '123456789012', (6, 2): 'DELA CRUZ, MARIA', (7, 2): 'Line\nbreak\tok'})), isNull);
  });

  test('the first cell with a control character is found (row and column, 1-based)', () {
    final hit = sf1FirstUnreadableCell(_sheet({(6, 2): 'ok', (36, 2): 'AB\u0000\u0001CD', (40, 7): '\u001f'}));
    expect(hit, (row: 37, column: 'C'));
  });

  test('the refusal tells the coordinator what to do', () {
    expect(sf1UnreadableMessage((row: 37, column: 'C')),
        "This file wasn't read correctly (row 37, column C holds unreadable characters). "
        'Open it in Excel, save it as an Excel Workbook (.xlsx) and import that file instead.');
  });
}
