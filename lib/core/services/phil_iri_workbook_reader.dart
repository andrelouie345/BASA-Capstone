// lib/core/services/phil_iri_workbook_reader.dart
//
// Reads ma's Phil-IRI/ARAL workbook into a PhilIriImportPlan (spec
// docs/superpowers/specs/2026-11-09-phil-iri-import-design.md; plan Task 6).
// Raw typed cells only, plus the workbook's own saved adjusted profile and
// level (cached formula values, read only for the D7 comparison).
//
// Layout rules (from the G7 workbook, 2026-11 update):
//  * A section sheet is any sheet with all five round block titles in rows
//    9-12, except a sheet named "Sample" (ma's demo sheet, same layout; Task 6
//    ruling, owner option A). A missing wb.name header is a header issue (the
//    sheet is listed, never silently dropped; owner option A, sheet 13).
//  * A round block spans from its title's column to the next title's column
//    (the last one is as wide as the block before it). Every field is found
//    by its header label (PhilIriImportHeaders), never by column letter; a
//    missing header is a PhilIriHeaderIssue and that sheet's learners are not
//    read (nothing is guessed).
//  * Learners: the wb.name header's column carries the MALES / FEMALES labels
//    and row numbers; names are in the column to its right. Males from below
//    MALES to above FEMALES, females from below FEMALES to the first row whose
//    label and name cells are both empty.
//  * Section: the cells right of "Grade and Section", "School:" (DepEd ID =
//    digits before " - ") and "SY:", and right of (else below) "Current Grade".
//
// Round outcome per learner (D9 as amended by R1 D18 and R2 D10):
//  * timed (one minute: typed words read > 0; whole text: typed words read
//    > 0 and a typed mm/ss total > 0) -> a reading; a blank passage =
//    "Untitled" (whole text: the words-read cell is the word count);
//  * otherwise a typed comprehension (0 counts) -> a comprehension-only
//    reading; its miscue counts are dropped with a problem;
//  * otherwise anything typed (passage, words read, time, miscues) -> skipped
//    as incomplete; nothing typed -> nothing.
// Miscues D4: Reversal/Hesitation -> counted reversal; Repetition/
// Self-correction -> self-corrected. A comprehension above the block's
// maximum is a problem and is dropped; an Untitled reading's comprehension
// needs the maximum (it is the total it is out of).
// Comprehension codes (ma, 2026-11-12; comprehension columns only, every
// block and sheet): 0.1 = blank, 0.2 = 0 correct (assessed).
import '../models/phil_iri_assessment.dart' show PhilIriRound;
import '../models/phil_iri_import.dart';
import '../models/phil_iri_miscue.dart';
import '../models/phil_iri_reading.dart' show PhilIriReadingMethod;
import 'phil_iri_import_headers.dart';
import 'table_reader.dart' show normalizeHeader;
import 'xlsx_cells.dart';

const _headerRows = (first: 9, last: 12);

/// Fields every round block needs (wb.time is not needed: mm and ss are found
/// directly; the adjusted profile and level are optional).
const _blockFields = [
  'wb.selection', 'wb.wordsRead', 'wb.mispronunciation', 'wb.omission', 'wb.substitution', 'wb.insertion',
  'wb.reversal', 'wb.repetition', 'wb.minutes', 'wb.seconds', 'wb.comprehension', 'wb.method',
];
const _optionalBlockFields = ['wb.adjProfile', 'wb.adjLevel'];

const _countedMiscues = {
  'wb.mispronunciation': PhilIriMiscueType.mispronunciation,
  'wb.omission': PhilIriMiscueType.omission,
  'wb.substitution': PhilIriMiscueType.substitution,
  'wb.insertion': PhilIriMiscueType.insertion,
  'wb.reversal': PhilIriMiscueType.reversal,
};

PhilIriImportPlan readPhilIriWorkbook(List<int> bytes, PhilIriImportHeaders headers) {
  final wb = XlsxWorkbook.decode(bytes);
  final out = _PlanBuilder();
  for (final sheet in wb.sheetNames) {
    if (sheet.trim().toLowerCase() == 'sample') continue;
    _SheetReader(sheet, wb.readSheet(sheet), wb.formulaRefs(sheet), headers, out).read();
  }
  return PhilIriImportPlan(
    source: PhilIriImportSource.workbook,
    sections: out.sections,
    gst: out.gst,
    readings: out.readings,
    skipped: out.skipped,
    problems: out.problems,
    headerIssues: out.issues.values.toList(),
  );
}

class _PlanBuilder {
  final sections = <PhilIriImportSectionRef>[];
  final gst = <PhilIriImportGst>[];
  final readings = <PhilIriImportReading>[];
  final skipped = <PhilIriImportSkip>[];
  final problems = <PhilIriImportProblem>[];
  final issues = <(String, String), PhilIriHeaderIssue>{}; // one per field and block, every sheet shares the template
}

