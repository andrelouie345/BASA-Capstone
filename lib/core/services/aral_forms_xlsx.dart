// lib/core/services/aral_forms_xlsx.dart
//
// ARAL Forms 1, 2 and 4 (Reading) of Division Memorandum 180 s. 2026 as
// plain .xlsx files (ARAL memo Plan B Task 6). Only the memo's PDF exists,
// so this is BASA's own layout copying the form's header fields and columns
// (owner 2026-11-19): a title, label/value header lines, the table, then the
// "Left blank for hand entry" line and the notes. Columns BASA can't fill
// keep their header and stay blank. Numbers are numbers, no formulas (the
// writer has none): Form 4's TOTAL row holds the sums.
import '../models/aral_forms.dart';
import 'xlsx_cells.dart';
import 'xlsx_writer.dart';

/// One sheet per class, named after its class code (see [aralFormSheetNames]).
/// Throws [XlsxException] when there is no class.
List<int> aralForm1Xlsx(List<AralForm1> forms) {
  if (forms.isEmpty) throw const XlsxException('There is no ARAL class to write.');
  final names = aralFormSheetNames([for (final f in forms) f.classCode]);
  return writeXlsx([
    for (var i = 0; i < forms.length; i++) _form1Sheet(names[i], forms[i]),
  ]);
}

XlsxSheetSpec _form1Sheet(String name, AralForm1 f) {
  final cells = <String, Object?>{'A1': 'ARAL Form 1: Class list (Reading)'};
  final header = <(String, Object?)>[
    ('School', f.schoolName),
    ('School ID', f.schoolCode),
    ('District', null),
    ('Class code', f.classCode),
    ('Grade', f.grade),
    ('Learning area', f.learningArea),
    ('Tutor', f.tutorName),
    ('Tutor type', f.tutorType),
    ('Session type', f.sessionType),
    ('Days and time', f.schedule),
    ('Venue', f.venue),
    ('Male', f.male),
    ('Female', f.female),
    ('Total', f.total),
  ];
  _labels(cells, 3, header);
  const columns = [
    'No.', 'LRN', 'Name (Last, First, MI)', 'Sex', 'Grade', 'Section', 'Class adviser', 'MoSY tool',
    'MoSY result', 'Workbook issued', 'Remarks',
  ];
  _row(cells, 18, columns);
  var r = 19;
  for (final x in f.rows) {
    _row(cells, r, [r - 18, x.lrn, x.name, x.sex, x.homeGrade, x.section, x.adviser, x.mosyTool, x.mosyResult,
        x.workbookIssued, x.remarks]);
    r++;
  }
  _notes(cells, r + 1, f.blanks, const []);
  return XlsxSheetSpec(
    name: name,
    cells: cells,
    textColumns: const {2},
    columnWidths: const [14, 15, 28, 6, 7, 16, 20, 10, 22, 16, 18],
  );
}

List<int> aralForm2Xlsx(AralForm2 f) {
  final cells = <String, Object?>{'A1': 'ARAL Form 2: Classes (Reading)'};
  _labels(cells, 3, [('School', f.schoolName), ('School ID', f.schoolCode), ('District', null)]);
  _row(cells, 7, const [
    'No.', 'Class code', 'Grade', 'Area', 'Male', 'Female', 'Total', 'MoSY result', 'Tutor', 'Type (I/E)',
    'Advisory class', 'Days and time', 'Session type', 'Venue', 'Mathematics',
  ]);
  var r = 8;
  for (final x in f.rows) {
    _row(cells, r, [r - 7, x.classCode, x.grade, x.area, x.male, x.female, x.total, x.mosyResult, x.tutorName,
        x.tutorType, x.advisoryClass, x.schedule, x.sessionType, x.venue]);
    r++;
  }
  r++;
  _labels(cells, r, [
    ('Reading classes', f.readingClasses),
    ('Reading learners', f.readingLearners),
    ('Internal tutors', f.internalTutors),
    ('External tutors', f.externalTutors),
    ('Mathematics classes', null),
  ]);
  _notes(cells, r + 6, f.blanks, f.notes);
  return writeXlsx([
    XlsxSheetSpec(
      name: 'Form 2',
      cells: cells,
      columnWidths: const [20, 16, 7, 6, 7, 7, 7, 22, 20, 10, 18, 16, 16, 12, 13],
    ),
  ]);
}

