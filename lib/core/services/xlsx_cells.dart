// lib/core/services/xlsx_cells.dart
//
// Reads and fills cells of an .xlsx workbook by editing its sheet XML inside
// the zip, leaving everything else (styles, merges, data validation, other
// sheets, formulas) untouched. Used to read filled DepEd forms (CRLA2
// scoresheets) and to fill DepEd templates (CRLA2 scoresheet, ARAL
// implementation report). A full spreadsheet library would rewrite the whole
// workbook and can drop what it doesn't understand.
//
//  * Reading returns each cell's value: text, a number (int when whole), a
//    bool, or for a formula cell the value Excel cached when the file was
//    last saved. Error cells (#N/A, ...) read as null.
//  * Writing replaces a cell's value and keeps its style; a cell or row that
//    doesn't exist yet is inserted in order. A formula cell is never
//    overwritten (it throws). Text is written as an inline string.
//  * encode() marks the workbook for a full recalculation on open, so the
//    template's formulas show results for the new values.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class XlsxException implements Exception {
  final String message;
  const XlsxException(this.message);
  @override
  String toString() => message;
}

class XlsxWorkbook {
  final Archive _archive;
  final List<String> _shared;
  final Map<String, String> _sheetPaths; // sheet name -> zip path, in workbook order
  final Map<String, XmlDocument> _parsed = {};
  final Set<String> _dirty = {};
  bool _structural = false; // rows or sheets removed: calcChain must go

  XlsxWorkbook._(this._archive, this._shared, this._sheetPaths);

  factory XlsxWorkbook.decode(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw XlsxException('Not an .xlsx file (could not open it as a zip): $e');
    }
    String text(String path) {
      final f = archive.find(path);
      if (f == null) throw XlsxException('Not an .xlsx workbook: $path is missing');
      return utf8.decode(f.content);
    }

    final shared = <String>[];
    final sharedFile = archive.find('xl/sharedStrings.xml');
    if (sharedFile != null) {
      for (final si in XmlDocument.parse(utf8.decode(sharedFile.content)).findAllElements('si')) {
        // Rich text runs (<r><t>) are joined; phonetic runs (<rPh>) are skipped.
        shared.add(si.descendantElements
            .where((e) => e.name.local == 't' && e.parentElement?.name.local != 'rPh')
            .map((e) => e.innerText)
            .join());
      }
    }

