// lib/core/services/xls_to_xlsx_converter.dart
import 'dart:io';
import 'package:excel2003/excel2003.dart' as legacy;
import 'package:excel_plus/excel_plus.dart';
import '../console/logger.dart';

/// Converts a legacy .xls (BIFF8) file to a .xlsx file, values only —
/// no formatting/styles are preserved, which is fine since import only
/// reads cell values anyway.
class XlsToXlsxConverter {
  final ScopedLogger _log;
  XlsToXlsxConverter({Logger? logger}) : _log = ScopedLogger(logger, 'XlsToXlsxConverter');

  /// Writes "<name>_converted.xlsx" beside [inputPath], returns that path.
Future<String> convert(String inputPath) async {
  _log('convert($inputPath)');
  final reader = legacy.XlsReader(inputPath);
  reader.open();

  final excel = Excel.createExcel();
  final defaultSheetName = excel.tables.keys.first; // whatever excel_plus actually calls it

  final realSheetNames = <String>{};

  for (var s = 0; s < reader.sheetCount; s++) {
    final sourceSheet = reader.sheet(s);
    final sheetName = reader.sheetNames[s];
    realSheetNames.add(sheetName);
    final targetSheet = excel[sheetName]; // creates it

    for (int r = sourceSheet.firstRow; r < sourceSheet.lastRow; r++) {
      for (int c = sourceSheet.firstCol; c < sourceSheet.lastCol; c++) {
        final value = sourceSheet.cell(r, c);
        if (value == null) continue;

        final cellIndex = CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);
        if (value is String) {
          targetSheet.updateCell(cellIndex, TextCellValue(value));
        } else if (value is int) {
          targetSheet.updateCell(cellIndex, IntCellValue(value));
        } else if (value is double) {
          targetSheet.updateCell(cellIndex, DoubleCellValue(value));
        } else if (value is bool) {
          targetSheet.updateCell(cellIndex, BoolCellValue(value));
        } else if (value is DateTime) {
          targetSheet.updateCell(cellIndex, DateTimeCellValue(
            year: value.year, month: value.month, day: value.day,
            hour: value.hour, minute: value.minute,
          ));
        } else {
          targetSheet.updateCell(cellIndex, TextCellValue(value.toString()));
        }
      }
    }
  }

  // Only delete the default sheet now — it's safe once real sheets exist,
  // and only if the source didn't happen to reuse that exact name itself.
  if (!realSheetNames.contains(defaultSheetName)) {
    excel.delete(defaultSheetName);
  }

    final outputPath = inputPath.replaceAll(RegExp(r'\.xls$', caseSensitive: false), '_converted.xlsx');
    final bytes = excel.save()!;
    await File(outputPath).writeAsBytes(bytes);
    _log('converted -> $outputPath');
    return outputPath;
  }
}