/// A header cell found in rows 9-12.
typedef _Cell = ({int col, int row});

class _Block {
  final PhilIriRound round;
  final String title;
  final int from, to; // column span [from, to)
  final Map<String, _Cell> fields = {};
  _Block(this.round, this.title, this.from, this.to);
}

class _SheetReader {
  final String sheet;
  final Map<String, Object> cells;
  final Set<String> formulas;
  final PhilIriImportHeaders headers;
  final _PlanBuilder out;

  _SheetReader(this.sheet, this.cells, this.formulas, this.headers, this.out);

  Object? at(int col, int row) => cells['${columnLetters(col)}$row'];
  bool isFormula(int col, int row) => formulas.contains('${columnLetters(col)}$row');

  /// Text header cells of rows 9-12, in column then row order.
  late final List<(_Cell, String)> _headerCells = () {
    final list = <(_Cell, String)>[];
    for (final e in cells.entries) {
      final (col, row) = splitRef(e.key);
      if (row < _headerRows.first || row > _headerRows.last || e.value is! String) continue;
      list.add(((col: col, row: row), e.value as String));
    }
    list.sort((a, b) => a.$1.col != b.$1.col ? a.$1.col.compareTo(b.$1.col) : a.$1.row.compareTo(b.$1.row));
    return list;
  }();

  _Cell? _find(String field, {int from = 1, int to = 1 << 20}) {
    for (final (cell, text) in _headerCells) {
      if (cell.col >= from && cell.col < to && headers.matches(field, text)) return cell;
    }
    return null;
  }

  void read() {
    final titles = <PhilIriRound, (_Cell, String)>{};
    for (final r in PhilIriRound.values) {
      for (final (cell, text) in _headerCells) {
        if (headers.matches('wb.block.${r.name}', text)) {
          titles[r] = (cell, text);
          break;
        }
      }
    }
    if (titles.length != PhilIriRound.values.length) return; // not a section sheet

    final ordered = titles.entries.toList()..sort((a, b) => a.value.$1.col.compareTo(b.value.$1.col));
    final blocks = <_Block>[];
    for (var i = 0; i < ordered.length; i++) {
      final from = ordered[i].value.$1.col;
      final to = i + 1 < ordered.length
          ? ordered[i + 1].value.$1.col
          : from + (i > 0 ? from - ordered[i - 1].value.$1.col : 30);
      blocks.add(_Block(ordered[i].key, ordered[i].value.$2, from, to));
    }

    // A missing name header is a header issue, never a dropped sheet.
    final name = _find('wb.name', to: blocks.first.from);
    if (name == null) {
      out.sections.add(_sectionRef(empty: false));
      _issue('wb.name', 'sheet', 1, blocks.first.from);
      return;
    }
    final learners = _learnerRows(name.col);
    out.sections.add(_sectionRef(empty: learners.isEmpty));

    // Every needed header, or nothing from this sheet.
    var missing = false;
    final gstCell = _find('wb.gst', to: blocks.first.from);
    if (gstCell == null) {
      missing = true;
      _issue('wb.gst', 'sheet', 1, blocks.first.from);
    }
    for (final b in blocks) {
      for (final f in [..._blockFields, ..._optionalBlockFields]) {
        final c = _find(f, from: b.from, to: b.to);
        if (c != null) {
          b.fields[f] = c;
        } else if (_blockFields.contains(f)) {
          missing = true;
          _issue(f, b.title, b.from, b.to);
        }
      }
    }
    if (missing) return;

    final gstMax = _numberBelow(gstCell!);
    final methods = <PhilIriRound, PhilIriReadingMethod?>{};
    for (final b in blocks) {
      methods[b.round] = _method(b);
    }
    for (final (row, sex) in learners) {
      final learnerName = (at(name.col + 1, row) as String).trim();
      final key = PhilIriLearnerKey(name: learnerName, sex: sex);
      final score = _typedInt(gstCell.col, row);
      if (score != null) {
        out.gst.add(PhilIriImportGst(
            ref: PhilIriImportRef(sheet: sheet, row: row, column: columnLetters(gstCell.col)),
            learner: key, score: score, max: gstMax));
      }
      for (final b in blocks) {
        final method = methods[b.round];
        if (method != null) _readBlock(b, method, row, key);
      }
    }
  }

  void _issue(String field, String block, int from, int to) {
    out.issues.putIfAbsent((field, block), () => PhilIriHeaderIssue(
          field: field,
          block: block,
          found: [
            for (final (cell, text) in _headerCells)
              if (cell.col >= from && cell.col < to && cell.row > _headerRows.first) text,
          ],
        ));
  }

