// Builds workbooks in ma's Phil-IRI/ARAL layout (G7 workbook, 2026-11 update)
// for the workbook reader tests. Made-up names only.
//
// Layout (same columns as the real file): A = MALES/FEMALES labels and row
// numbers, B = names (header "NAME OF STUDENT" at A10), G = GST raw score
// (header G10, maximum G12). Round blocks start at R, AU, BX, DA, ED (29
// columns apart); inside a block at title column t: SELECTION t+1 (row 12),
// "# of Words Read" t+2, the six miscue columns t+3..t+8 (row 11), "Reading
// Method" t+9 (row 9) with the method in t+10, mm t+10 / ss t+11 (row 12),
// comprehension t+18 (header row 10, maximum row 12), Adj. Reading Profile
// t+21, Adj. Grade Level t+22. Section info: B6/C6 grade and section, B7/C7
// school, D8/E8 school year, M6 "Current Grade" with the grade below in M7.
//
// writeXlsx writes no formulas; cells listed as formulas get an <f> element
// patched into the sheet XML afterwards (the reader only asks isFormula).
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:basa_capstone/core/models/phil_iri_assessment.dart' show PhilIriRound;
import 'package:basa_capstone/core/services/xlsx_cells.dart';
import 'package:basa_capstone/core/services/xlsx_writer.dart';

const wbTitles = {
  PhilIriRound.bosy: 'IRA FOR GST RESULTS VALIDATION/PRETEST',
  PhilIriRound.mosy1: 'MIDDLE OF SCHOOL YEAR ASSESSMENT (MOSY #1)',
  PhilIriRound.mosy2: 'MIDDLE OF SCHOOL YEAR ASSESSMENT (MOSY #2)',
  PhilIriRound.mosy3: 'MIDDLE OF SCHOOL YEAR ASSESSMENT (MOSY #3)',
  PhilIriRound.eosy: 'END OF SCHOOL YEAR ASSESSMENT (EOSY) / POSTTEST',
};

/// Title column of each round block (R, AU, BX, DA, ED).
int wbBlockColumn(PhilIriRound r) => 18 + 29 * PhilIriRound.values.indexOf(r);

/// One learner's typed cells in one round block. [wordsReadFormula] leaves
/// the words-read cell as the template's formula (cached 0).
class WbRound {
  final String? passage;
  final int? wordsRead;
  final bool wordsReadFormula;
  final int? mm, ss;
  final int mispronunciation, omission, substitution, insertion, reversal, repetition;
  final int? comprehension;
  final String? adjProfile;
  final int? adjLevel;

  const WbRound({
    this.passage,
    this.wordsRead,
    this.wordsReadFormula = false,
    this.mm,
    this.ss,
    this.mispronunciation = 0,
    this.omission = 0,
    this.substitution = 0,
    this.insertion = 0,
    this.reversal = 0,
    this.repetition = 0,
    this.comprehension,
    this.adjProfile,
    this.adjLevel,
  });
}

class WbLearner {
  final String name;
  final int? gst;
  final Map<PhilIriRound, WbRound> rounds;
  const WbLearner(this.name, {this.gst, this.rounds = const {}});
}

class WbSheet {
  final String name;
  final String section;
  final String school; // "303988 - VNHS"
  final String schoolYear;
  final int grade;
  final List<WbLearner> males, females;

  /// Round -> "One-Minute Reading" / "Whole-Text Reading" (default one minute).
  final Map<PhilIriRound, String> methods;

  /// Round -> comprehension maximum in row 12 (default 8 for BOSY/MOSY 1, else 20).
  final Map<PhilIriRound, int?> comprehensionMax;

  /// Header text replaced in every block: default text -> new text.
  final Map<String, String> renames;

  /// Inserts an empty column before this round's SELECTION column (moves
  /// everything right of it, as Excel's Insert Column does).
  final PhilIriRound? insertColumnBeforeSelection;

  const WbSheet(
    this.name, {
    this.section = 'IRON',
    this.school = '303988 - VNHS',
    this.schoolYear = '2027-2028',
    this.grade = 7,
    this.males = const [],
    this.females = const [],
    this.methods = const {},
    this.comprehensionMax = const {},
    this.renames = const {},
    this.insertColumnBeforeSelection,
  });
}

/// Rows of the learner blocks: MALES label row, first male row, FEMALES label
/// row, first female row (each block = its learners + 2 numbered empty rows).
({int malesLabel, int femalesLabel}) wbLabelRows(WbSheet s) =>
    (malesLabel: 13, femalesLabel: 14 + s.males.length + 2);

/// The row of [learner] in [s] (males first, then females).
int wbRowOf(WbSheet s, WbLearner learner) {
  final m = s.males.indexOf(learner);
  if (m >= 0) return 14 + m;
  return wbLabelRows(s).femalesLabel + 1 + s.females.indexOf(learner);
}

