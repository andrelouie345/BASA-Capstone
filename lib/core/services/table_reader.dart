// lib/core/services/table_reader.dart
//
// Reads a simple table (a header row, then one record per row) from a .csv
// or the first sheet of an .xlsx, for imports such as the ARAL roster (IE5).
// Headers are matched case- and space-insensitively by the caller through
// [TableRow.get]. Blank rows are skipped. Cell values come back as trimmed
// text (Excel numbers without a needless ".0"; dates as their serial, see
// [parseSheetDate]).
import 'dart:convert';

import 'xlsx_cells.dart';

class TableRow {
  final int rowNo;                     // 1-based, as in the file
  final Map<String, String> _cells;    // normalized header -> value
  const TableRow(this.rowNo, this._cells);

  /// The first non-empty value among [headers] (any spelling/case/spaces).
  String? get(List<String> headers) {
    for (final h in headers) {
      final v = _cells[normalizeHeader(h)];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }
}

class TableReadException implements Exception {
  final String message;
  const TableReadException(this.message);
  @override
  String toString() => message;
}

String normalizeHeader(String h) => h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// [fileName] decides the format (.xlsx or .csv).
(List<String>, List<TableRow>) readTable(List<int> bytes, String fileName) {
  final lower = fileName.toLowerCase();
  final List<List<String>> grid;
  if (lower.endsWith('.xlsx')) {
    grid = _xlsxGrid(bytes);
  } else if (lower.endsWith('.csv')) {
    grid = _csvGrid(utf8.decode(bytes, allowMalformed: true));
  } else {
    throw const TableReadException('Use a .csv or .xlsx file.');
  }
  final headerIndex = grid.indexWhere((r) => r.any((c) => c.trim().isNotEmpty));
  if (headerIndex < 0) throw const TableReadException('The file is empty.');
  final headers = grid[headerIndex].map((h) => h.trim()).toList();
  final rows = <TableRow>[];
  for (var i = headerIndex + 1; i < grid.length; i++) {
    final r = grid[i];
    if (r.every((c) => c.trim().isEmpty)) continue;
    rows.add(TableRow(i + 1, {
      for (var c = 0; c < headers.length && c < r.length; c++)
        if (headers[c].isNotEmpty) normalizeHeader(headers[c]): r[c].trim(),
    }));
  }
  return (headers, rows);
}

List<List<String>> _xlsxGrid(List<int> bytes) {
  final XlsxWorkbook wb;
  try {
    wb = XlsxWorkbook.decode(bytes);
  } on XlsxException catch (e) {
    throw TableReadException('$e');
  }
  final cells = wb.readSheet(wb.sheetNames.first);
  var maxRow = 0, maxCol = 0;
  for (final ref in cells.keys) {
    final (c, r) = splitRef(ref);
    if (r > maxRow) maxRow = r;
    if (c > maxCol) maxCol = c;
  }
  return [
    for (var r = 1; r <= maxRow; r++)
      [
        for (var c = 1; c <= maxCol; c++)
          switch (cells['${columnLetters(c)}$r']) {
            null => '',
            double d when d == d.truncateToDouble() => '${d.toInt()}',
            final v => '$v',
          },
      ],
  ];
}

/// RFC 4180-ish: quoted fields, doubled quotes, CR/LF line ends, a UTF-8 BOM.
List<List<String>> _csvGrid(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

/// A date cell: an Excel serial ("45900"), YYYY-MM-DD or M/D/YYYY (M/D/YY)
/// -> YYYY-MM-DD, else null.
String? parseSheetDate(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  final s = v.trim();
  DateTime? d;
  final serial = num.tryParse(s);
  if (serial != null) {
    if (serial > 20000 && serial < 80000) d = excelSerialDate(serial);
  } else {
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    final us = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})$').firstMatch(s);
    if (iso != null) {
      d = DateTime.utc(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    } else if (us != null) {
      var y = int.parse(us.group(3)!);
      if (y < 100) y += 2000;
      d = DateTime.utc(y, int.parse(us.group(1)!), int.parse(us.group(2)!));
    }
  }
  if (d == null) return null;
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