  /// (row, sex) of every learner row with a name.
  List<(int, String)> _learnerRows(int labelCol) {
    int? males, females;
    var last = 0;
    for (final k in cells.keys) {
      final (col, row) = splitRef(k);
      if (row > last) last = row;
      if (col != labelCol || row <= _headerRows.last) continue;
      final v = normalizeHeader('${cells[k]}');
      if (v == 'males' && (males == null || row < males)) males = row;
      if (v == 'females' && (females == null || row < females)) females = row;
    }
    final rows = <(int, String)>[];
    bool named(int row) {
      final v = at(labelCol + 1, row);
      return v is String && v.trim().isNotEmpty;
    }

    if (males != null) {
      final end = females ?? last + 1;
      for (var r = males + 1; r < end; r++) {
        if (named(r)) rows.add((r, 'M'));
      }
    }
    if (females != null) {
      for (var r = females + 1; r <= last; r++) {
        if (at(labelCol, r) == null && at(labelCol + 1, r) == null) break;
        if (named(r)) rows.add((r, 'F'));
      }
    }
    return rows;
  }

  PhilIriImportSectionRef _sectionRef({required bool empty}) {
    Object? valueOf(String label, {bool below = false}) {
      final want = normalizeHeader(label);
      final hits = <(int, int)>[];
      for (final e in cells.entries) {
        final (col, row) = splitRef(e.key);
        if (row < _headerRows.first && e.value is String && normalizeHeader(e.value as String) == want) {
          hits.add((col, row));
        }
      }
      hits.sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
      for (final (col, row) in hits) {
        final v = at(col + 1, row) ?? (below ? at(col, row + 1) : null);
        if (v != null) return v;
      }
      return null;
    }

    final school = valueOf('School:');
    final year = valueOf('SY:');
    final grade = valueOf('Current Grade', below: true);
    final section = valueOf('Grade and Section');
    return PhilIriImportSectionRef(
      sheet: sheet,
      depedSchoolId: school == null ? null : RegExp(r'^\s*(\d+)').firstMatch('$school')?.group(1),
      schoolYear: year == null ? null : RegExp(r'^\s*(\d{4}-\d{4})').firstMatch('$year')?.group(1),
      grade: grade is num ? grade.toInt() : int.tryParse('${grade ?? ''}'.trim()),
      sectionName: section == null ? null : '$section'.trim(),
      empty: empty,
    );
  }

  /// The first number below a header cell, down to row 12 (a column's maximum).
  int? _numberBelow(_Cell c) {
    for (var r = c.row + 1; r <= _headerRows.last; r++) {
      final v = at(c.col, r);
      if (v is num) return v.toInt();
    }
    return null;
  }

  PhilIriReadingMethod? _method(_Block b) {
    final label = b.fields['wb.method']!;
    final v = at(label.col + 1, label.row);
    final n = normalizeHeader('${v ?? ''}');
    if (n.contains('oneminute')) return PhilIriReadingMethod.oneMinute;
    if (n.contains('wholetext')) return PhilIriReadingMethod.wholeText;
    out.problems.add(PhilIriImportProblem(
      ref: PhilIriImportRef(sheet: sheet, row: label.row, column: columnLetters(label.col + 1)),
      message: 'unknown reading method "${v ?? ''}" for ${b.title}: this round is not imported from this sheet',
    ));
    return null;
  }

  /// A typed whole number >= 0, or null (blank, a formula, or unreadable:
  /// then a problem is listed).
  int? _typedInt(int col, int row, {String expected = 'a whole number is expected'}) {
    final v = at(col, row);
    if (v == null || isFormula(col, row)) return null;
    int? n;
    if (v is int) {
      n = v;
    } else if (v is num && v == v.roundToDouble()) {
      n = v.toInt();
    } else if (v is String) {
      if (v.trim().isEmpty) return null;
      n = int.tryParse(v.trim());
    }
    if (n == null || n < 0) {
      _problem(col, row, 'unreadable value "$v" ($expected)');
      return null;
    }
    return n;
  }

