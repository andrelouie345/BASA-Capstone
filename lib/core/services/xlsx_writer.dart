// lib/core/services/xlsx_writer.dart
//
// Writes a new, plain .xlsx workbook: sheets of text and numbers, text-format
// columns and drop-down lists. Used for the Phil-IRI scoresheet template
// (spec 2026-11-09 D16). Filling an existing DepEd template is xlsx_cells.dart's
// job; this writes only what Excel needs to open a file without a repair:
//
//  * Text is an inline string (no shared-strings part), numbers are numbers,
//    bools are bools; null leaves the cell out. No formulas, no merges.
//  * A text column ([XlsxSheetSpec.textColumns]) gets the "@" format (numFmt
//    49) on its cells AND on the whole column, so an LRN typed in later rows
//    keeps its digits instead of turning into 1.23457E+11.
//  * A drop-down list ([XlsxSheetSpec.listValidations]) is a list data
//    validation over a range, e.g. "D2:D500" -> "Codes!$A$2:$A$7".
//
// Read the result back with XlsxWorkbook (the tests do).
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'xlsx_cells.dart';

class XlsxSheetSpec {
  final String name;

  /// "B2" -> String / num / bool / null.
  final Map<String, Object?> cells;

  /// Columns (from 1) formatted as text ("@").
  final Set<int> textColumns;

  /// Range -> list source: "D2:D500" -> "Codes!\$A\$2:\$A\$7" (or a quoted
  /// inline list, "\"Yes,No\"").
  final Map<String, String> listValidations;

  /// Widths in Excel's character units; index 0 = column A. Null keeps
  /// Excel's default.
  final List<double>? columnWidths;

  const XlsxSheetSpec({
    required this.name,
    required this.cells,
    this.textColumns = const {},
    this.listValidations = const {},
    this.columnWidths,
  });
}

const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _nsRel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _nsPkgRel = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _relBase = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _ctBase = 'application/vnd.openxmlformats-officedocument.spreadsheetml';
const _textStyle = 1; // cellXfs index with numFmtId 49
const _defaultWidth = 9.140625; // Excel's default column width (8.43 + padding)