List<int> buildPhilIriWorkbook(List<WbSheet> sections, {List<String> otherSheets = const ['STARTHERE']}) {
  final specs = <XlsxSheetSpec>[];
  final formulas = <String, Set<String>>{}; // sheet -> refs
  for (final o in otherSheets) {
    specs.add(XlsxSheetSpec(name: o, cells: {'A1': 'not a section sheet'}));
  }
  for (final s in sections) {
    final cells = <(int, int), Object?>{};
    final f = <(int, int)>{};
    void put(int col, int row, Object? v, {bool formula = false}) {
      cells[(col, row)] = v;
      formula ? f.add((col, row)) : f.remove((col, row)); // a typed value replaces the template formula
    }

    String h(String text) => s.renames[text] ?? text;
    put(2, 6, 'Grade and Section');
    put(3, 6, s.section, formula: true);
    put(2, 7, 'School:');
    put(3, 7, s.school, formula: true);
    put(4, 8, 'SY:');
    put(5, 8, s.schoolYear, formula: true);
    put(13, 6, 'Current Grade');
    put(13, 7, s.grade, formula: true);
    put(1, 10, h('NAME OF STUDENT'));
    put(7, 10, h('GST Raw Score'));
    put(7, 12, 40);
    for (final r in PhilIriRound.values) {
      final t = wbBlockColumn(r);
      put(t, 9, wbTitles[r]);
      put(t + 9, 9, h('Reading Method'));
      put(t + 10, 9, s.methods[r] ?? 'One-Minute Reading');
      put(t, 10, 'Phil-IRI');
      put(t, 12, 'SET');
      put(t + 1, 12, h('SELECTION'));
      put(t + 2, 10, h('# of Words Read'));
      put(t + 3, 10, 'Types of Miscues');
      const miscues = ['Mispronounciation', 'Omission / Deletion', 'Substitution', 'Insertion',
          'Reversal/ Hesitation', 'Repetition / Self-orrection'];
      for (var i = 0; i < miscues.length; i++) {
        put(t + 3 + i, 11, h(miscues[i]));
      }
      put(t + 10, 10, h('Total Time Reading  the Text'));
      put(t + 10, 12, h('mm'));
      put(t + 11, 12, h('ss'));
      put(t + 12, 12, 'in secs');
      put(t + 18, 10, h('Reading Comprehension (Percent Score)'));
      final max = s.comprehensionMax.containsKey(r)
          ? s.comprehensionMax[r]
          : (r == PhilIriRound.bosy || r == PhilIriRound.mosy1 ? 8 : 20);
      put(t + 18, 12, max);
      put(t + 21, 10, h('Adj. Reading Profile'));
      put(t + 22, 10, h('Adj. Grade Level'));
    }
    final labels = wbLabelRows(s);
    put(1, labels.malesLabel, 'MALES');
    put(1, labels.femalesLabel, 'FEMALES');
    void block(List<WbLearner> learners, int firstRow) {
      for (var i = 0; i < learners.length + 2; i++) {
        final row = firstRow + i;
        put(1, row, i + 1);
        put(wbBlockColumn(PhilIriRound.bosy) + 2, row, 0, formula: true); // template formulas, cached 0
        if (i >= learners.length) continue;
        final l = learners[i];
        put(2, row, l.name);
        if (l.gst != null) put(7, row, l.gst);
        for (final e in l.rounds.entries) {
          final t = wbBlockColumn(e.key), v = e.value;
          if (v.passage != null) put(t + 1, row, v.passage);
          if (v.wordsReadFormula) {
            put(t + 2, row, 0, formula: true);
          } else if (v.wordsRead != null) {
            put(t + 2, row, v.wordsRead);
          }
          final counts = [v.mispronunciation, v.omission, v.substitution, v.insertion, v.reversal, v.repetition];
          for (var k = 0; k < counts.length; k++) {
            if (counts[k] != 0) put(t + 3 + k, row, counts[k]);
          }
          if (v.mm != null) put(t + 10, row, v.mm);
          if (v.ss != null) put(t + 11, row, v.ss);
          if (v.comprehension != null) put(t + 18, row, v.comprehension);
          if (v.adjProfile != null) put(t + 21, row, v.adjProfile, formula: true);
          if (v.adjLevel != null) put(t + 22, row, v.adjLevel, formula: true);
        }
      }
    }

    block(s.males, labels.malesLabel + 1);
    block(s.females, labels.femalesLabel + 1);
    // A note below the female block after a fully blank row (sheet 40 has these).
    final end = labels.femalesLabel + 1 + s.females.length + 2;
    put(2, end + 2, 'Prepared by: (signature)');

    final shiftFrom = s.insertColumnBeforeSelection == null ? null : wbBlockColumn(s.insertColumnBeforeSelection!) + 1;
    (int, int) moved((int, int) k) => shiftFrom != null && k.$1 >= shiftFrom ? (k.$1 + 1, k.$2) : k;
    specs.add(XlsxSheetSpec(name: s.name, cells: {
      for (final e in cells.entries) '${columnLetters(moved(e.key).$1)}${moved(e.key).$2}': e.value,
    }));
    formulas[s.name] = {for (final k in f) '${columnLetters(moved(k).$1)}${moved(k).$2}'};
  }
  return _withFormulas(writeXlsx(specs), [for (final s in specs) s.name], formulas);
}

/// Adds an `<f>` element to the listed cells (sheet i+1 of the written workbook = names[i]).
List<int> _withFormulas(List<int> bytes, List<String> names, Map<String, Set<String>> formulas) {
  final input = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final file in input.files) {
    var content = file.content as List<int>;
    final m = RegExp(r'^xl/worksheets/sheet(\d+)\.xml$').firstMatch(file.name);
    final refs = m == null ? null : formulas[names[int.parse(m.group(1)!) - 1]];
    if (refs != null && refs.isNotEmpty) {
      var xml = utf8.decode(content);
      xml = xml.replaceAllMapped(RegExp(r'<c r="([A-Z]+\d+)"([^>]*)>'), (c) {
        if (!refs.contains(c.group(1))) return c.group(0)!;
        return '<c r="${c.group(1)}"${c.group(2)}><f>N(0)</f>';
      });
      content = utf8.encode(xml);
    }
    out.add(ArchiveFile.bytes(file.name, content));
  }
  return ZipEncoder().encodeBytes(out);
}
