// The minimal .xlsx writer (Phil-IRI import plan, Task 4): the scoresheet
// template is written with it and read back through XlsxWorkbook.
//
// Set XLSX_WRITER_OUT=<file.xlsx> to also save the sample workbook (verify
// kit: open it in Excel once, no repair prompt, the drop-down works).
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:basa_capstone/core/services/xlsx_cells.dart';
import 'package:basa_capstone/core/services/xlsx_writer.dart';
import 'package:flutter_test/flutter_test.dart';

List<XlsxSheetSpec> _sample() => [
      XlsxSheetSpec(
        name: 'Learners',
        cells: {
          'A1': 'LRN',
          'B1': 'Name',
          'C1': 'Words read',
          'D1': 'Round',
          'E1': 'Time (sec)',
          'A2': '00123',
          'B2': 'Dela Cruz, Juan & "Jun" <Jr>',
          'C2': 96,
          'D2': 'BOSY',
          'E2': 75.5,
          'A3': '123456789012',
          'B3': '  spaces kept  ',
          'D3': null,
        },
        textColumns: {1},
        listValidations: {'D2:D500': r'Codes!$A$2:$A$7'},
        columnWidths: [16, 30, 12, 10],
      ),
      XlsxSheetSpec(
        name: 'Codes',
        cells: {'A1': 'Round', 'A2': 'GST', 'A3': 'BOSY', 'A4': 'MOSY1', 'A5': 'MOSY2', 'A6': 'MOSY3', 'A7': 'EOSY'},
      ),
      XlsxSheetSpec(name: 'Instructions', cells: {'A1': 'One row per reading.'}),
    ];

String _entry(List<int> bytes, String path) =>
    utf8.decode(ZipDecoder().decodeBytes(bytes).find(path)!.content);

void main() {
  test('round trip through XlsxWorkbook', () {
    final bytes = writeXlsx(_sample());
    final out = Platform.environment['XLSX_WRITER_OUT'];
    if (out != null && out.isNotEmpty) File(out).writeAsBytesSync(bytes);

    final wb = XlsxWorkbook.decode(bytes);
    expect(wb.sheetNames, ['Learners', 'Codes', 'Instructions']);
    final cells = wb.readSheet('Learners');
    expect(cells['A2'], '00123'); // text column: leading zeros stay
    expect(cells['A3'], '123456789012'); // an LRN stays text, never 1.23E11
    expect(cells['B2'], 'Dela Cruz, Juan & "Jun" <Jr>');
    expect(cells['B3'], '  spaces kept  ');
    expect(cells['C2'], 96);
    expect(cells['C2'], isA<int>());
    expect(cells['E2'], 75.5);
    expect(cells.containsKey('D3'), isFalse); // null = no value
    expect(wb.read('Codes', 'A7'), 'EOSY');
    expect(wb.read('Instructions', 'A1'), 'One row per reading.');
  });

  test('the validation is in the sheet XML', () {
    final sheet = _entry(writeXlsx(_sample()), 'xl/worksheets/sheet1.xml');
    expect(sheet, contains('<dataValidation type="list"'));
    expect(sheet, contains('sqref="D2:D500"'));
    expect(sheet, contains(r'<formula1>Codes!$A$2:$A$7</formula1>'));
    // Only the first sheet has a list.
    expect(_entry(writeXlsx(_sample()), 'xl/worksheets/sheet2.xml'), isNot(contains('dataValidation')));
  });

  test('text columns are formatted as text, also for rows typed in later', () {
    final bytes = writeXlsx(_sample());
    final styles = _entry(bytes, 'xl/styles.xml');
    expect(styles, contains('numFmtId="49"'));
    final sheet = _entry(bytes, 'xl/worksheets/sheet1.xml');
    // Column A carries the text style, so a cell typed in an empty row is text too.
    expect(sheet, contains('<col min="1" max="1" width="16" customWidth="1" style="1"/>'));
    expect(RegExp(r'<c r="A2" s="1" t="inlineStr">').hasMatch(sheet), isTrue);
    expect(RegExp(r'<c r="B2" t="inlineStr">').hasMatch(sheet), isTrue);
  });

  test('cells are written in row and column order whatever the map order', () {
    final bytes = writeXlsx([
      XlsxSheetSpec(name: 'S', cells: {'B2': 'b2', 'AA1': 'aa1', 'A2': 'a2', 'B1': 'b1', 'A10': 'a10'}),
    ]);
    final sheet = _entry(bytes, 'xl/worksheets/sheet1.xml');
    final refs = RegExp(r'<c r="([A-Z]+\d+)"').allMatches(sheet).map((m) => m.group(1)).toList();
    expect(refs, ['B1', 'AA1', 'A2', 'B2', 'A10']);
    expect(XlsxWorkbook.decode(bytes).read('S', 'AA1'), 'aa1');
  });

  test('bad sheet names and cell values are refused', () {
    expect(() => writeXlsx([]), throwsA(isA<XlsxException>()));
    expect(() => writeXlsx([XlsxSheetSpec(name: 'A/B', cells: {})]), throwsA(isA<XlsxException>()));
    expect(() => writeXlsx([XlsxSheetSpec(name: 'x' * 32, cells: {})]), throwsA(isA<XlsxException>()));
    expect(() => writeXlsx([XlsxSheetSpec(name: '', cells: {})]), throwsA(isA<XlsxException>()));
    expect(() => writeXlsx([XlsxSheetSpec(name: 'Same', cells: {}), XlsxSheetSpec(name: 'same', cells: {})]),
        throwsA(isA<XlsxException>()));
    expect(() => writeXlsx([XlsxSheetSpec(name: 'S', cells: {'A1': DateTime(2026)})]), throwsA(isA<XlsxException>()));
    expect(() => writeXlsx([XlsxSheetSpec(name: 'S', cells: {'1A': 'x'})]), throwsA(isA<XlsxException>()));
    expect(() => writeXlsx([XlsxSheetSpec(name: 'S', cells: {'A1': double.nan})]), throwsA(isA<XlsxException>()));
  });

  test('a sheet name with an apostrophe and a space round-trips', () {
    final bytes = writeXlsx([XlsxSheetSpec(name: "Ma's G7 A", cells: {'A1': 1})]);
    expect(XlsxWorkbook.decode(bytes).read("Ma's G7 A", 'A1'), 1);
  });
}