List<int> aralForm4Xlsx(AralForm4 f) {
  final cells = <String, Object?>{'A1': 'ARAL Form 4: Progress report (Reading)'};
  _labels(cells, 3, [('School', f.schoolName), ('School ID', f.schoolCode), ('As of', f.asOf)]);
  cells['A7'] = 'Part I. Learners (Reading)';
  _row(cells, 8, const [
    'Grade', 'Identified at BoSY', 'Served in ARAL classes', 'Reached grade level (exited)',
    'Improved, still below (continue)', 'No improvement (referred)', 'ARAL learners at MoSY', 'Mathematics',
  ]);
  List<int> counts(AralForm4Grade g) =>
      [g.identified, g.served, g.reachedGradeLevel, g.improved, g.noImprovement, g.atMosy];
  final totals = List.filled(6, 0);
  var r = 9;
  for (final g in f.grades) {
    final c = counts(g);
    for (var i = 0; i < 6; i++) {
      totals[i] += c[i];
    }
    _row(cells, r++, ['Grade ${g.grade}', ...c]);
  }
  _row(cells, r, ['TOTAL', ...totals]);
  r += 2;
  cells['A$r'] = 'Part II. Implementation';
  _labels(cells, r + 1, [
    ('Organized ARAL classes', f.classes),
    ('Internal tutors', f.internalTutors),
    ('External tutors', f.externalTutors),
    ('Sessions conducted', f.sessions),
    ('Hours rendered', (f.hours * 100).round() / 100),
  ]);
  _notes(cells, r + 7, const [], f.notes);
  return writeXlsx([
    XlsxSheetSpec(name: 'Form 4', cells: cells, columnWidths: const [24, 14, 14, 16, 18, 16, 14, 13]),
  ]);
}

/// Excel sheet names for [codes], in order: the characters Excel refuses
/// (\ / ? * [ ] :) become '-', apostrophes at either end go, at most 31
/// characters, and a name already used (ignoring case, as Excel does) gets
/// " (2)", " (3)", ...
List<String> aralFormSheetNames(List<String> codes) {
  final used = <String>{};
  final out = <String>[];
  for (final code in codes) {
    var base = code.replaceAll(RegExp(r'[\\/?*\[\]:]'), '-').replaceAll(RegExp(r"^'+|'+$"), '').trim();
    if (base.isEmpty) base = 'Class';
    String fit(String b, String suffix) {
      final room = 31 - suffix.length;
      return (b.length > room ? b.substring(0, room).trimRight() : b) + suffix;
    }

    var name = fit(base, '');
    for (var n = 2; used.contains(name.toLowerCase()); n++) {
      name = fit(base, ' ($n)');
    }
    used.add(name.toLowerCase());
    out.add(name);
  }
  return out;
}

// --- helpers ---

/// Label in A, value in B, one per line from [row]; '' and null leave B blank.
void _labels(Map<String, Object?> cells, int row, List<(String, Object?)> lines) {
  for (final (label, value) in lines) {
    cells['A$row'] = label;
    cells['B$row'] = _blank(value);
    row++;
  }
}

void _row(Map<String, Object?> cells, int row, List<Object?> values) {
  for (var c = 0; c < values.length; c++) {
    cells['${columnLetters(c + 1)}$row'] = _blank(values[c]);
  }
}

/// The "Left blank for hand entry" line (when [blanks]), then each note.
void _notes(Map<String, Object?> cells, int row, List<String> blanks, List<String> notes) {
  if (blanks.isNotEmpty) cells['A${row++}'] = 'Left blank for hand entry: ${blanks.join(', ')}.';
  for (final n in notes) {
    cells['A${row++}'] = n;
  }
}

Object? _blank(Object? v) => v is String && v.isEmpty ? null : v;