    final rels = <String, String>{};
    for (final r in XmlDocument.parse(text('xl/_rels/workbook.xml.rels')).findAllElements('Relationship')) {
      rels[r.getAttribute('Id')!] = r.getAttribute('Target')!;
    }
    final paths = <String, String>{};
    for (final s in XmlDocument.parse(text('xl/workbook.xml')).findAllElements('sheet')) {
      final rid = s.attributes.firstWhere((a) => a.name.local == 'id').value;
      var target = rels[rid]!;
      target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      paths[s.getAttribute('name')!] = target;
    }
    return XlsxWorkbook._(archive, shared, paths);
  }

  List<String> get sheetNames => _sheetPaths.keys.toList();

  bool hasSheet(String name) => _sheetPaths.containsKey(name);

  XmlDocument _sheet(String name) {
    final path = _sheetPaths[name];
    if (path == null) throw XlsxException('The workbook has no sheet "$name" (sheets: ${sheetNames.join(', ')})');
    return _parsed.putIfAbsent(path, () => XmlDocument.parse(utf8.decode(_archive.find(path)!.content)));
  }

  // ---- Reading ----

  /// Every non-empty cell of [sheet]: "B11" -> value.
  Map<String, Object> readSheet(String sheet) {
    final out = <String, Object>{};
    for (final c in _sheet(sheet).findAllElements('c')) {
      final v = _value(c);
      if (v != null) out[c.getAttribute('r')!] = v;
    }
    return out;
  }

  /// One cell's value, or null when empty.
  Object? read(String sheet, String ref) {
    final c = _cell(_sheet(sheet), ref.toUpperCase());
    return c == null ? null : _value(c);
  }

  /// Whether the cell holds a formula.
  bool isFormula(String sheet, String ref) =>
      _cell(_sheet(sheet), ref.toUpperCase())?.getElement('f') != null;

  Object? _value(XmlElement c) {
    final type = c.getAttribute('t');
    if (type == 'inlineStr') {
      final s = c.getElement('is')?.descendantElements.where((e) => e.name.local == 't').map((e) => e.innerText).join();
      return s == null || s.isEmpty ? null : s;
    }
    final raw = c.getElement('v')?.innerText;
    if (raw == null || raw.isEmpty) return null;
    switch (type) {
      case 's':
        final i = int.tryParse(raw);
        final s = i == null || i >= _shared.length ? null : _shared[i];
        return s == null || s.isEmpty ? null : s;
      case 'str':
        return raw;
      case 'b':
        return raw == '1';
      case 'e':
        return null;
      default:
        final n = num.tryParse(raw);
        if (n == null) return raw;
        return n is double && n == n.truncateToDouble() && n.abs() < 1e15 ? n.toInt() : n;
    }
  }

  // ---- Writing ----

  /// Sets cells of [sheet]: "B11" -> String / num / bool / null (null clears
  /// the value and keeps the style). Throws on a formula cell.
  void write(String sheet, Map<String, Object?> values) {
    final doc = _sheet(sheet);
    final data = doc.findAllElements('sheetData').firstOrNull;
    if (data == null) throw XlsxException('Sheet "$sheet" has no sheetData');
    for (final e in values.entries) {
      final ref = e.key.toUpperCase();
      final (col, row) = splitRef(ref);
      final cell = _cell(doc, ref) ?? _insertCell(data, row, col, ref);
      if (cell.getElement('f') != null) {
        throw XlsxException('Cell $sheet!$ref holds a formula; it is not overwritten');
      }
      _setValue(cell, e.value);
    }
    _dirty.add(_sheetPaths[sheet]!);
  }

  void _setValue(XmlElement c, Object? value) {
    c.children.clear();
    c.removeAttribute('t');
    switch (value) {
      case null:
        return;
      case String s:
        c.setAttribute('t', 'inlineStr');
        c.children.add(XmlElement(XmlName('is'), [], [
          XmlElement(XmlName('t'), [XmlAttribute(XmlName('space', 'xml'), 'preserve')], [XmlText(s)]),
        ]));
      case bool b:
        c.setAttribute('t', 'b');
        c.children.add(XmlElement(XmlName('v'), [], [XmlText(b ? '1' : '0')]));
      case num n:
        c.children.add(XmlElement(XmlName('v'), [], [XmlText('$n')]));
      default:
        throw XlsxException('Unsupported cell value ${value.runtimeType}');
    }
  }

  XmlElement? _cell(XmlDocument doc, String ref) {
    final (_, row) = splitRef(ref);
    for (final r in doc.findAllElements('row')) {
      if (r.getAttribute('r') != '$row') continue;
      for (final c in r.findElements('c')) {
        if (c.getAttribute('r') == ref) return c;
      }
      return null;
    }
    return null;
  }

  XmlElement _insertCell(XmlElement data, int row, int col, String ref) {
    XmlElement? rowEl;
    XmlElement? before;
    for (final r in data.findElements('row')) {
      final n = int.parse(r.getAttribute('r')!);
      if (n == row) {
        rowEl = r;
        break;
      }
      if (n > row) {
        before = r;
        break;
      }
    }
    if (rowEl == null) {
      rowEl = XmlElement(XmlName('row'), [XmlAttribute(XmlName('r'), '$row')]);
      if (before == null) {
        data.children.add(rowEl);
      } else {
        data.children.insert(data.children.indexOf(before), rowEl);
      }
    }
    final cell = XmlElement(XmlName('c'), [XmlAttribute(XmlName('r'), ref)]);
    final next = rowEl.findElements('c').where((c) => splitRef(c.getAttribute('r')!).$1 > col).firstOrNull;
    if (next == null) {
      rowEl.children.add(cell);
    } else {
      rowEl.children.insert(rowEl.children.indexOf(next), cell);
    }
    // A row's "spans" hint may no longer cover the new cell; Excel doesn't need it.
    rowEl.removeAttribute('spans');
    return cell;
  }

  // ---- Styles and structure ----

  /// The cell's style index (its "s"), or null when it has none.
  int? styleOf(String sheet, String ref) =>
      int.tryParse(_cell(_sheet(sheet), ref.toUpperCase())?.getAttribute('s') ?? '');

  /// Sets cells' style indexes (creating the cells when needed); null removes it.
  void setStyles(String sheet, Map<String, int?> styles) {
    final doc = _sheet(sheet);
    final data = doc.findAllElements('sheetData').first;
    for (final e in styles.entries) {
      final ref = e.key.toUpperCase();
      final (col, row) = splitRef(ref);
      final cell = _cell(doc, ref) ?? _insertCell(data, row, col, ref);
      if (e.value == null) {
        cell.removeAttribute('s');
      } else {
        cell.setAttribute('s', '${e.value}');
      }
    }
    _dirty.add(_sheetPaths[sheet]!);
  }

  /// Removes every row from [firstRow] down, and every merge that reaches it.
  void clearRowsFrom(String sheet, int firstRow) {
    final doc = _sheet(sheet);
    for (final r in doc.findAllElements('row').toList()) {
      if (int.parse(r.getAttribute('r')!) >= firstRow) r.remove();
    }
    final merges = doc.findAllElements('mergeCells').firstOrNull;
    if (merges != null) {
      for (final m in merges.findElements('mergeCell').toList()) {
        final last = m.getAttribute('ref')!.split(':').last;
        if (splitRef(last).$2 >= firstRow) m.remove();
      }
      final left = merges.findElements('mergeCell').length;
      if (left == 0) {
        merges.remove();
      } else {
        merges.setAttribute('count', '$left');
      }
    }
    doc.findAllElements('dimension').firstOrNull?.remove(); // optional; Excel recomputes it
    _structural = true;
    _dirty.add(_sheetPaths[sheet]!);
  }

  /// Merges a range such as "B4:B9".
  void merge(String sheet, String range) {
    final doc = _sheet(sheet);
    var merges = doc.findAllElements('mergeCells').firstOrNull;
    if (merges == null) {
      merges = XmlElement(XmlName('mergeCells'));
      // CT_Worksheet order: sheetData, sheetCalcPr, sheetProtection, protectedRanges,
      // scenarios, autoFilter, sortState, dataConsolidate, customSheetViews, mergeCells, ...
      var anchor = doc.rootElement.getElement('sheetData')!;
      for (final name in const ['sheetCalcPr', 'sheetProtection', 'protectedRanges', 'scenarios', 'autoFilter',
          'sortState', 'dataConsolidate', 'customSheetViews']) {
        anchor = doc.rootElement.getElement(name) ?? anchor;
      }
      doc.rootElement.children.insert(doc.rootElement.children.indexOf(anchor) + 1, merges);
    }
    merges.children.add(XmlElement(XmlName('mergeCell'), [XmlAttribute(XmlName('ref'), range.toUpperCase())]));
    merges.setAttribute('count', '${merges.findElements('mergeCell').length}');
    _dirty.add(_sheetPaths[sheet]!);
  }

  /// Removes a sheet: its part, relationship, content type and defined names.
  void removeSheet(String name) {
    final path = _sheetPaths[name];
    if (path == null) throw XlsxException('The workbook has no sheet "$name"');
    if (_sheetPaths.length == 1) throw const XlsxException('A workbook needs at least one sheet');
    final wb = _xml('xl/workbook.xml');
    final sheets = wb.findAllElements('sheet').toList();
    final index = sheets.indexWhere((s) => s.getAttribute('name') == name);
    final rid = sheets[index].attributes.firstWhere((a) => a.name.local == 'id').value;
    sheets[index].remove();
    final quoted = "'$name'!";
    for (final d in wb.findAllElements('definedName').toList()) {
      final local = int.tryParse(d.getAttribute('localSheetId') ?? '');
      if (local == index || d.innerText.contains(quoted) || d.innerText.contains('$name!')) {
        d.remove();
      } else if (local != null && local > index) {
        d.setAttribute('localSheetId', '${local - 1}');
      }
    }
    final names = wb.findAllElements('definedNames').firstOrNull;
    if (names != null && names.findElements('definedName').isEmpty) names.remove();
    for (final v in wb.findAllElements('workbookView')) {
      v.setAttribute('activeTab', '0');
      v.setAttribute('firstSheet', '0');
    }
    _putXml('xl/workbook.xml', wb);

    final rels = _xml('xl/_rels/workbook.xml.rels');
    for (final r in rels.findAllElements('Relationship').where((r) => r.getAttribute('Id') == rid).toList()) {
      r.remove();
    }
    _putXml('xl/_rels/workbook.xml.rels', rels);
    _removePart(path);
    _parsed.remove(path);
    _dirty.remove(path);
    _sheetPaths.remove(name);
    // The first remaining sheet becomes the selected one.
    final first = _sheetPaths.keys.first;
    for (final v in _sheet(first).findAllElements('sheetView')) {
      v.setAttribute('tabSelected', '1');
    }
    _dirty.add(_sheetPaths[first]!);
    _structural = true;
  }

  /// Removes who made and last saved the file and where it was stored
  /// (docProps/core.xml creator and lastModifiedBy, the workbook's absPath).
  void stripAuthorship() {
    if (_archive.find('docProps/core.xml') != null) {
      final doc = _xml('docProps/core.xml');
      for (final e in doc.descendantElements.toList()) {
        if (e.name.local == 'creator' || e.name.local == 'lastModifiedBy') e.children.clear();
      }
      _putXml('docProps/core.xml', doc);
    }
    final wb = _xml('xl/workbook.xml');
    for (final e in wb.descendantElements.toList()) {
      if (e.name.local == 'absPath') {
        // It sits in an mc:AlternateContent/mc:Choice wrapper; drop the wrapper.
        final wrapper = e.ancestorElements.where((a) => a.name.local == 'AlternateContent').firstOrNull;
        (wrapper ?? e).remove();
      }
    }
    _putXml('xl/workbook.xml', wb);
  }

  XmlDocument _xml(String path) {
    final f = _archive.find(path);
    if (f == null) throw XlsxException('Not an .xlsx workbook: $path is missing');
    return XmlDocument.parse(utf8.decode(f.content));
  }

  void _putXml(String path, XmlDocument doc) => _archive.add(ArchiveFile.string(path, doc.toXmlString()));

  /// Removes a part and its [Content_Types] override.
  void _removePart(String path) {
    final f = _archive.find(path);
    if (f != null) _archive.removeFile(f);
    final types = _xml('[Content_Types].xml');
    for (final o in types.findAllElements('Override').where((o) => o.getAttribute('PartName') == '/$path').toList()) {
      o.remove();
    }
    _putXml('[Content_Types].xml', types);
  }

  /// After rows or sheets were removed: keeps only the shared strings still
  /// used (removed content must not linger in the file) and drops the
  /// optional sheet list in docProps/app.xml (it would name removed sheets).
  void _compact() {
    final sst = _archive.find('xl/sharedStrings.xml');
    if (sst != null) {
      final cells = <XmlElement>[];
      for (final name in _sheetPaths.keys) {
        cells.addAll(_sheet(name).findAllElements('c').where((c) => c.getAttribute('t') == 's'));
        _dirty.add(_sheetPaths[name]!);
      }
      final doc = XmlDocument.parse(utf8.decode(sst.content));
      final items = doc.rootElement.findElements('si').toList();
      final map = <int, int>{};
      for (final c in cells) {
        final v = c.getElement('v');
        final old = int.tryParse(v?.innerText ?? '');
        if (v == null || old == null || old >= items.length) continue;
        final now = map.putIfAbsent(old, () => map.length);
        v.innerText = '$now';
      }
      final kept = (map.entries.toList()..sort((a, b) => a.value.compareTo(b.value))).map((e) => items[e.key].copy());
      doc.rootElement.children
        ..clear()
        ..addAll(kept);
      doc.rootElement.setAttribute('count', '${cells.length}');
      doc.rootElement.setAttribute('uniqueCount', '${map.length}');
      _putXml('xl/sharedStrings.xml', doc);
    }
    final app = _archive.find('docProps/app.xml');
    if (app != null) {
      final doc = XmlDocument.parse(utf8.decode(app.content));
      for (final e in doc.rootElement.childElements.toList()) {
        if (e.name.local == 'HeadingPairs' || e.name.local == 'TitlesOfParts') e.remove();
      }
      _putXml('docProps/app.xml', doc);
    }
  }

  /// The workbook with every change, marked for a full recalculation on open.
  /// After rows or sheets were removed, calcChain.xml (Excel's list of
  /// formula cells) is dropped: a stale one makes Excel repair the file.
  List<int> encode() {
    if (_structural) _compact();
    for (final path in _dirty) {
      _archive.add(ArchiveFile.string(path, _parsed[path]!.toXmlString()));
    }
    if (_structural && _archive.find('xl/calcChain.xml') != null) {
      _removePart('xl/calcChain.xml');
      final rels = _xml('xl/_rels/workbook.xml.rels');
      for (final r in rels.findAllElements('Relationship')
          .where((r) => (r.getAttribute('Type') ?? '').endsWith('/calcChain'))
          .toList()) {
        r.remove();
      }
      _putXml('xl/_rels/workbook.xml.rels', rels);
    }
    final wb = XmlDocument.parse(utf8.decode(_archive.find('xl/workbook.xml')!.content));
    final root = wb.rootElement;
    var calc = root.getElement('calcPr');
    if (calc == null) {
      // CT_Workbook order: ... sheets, functionGroups, externalReferences, definedNames, calcPr ...
      calc = XmlElement(XmlName('calcPr'));
      final after = root.getElement('definedNames') ??
          root.getElement('externalReferences') ??
          root.getElement('functionGroups') ??
          root.getElement('sheets')!;
      root.children.insert(root.children.indexOf(after) + 1, calc);
    }
    calc.setAttribute('fullCalcOnLoad', '1');
    _archive.add(ArchiveFile.string('xl/workbook.xml', wb.toXmlString()));
    return ZipEncoder().encodeBytes(_archive);
  }
}

/// "AB12" -> (column 28, row 12); columns count from 1.
(int, int) splitRef(String ref) {
  final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(ref.toUpperCase());
  if (m == null) throw XlsxException('Not a cell reference: $ref');
  var col = 0;
  for (final ch in m.group(1)!.codeUnits) {
    col = col * 26 + (ch - 64);
  }
  return (col, int.parse(m.group(2)!));
}

/// Column number (from 1) -> letters: 28 -> "AB".
String columnLetters(int col) {
  var s = '';
  for (var n = col; n > 0; n = (n - 1) ~/ 26) {
    s = String.fromCharCode(65 + (n - 1) % 26) + s;
  }
  return s;
}

/// An Excel date serial (1900 date system) as a date, e.g. 45960 -> 2025-10-31.
DateTime excelSerialDate(num serial) =>
    DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()));