  /// A comprehension cell: ma's codes first (an Excel quirk shows a blank and
  /// a 0 alike, so she types 0.1 = blank and 0.2 = 0 correct; number or text),
  /// then a typed whole number as [_typedInt]. Returns (correct, entered).
  (int?, bool) _comprehension(int col, int row) {
    final v = at(col, row);
    if (v != null && !isFormula(col, row)) {
      final n = v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);
      if (n != null && (n - 0.1).abs() < 1e-9) return (null, false);
      if (n != null && (n - 0.2).abs() < 1e-9) return (0, true);
    }
    final correct = _typedInt(col, row, expected: 'a whole number is expected, or 0.1 = blank / 0.2 = 0');
    return (correct, correct != null);
  }

  void _problem(int col, int row, String message) => out.problems.add(
      PhilIriImportProblem(ref: PhilIriImportRef(sheet: sheet, row: row, column: columnLetters(col)), message: message));

  void _readBlock(_Block b, PhilIriReadingMethod method, int row, PhilIriLearnerKey key) {
    final f = b.fields;
    final passageCell = f['wb.selection']!;
    final pv = isFormula(passageCell.col, row) ? null : at(passageCell.col, row);
    final passageRaw = pv == null || '$pv'.trim().isEmpty ? null : '$pv'.trim();
    final wordsRead = _typedInt(f['wb.wordsRead']!.col, row);
    final mm = _typedInt(f['wb.minutes']!.col, row);
    final ss = _typedInt(f['wb.seconds']!.col, row);
    final seconds = mm == null && ss == null ? null : (mm ?? 0) * 60 + (ss ?? 0);
    final miscues = <PhilIriMiscueType, int>{};
    for (final e in _countedMiscues.entries) {
      final n = _typedInt(f[e.key]!.col, row);
      if (n != null && n > 0) miscues[e.value] = n;
    }
    final selfCorrected = _typedInt(f['wb.repetition']!.col, row) ?? 0;

    final compCell = f['wb.comprehension']!;
    final max = _numberBelow(compCell);
    var (correct, compEntered) = _comprehension(compCell.col, row);
    if (correct != null && max != null && correct > max) {
      _problem(compCell.col, row, 'comprehension $correct is more than the maximum $max, not imported');
      correct = null;
    }
    if (correct != null && passageRaw == null && max == null) {
      _problem(compCell.col, row, 'comprehension without a maximum, not imported');
      correct = null;
    }

    final hasWords = wordsRead != null && wordsRead > 0;
    final hasTime = seconds != null && seconds > 0;
    final timed = method == PhilIriReadingMethod.oneMinute ? hasWords : hasWords && hasTime;
    final ref = PhilIriImportRef(sheet: sheet, row: row);
    final passage = passageRaw == null ? null : _passageRef(passageRaw);
    String? cachedProfile;
    int? cachedLevel;
    final pc = f['wb.adjProfile'], lc = f['wb.adjLevel'];
    if (pc != null && at(pc.col, row) is String) cachedProfile = (at(pc.col, row) as String).trim();
    if (lc != null && at(lc.col, row) is num) cachedLevel = (at(lc.col, row) as num).toInt();

    if (timed) {
      final oneMinute = method == PhilIriReadingMethod.oneMinute;
      out.readings.add(PhilIriImportReading(
        ref: ref,
        learner: key,
        round: b.round,
        passage: passage,
        method: method,
        seconds: oneMinute ? null : seconds,
        wordsRead: passage == null && !oneMinute ? null : wordsRead,
        wordCount: passage == null && !oneMinute ? wordsRead : null,
        miscues: miscues,
        selfCorrected: selfCorrected,
        correctCount: correct,
        correctTotal: correct == null ? null : max,
        workbookProfile: cachedProfile,
        workbookAdjustedLevel: cachedLevel,
      ));
      return;
    }
    if (correct != null) {
      if (miscues.isNotEmpty || selfCorrected > 0) {
        out.problems.add(PhilIriImportProblem(ref: ref, message: 'miscues without a time, not imported'));
      }
      out.readings.add(PhilIriImportReading(
        ref: ref,
        learner: key,
        round: b.round,
        passage: passage,
        method: method,
        correctCount: correct,
        correctTotal: max,
        workbookProfile: cachedProfile,
        workbookAdjustedLevel: cachedLevel,
      ));
      return;
    }
    final anything = passageRaw != null || wordsRead != null || seconds != null || miscues.isNotEmpty ||
        selfCorrected > 0 || compEntered;
    if (!anything) return;
    final missingParts = [
      if (!hasWords) 'no words read',
      if (method == PhilIriReadingMethod.wholeText && !hasTime) 'no time',
    ];
    out.skipped.add(PhilIriImportSkip(
      ref: ref,
      learner: key,
      round: b.round,
      reason: 'incomplete: ${missingParts.isEmpty ? 'no usable comprehension' : missingParts.join(', ')}',
    ));
  }

  /// `7C Dust` -> level 7, code 7C, title Dust; `7D2 Ecosystems` -> 7D2.
  PhilIriImportPassageRef _passageRef(String raw) {
    final m = RegExp(r'^(\d{1,2})([A-Za-z]+\d*)\s+(.+)$').firstMatch(raw);
    if (m == null) return PhilIriImportPassageRef(raw: raw);
    return PhilIriImportPassageRef(
      raw: raw,
      level: int.parse(m.group(1)!),
      code: '${m.group(1)}${m.group(2)!.toUpperCase()}',
      title: m.group(3)!.trim(),
    );
  }
}