/// The workbook's bytes. Throws [XlsxException] on no sheets, a bad or
/// duplicate sheet name, a bad cell reference or a value that isn't text,
/// a number or a bool.
List<int> writeXlsx(List<XlsxSheetSpec> sheets) {
  if (sheets.isEmpty) throw const XlsxException('A workbook needs at least one sheet');
  final seen = <String>{};
  for (final s in sheets) {
    _checkSheetName(s.name);
    if (!seen.add(s.name.toLowerCase())) {
      throw XlsxException('Two sheets are named "${s.name}" (Excel ignores case)');
    }
  }

  final archive = Archive();
  void put(String path, String xml) => archive.add(ArchiveFile.bytes(path, utf8.encode(xml)));

  put('[Content_Types].xml', _contentTypes(sheets.length));
  put('_rels/.rels', _rootRels());
  put('xl/workbook.xml', _workbook(sheets));
  put('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length));
  put('xl/styles.xml', _styles());
  for (var i = 0; i < sheets.length; i++) {
    put('xl/worksheets/sheet${i + 1}.xml', _sheet(sheets[i]));
  }
  return ZipEncoder().encodeBytes(archive);
}

void _checkSheetName(String name) {
  if (name.isEmpty || name.length > 31) {
    throw XlsxException('A sheet name must be 1 to 31 characters: "$name"');
  }
  if (RegExp(r'[\\/?*\[\]:]').hasMatch(name)) {
    throw XlsxException('A sheet name cannot hold \\ / ? * [ ] or : ("$name")');
  }
  if (name.startsWith("'") || name.endsWith("'")) {
    throw XlsxException('A sheet name cannot start or end with an apostrophe ("$name")');
  }
}

String _doc(void Function(XmlBuilder b) body) {
  final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  body(b);
  return b.buildDocument().toXmlString();
}

String _contentTypes(int sheetCount) => _doc((b) {
      b.element('Types', namespaces: {'http://schemas.openxmlformats.org/package/2006/content-types': null}, nest: () {
        b.element('Default', attributes: {
          'Extension': 'rels',
          'ContentType': 'application/vnd.openxmlformats-package.relationships+xml',
        });
        b.element('Default', attributes: {'Extension': 'xml', 'ContentType': 'application/xml'});
        b.element('Override', attributes: {
          'PartName': '/xl/workbook.xml',
          'ContentType': '$_ctBase.sheet.main+xml',
        });
        b.element('Override', attributes: {
          'PartName': '/xl/styles.xml',
          'ContentType': '$_ctBase.styles+xml',
        });
        for (var i = 1; i <= sheetCount; i++) {
          b.element('Override', attributes: {
            'PartName': '/xl/worksheets/sheet$i.xml',
            'ContentType': '$_ctBase.worksheet+xml',
          });
        }
      });
    });

String _rootRels() => _doc((b) {
      b.element('Relationships', namespaces: {_nsPkgRel: null}, nest: () {
        b.element('Relationship', attributes: {
          'Id': 'rId1',
          'Type': '$_relBase/officeDocument',
          'Target': 'xl/workbook.xml',
        });
      });
    });

String _workbook(List<XlsxSheetSpec> sheets) => _doc((b) {
      b.element('workbook', namespaces: {_ns: null, _nsRel: 'r'}, nest: () {
        b.element('sheets', nest: () {
          for (var i = 0; i < sheets.length; i++) {
            b.element('sheet', attributes: {
              'name': sheets[i].name,
              'sheetId': '${i + 1}',
              'r:id': 'rId${i + 1}',
            });
          }
        });
      });
    });

String _workbookRels(int sheetCount) => _doc((b) {
      b.element('Relationships', namespaces: {_nsPkgRel: null}, nest: () {
        for (var i = 1; i <= sheetCount; i++) {
          b.element('Relationship', attributes: {
            'Id': 'rId$i',
            'Type': '$_relBase/worksheet',
            'Target': 'worksheets/sheet$i.xml',
          });
        }
        b.element('Relationship', attributes: {
          'Id': 'rId${sheetCount + 1}',
          'Type': '$_relBase/styles',
          'Target': 'styles.xml',
        });
      });
    });

// The smallest styles part Excel accepts: one font, the two required fills,
// one border, and two cell formats (0 = General, 1 = Text "@").
String _styles() => _doc((b) {
      b.element('styleSheet', namespaces: {_ns: null}, nest: () {
        b.element('fonts', attributes: {'count': '1'}, nest: () {
          b.element('font', nest: () {
            b.element('sz', attributes: {'val': '11'});
            b.element('name', attributes: {'val': 'Calibri'});
            b.element('family', attributes: {'val': '2'});
          });
        });
        b.element('fills', attributes: {'count': '2'}, nest: () {
          b.element('fill', nest: () => b.element('patternFill', attributes: {'patternType': 'none'}));
          b.element('fill', nest: () => b.element('patternFill', attributes: {'patternType': 'gray125'}));
        });
        b.element('borders', attributes: {'count': '1'}, nest: () {
          b.element('border', nest: () {
            for (final side in ['left', 'right', 'top', 'bottom', 'diagonal']) {
              b.element(side);
            }
          });
        });
        b.element('cellStyleXfs', attributes: {'count': '1'}, nest: () {
          b.element('xf', attributes: {'numFmtId': '0', 'fontId': '0', 'fillId': '0', 'borderId': '0'});
        });
        b.element('cellXfs', attributes: {'count': '2'}, nest: () {
          b.element('xf', attributes: {'numFmtId': '0', 'fontId': '0', 'fillId': '0', 'borderId': '0', 'xfId': '0'});
          b.element('xf', attributes: {
            'numFmtId': '49',
            'fontId': '0',
            'fillId': '0',
            'borderId': '0',
            'xfId': '0',
            'applyNumberFormat': '1',
          });
        });
        b.element('cellStyles', attributes: {'count': '1'}, nest: () {
          b.element('cellStyle', attributes: {'name': 'Normal', 'xfId': '0', 'builtinId': '0'});
        });
      });
    });

String _width(double w) => w == w.truncateToDouble() ? '${w.toInt()}' : '$w';

String _sheet(XlsxSheetSpec spec) {
  // row -> (col -> value), both sorted: Excel refuses cells out of order.
  final rows = <int, Map<int, Object>>{};
  for (final e in spec.cells.entries) {
    final (col, row) = splitRef(e.key);
    final v = e.value;
    if (v == null) continue;
    if (v is num && !v.isFinite) throw XlsxException('${spec.name}!${e.key}: $v is not a number Excel can hold');
    if (v is! String && v is! num && v is! bool) {
      throw XlsxException('${spec.name}!${e.key}: a ${v.runtimeType} can\'t be written (text, a number or a bool only)');
    }
    rows.putIfAbsent(row, () => {})[col] = v;
  }

  final widths = spec.columnWidths ?? const <double>[];
  final colCount = [
    widths.length,
    if (spec.textColumns.isNotEmpty) spec.textColumns.reduce((a, b) => a > b ? a : b),
  ].fold(0, (a, b) => a > b ? a : b);

  return _doc((b) {
    b.element('worksheet', namespaces: {_ns: null, _nsRel: 'r'}, nest: () {
      if (colCount > 0) {
        b.element('cols', nest: () {
          for (var c = 1; c <= colCount; c++) {
            final hasWidth = c <= widths.length;
            final text = spec.textColumns.contains(c);
            if (!hasWidth && !text) continue;
            b.element('col', attributes: {
              'min': '$c',
              'max': '$c',
              'width': _width(hasWidth ? widths[c - 1] : _defaultWidth),
              if (hasWidth) 'customWidth': '1',
              if (text) 'style': '$_textStyle',
            });
          }
        });
      }
      b.element('sheetData', nest: () {
        for (final r in rows.keys.toList()..sort()) {
          final cols = rows[r]!;
          b.element('row', attributes: {'r': '$r'}, nest: () {
            for (final c in cols.keys.toList()..sort()) {
              final v = cols[c]!;
              final attrs = <String, String>{
                'r': '${columnLetters(c)}$r',
                if (spec.textColumns.contains(c)) 's': '$_textStyle',
              };
              if (v is String) {
                b.element('c', attributes: {...attrs, 't': 'inlineStr'}, nest: () {
                  b.element('is', nest: () {
                    b.element('t', attributes: {'xml:space': 'preserve'}, nest: v);
                  });
                });
              } else if (v is bool) {
                b.element('c', attributes: {...attrs, 't': 'b'}, nest: () => b.element('v', nest: v ? '1' : '0'));
              } else {
                b.element('c', attributes: attrs, nest: () => b.element('v', nest: '$v'));
              }
            }
          });
        }
      });
      // CT_Worksheet order: sheetData ... dataValidations ... pageMargins.
      if (spec.listValidations.isNotEmpty) {
        b.element('dataValidations', attributes: {'count': '${spec.listValidations.length}'}, nest: () {
          for (final e in spec.listValidations.entries) {
            b.element('dataValidation', attributes: {
              'type': 'list',
              'allowBlank': '1',
              'showErrorMessage': '1',
              'sqref': e.key,
            }, nest: () => b.element('formula1', nest: e.value));
          }
        });
      }
    });
  });
}
